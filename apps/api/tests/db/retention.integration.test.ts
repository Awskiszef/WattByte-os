import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { AI_QUOTA_RETENTION_DAYS, loadRetentionConfig, runRetention, SESSION_RETENTION_DAYS } from '../../src/scripts/retention.js';
import { DATABASE_URL, uniqueEmail } from './helpers.js';

const run = promisify(execFile);
const DAY = 86_400_000;
const apiRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

describe('retention configuration (no database needed)', () => {
  it('reads three variables, with 90 days as the default history', () => {
    expect(loadRetentionConfig({ DATABASE_URL: 'postgres://u:p@h:5432/d' })).toEqual({ databaseUrl: 'postgres://u:p@h:5432/d', ssl: undefined, aiHistoryDays: 90 });
    expect(loadRetentionConfig({ DATABASE_URL: 'postgres://u:p@h:5432/d', DATABASE_SSL: '1', AI_HISTORY_RETENTION_DAYS: '30' })).toMatchObject({ ssl: { rejectUnauthorized: true }, aiHistoryDays: 30 });
  });

  it('refuses a missing database and a retention of zero or a fraction of a day (that would purge everything / nothing sensible)', () => {
    expect(() => loadRetentionConfig({})).toThrow(/DATABASE_URL/);
    expect(() => loadRetentionConfig({ DATABASE_URL: 'postgres://u:p@h/d', AI_HISTORY_RETENTION_DAYS: '0' })).toThrow(/AI_HISTORY_RETENTION_DAYS/);
    expect(() => loadRetentionConfig({ DATABASE_URL: 'postgres://u:p@h/d', AI_HISTORY_RETENTION_DAYS: '0.5' })).toThrow(/AI_HISTORY_RETENTION_DAYS/);
    expect(() => loadRetentionConfig({ DATABASE_URL: 'postgres://u:p@h/d', AI_HISTORY_RETENTION_DAYS: 'ninety' })).toThrow(/AI_HISTORY_RETENTION_DAYS/);
  });

  it('documents the fixed windows', () => {
    expect(SESSION_RETENTION_DAYS).toBe(30);
    expect(AI_QUOTA_RETENTION_DAYS).toBe(7);
  });
});

