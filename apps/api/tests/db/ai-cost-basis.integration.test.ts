import type { MockProvider } from '@wattbyte/ai';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { sampleInput } from '../helpers.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

/**
 * A provider that sends no token counts used to be stored as '0 tokens, $0', indistinguishable from a free call.
 * The database now records HOW the cost was derived (migration 0004).
 */
describe.skipIf(!DATABASE_URL)('AI cost basis (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ AI_FREE_DAILY_LIMIT: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const generate = (token: string) =>
    ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: { authorization: `Bearer ${token}` }, payload: { input: sampleInput } });

  it('stores cost_basis and usage_reported next to the tokens and the cost', async () => {
    const reg = await register(ctx.app, uniqueEmail('cost-basis'));
    expect((await generate(reg.tokens.accessToken)).statusCode).toBe(200);
    const known = (await ctx.pool.query('SELECT input_tokens, estimated_cost_usd, cost_basis, usage_reported FROM ai_generations WHERE user_id = $1', [reg.user.id])).rows[0];
    expect(known.usage_reported).toBe(true);
    expect(known.input_tokens).toBeGreaterThan(0);
    expect(['model_price', 'provider_estimate']).toContain(known.cost_basis);
  });

  it('a call without token usage is recorded as unknown cost, not as a free call', async () => {
    const reg = await register(ctx.app, uniqueEmail('cost-unknown'));
    const originals = ctx.providers.map((p) => p.generate.bind(p));
    ctx.providers.forEach((p: MockProvider, i) => {
      const original = originals[i]!;
      p.generate = async (request) => {
        const result = await original(request);
        // What every real adapter returns when the provider's answer carries no usage block.
        return { ...result, inputTokens: 0, outputTokens: 0, usageReported: false };
      };
    });
    try {
      expect((await generate(reg.tokens.accessToken)).statusCode).toBe(200);
    } finally {
      ctx.providers.forEach((p, i) => (p.generate = originals[i]!));
    }
    const row = (await ctx.pool.query('SELECT input_tokens, output_tokens, estimated_cost_usd, cost_basis, usage_reported FROM ai_generations WHERE user_id = $1', [reg.user.id])).rows[0];
    expect(row.usage_reported).toBe(false);
    expect(row.cost_basis).toBe('unknown');
    expect(Number(row.estimated_cost_usd)).toBe(0);
    expect(row.input_tokens).toBe(0);
  });
});
