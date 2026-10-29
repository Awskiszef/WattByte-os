import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { sampleInput } from '../helpers.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

/** The spend ledger against a real PostgreSQL: atomic limits, settle, and billed rejections end to end (D-01, D-06). */
/** A UTC day nobody else writes to: the test database outlives runs, so fixed dates would accumulate across them. */
const uniqueMonth = (): { month: string; day: (n: number) => string } => {
  const year = 3000 + Math.floor(Math.random() * 6000);
  const month = String(1 + Math.floor(Math.random() * 12)).padStart(2, '0');
  return { month: `${year}-${month}`, day: (n) => `${year}-${month}-${String(n).padStart(2, '0')}` };
};

describe.skipIf(!DATABASE_URL)('AI spend ledger (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ AI_FREE_DAILY_LIMIT: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const spent = (day: string, provider?: string) => ctx.repos.ai.spentUsd(day, provider);

  it('thirty concurrent holds against a provider limit of 10 USD: exactly ten of 1 USD succeed', async () => {
    const provider = `ledger-${randomUUID()}`;
    const day = uniqueMonth().day(17);
    const results = await Promise.all(
      Array.from({ length: 30 }, () => ctx.repos.ai.reserveSpend({ day, provider, plan: 'premium', usd: 1, limits: { providerDailyUsd: 10 } })),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(10);
    expect(results.filter((r) => !r.ok).every((r) => !r.ok && r.exceeded === 'provider')).toBe(true);
    expect(await spent(day, provider)).toBeCloseTo(10, 6);
  });

  it('the daily and monthly totals are enforced across providers; the right limit is named', async () => {
    const m = uniqueMonth();
    const day = m.day(20);
    const a = `ledger-${randomUUID()}`;
    const b = `ledger-${randomUUID()}`;
    expect(await ctx.repos.ai.reserveSpend({ day, provider: a, plan: 'premium', usd: 3, limits: { dailyUsd: 5 } })).toEqual({ ok: true });
    expect(await ctx.repos.ai.reserveSpend({ day, provider: b, plan: 'premium', usd: 3, limits: { dailyUsd: 5 } })).toEqual({ ok: false, exceeded: 'daily' });
    // another day of the same month: the daily limit does not apply, the monthly one does
    expect(await ctx.repos.ai.reserveSpend({ day: m.day(21), provider: b, plan: 'premium', usd: 3, limits: { dailyUsd: 5, monthlyUsd: 5 } })).toEqual({ ok: false, exceeded: 'monthly' });
    expect(await ctx.repos.ai.reserveSpend({ day: m.day(21), provider: b, plan: 'premium', usd: 2, limits: { dailyUsd: 5, monthlyUsd: 5 } })).toEqual({ ok: true });
  });

  it('the free plan has its own daily limit: 20 concurrent holds of 1 USD against a free share of 6 USD -> exactly 6; premium is not affected', async () => {
    const day = uniqueMonth().day(10);
    const provider = `ledger-${randomUUID()}`;
    const results = await Promise.all(
      Array.from({ length: 20 }, () => ctx.repos.ai.reserveSpend({ day, provider, plan: 'free', usd: 1, limits: { planDailyUsd: 6 } })),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(6);
    expect(results.filter((r) => !r.ok).every((r) => !r.ok && r.exceeded === 'plan')).toBe(true);
    expect(await ctx.repos.ai.reserveSpend({ day, provider, plan: 'premium', usd: 1, limits: { planDailyUsd: 6 } })).toEqual({ ok: true });
    const free = (await ctx.pool.query("SELECT cost_usd FROM ai_spend_plan_daily WHERE day = $1 AND plan = 'free'", [day])).rows[0];
    expect(Number(free.cost_usd)).toBeCloseTo(6, 6);
    await ctx.repos.ai.adjustSpend({ day, provider, plan: 'free', deltaUsd: -2, deltaRequests: 0 });
    const after = (await ctx.pool.query("SELECT cost_usd FROM ai_spend_plan_daily WHERE day = $1 AND plan = 'free'", [day])).rows[0];
    expect(Number(after.cost_usd)).toBeCloseTo(4, 6);
  });

  it('settling replaces the hold by the real cost; an unbilled call gives it all back; nothing goes below zero', async () => {
    const provider = `ledger-${randomUUID()}`;
    const day = uniqueMonth().day(1);
    await ctx.repos.ai.reserveSpend({ day, provider, plan: 'premium', usd: 0.5, limits: {} });
    await ctx.repos.ai.adjustSpend({ day, provider, plan: 'premium', deltaUsd: 0.02 - 0.5, deltaRequests: 0 }); // billed 0.02
    expect(await spent(day, provider)).toBeCloseTo(0.02, 6);
    await ctx.repos.ai.reserveSpend({ day, provider, plan: 'premium', usd: 0.5, limits: {} });
    await ctx.repos.ai.adjustSpend({ day, provider, plan: 'premium', deltaUsd: -0.5, deltaRequests: -1 }); // not billed
    expect(await spent(day, provider)).toBeCloseTo(0.02, 6);
    await ctx.repos.ai.adjustSpend({ day, provider, plan: 'premium', deltaUsd: -100, deltaRequests: -100 });
    expect(await spent(day, provider)).toBe(0);
    const row = (await ctx.pool.query('SELECT requests, cost_usd FROM ai_spend_daily WHERE day = $1 AND provider = $2', [day, provider])).rows[0];
    expect(row.requests).toBe(0);
  });

  it('a billed but rejected answer through the HTTP route: 503, spend on the ledger, the quota slot stays used', async () => {
    const reg = await register(ctx.app, uniqueEmail('billed'));
    const original = ctx.providers.map((p) => p.generate.bind(p));
    ctx.providers.forEach((p, i) => {
      p.generate = async (request) => ({ ...(await original[i]!(request)), text: 'prose, not json' });
    });
    try {
      const before = await spent('1970-01-01');
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: { authorization: `Bearer ${reg.tokens.accessToken}` }, payload: { input: sampleInput } });
      expect(res.statusCode).toBe(503);
      expect(await spent('1970-01-01')).toBeGreaterThan(before);
      const used = (await ctx.pool.query('SELECT used FROM ai_quota_usage WHERE user_id = $1', [reg.user.id])).rows[0];
      expect(used.used).toBe(1);
      const logged = await ctx.pool.query('SELECT 1 FROM ai_generations WHERE user_id = $1', [reg.user.id]);
      expect(logged.rowCount).toBe(0); // nothing was delivered, so nothing is in the user's AI history
    } finally {
      ctx.providers.forEach((p, i) => (p.generate = original[i]!));
    }
  });
});