describe.skipIf(!DATABASE_URL)('retention (PostgreSQL)', () => {
  let pool: pg.Pool;
  const users: string[] = [];

  beforeAll(async () => {
    await migrate(DATABASE_URL!);
    pool = new pg.Pool({ connectionString: DATABASE_URL, max: 3 });
  });
  afterAll(async () => {
    if (users.length) await pool.query('DELETE FROM users WHERE id = ANY($1)', [users]);
    await pool.end();
  });

  async function newUser(): Promise<string> {
    const res = await pool.query('INSERT INTO users(email) VALUES ($1) RETURNING id', [uniqueEmail('retention')]);
    const id = (res.rows[0] as { id: string }).id;
    users.push(id);
    return id;
  }

  const at = (now: Date, daysAgo: number): Date => new Date(now.getTime() - daysAgo * DAY);

  async function session(userId: string, now: Date, o: { expiresDaysAgo?: number; expiresInDays?: number; revokedDaysAgo?: number; createdDaysAgo?: number; replacedBy?: string }): Promise<string> {
    const expires = o.expiresDaysAgo !== undefined ? at(now, o.expiresDaysAgo) : new Date(now.getTime() + (o.expiresInDays ?? 10) * DAY);
    const res = await pool.query(
      'INSERT INTO sessions(id, family_id, family_started_at, user_id, refresh_hash, expires_at, revoked_at, replaced_by, created_at) VALUES (gen_random_uuid(), gen_random_uuid(), now(), $1, $2, $3, $4, $5, $6) RETURNING id',
      [userId, randomUUID(), expires, o.revokedDaysAgo === undefined ? null : at(now, o.revokedDaysAgo), o.replacedBy ?? null, at(now, o.createdDaysAgo ?? 1)],
    );
    return (res.rows[0] as { id: string }).id;
  }

  const alive = async (table: string, ids: string[]): Promise<string[]> =>
    ((await pool.query(`SELECT id FROM ${table} WHERE id = ANY($1)`, [ids])).rows as { id: string }[]).map((r) => r.id);

  async function generation(userId: string, createdAt: Date): Promise<string> {
    const res = await pool.query(
      "INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, created_at) VALUES ($1, 'insight', 'normal', 'openai', 'm', $2) RETURNING id",
      [userId, createdAt],
    );
    return (res.rows[0] as { id: string }).id;
  }

  it('purges sessions that expired or were revoked more than 30 days ago, and only those', async () => {
    const now = new Date();
    const u = await newUser();
    const live = await session(u, now, { expiresInDays: 20, createdDaysAgo: 100 }); // old but alive: age alone never purges
    const expired31 = await session(u, now, { expiresDaysAgo: 31 });
    const expired29 = await session(u, now, { expiresDaysAgo: 29 });
    const expiredJustPast = await session(u, now, { expiresDaysAgo: 30.001 });
    const expiredJustInside = await session(u, now, { expiresDaysAgo: 29.999 });
    const revoked31 = await session(u, now, { revokedDaysAgo: 31, expiresInDays: 5 });
    const revoked29 = await session(u, now, { revokedDaysAgo: 29, expiresInDays: 5 });
    const revokedRecentlyExpiredLongAgo = await session(u, now, { revokedDaysAgo: 1, expiresDaysAgo: 40 }); // expired long ago: dead for > 30 days
    // A kept revoked session pointing at a purged one, and a purged one pointing at a live one.
    const successor = await session(u, now, { expiresInDays: 20 });
    const rotatedLongAgo = await session(u, now, { revokedDaysAgo: 45, expiresInDays: 1, replacedBy: successor });

    const all = [live, expired31, expired29, expiredJustPast, expiredJustInside, revoked31, revoked29, revokedRecentlyExpiredLongAgo, successor, rotatedLongAgo];
    const result = await runRetention(pool, { now });
    expect(result.rows.sessions).toBeGreaterThanOrEqual(5);
    expect((await alive('sessions', all)).sort()).toEqual([live, expired29, expiredJustInside, revoked29, successor].sort());
    expect(result.cutoffs.sessions).toBe(at(now, 30).toISOString());
  });

  it('purges AI history older than AI_HISTORY_RETENTION_DAYS (default 90): older goes, the boundary and newer stay', async () => {
    const now = new Date();
    const u = await newUser();
    const rows = {
      veryOld: await generation(u, at(now, 400)),
      old91: await generation(u, at(now, 91)),
      justPast: await generation(u, new Date(at(now, 90).getTime() - 1)),
      boundary: await generation(u, at(now, 90)),
      inside89: await generation(u, at(now, 89)),
      today: await generation(u, now),
    };
    const result = await runRetention(pool, { now });
    expect(result.rows.aiGenerations).toBeGreaterThanOrEqual(3);
    expect((await alive('ai_generations', Object.values(rows))).sort()).toEqual([rows.boundary, rows.inside89, rows.today].sort());
    expect(result.cutoffs.aiGenerations).toBe(at(now, 90).toISOString());
  });

  it('honours a shorter history window', async () => {
    const now = new Date();
    const u = await newUser();
    const old31 = await generation(u, at(now, 31));
    const inside29 = await generation(u, at(now, 29));
    await runRetention(pool, { now, aiHistoryDays: 30 });
    expect(await alive('ai_generations', [old31, inside29])).toEqual([inside29]);
  });

  it('purges AI quota counters older than 7 days (UTC days)', async () => {
    const now = new Date('2026-10-13T00:30:00Z');
    const u = await newUser();
    const days = ['2026-09-01', '2026-10-05', '2026-10-06', '2026-10-12', '2026-10-13'];
    for (const day of days) await pool.query('INSERT INTO ai_quota_usage(user_id, day, used) VALUES ($1, $2, 1)', [u, day]);
    const result = await runRetention(pool, { now });
    expect(result.cutoffs.aiQuotaDay).toBe('2026-10-06');
    const left = (await pool.query("SELECT to_char(day, 'YYYY-MM-DD') AS day FROM ai_quota_usage WHERE user_id = $1 ORDER BY day", [u])).rows.map((r: { day: string }) => r.day);
    expect(left).toEqual(['2026-10-06', '2026-10-12', '2026-10-13']);
    expect(result.rows.aiQuotaUsage).toBeGreaterThanOrEqual(2);
  });

  it('leaves accounts, devices, daily aggregates and settings alone', async () => {
    const now = new Date();
    const u = await newUser();
    const device = (await pool.query("INSERT INTO devices(user_id, installation_id, platform, created_at, last_seen_at) VALUES ($1, 'retention-install-1', 'ios', $2, $2) RETURNING id", [u, at(now, 800)])).rows[0] as { id: string };
    await pool.query("INSERT INTO daily_usage(user_id, device_id, date, currency) VALUES ($1, $2, '2016-01-01', 'PLN')", [u, device.id]);
    await pool.query('INSERT INTO user_settings(user_id) VALUES ($1)', [u]);
    await pool.query('UPDATE users SET created_at = $2, updated_at = $2 WHERE id = $1', [u, at(now, 900)]);
    await runRetention(pool, { now });
    const count = async (table: string) => (await pool.query(`SELECT count(*)::int AS n FROM ${table} WHERE user_id = $1`, [u])).rows[0].n as number;
    expect(await count('devices')).toBe(1);
    expect(await count('daily_usage')).toBe(1);
    expect(await count('user_settings')).toBe(1);
    expect((await pool.query('SELECT count(*)::int AS n FROM users WHERE id = $1', [u])).rows[0].n).toBe(1);
  });

  it('dry run counts but deletes nothing; a real run is idempotent', async () => {
    const now = new Date();
    const u = await newUser();
    const old = [await generation(u, at(now, 200)), await generation(u, at(now, 201))];
    const dead = await session(u, now, { revokedDaysAgo: 60 });
    const dry = await runRetention(pool, { now, dryRun: true });
    expect(dry.dryRun).toBe(true);
    expect(dry.rows.aiGenerations).toBeGreaterThanOrEqual(2);
    expect(dry.rows.sessions).toBeGreaterThanOrEqual(1);
    expect((await alive('ai_generations', old)).length).toBe(2);
    expect((await alive('sessions', [dead])).length).toBe(1);

    const first = await runRetention(pool, { now });
    expect(first.rows.aiGenerations).toBeGreaterThanOrEqual(2);
    expect(await alive('ai_generations', old)).toEqual([]);
    expect(await alive('sessions', [dead])).toEqual([]);
    const second = await runRetention(pool, { now });
    expect(second.rows).toEqual({ aiGenerations: 0, sessions: 0, aiQuotaUsage: 0, loginThrottle: 0 });
  });

  it('deletes in batches until nothing is left', async () => {
    const now = new Date();
    const u = await newUser();
    const ids: string[] = [];
    for (let i = 0; i < 25; i++) ids.push(await generation(u, at(now, 120 + i)));
    const result = await runRetention(pool, { now, batchSize: 10 });
    expect(result.rows.aiGenerations).toBeGreaterThanOrEqual(25);
    expect(await alive('ai_generations', ids)).toEqual([]);
  });

  it('rejects nonsense options instead of purging with them', async () => {
    await expect(runRetention(pool, { aiHistoryDays: 0 })).rejects.toThrow(/aiHistoryDays/);
    await expect(runRetention(pool, { batchSize: 0 })).rejects.toThrow(/batchSize/);
  });

  it('runs as a command: `node --conditions=development --import tsx src/scripts/retention.ts --dry-run` prints one JSON result', async () => {
    const env = { ...process.env, DATABASE_URL, AI_HISTORY_RETENTION_DAYS: '90' };
    const { stdout } = await run(process.execPath, ['--conditions=development', '--import', 'tsx', 'src/scripts/retention.ts', '--dry-run'], { cwd: apiRoot, env });
    const result = JSON.parse(stdout.trim()) as { dryRun: boolean; rows: Record<string, number>; cutoffs: Record<string, string> };
    expect(result.dryRun).toBe(true);
    expect(Object.keys(result.rows).sort()).toEqual(['aiGenerations', 'aiQuotaUsage', 'loginThrottle', 'sessions']);
    expect(result.cutoffs.aiGenerations).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  }, 30_000);

  it('the command fails with a clear message when DATABASE_URL is missing', async () => {
    const env = { ...process.env };
    delete env.DATABASE_URL;
    await expect(run(process.execPath, ['--conditions=development', '--import', 'tsx', 'src/scripts/retention.ts'], { cwd: apiRoot, env })).rejects.toMatchObject({
      code: 1,
      stderr: expect.stringContaining('DATABASE_URL'),
    });
  }, 30_000);
});
