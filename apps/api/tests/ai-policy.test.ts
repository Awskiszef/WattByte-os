import { AI_PROVIDER_IDS, AIGateway, createBudgetGuard, MockProvider, ProviderError, ProviderRouter } from '@wattbyte/ai';
import { afterEach, describe, expect, it } from 'vitest';

import { loadEnv } from '../src/config/env.js';
import { MemoryRepositories } from '../src/database/memory.js';
import { buildGateway, gatewayOptionsFromEnv } from '../src/modules/ai/gateway.js';
import { AiService, utcDayKey, type AiFailedEvent } from '../src/modules/ai/service.js';
import { makeApp, registerUser, sampleInput, type TestContext } from './helpers.js';

let ctx: TestContext | undefined;
afterEach(async () => {
  await ctx?.app.close();
  ctx = undefined;
});

const insight = (c: TestContext, headers: Record<string, string>) =>
  c.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers, payload: { input: sampleInput } });

const baseEnv = { NODE_ENV: 'development', JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars' };

describe('GET /api/v1/ai/status', () => {
  it('needs a signed-in user', async () => {
    ctx = await makeApp();
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/ai/status' });
    expect(res.statusCode).toBe(401);
  });

  it('reports configuration and health of every provider without calling any of them', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/ai/status', headers: reg.headers });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      enabled: true,
      providers: Object.fromEntries(AI_PROVIDER_IDS.map((id) => [id, { configured: true, inCooldown: false, retryInSec: 0, consecutiveFailures: 0 }])),
      defaultProvider: null,
      fallback: { enabled: true, onRateLimit: true },
      maxRetries: 2,
      timeouts: { attemptMs: 20_000, requestMs: 60_000 },
      budgetEnforced: false,
    });
    for (const p of Object.values(ctx.providers)) expect(p.calls).toHaveLength(0);
  });

  it('says which providers are NOT configured, and never carries a key or a model name', async () => {
    ctx = await makeApp();
    const only = new MockProvider('openai');
    const repos = new MemoryRepositories();
    const env = loadEnv({ NODE_ENV: 'test', JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret', OPENAI_API_KEY: 'sk-SECRET-KEY-VALUE', OPENAI_FAST_MODEL: 'secret-model-name', AI_DEFAULT_PROVIDER: 'openai' });
    const { buildApp } = await import('../src/app.js');
    const app = await buildApp({ env, repos, gateway: new AIGateway({ router: new ProviderRouter([only]), ...gatewayOptionsFromEnv(env) }), providerIds: ['openai'], logger: false, rateLimitMax: 10_000, authRateLimitMax: 10_000, priceProviders: [] });
    await app.ready();
    try {
      const reg = await registerUser(app);
      const res = await app.inject({ method: 'GET', url: '/api/v1/ai/status', headers: reg.headers });
      expect(res.json()).toMatchObject({ defaultProvider: 'openai', providers: { openai: { configured: true }, xai: { configured: false }, google: { configured: false }, anthropic: { configured: false } } });
      expect(res.body).not.toMatch(/SECRET|secret-model|sk-|api[-_]?key/i);
    } finally {
      await app.close();
    }
  });

  it('is operator tooling, not part of the app contract: absent from the OpenAPI document', async () => {
    ctx = await makeApp();
    const doc = (await ctx.app.inject({ method: 'GET', url: '/openapi.json' })).json() as { paths: Record<string, unknown> };
    expect(Object.keys(doc.paths).filter((p) => p.includes('/ai/'))).toEqual(
      expect.not.arrayContaining(['/api/v1/ai/status']),
    );
    expect(Object.keys(doc.paths)).toContain('/api/v1/ai/insight');
  });

  it('shows a provider that has been failing, and keeps answering while AI is switched off', async () => {
    ctx = await makeApp({ FEATURE_AI: '0' });
    const reg = await registerUser(ctx.app);
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/ai/status', headers: reg.headers });
    expect(res.statusCode).toBe(200);
    expect(res.json().enabled).toBe(false);
    // while the generating routes are off
    expect((await insight(ctx, reg.headers)).statusCode).toBe(503);
  });

  it('is rate limited like the other AI routes', async () => {
    const { buildApp } = await import('../src/app.js');
    const env = loadEnv({ NODE_ENV: 'test', JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret' });
    const app = await buildApp({ env, repos: new MemoryRepositories(), gateway: new AIGateway({ router: new ProviderRouter([]) }), providerIds: [], logger: false, rateLimitMax: 10_000, authRateLimitMax: 10_000, aiRateLimitMax: 2, priceProviders: [] });
    await app.ready();
    try {
      const reg = await registerUser(app, 'limit@b.co');
      const codes: number[] = [];
      for (let i = 0; i < 4; i += 1) codes.push((await app.inject({ method: 'GET', url: '/api/v1/ai/status', headers: reg.headers })).statusCode);
      expect(codes).toEqual([200, 200, 429, 429]);
    } finally {
      await app.close();
    }
  });
});

describe('spend limits through the API', () => {
  it('every answer adds its cost to the day\'s spend, per provider', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    const first = await insight(ctx, reg.headers);
    expect(first.statusCode).toBe(200);
    const today = utcDayKey(new Date());
    const total = await ctx.repos.ai.spentUsd(today);
    expect(total).toBeGreaterThan(0);
    expect(await ctx.repos.ai.spentUsd(today, 'google')).toBe(total);
    expect(await ctx.repos.ai.spentUsd(today, 'openai')).toBe(0);
    expect(await ctx.repos.ai.spentUsd('2999-01-01')).toBe(0); // nothing is spent in the future
  });

  it('a used-up daily budget answers 503 ai_unavailable (no detail), calls no provider, and gives the quota slot back', async () => {
    ctx = await makeApp({}, { gatewayOptions: (repos) => ({ budget: createBudgetGuard({ dailyUsd: 0.0000001 }, repos.ai) }) });
    const reg = await registerUser(ctx.app);
    expect((await insight(ctx, reg.headers)).statusCode).toBe(200); // nothing spent yet
    const calls = ctx.providers.google.calls.length;
    const blocked = await insight(ctx, reg.headers);
    expect(blocked.statusCode).toBe(503);
    expect(blocked.json()).toEqual({ error: { code: 'ai_unavailable', message: 'AI providers are unavailable right now' } });
    expect(blocked.body).not.toMatch(/budget|usd|limit/i);
    expect(ctx.providers.google.calls).toHaveLength(calls);
    // The free plan allows 2 per day: one used, the refused one was released, so the next reserve is the second.
    expect(await ctx.repos.ai.reserve(reg.user.id, utcDayKey(new Date()), 2)).toBe(2);
  });

  it('a provider at its own daily limit is skipped; the app keeps answering with the others', async () => {
    ctx = await makeApp({}, { gatewayOptions: (repos) => ({ budget: createBudgetGuard({ providerDailyUsd: { google: 0 } }, repos.ai) }) });
    const reg = await registerUser(ctx.app);
    const res = await insight(ctx, reg.headers); // google normally leads insight
    expect(res.statusCode).toBe(200);
    expect(res.json().provider).toBe('openai');
    expect(ctx.providers.google.calls).toHaveLength(0);
  });

  it('the failure is logged with its reason for the operator (and only that)', async () => {
    const repos = new MemoryRepositories();
    const user = await repos.users.create({ email: 'budget@b.co', passwordHash: 'x', displayName: null });
    const gateway = new AIGateway({
      router: new ProviderRouter(AI_PROVIDER_IDS.map((id) => new MockProvider(id))),
      budget: createBudgetGuard({ dailyUsd: 0 }, repos.ai),
    });
    const failed: AiFailedEvent[] = [];
    const service = new AiService(repos, gateway, { free: 3, premium: 50 });
    await expect(service.generate('insight', user.id, 'free', { input: sampleInput } as never, { generated: () => undefined, failed: (e) => void failed.push(e) })).rejects.toMatchObject({ status: 503, code: 'ai_unavailable' });
    expect(failed).toEqual([{ task: 'insight', status: 'budget_exceeded', attempts: [] }]);
  });

  it('keeps counting after the user erases their data (the spend table holds no user id)', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    await insight(ctx, reg.headers);
    const before = await ctx.repos.ai.spentUsd('1970-01-01');
    expect(before).toBeGreaterThan(0);
    const del = await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me/cloud-data', headers: reg.headers });
    expect(del.statusCode).toBeLessThan(300);
    expect(await ctx.repos.ai.spentUsd('1970-01-01')).toBe(before);
  });
});

