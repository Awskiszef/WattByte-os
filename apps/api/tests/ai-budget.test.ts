import { AI_PROVIDER_IDS, MockProvider } from '@wattbyte/ai';
import { describe, expect, it } from 'vitest';

import { envWarnings, loadEnv } from '../src/config/env.js';
import { MemoryRepositories } from '../src/database/memory.js';
import { buildGateway, freePlanDailyUsd } from '../src/modules/ai/gateway.js';
import { AiService, utcDayKey } from '../src/modules/ai/service.js';
import { sampleInput } from './helpers.js';

const base = { NODE_ENV: 'production', DATABASE_URL: 'postgres://app:s3cr3t-db-pass@db.internal:5432/wattbyte', DATABASE_SSL: '1', TRUST_PROXY_HOPS: '1', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd' };
const openai = { OPENAI_API_KEY: 'sk-test-key-not-real', OPENAI_FAST_MODEL: 'model-fast', OPENAI_QUALITY_MODEL: 'model-quality' };
const prices = JSON.stringify({ 'model-fast': { input: 0.4, output: 1.6 }, 'model-quality': { input: 2, output: 8 } });

/** D-02, B-08, D-07: staging and production do not run real AI providers without a spend ceiling that is measured with real prices. */
describe.each(['staging', 'production'] as const)('%s with real AI providers', (appEnv) => {
  const env = { ...base, APP_ENV: appEnv, ...openai };

  it('refuses to start without AI_BUDGET_DAILY_USD, naming it', () => {
    expect(() => loadEnv(env)).toThrow(/AI_BUDGET_DAILY_USD must be set/);
  });

  it('refuses a budget measured with a flat provider price: every configured model needs an AI_MODEL_PRICES entry', () => {
    expect(() => loadEnv({ ...env, AI_BUDGET_DAILY_USD: '5' })).toThrow(/OPENAI_FAST_MODEL=model-fast has no entry in AI_MODEL_PRICES/);
    expect(() => loadEnv({ ...env, AI_BUDGET_DAILY_USD: '5', AI_MODEL_PRICES: JSON.stringify({ 'model-fast': { input: 1, output: 2 } }) })).toThrow(/OPENAI_QUALITY_MODEL=model-quality has no entry/);
    expect(loadEnv({ ...env, AI_BUDGET_DAILY_USD: '5', AI_MODEL_PRICES: prices }).AI_BUDGET_DAILY_USD).toBe(5);
  });

  it('a dated snapshot of a priced model counts as priced, a variant does not', () => {
    const dated = { ...env, OPENAI_FAST_MODEL: 'model-fast-2026-01-15', AI_BUDGET_DAILY_USD: '5', AI_MODEL_PRICES: prices };
    expect(loadEnv(dated).OPENAI_FAST_MODEL).toBe('model-fast-2026-01-15');
    expect(() => loadEnv({ ...dated, OPENAI_FAST_MODEL: 'model-fast-mini' })).toThrow(/no entry in AI_MODEL_PRICES/);
  });

  it('AI_BUDGET_UNLIMITED=1 is the conscious opt-out: it starts, and every boot says so', () => {
    const loaded = loadEnv({ ...env, AI_BUDGET_UNLIMITED: '1' });
    expect(loaded.AI_BUDGET_UNLIMITED).toBe('1');
    const old = process.env.OPENAI_API_KEY;
    process.env.OPENAI_API_KEY = openai.OPENAI_API_KEY;
    try {
      expect(envWarnings(loaded).join('\n')).toMatch(/AI_BUDGET_UNLIMITED=1: nothing in this application limits AI spend/);
    } finally {
      if (old === undefined) delete process.env.OPENAI_API_KEY;
      else process.env.OPENAI_API_KEY = old;
    }
  });

  it('the opt-out cannot be combined with limits (a contradiction is a mistake)', () => {
    expect(() => loadEnv({ ...env, AI_BUDGET_UNLIMITED: '1', AI_BUDGET_DAILY_USD: '5' })).toThrow(/contradicts/);
  });

  it('nothing is required when AI cannot spend: feature off, or no provider key', () => {
    expect(loadEnv({ ...env, FEATURE_AI: '0' }).FEATURE_AI).toBe('0');
    expect(loadEnv({ ...base, APP_ENV: appEnv }).FEATURE_AI).toBe('1');
  });
});

describe('development is not held to it', () => {
  it('real keys without a budget are fine locally', () => {
    expect(loadEnv({ NODE_ENV: 'development', JWT_SECRET: base.JWT_SECRET, ...openai }).AI_BUDGET_DAILY_USD).toBeUndefined();
  });
});

describe('the free plan gets a share of the budget, not the whole of it (A-01, D-05)', () => {
  it('the share is AI_BUDGET_FREE_DAILY_USD, else half of the daily budget, else none', () => {
    expect(freePlanDailyUsd({ AI_BUDGET_FREE_DAILY_USD: 1.5, AI_BUDGET_DAILY_USD: 10 })).toBe(1.5);
    expect(freePlanDailyUsd({ AI_BUDGET_FREE_DAILY_USD: undefined, AI_BUDGET_DAILY_USD: 10 })).toBe(5);
    expect(freePlanDailyUsd({ AI_BUDGET_FREE_DAILY_USD: undefined, AI_BUDGET_DAILY_USD: undefined })).toBeUndefined();
  });

  it('free accounts cannot use up the day: once the free share is spent, free callers are refused while premium callers are still served', async () => {
    const repos = new MemoryRepositories();
    const providers = AI_PROVIDER_IDS.map((id) => new MockProvider(id));
    // The share is sized from the worst-case hold of one call: it fits one call while next to nothing is spent, but not
    // once the real costs of the answers so far have accumulated.
    let hold = 0;
    const reserve = repos.ai.reserveSpend.bind(repos.ai);
    repos.ai.reserveSpend = async (r) => ((hold = r.usd), reserve(r));
    await buildGateway(loadEnv({ NODE_ENV: 'development', JWT_SECRET: base.JWT_SECRET }), repos, providers, { info: () => undefined, warn: () => undefined })
      .generate('insight', 'normal', sampleInput, { userRef: 'probe', plan: 'free', locale: 'en' });
    expect(hold).toBeGreaterThan(0);
    const share = hold * 3;
    const probeSpent = await repos.ai.spentUsd('1970-01-01');
    const loaded = loadEnv({ NODE_ENV: 'development', JWT_SECRET: base.JWT_SECRET, AI_BUDGET_DAILY_USD: '1', AI_BUDGET_FREE_DAILY_USD: String(share), AI_FREE_DAILY_LIMIT: '1000' });
    const gateway = buildGateway(loaded, repos, providers, { info: () => undefined, warn: () => undefined });
    const service = new AiService(repos, gateway, { free: 1000, premium: 1000 });
    const body = { input: sampleInput } as never;
    const free = await repos.users.create({ email: 'free@b.co', passwordHash: 'x', displayName: null });
    const paying = await repos.users.create({ email: 'premium@b.co', passwordHash: 'x', displayName: null });

    let served = 0;
    let refused = 0;
    for (let i = 0; i < 40; i++) {
      await service.generate('insight', free.id, 'free', body).then(() => (served += 1), () => (refused += 1));
    }
    expect(served).toBeGreaterThan(0); // the share is usable
    expect(refused).toBeGreaterThan(0); // and it ends
    const afterFree = await repos.ai.spentUsd(utcDayKey(new Date()));
    expect(afterFree - probeSpent).toBeLessThanOrEqual(share + 1e-9);
    await expect(service.generate('insight', paying.id, 'premium', body)).resolves.toMatchObject({ provider: expect.any(String) });
  });

  it('the free plan stays on the fast tier even for the summaries; premium keeps the quality tier', async () => {
    const repos = new MemoryRepositories();
    const providers = AI_PROVIDER_IDS.map((id) => new MockProvider(id));
    const loaded = loadEnv({ NODE_ENV: 'development', JWT_SECRET: base.JWT_SECRET });
    const gateway = buildGateway(loaded, repos, providers, { info: () => undefined, warn: () => undefined });
    const service = new AiService(repos, gateway, { free: 10, premium: 10 });
    const user = await repos.users.create({ email: 'tier@b.co', passwordHash: 'x', displayName: null });
    await service.generate('monthly_summary', user.id, 'free', { input: sampleInput } as never);
    await service.generate('monthly_summary', user.id, 'premium', { input: sampleInput } as never);
    const tiers = providers.flatMap((p) => p.calls.map((c) => c.tier));
    expect(tiers).toEqual(['fast', 'quality']);
  });
});
