import { describe, expect, it } from 'vitest';

import {
  estimateCost,
  modelPriceFor,
  PRICE_PER_MILLION_USD,
  ProviderError,
  type AIGatewayError,
  type AIGenerationResult,
  type SpendLedger,
  type SpendReservationResult,
  worstCaseCostUsd,
} from '../src/index.js';
import { ctx, gatewayInput as input } from './helpers/doubles.js';
import { httpError, scripted, setup } from './helpers/gateway.js';

/** A ledger with the real contract: an atomic check-and-hold against limits, settle adjusts by the difference. */
function fakeLedger(limitUsd = Infinity) {
  const state = { held: 0, reserves: [] as number[], settles: [] as { actual: number; billed: boolean }[] };
  const ledger: SpendLedger = {
    async reserve({ estimateUsd }): Promise<SpendReservationResult> {
      state.reserves.push(estimateUsd);
      if (state.held + estimateUsd > limitUsd) return { ok: false, exceeded: 'daily' };
      state.held += estimateUsd;
      return {
        ok: true,
        reservation: {
          settle: async (actual, billed) => {
            state.settles.push({ actual, billed });
            state.held += (billed ? actual : 0) - estimateUsd;
          },
        },
      };
    },
  };
  return { ledger, state };
}

const silentResult = (): AIGenerationResult => ({ providerId: 'google', model: 'google-mock', text: 'prose', inputTokens: 0, outputTokens: 0, usageReported: false, latencyMs: 1 });

describe('every provider call is held on the ledger and settled (D-01, D-06)', () => {
  it('a delivered answer: the worst case is held first, the real cost is settled', async () => {
    const { ledger, state } = fakeLedger();
    const { gateway, providers } = setup({ ledger });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(state.reserves).toHaveLength(1);
    expect(state.settles).toEqual([{ actual: r.usage.estimatedCostUsd, billed: true }]);
    expect(state.reserves[0]!).toBeGreaterThanOrEqual(r.usage.estimatedCostUsd);
    expect(providers.google.calls).toHaveLength(1);
  });

  it('a billed but rejected answer (prose instead of JSON) is booked and reported as billed', async () => {
    const { ledger, state } = fakeLedger();
    const { providers, gateway } = setup({ ledger });
    providers.google.set({ text: 'Sure! Here is a thought in plain prose, not JSON.' });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.code).toBe('all_providers_failed');
    expect(e.billed).toHaveLength(1);
    expect(e.billed[0]).toMatchObject({ providerId: 'google', kind: 'invalid_output', usageReported: true });
    expect(e.billed[0]!.costUsd).toBeGreaterThan(0);
    expect(state.settles).toEqual([{ actual: e.billed[0]!.costUsd, billed: true }]);
  });

  it('a rejected answer without any usage is booked at the worst case, never at $0 (D-07)', async () => {
    const { ledger, state } = fakeLedger();
    const { providers, gateway } = setup({ ledger });
    providers.google.generate = async () => silentResult();
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.billed[0]).toMatchObject({ costBasis: 'conservative_estimate', usageReported: false });
    expect(e.billed[0]!.costUsd).toBeGreaterThan(0);
    expect(state.settles[0]).toMatchObject({ billed: true });
  });

  it.each([
    ['no connection', new ProviderError('google', 'down', undefined)],
    ['HTTP 401', httpError('google', 401)],
    ['HTTP 429', httpError('google', 429)],
    ['HTTP 503', httpError('google', 503)],
  ])('%s: provably unbilled, the hold is returned and nothing is reported as billed', async (_name, failure) => {
    const { ledger, state } = fakeLedger();
    const { providers, gateway } = setup({ ledger, fallback: { enabled: false }, maxRetries: 0 });
    providers.google.set({ fail: failure });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.billed).toEqual([]);
    expect(state.settles).toEqual([{ actual: 0, billed: false }]);
    expect(state.held).toBeCloseTo(0, 10);
  });

  it('a retry after a transient failure holds again: two holds, the first returned, the second settled', async () => {
    const { ledger, state } = fakeLedger();
    const { providers, gateway } = setup({ ledger, maxRetries: 1 });
    const google = scripted('google', [httpError('google', 503), 'ok']);
    providers.google.generate = google.generate.bind(google);
    await gateway.generate('insight', 'normal', input, ctx);
    expect(state.reserves).toHaveLength(2);
    expect(state.settles[0]).toEqual({ actual: 0, billed: false });
    expect(state.settles[1]!.billed).toBe(true);
  });
});

