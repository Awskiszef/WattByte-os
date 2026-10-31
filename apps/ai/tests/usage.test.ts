// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import { AI_PROVIDER_IDS, estimateCost, estimateCostUsd, MemoryUsageSink, PRICE_PER_MILLION_USD, type AIProviderId, type UsageRecord } from '../src/index.js';

describe('price table', () => {
  it('has a finite, positive price for every provider', () => {
    for (const id of AI_PROVIDER_IDS) {
      const p = PRICE_PER_MILLION_USD[id];
      expect(Number.isFinite(p.input) && p.input > 0, id).toBe(true);
      expect(Number.isFinite(p.output) && p.output > 0, id).toBe(true);
    }
  });
});

describe('estimateCost arithmetic', () => {
  it.each<[AIProviderId, number, number, number]>([
    // (input * in$ + output * out$) / 1M
    ['openai', 1_000_000, 0, 0.4],
    ['openai', 0, 1_000_000, 1.6],
    ['openai', 1000, 500, 0.0012],
    ['anthropic', 1000, 500, 0.0105],
    ['google', 290, 61, 0.00024], // 239.5e-6 rounds half up to 6 decimals
    ['xai', 2_000_000, 4_000_000, 28], // 2 x $2 + 4 x $6
    ['openai', 0, 0, 0],
  ])('%s: %i in + %i out = $%s', (id, input, output, usd) => {
    const e = estimateCost({ providerId: id, model: 'any', inputTokens: input, outputTokens: output });
    expect(e.usd).toBeCloseTo(usd, 9);
    expect(e.basis).toBe('provider_estimate');
  });

  it('rounds to 6 decimals, the precision of the numeric(12,6) column', () => {
    const e = estimateCost({ providerId: 'openai', model: 'm', inputTokens: 1, outputTokens: 1 }); // 2.0e-6 exactly
    expect(e.usd).toBe(0.000002);
    expect(estimateCost({ providerId: 'openai', model: 'm', inputTokens: 1, outputTokens: 0 }).usd).toBe(0); // 4e-7 rounds away
  });

  it('is monotonic in both token counts', () => {
    const base = estimateCost({ providerId: 'anthropic', model: 'm', inputTokens: 100, outputTokens: 100 }).usd;
    expect(estimateCost({ providerId: 'anthropic', model: 'm', inputTokens: 200, outputTokens: 100 }).usd).toBeGreaterThan(base);
    expect(estimateCost({ providerId: 'anthropic', model: 'm', inputTokens: 100, outputTokens: 200 }).usd).toBeGreaterThan(base);
  });
});

describe('the provider\'s own figure beats every estimate', () => {
  it('a reported charge is used as is (rounded to the column precision) and labelled provider_reported', () => {
    expect(estimateCost({ providerId: 'xai', model: 'm', inputTokens: 1000, outputTokens: 500, reportedCostUsd: 0.0037756 })).toEqual({ usd: 0.003776, basis: 'provider_reported' });
  });

  it('beats a configured model price', () => {
    const e = estimateCost({ providerId: 'xai', model: 'm', inputTokens: 1000, outputTokens: 500, reportedCostUsd: 0.5, modelPrices: { m: { input: 100, output: 100 } } });
    expect(e).toEqual({ usd: 0.5, basis: 'provider_reported' });
  });

  it('is known even when the token counts are not (a free call would not carry a charge)', () => {
    expect(estimateCost({ providerId: 'xai', model: 'm', inputTokens: 0, outputTokens: 0, usageReported: false, reportedCostUsd: 0.25 })).toEqual({ usd: 0.25, basis: 'provider_reported' });
  });

  it('a reported zero is a real zero, not "unknown"', () => {
    expect(estimateCost({ providerId: 'xai', model: 'm', inputTokens: 5, outputTokens: 5, reportedCostUsd: 0 })).toEqual({ usd: 0, basis: 'provider_reported' });
  });

  it.each([NaN, Infinity, -1])('a nonsensical reported charge (%s) is ignored in favour of the estimate', (bad) => {
    expect(estimateCost({ providerId: 'openai', model: 'm', inputTokens: 1000, outputTokens: 500, reportedCostUsd: bad })).toEqual({ usd: 0.0012, basis: 'provider_estimate' });
  });
});

