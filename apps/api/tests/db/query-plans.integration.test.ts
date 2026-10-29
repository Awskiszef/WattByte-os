import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { schemaUrl } from '../cloud-support.js';
import { DATABASE_URL } from './helpers.js';

vi.setConfig({ testTimeout: 120_000, hookTimeout: 120_000 });

/**
 * C-02, C-05: the queries that used to scan whole tables use an index. The plans are read with EXPLAIN on a table that is
 * big enough for the planner to prefer an index (generated rows, ANALYZE), in a schema of its own.
 */
const SCHEMA = `wb_plans_${process.pid}_${Date.now().toString(36)}`;

describe.skipIf(!DATABASE_URL)('query plans (PostgreSQL)', () => {
  let admin: pg.Pool;
  let db: pg.Pool;
  let probeUser: string;
  let probeDevice: string;
  let probeSession: string;

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    await admin.query(`CREATE SCHEMA ${SCHEMA}`);
    await migrate(schemaUrl(SCHEMA));
    db = new pg.Pool({ connectionString: schemaUrl(SCHEMA), max: 2 });
    await db.query(`INSERT INTO users(email, password_hash) SELECT 'user-' || g || '@plans.test', 'x' FROM generate_series(1, 30000) g`);
    await db.query(`INSERT INTO devices(user_id, installation_id, platform) SELECT id, 'install-' || row_number() OVER (), 'android' FROM users`);
    await db.query(
      `INSERT INTO sessions(id, family_id, family_started_at, user_id, refresh_hash, expires_at, revoked_at, replaced_by)
       SELECT gen_random_uuid(), gen_random_uuid(), now(), u.id, 'h-' || u.id || '-' || n, now() + interval '30 days', NULL, NULL
       FROM users u, generate_series(1, 2) n`,
    );
    await db.query(
      `INSERT INTO daily_usage(user_id, device_id, date, mobile_bytes, wifi_bytes, charged_wh, wall_wh, charging_sessions, estimated_cost, currency)
       SELECT d.user_id, d.id, DATE '2026-01-01' + n, 1, 1, 1, 1, 0, 0, 'PLN' FROM devices d, generate_series(0, 4) n`,
    );
    await db.query(
      `INSERT INTO charging_summaries(user_id, device_id, started_at, ended_at, start_percent, end_percent)
       SELECT d.user_id, d.id, TIMESTAMPTZ '2026-01-01' + n * interval '1 day', TIMESTAMPTZ '2026-01-01' + n * interval '1 day' + interval '1 hour', 10, 80 FROM devices d, generate_series(0, 2) n`,
    );
    await db.query(`ANALYZE`);
    probeUser = (await db.query(`SELECT id FROM users ORDER BY email LIMIT 1 OFFSET 12345`)).rows[0].id as string;
    probeDevice = (await db.query(`SELECT id FROM devices WHERE user_id = $1`, [probeUser])).rows[0].id as string;
    probeSession = (await db.query(`SELECT id FROM sessions WHERE user_id = $1 LIMIT 1`, [probeUser])).rows[0].id as string;
  });

  afterAll(async () => {
    await db?.end();
    await admin?.query(`DROP SCHEMA IF EXISTS ${SCHEMA} CASCADE`);
    await admin?.end();
  });

  const plan = async (sql: string, params: unknown[]): Promise<string> =>
    (await db.query(`EXPLAIN ${sql}`, params)).rows.map((r) => r['QUERY PLAN'] as string).join('\n');

  it('login: the e-mail lookup uses users_email_key, not a sequential scan (C-05)', async () => {
    const p = await plan('SELECT * FROM users WHERE lower(email) = lower($1)', ['User-12345@plans.test']);
    expect(p).toContain('users_email_key');
    expect(p).not.toMatch(/Seq Scan on users/);
  });

  it('the repository query for login is exactly that predicate (a regression to `email = lower($1)` fails here)', async () => {
    const { PostgresRepositories } = await import('../../src/database/postgres.js');
    const repos = new PostgresRepositories(schemaUrl(SCHEMA), { max: 1 });
    try {
      expect((await repos.users.findByEmail('USER-77@PLANS.TEST'))?.email).toBe('user-77@plans.test'); // case-insensitive
      expect(await repos.users.findByEmail('nobody@plans.test')).toBeNull();
    } finally {
      await repos.close();
    }
    const source = (await import('node:fs')).readFileSync(new URL('../../src/database/postgres.ts', import.meta.url), 'utf8');
    expect(source).toContain('WHERE lower(email) = lower($1)');
  });

  it.each([
    ['the cascade of DELETE /me over sessions.user_id', 'DELETE FROM sessions WHERE user_id = $1', () => [probeUser], /sessions_user_id_idx/],
    ['the SET NULL of a deleted session (sessions.replaced_by)', 'UPDATE sessions SET replaced_by = NULL WHERE replaced_by = $1', () => [probeSession], /sessions_replaced_by_idx/],
    ['deleting a device over daily_usage.device_id', 'DELETE FROM daily_usage WHERE device_id = $1', () => [probeDevice], /daily_usage_device_idx/],
    ['deleting a device over charging_summaries.device_id', 'DELETE FROM charging_summaries WHERE device_id = $1', () => [probeDevice], /charging_summaries_device_idx/],
  ])('%s uses an index (C-02)', async (_name, sql, params, index) => {
    const p = await plan(sql, params());
    expect(p).toMatch(index);
    expect(p).not.toMatch(/Seq Scan on (sessions|daily_usage|charging_summaries)\b/);
  });

  it('the retention purge of sessions can use the expiry and revocation indexes (C-02)', async () => {
    const p = await plan('SELECT id FROM sessions WHERE expires_at < $1 OR revoked_at < $1', [new Date('2020-01-01')]);
    expect(p).toMatch(/sessions_expires_at_idx|sessions_revoked_at_idx/);
  });
});