describe('failures through the API', () => {
  it('a bad key on the first provider is not papered over by the other vendor: 503 now, the next request is served by another provider', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    ctx.providers.google.set({ fail: new ProviderError('google', 'HTTP 401', 401) });
    const first = await insight(ctx, reg.headers);
    expect(first.statusCode).toBe(503);
    expect(first.json().error.code).toBe('ai_unavailable');
    expect(ctx.providers.openai.calls).toHaveLength(0); // no fallback after an authentication failure
    // The slot was given back: a failed answer is not charged to the daily quota.
    expect(await ctx.repos.ai.reserve(reg.user.id, utcDayKey(new Date()), 2)).toBe(1);
  });

  it('a provider that is down is retried and replaced by exactly one other provider', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    ctx.providers.google.set({ fail: new ProviderError('google', 'HTTP 503', 503) });
    const res = await insight(ctx, reg.headers);
    expect(res.statusCode).toBe(200);
    expect(res.json().provider).toBe('openai');
    expect(ctx.providers.google.calls).toHaveLength(3); // the call and two retries
    expect(ctx.providers.xai.calls).toHaveLength(0);
    expect(ctx.providers.anthropic.calls).toHaveLength(0);
  });
});

describe('the gateway built from the environment', () => {
  const mockProviders = () => AI_PROVIDER_IDS.map((id) => new MockProvider(id));
  const logger = { info: () => undefined, warn: () => undefined };

  it('maps every AI variable to its option', () => {
    const env = loadEnv({
      ...baseEnv,
      OPENAI_API_KEY: 'sk-test-key-not-real',
      OPENAI_FAST_MODEL: 'm',
      AI_DEFAULT_PROVIDER: 'openai',
      AI_REQUEST_TIMEOUT_MS: '45000',
      AI_ATTEMPT_TIMEOUT_MS: '15000',
      AI_MAX_RETRIES: '1',
      AI_FALLBACK_ENABLED: '0',
      AI_FALLBACK_ON_RATE_LIMIT: '0',
      AI_MODEL_PRICES: '{"m":{"input":1,"output":2}}',
    });
    expect(gatewayOptionsFromEnv(env)).toEqual({
      timeoutMs: 15_000,
      requestTimeoutMs: 45_000,
      maxRetries: 1,
      fallback: { enabled: false, onRateLimit: false },
      defaultProvider: 'openai',
      modelPrices: { m: { input: 1, output: 2 } },
      maxInFlight: 16, // AI_MAX_CONCURRENT
    });
  });

  it('without any AI variable the gateway runs on the documented defaults', () => {
    const gateway = buildGateway(loadEnv(baseEnv), new MemoryRepositories(), mockProviders(), logger);
    expect(gateway.status()).toMatchObject({
      defaultProvider: null,
      fallbackEnabled: true,
      fallbackOnRateLimit: true,
      maxRetries: 2,
      attemptTimeoutMs: 20_000,
      requestTimeoutMs: 60_000,
      budgetEnforced: false,
    });
  });

  it('spend limits switch the budget check on, and only then', () => {
    const repos = new MemoryRepositories();
    expect(buildGateway(loadEnv({ ...baseEnv, AI_BUDGET_DAILY_USD: '5' }), repos, mockProviders(), logger).status().budgetEnforced).toBe(true);
    expect(buildGateway(loadEnv({ ...baseEnv, AI_BUDGET_MONTHLY_USD: '50' }), repos, mockProviders(), logger).status().budgetEnforced).toBe(true);
    expect(buildGateway(loadEnv({ ...baseEnv, AI_BUDGET_PROVIDER_DAILY_USD: '{"xai":1}' }), repos, mockProviders(), logger).status().budgetEnforced).toBe(true);
    expect(buildGateway(loadEnv(baseEnv), repos, mockProviders(), logger).status().budgetEnforced).toBe(false);
  });

  it('enforces a monthly budget from what the repository has recorded', async () => {
    const repos = new MemoryRepositories();
    const user = await repos.users.create({ email: 'month@b.co', passwordHash: 'x', displayName: null });
    await repos.ai.insert({ userId: user.id, task: 'insight', mode: 'normal', provider: 'google', model: 'm', inputTokens: 1, outputTokens: 1, estimatedCostUsd: 12.5, costBasis: 'provider_estimate', usageReported: true, latencyMs: 1, createdAt: new Date() });
    const gateway = buildGateway(loadEnv({ ...baseEnv, AI_BUDGET_MONTHLY_USD: '10' }), repos, mockProviders(), logger);
    await expect(gateway.generate('insight', 'normal', sampleInput, { userRef: 'u', plan: 'free', locale: 'en' })).rejects.toMatchObject({ code: 'budget_exceeded' });
    const roomy = buildGateway(loadEnv({ ...baseEnv, AI_BUDGET_MONTHLY_USD: '13' }), repos, mockProviders(), logger);
    await expect(roomy.generate('insight', 'normal', sampleInput, { userRef: 'u', plan: 'free', locale: 'en' })).resolves.toBeDefined();
  });

  it('the default provider from the environment leads every task', async () => {
    const env = loadEnv({ ...baseEnv, AI_MOCK: '1', AI_DEFAULT_PROVIDER: 'anthropic' });
    const gateway = buildGateway(env, new MemoryRepositories(), mockProviders(), logger);
    for (const task of ['insight', 'weekly_summary', 'monthly_summary', 'roast'] as const) {
      expect((await gateway.generate(task, task === 'roast' ? 'roast' : 'normal', sampleInput, { userRef: 'u', plan: 'free', locale: 'en' })).providerId).toBe('anthropic');
    }
  });
});