describe('unknown cost is reported as unknown, never as a silent 0', () => {
  it('unreported usage -> basis unknown (cost 0 is then not a claim that the call was free)', () => {
    expect(estimateCost({ providerId: 'openai', model: 'm', inputTokens: 0, outputTokens: 0, usageReported: false })).toEqual({ usd: 0, basis: 'unknown' });
    // reported 0/0 is a real (tiny) cost, distinguishable from unknown
    expect(estimateCost({ providerId: 'openai', model: 'm', inputTokens: 0, outputTokens: 0, usageReported: true }).basis).toBe('provider_estimate');
  });

  it.each([NaN, Infinity, -Infinity, -1])('invalid token count %s -> unknown, never NaN/Infinity/negative', (bad) => {
    for (const [i, o] of [[bad, 5], [5, bad]] as const) {
      const e = estimateCost({ providerId: 'google', model: 'm', inputTokens: i, outputTokens: o });
      expect(e).toEqual({ usd: 0, basis: 'unknown' });
    }
  });

  it('an unknown model does not crash: it is priced at the provider figure and labelled as such', () => {
    const e = estimateCost({ providerId: 'anthropic', model: 'brand-new-model-9000', inputTokens: 1000, outputTokens: 500, modelPrices: { 'other-model': { input: 1, output: 1 } } });
    expect(e).toEqual({ usd: 0.0105, basis: 'provider_estimate' });
  });

  it('a provider without a price table entry (JS caller, corrupted id) is unknown rather than a crash', () => {
    const e = estimateCost({ providerId: 'mystery' as unknown as AIProviderId, model: 'm', inputTokens: 10, outputTokens: 10 });
    expect(e).toEqual({ usd: 0, basis: 'unknown' });
  });

  it('a corrupted per-model price is ignored in favour of unknown, not NaN', () => {
    const e = estimateCost({ providerId: 'openai', model: 'm', inputTokens: 10, outputTokens: 10, modelPrices: { m: { input: NaN, output: 1 } } });
    expect(e).toEqual({ usd: 0, basis: 'unknown' });
  });
});

describe('per-model prices', () => {
  const modelPrices = { 'model-a': { input: 10, output: 20 }, 'model-a-mini': { input: 1, output: 2 } };

  it('use the exact model name', () => {
    expect(estimateCost({ providerId: 'openai', model: 'model-a', inputTokens: 1_000_000, outputTokens: 1_000_000, modelPrices })).toEqual({ usd: 30, basis: 'model_price' });
  });

  it('match a dated snapshot of a configured model, longest name wins', () => {
    expect(estimateCost({ providerId: 'openai', model: 'model-a-2026-01-01', inputTokens: 1_000_000, outputTokens: 0, modelPrices }).usd).toBe(10);
    expect(estimateCost({ providerId: 'openai', model: 'model-a-mini-2026-01-01', inputTokens: 1_000_000, outputTokens: 0, modelPrices }).usd).toBe(1);
  });

  it('do not match a different model that merely starts with the same letters', () => {
    expect(estimateCost({ providerId: 'openai', model: 'model-ab', inputTokens: 1_000_000, outputTokens: 0, modelPrices }).basis).toBe('provider_estimate');
  });

  it('cannot be hijacked through prototype keys', () => {
    expect(estimateCost({ providerId: 'openai', model: '__proto__', inputTokens: 1, outputTokens: 1, modelPrices: {} }).basis).toBe('provider_estimate');
    expect(estimateCost({ providerId: 'openai', model: 'constructor', inputTokens: 1, outputTokens: 1, modelPrices: {} }).basis).toBe('provider_estimate');
  });
});

describe('estimateCostUsd (provider-level convenience)', () => {
  it('matches estimateCost for valid counts', () => {
    expect(estimateCostUsd('openai', 1000, 500)).toBe(0.0012);
  });

  it('throws on invalid counts instead of pricing them as 0', () => {
    expect(() => estimateCostUsd('openai', NaN, 1)).toThrow(RangeError);
    expect(() => estimateCostUsd('openai', 1, -1)).toThrow(RangeError);
  });
});

describe('MemoryUsageSink', () => {
  it('keeps what it is given', async () => {
    const sink = new MemoryUsageSink();
    const record = { userRef: 'u' } as UsageRecord;
    await sink.record(record);
    expect(sink.records).toEqual([record]);
  });
});
