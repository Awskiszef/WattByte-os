import { cpSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { utcDayKey } from '../../src/modules/ai/service.js';
import { sampleInput } from '../helpers.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

const MIGRATIONS = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../src/database/migrations');

/**
 * What the budget limits are checked against (migration 0005): a table of daily totals per provider that is written
 * in the same statement as the answer's log row and holds no user id.
 */
describe.skipIf(!DATABASE_URL)('AI spend per day (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ AI_FREE_DAILY_LIMIT: '50' });
  });
  afterAll(() => closePgApp(ctx));

  const today = () => utcDayKey(new Date());
  const spendRows = async (provider: string, day = today()) =>
    (await ctx.pool.query('SELECT requests, cost_usd FROM ai_spend_daily WHERE day = $1 AND provider = $2', [day, provider])).rows[0] as { requests: number; cost_usd: string } | undefined;
  const generate = (token: string, path = 'insight') =>
    ctx.app.inject({ method: 'POST', url: `/api/v1/ai/${path}`, headers: { authorization: `Bearer ${token}` }, payload: { input: sampleInput } });
  const row = (userId: string, provider: string, over: Record<string, unknown> = {}) => ({
    userId,
    task: 'insight',
    mode: 'normal',
    provider,
    model: 'm',
    inputTokens: 10,
    outputTokens: 5,
    estimatedCostUsd: 0.25,
    costBasis: 'provider_estimate' as const,
    usageReported: true,
    latencyMs: 3,
    createdAt: new Date(),
    ...over,
  });

  it('an answer adds its cost to the day of its creation, per provider, together with the log row', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-a'));
    const before = (await spendRows('google')) ?? { requests: 0, cost_usd: '0' };
    expect((await generate(reg.tokens.accessToken)).statusCode).toBe(200);
    const logged = (await ctx.pool.query('SELECT estimated_cost_usd FROM ai_generations WHERE user_id = $1', [reg.user.id])).rows[0];
    const after = (await spendRows('google'))!;
    // At least this answer: other suites answer through the same provider in parallel and add to the same row. The exact
    // arithmetic is proved below with providers of their own (concurrency, UTC midnight, atomicity).
    expect(after.requests - before.requests).toBeGreaterThanOrEqual(1);
    expect(Number(after.cost_usd) - Number(before.cost_usd)).toBeGreaterThanOrEqual(Number(logged.estimated_cost_usd) - 1e-6);
  });

  it('spentUsd sums from the given UTC day on (inclusive), for one provider or all of them', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-b'));
    const probe = `probe-${process.pid}-${Date.now()}`;
    const yesterday = new Date(Date.now() - 86_400_000);
    await ctx.repos.ai.insert(row(reg.user.id, probe, { estimatedCostUsd: 1.5, createdAt: yesterday }));
    await ctx.repos.ai.insert(row(reg.user.id, probe, { estimatedCostUsd: 0.25 }));
    await ctx.repos.ai.insert(row(reg.user.id, `${probe}-other`, { estimatedCostUsd: 4 }));
    expect(await ctx.repos.ai.spentUsd(utcDayKey(yesterday), probe)).toBeCloseTo(1.75, 6);
    expect(await ctx.repos.ai.spentUsd(today(), probe)).toBeCloseTo(0.25, 6);
    expect(await ctx.repos.ai.spentUsd(utcDayKey(new Date(Date.now() + 86_400_000)), probe)).toBe(0);
    expect(await ctx.repos.ai.spentUsd(utcDayKey(yesterday))).toBeGreaterThanOrEqual(5.75);
  });

  it('a UTC midnight is a new day: the row lands on the UTC date of createdAt, whatever the server time zone', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-c'));
    const provider = `tz-${process.pid}-${Date.now()}`;
    await ctx.repos.ai.insert(row(reg.user.id, provider, { createdAt: new Date('2026-03-31T23:59:59.999Z') }));
    await ctx.repos.ai.insert(row(reg.user.id, provider, { createdAt: new Date('2026-04-01T00:00:00.000Z') }));
    expect((await spendRows(provider, '2026-03-31'))!.requests).toBe(1);
    expect((await spendRows(provider, '2026-04-01'))!.requests).toBe(1);
  });

  it('concurrent answers add up exactly: no lost update', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-d'));
    const provider = `race-${process.pid}-${Date.now()}`;
    await Promise.all(Array.from({ length: 40 }, () => ctx.repos.ai.insert(row(reg.user.id, provider, { estimatedCostUsd: 0.125 }))));
    const total = (await spendRows(provider))!;
    expect(total.requests).toBe(40);
    expect(Number(total.cost_usd)).toBeCloseTo(5, 6);
  });

  it('an answer that cannot be logged (the account is gone) is not counted either: both or neither', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-e'));
    const provider = `gone-${process.pid}-${Date.now()}`;
    await ctx.pool.query('DELETE FROM users WHERE id = $1', [reg.user.id]);
    await expect(ctx.repos.ai.insert(row(reg.user.id, provider))).rejects.toThrow();
    expect(await spendRows(provider)).toBeUndefined();
  });

  it('survives what erases the log: a user wiping their data, deleting the account, the retention purge', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-f'));
    const provider = `keep-${process.pid}-${Date.now()}`;
    await ctx.repos.ai.insert(row(reg.user.id, provider, { estimatedCostUsd: 2 }));
    const headers = { authorization: `Bearer ${reg.tokens.accessToken}` };
    expect((await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me/cloud-data', headers })).statusCode).toBeLessThan(300);
    expect((await ctx.pool.query('SELECT count(*)::int AS n FROM ai_generations WHERE user_id = $1', [reg.user.id])).rows[0].n).toBe(0);
    expect(Number((await spendRows(provider))!.cost_usd)).toBeCloseTo(2, 6);
    expect((await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers })).statusCode).toBeLessThan(300);
    expect(Number((await spendRows(provider))!.cost_usd)).toBeCloseTo(2, 6);
  });

  it('the table has no user id (so it is not personal data and needs no retention rule)', async () => {
    const cols = (await ctx.pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'ai_spend_daily' ORDER BY ordinal_position")).rows.map((r) => r.column_name);
    expect(cols).toEqual(['day', 'provider', 'requests', 'cost_usd']);
  });

  it('a charge reported by the provider is stored as such, with its exact amount', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-g'));
    ctx.providers.find((p) => p.id === 'google')!.generate = async (request) => ({
      providerId: 'google',
      model: 'google-mock',
      text: JSON.stringify({ title: 't', message: 'm', tone: request.mode, severity: 'info', emoji: '⚡' }),
      inputTokens: 100,
      outputTokens: 20,
      costUsd: 0.003776,
      latencyMs: 1,
    });
    expect((await generate(reg.tokens.accessToken)).statusCode).toBe(200);
    const stored = (await ctx.pool.query('SELECT estimated_cost_usd, cost_basis FROM ai_generations WHERE user_id = $1', [reg.user.id])).rows[0];
    expect(stored.cost_basis).toBe('provider_reported');
    expect(Number(stored.estimated_cost_usd)).toBe(0.003776);
  });

  it('the cost_basis constraint knows all four bases and nothing else', async () => {
    const reg = await register(ctx.app, uniqueEmail('spend-h'));
    for (const basis of ['provider_reported', 'model_price', 'provider_estimate', 'unknown'] as const) {
      await ctx.repos.ai.insert(row(reg.user.id, `basis-${basis}`, { costBasis: basis }));
    }
    await expect(ctx.repos.ai.insert(row(reg.user.id, 'basis-bad', { costBasis: 'made_up' }))).rejects.toThrow();
  });
});

