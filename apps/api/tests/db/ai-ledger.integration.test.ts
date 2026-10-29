import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { sampleInput } from '../helpers.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

/** The spend ledger against a real PostgreSQL: atomic limits, settle, and billed rejections end to end (D-01, D-06). */
describe.skipIf(!DATABASE_URL)('AI spend ledger (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ AI_FREE_DAILY_LIMIT: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const spent = (day: string, provider?: string) => ctx.repos.ai.spentUsd(day, provider);

  it('thirty concurrent holds against a provider limit of 10 USD: exactly ten of 1 USD succeed', async () => {
    const provider = `ledger-${randomUUID()}`;
    const day = '2099-05-17';
    const results = await Promise.all(
      Array.from({ length: 30 }, () => ctx.repos.ai.reserveSpend({ day, provider, usd: 1, limits: { providerDailyUsd: 10 } })),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(10);
    expect(results.filter((r) => !r.ok).every((r) => !r.ok && r.exceeded === 'provider')).toBe(true);
    expect(await spent(day, provider)).toBeCloseTo(10, 6);
  });

  it('the daily and monthly totals are enforced across providers; the right limit is named', async () => {
    const day = '2099-06-20';
    const a = `ledger-${randomUUID()}`;
    const b = `ledger-${randomUUID()}`;
    expect(await ctx.repos.ai.reserveSpend({ day, provider: a, usd: 3, limits: { dailyUsd: 5 } })).toEqual({ ok: true });
    expect(await ctx.repos.ai.reserveSpend({ day, provider: b, usd: 3, limits: { dailyUsd: 5 } })).toEqual({ ok: false, exceeded: 'daily' });
    // another day of the same month: the daily limit does not apply, the monthly one does
    expect(await ctx.repos.ai.reserveSpend({ day: '2099-06-21', provider: b, usd: 3, limits: { dailyUsd: 5, monthlyUsd: 5 } })).toEqual({ ok: false, exceeded: 'monthly' });
    expect(await ctx.repos.ai.reserveSpend({ day: '2099-06-21', provider: b, usd: 2, limits: { dailyUsd: 5, monthlyUsd: 5 } })).toEqual({ ok: true });
  });

  it('settling replaces the hold by the real cost; an unbilled call gives it all back; nothing goes below zero', async () => {
    const provider = `ledger-${randomUUID()}`;
    const day = '2099-07-01';
    await ctx.repos.ai.reserveSpend({ day, provider, usd: 0.5, limits: {} });
    await ctx.repos.ai.adjustSpend({ day, provider, deltaUsd: 0.02 - 0.5, deltaRequests: 0 }); // billed 0.02
    expect(await spent(day, provider)).toBeCloseTo(0.02, 6);
    await ctx.repos.ai.reserveSpend({ day, provider, usd: 0.5, limits: {} });
    await ctx.repos.ai.adjustSpend({ day, provider, deltaUsd: -0.5, deltaRequests: -1 }); // not billed
    expect(await spent(day, provider)).toBeCloseTo(0.02, 6);
    await ctx.repos.ai.adjustSpend({ day, provider, deltaUsd: -100, deltaRequests: -100 });
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