describe('the ledger decides before the money is spent', () => {
  it('a call that does not fit under the limit is not made: budget_exceeded', async () => {
    const { ledger } = fakeLedger(0);
    const { providers, gateway } = setup({ ledger });
    await expect(gateway.generate('insight', 'normal', input, ctx)).rejects.toMatchObject({ code: 'budget_exceeded', billed: [] });
    expect(Object.values(providers).every((p) => p.calls.length === 0)).toBe(true);
  });

  it('a burst cannot overshoot: ten concurrent calls, room for three -> exactly three provider calls', async () => {
    // Size the limit from a probe call so that exactly three holds fit.
    const probe = fakeLedger();
    const p = setup({ ledger: probe.ledger });
    await p.gateway.generate('insight', 'normal', input, ctx);
    const hold = probe.state.reserves[0]!;
    const { ledger } = fakeLedger(hold * 3.5);
    const { providers, gateway } = setup({ ledger });
    const results = await Promise.allSettled(Array.from({ length: 10 }, () => gateway.generate('insight', 'normal', input, ctx)));
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    expect(ok).toBe(3);
    expect(Object.values(providers).reduce((n, pr) => n + pr.calls.length, 0)).toBe(3);
    for (const r of results) if (r.status === 'rejected') expect((r.reason as AIGatewayError).code).toBe('budget_exceeded');
  });

  it('a ledger that cannot be reached stops the call (fails closed), and so does one that hangs', async () => {
    const broken: SpendLedger = { reserve: () => Promise.reject(new Error('db down SENTINEL-DB')) };
    const hanging: SpendLedger = { reserve: () => new Promise(() => undefined) };
    for (const ledger of [broken, hanging]) {
      const { providers, gateway } = setup({ ledger, ledgerTimeoutMs: 20 });
      await expect(gateway.generate('insight', 'normal', input, ctx)).rejects.toMatchObject({ code: 'budget_unavailable', billed: [] });
      expect(Object.values(providers).every((pr) => pr.calls.length === 0)).toBe(true);
    }
  });

  it('a failing settle leaves the hold booked (over-counts) and does not fail the answer', async () => {
    const ledger: SpendLedger = {
      reserve: async () => ({ ok: true, reservation: { settle: () => Promise.reject(new Error('db down')) } }),
    };
    const { gateway } = setup({ ledger });
    await expect(gateway.generate('insight', 'normal', input, ctx)).resolves.toMatchObject({ providerId: 'google' });
  });
});

describe('prices (D-07)', () => {
  const prices = { 'model-a': { input: 1, output: 4 }, 'model-b': { input: 10, output: 40 } };

  it('a dated snapshot is priced as its model, a different variant is not', () => {
    expect(modelPriceFor(prices, 'model-a-2026-01-15')).toEqual(prices['model-a']);
    expect(modelPriceFor(prices, 'model-a-20260115')).toEqual(prices['model-a']);
    expect(modelPriceFor(prices, 'model-a-mini')).toBeUndefined();
    expect(modelPriceFor(prices, 'model-a-pro-2026-01-15')).toBeUndefined();
    expect(modelPriceFor(prices, 'model-a')).toEqual(prices['model-a']);
    // and so an unpriced variant falls back to the provider's flat price, flagged as such
    const e = estimateCost({ providerId: 'openai', model: 'model-a-mini', inputTokens: 1000, outputTokens: 1000, modelPrices: prices });
    expect(e.basis).toBe('provider_estimate');
  });

  it('the worst case uses the dearest price that could apply; a known model its own', () => {
    const flat = PRICE_PER_MILLION_USD.openai;
    const base = { providerId: 'openai' as const, promptChars: 3_000, maxOutputTokens: 200 };
    const noPrices = worstCaseCostUsd(base);
    expect(noPrices).toBeCloseTo((1000 * flat.input + 200 * flat.output) / 1e6, 6);
    const withPrices = worstCaseCostUsd({ ...base, modelPrices: prices });
    expect(withPrices).toBeCloseTo((1000 * 10 + 200 * 40) / 1e6, 6); // model-b is the dearest
    expect(worstCaseCostUsd({ ...base, modelPrices: prices, model: 'model-a' })).toBeCloseTo((1000 * 1 + 200 * 4) / 1e6, 6);
  });
});
