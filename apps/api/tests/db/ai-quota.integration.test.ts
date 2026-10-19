import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { sampleInput } from '../helpers.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

describe.skipIf(!DATABASE_URL)('AI quota (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ AI_FREE_DAILY_LIMIT: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const generate = (token: string) =>
    ctx.app.inject({
      method: 'POST',
      url: '/api/v1/ai/insight',
      headers: { authorization: `Bearer ${token}` },
      payload: { input: sampleInput },
    });

  it('100 concurrent requests with limit 10 are accepted at most 10 times', async () => {
    const reg = await register(ctx.app, uniqueEmail('quota'));
    const results = await Promise.all(Array.from({ length: 100 }, () => generate(reg.tokens.accessToken)));
    const accepted = results.filter((r) => r.statusCode === 200).length;
    const limited = results.filter((r) => r.statusCode === 429 && r.json().error.code === 'ai_quota_exceeded').length;
    expect(accepted).toBe(10);
    expect(limited).toBe(90);
    const used = await ctx.pool.query('SELECT used FROM ai_quota_usage WHERE user_id = $1', [reg.user.id]);
    expect(used.rows[0].used).toBe(10);
    const logged = await ctx.pool.query('SELECT count(*)::int AS n FROM ai_generations WHERE user_id = $1', [reg.user.id]);
    expect(logged.rows[0].n).toBe(10);
  });

  it('a failed generation gives its slot back', async () => {
    const reg = await register(ctx.app, uniqueEmail('refund'));
    ctx.providers.forEach((p) => p.set({ fail: true }));
    try {
      const failed = await generate(reg.tokens.accessToken);
      expect(failed.statusCode).toBe(503);
    } finally {
      ctx.providers.forEach((p) => p.set({ fail: false }));
    }
    const used = await ctx.pool.query('SELECT used FROM ai_quota_usage WHERE user_id = $1', [reg.user.id]);
    expect(used.rows[0].used).toBe(0);
    const ok = await generate(reg.tokens.accessToken);
    expect(ok.statusCode).toBe(200);
    expect(ok.json().remainingToday).toBe(9);
  });

  it('a deleted account with a still valid token gets 401, and no provider is called', async () => {
    const reg = await register(ctx.app, uniqueEmail('gone'));
    const headers = { authorization: `Bearer ${reg.tokens.accessToken}` };
    expect((await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers })).statusCode).toBe(204);
    const calls = ctx.providers.reduce((n, p) => n + p.calls.length, 0);
    const ai = await generate(reg.tokens.accessToken);
    expect(ai.statusCode).toBe(401);
    expect(ctx.providers.reduce((n, p) => n + p.calls.length, 0)).toBe(calls);
    const dev = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers, payload: { installationId: 'install-1234', platform: 'ios' } });
    expect(dev.statusCode).toBe(401);
  });
});