/** The migration itself, on a database that already has history: it must carry it over, not start from zero. */
describe.skipIf(!DATABASE_URL)('migration 0005 on a database with AI history', () => {
  const name = `wb_mig_${process.pid}_${Date.now()}`;
  let admin: pg.Client;
  let url: string;
  let dir: string;

  beforeAll(async () => {
    const u = new URL(DATABASE_URL!);
    admin = new pg.Client({ connectionString: DATABASE_URL });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${name}`);
    u.pathname = `/${name}`;
    url = u.toString();
    dir = mkdtempSync(path.join(tmpdir(), 'wb-migrations-'));
    for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x < '0005')) cpSync(path.join(MIGRATIONS, f), path.join(dir, f));
  });
  afterAll(async () => {
    rmSync(dir, { recursive: true, force: true });
    await admin.query(`DROP DATABASE IF EXISTS ${name} WITH (FORCE)`);
    await admin.end();
  });

  it('backfills the daily totals from the existing log, keeps old rows valid, and accepts the new basis', async () => {
    expect(await migrate(url, dir)).toEqual(['0001_init.sql', '0002_ai_quota.sql', '0003_auto_setup.sql', '0004_ai_cost_basis.sql']);
    const db = new pg.Client({ connectionString: url });
    await db.connect();
    try {
      const user = (await db.query("INSERT INTO users(email, password_hash) VALUES ('mig@test.wattbyte', 'x') RETURNING id")).rows[0].id as string;
      const insert = (provider: string, cost: number, at: string, basis = 'provider_estimate') =>
        db.query(
          "INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, estimated_cost_usd, cost_basis, created_at) VALUES ($1, 'insight', 'normal', $2, 'm', $3, $4, $5)",
          [user, provider, cost, basis, at],
        );
      await insert('openai', 0.5, '2026-09-30T23:30:00Z');
      await insert('openai', 0.25, '2026-10-01T00:30:00Z');
      await insert('openai', 0.125, '2026-10-01T10:00:00Z', 'model_price');
      await insert('xai', 1, '2026-10-01T11:00:00Z', 'unknown');

      // 0005 is the first of whatever is still to apply (later migrations may exist; they run on this history too).
      const applied = await migrate(url);
      expect(applied[0]).toBe('0005_ai_spend.sql');

      const totals = (await db.query("SELECT day::text, provider, requests, cost_usd::float8 AS cost FROM ai_spend_daily ORDER BY day, provider")).rows;
      expect(totals).toEqual([
        { day: '2026-09-30', provider: 'openai', requests: 1, cost: 0.5 },
        { day: '2026-10-01', provider: 'openai', requests: 2, cost: 0.375 },
        { day: '2026-10-01', provider: 'xai', requests: 1, cost: 1 },
      ]);
      expect((await db.query('SELECT count(*)::int AS n FROM ai_generations')).rows[0].n).toBe(4);
      await db.query("INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, cost_basis) VALUES ($1, 'insight', 'normal', 'xai', 'm', 'provider_reported')", [user]);
      await expect(db.query("INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, cost_basis) VALUES ($1, 'insight', 'normal', 'xai', 'm', 'invented')", [user])).rejects.toThrow(/cost_basis/);
    } finally {
      await db.end();
    }
  });
});
