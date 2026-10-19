import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  AI_ERROR_CATEGORIES,
  AIGateway,
  allowsFallback,
  backoffDelayMs,
  categorize,
  createBudgetGuard,
  DEFAULT_RETRY_POLICY,
  isRetryable,
  MemoryUsageSink,
  MockProvider,
  ProviderError,
  ProviderRouter,
  type AIErrorCategory,
  type AIGatewayError,
  type AIGenerationResult,
  type AIProvider,
  type AIProviderId,
  type BudgetGuard,
  type FallbackPolicy,
  type ProviderErrorKind,
  type SpendReader,
} from '../src/index.js';
import { ctx, fakeFetch, gatewayInput as input, json } from './helpers/doubles.js';
import { IDS, capture, httpError, instant, scripted, setup } from './helpers/gateway.js';

afterEach(() => {
  vi.useRealTimers();
});

const err = (kind: ProviderErrorKind, status?: number, code?: string) => new ProviderError('openai', 'x', status, undefined, { kind, code });

describe('error categories (one vocabulary for every vendor)', () => {
  it.each<[string, ProviderError, AIErrorCategory]>([
    ['HTTP 401', err('http', 401), 'authentication'],
    ['HTTP 403', err('http', 403), 'authentication'],
    ['HTTP 429', err('http', 429), 'rate_limit'],
    ['HTTP 408', err('http', 408), 'timeout'],
    ['our own timeout', err('timeout'), 'timeout'],
    ['HTTP 500', err('http', 500), 'provider_unavailable'],
    ['HTTP 503', err('http', 503), 'provider_unavailable'],
    ['HTTP 529', err('http', 529), 'provider_unavailable'],
    ['no connection', err('network'), 'provider_unavailable'],
    ['HTTP 400', err('http', 400), 'invalid_request'],
    ['HTTP 404', err('http', 404), 'invalid_request'],
    ['HTTP 422', err('http', 422), 'invalid_request'],
    ['a refusal', err('refusal'), 'response'],
    ['empty output', err('empty_output'), 'response'],
    ['output that fails the schema', err('invalid_output'), 'response'],
    ['a body that is not JSON', err('invalid_response', 200), 'response'],
    ['an unforeseen exception', err('unexpected'), 'response'],
    ['a cancelled request', err('aborted'), 'aborted'],
  ])('%s is %s', (_name, e, category) => {
    expect(categorize(e)).toBe(category);
    expect(AI_ERROR_CATEGORIES).toContain(category);
  });
});

describe('what is worth retrying on the same provider', () => {
  it.each<[string, ProviderError, boolean]>([
    ['429', err('http', 429), true],
    ['429 because the account has no quota left', err('http', 429, 'insufficient_quota'), false],
    ['429 because billing is not active', err('http', 429, 'billing_not_active'), false],
    ['408', err('http', 408), true],
    ['500', err('http', 500), true],
    ['502', err('http', 502), true],
    ['503', err('http', 503), true],
    ['504', err('http', 504), true],
    ['529 (overloaded)', err('http', 529), true],
    ['501 (not implemented: waiting does not help)', err('http', 501), false],
    ['505', err('http', 505), false],
    ['no connection', err('network'), true],
    ['our own timeout (the attempt used its whole slice)', err('timeout'), false],
    ['400', err('http', 400), false],
    ['401', err('http', 401), false],
    ['403', err('http', 403), false],
    ['404', err('http', 404), false],
    ['a refusal', err('refusal'), false],
    ['empty output', err('empty_output'), false],
    ['invalid output', err('invalid_output'), false],
    ['a body that is not JSON', err('invalid_response', 200), false],
    ['an unforeseen exception', err('unexpected'), false],
    ['a cancelled request', err('aborted'), false],
  ])('%s -> %s', (_name, e, expected) => {
    expect(isRetryable(e)).toBe(expected);
  });
});

describe('what may go to the other provider', () => {
  const on: FallbackPolicy = { onRateLimit: true };
  const off: FallbackPolicy = { onRateLimit: false };

  it.each<[string, ProviderError, boolean]>([
    ['timeout', err('timeout'), true],
    ['HTTP 408', err('http', 408), true],
    ['no connection', err('network'), true],
    ['HTTP 500', err('http', 500), true],
    ['HTTP 503', err('http', 503), true],
    ['HTTP 529', err('http', 529), true],
    ['a body that is not JSON', err('invalid_response', 200), true],
    ['HTTP 400 (invalid request)', err('http', 400), false],
    ['HTTP 404 (wrong model)', err('http', 404), false],
    ['HTTP 422', err('http', 422), false],
    ['HTTP 401 (authentication)', err('http', 401), false],
    ['HTTP 403', err('http', 403), false],
    ['a refusal (blocked by the safety policy)', err('refusal'), false],
    ['empty output', err('empty_output'), false],
    ['output that fails validation', err('invalid_output'), false],
    ['an unforeseen exception', err('unexpected'), false],
    ['a cancelled request', err('aborted'), false],
  ])('%s -> %s', (_name, e, expected) => {
    expect(allowsFallback(e, on)).toBe(expected);
    expect(allowsFallback(e, off)).toBe(expected); // the rate-limit switch only concerns 429
  });

  it('HTTP 429 follows the rate-limit switch (including a quota-exhausted account: the other vendor can still answer)', () => {
    expect(allowsFallback(err('http', 429), on)).toBe(true);
    expect(allowsFallback(err('http', 429, 'insufficient_quota'), on)).toBe(true);
    expect(allowsFallback(err('http', 429), off)).toBe(false);
  });
});

describe('backoff with jitter', () => {
  const policy = DEFAULT_RETRY_POLICY;
  const delays = (random: number, n = 6) => Array.from({ length: n }, (_, i) => backoffDelayMs(i, policy, () => random));

  it('doubles from 500 ms and stops at the cap: 500, 1000, 2000, 4000, 8000, 8000 (middle of the jitter range)', () => {
    expect(delays(0.5)).toEqual([500, 1000, 2000, 4000, 8000, 8000]);
  });

  it('the jitter spreads each wait by +-25 %', () => {
    expect(delays(0, 3)).toEqual([375, 750, 1500]);
    expect(delays(1, 3)).toEqual([625, 1250, 2500]);
  });

  it('never waits less than the provider asked for, but gives up when it asks for too much', () => {
    expect(backoffDelayMs(0, policy, () => 0.5, 3000)).toBe(3000);
    expect(backoffDelayMs(2, policy, () => 0.5, 1000)).toBe(2000);
    expect(backoffDelayMs(0, policy, () => 0.5, policy.maxRetryAfterMs)).toBe(policy.maxRetryAfterMs);
    expect(backoffDelayMs(0, policy, () => 0.5, policy.maxRetryAfterMs + 1)).toBeUndefined();
  });

  it('is always a finite, non-negative whole number, whatever the random source and the retry index do', () => {
    for (const r of [-5, 0, 0.3, 1, 7, Number.NaN]) {
      for (const i of [0, 1, 10, 50, 1000]) {
        const d = backoffDelayMs(i, policy, () => r);
        expect(Number.isInteger(d) && d! >= 0 && d! <= policy.maxDelayMs * (1 + policy.jitter)).toBe(true);
      }
    }
  });
});

describe('retry inside one request', () => {
  it('a transient failure is retried after 500 ms and the same provider answers: no fallback, no demotion, one usage record', async () => {
    const { logger, entries } = capture();
    const flaky = scripted('google', [httpError('google', 503), 'ok']);
    const { sleeps, sleep, random } = instant();
    const usage = new MemoryUsageSink();
    const router = new ProviderRouter([flaky, new MockProvider('openai')]);
    const gateway = new AIGateway({ router, usage, logger, sleep, random });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r).toMatchObject({ providerId: 'google', fallbacks: [] });
    expect(flaky.calls).toHaveLength(2);
    expect(sleeps).toEqual([500]);
    expect(usage.records).toHaveLength(1);
    expect(entries.map((e) => [e.level, e.entry.outcome, e.entry.attempt])).toEqual([['warn', 'http', 1], ['info', 'ok', 2]]);
  });

  it('retries up to maxRetries with doubling waits, then the one fallback answers', async () => {
    const { providers, gateway, sleeps } = setup({ maxRetries: 4 });
    providers.google.set({ fail: httpError('google', 502) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(providers.google.calls).toHaveLength(5);
    expect(sleeps).toEqual([500, 1000, 2000, 4000]);
    expect(r).toMatchObject({ providerId: 'openai', fallbacks: ['google'] });
  });

  it('maxRetries 0 means the first failure goes straight to the fallback', async () => {
    const { providers, gateway, sleeps } = setup({ maxRetries: 0 });
    providers.google.set({ fail: httpError('google', 503) });
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('openai');
    expect(providers.google.calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
  });

  it('the default is two retries (three calls) per provider', async () => {
    const { providers, gateway } = setup();
    providers.google.set({ fail: httpError('google', 503) });
    await gateway.generate('insight', 'normal', input, ctx);
    expect(providers.google.calls).toHaveLength(3);
  });

  it('a short Retry-After is waited for (and wins over the backoff)', async () => {
    const { providers, gateway, sleeps } = setup();
    providers.google.set({ fail: httpError('google', 429, 3000) });
    await gateway.generate('insight', 'normal', input, ctx);
    expect(sleeps).toEqual([3000, 3000]);
    expect(providers.google.calls).toHaveLength(3);
  });

  it('a long Retry-After is not waited for: no retry, the fallback answers at once, the router keeps the provider out as long as it asked', async () => {
    const { providers, gateway, sleeps, router } = setup();
    providers.google.set({ fail: httpError('google', 429, 120_000) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(providers.google.calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
    expect(r.providerId).toBe('openai');
    expect(router.health().find((h) => h.id === 'google')!.retryInMs).toBe(120_000);
  });

  it.each([
    ['a timeout', new ProviderError('google', 't', undefined, true, { kind: 'timeout' })],
    ['a bad request', httpError('google', 400)],
    ['a bad key', httpError('google', 401)],
    ['an exhausted account', new ProviderError('google', 'q', 429, undefined, { code: 'insufficient_quota' })],
  ])('%s is not retried', async (_name, failure) => {
    const { providers, gateway, sleeps } = setup();
    providers.google.set({ fail: failure });
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(providers.google.calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
  });

  it('applies the jitter from the random source', async () => {
    for (const [random, expected] of [[0, 375], [1, 625]] as const) {
      const providers = { google: new MockProvider('google', { fail: httpError('google', 503) }), openai: new MockProvider('openai') };
      const sleeps: number[] = [];
      const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)), maxRetries: 1, random: () => random, sleep: async (ms) => void sleeps.push(ms) });
      await gateway.generate('insight', 'normal', input, ctx);
      expect(sleeps).toEqual([expected]);
    }
  });

  it('does not wait when the pause plus one more call no longer fits the request budget; the fallback gets the remaining time instead', async () => {
    let t = 0;
    const providers = { google: new MockProvider('google', { fail: httpError('google', 503) }), openai: new MockProvider('openai') };
    const sleeps: number[] = [];
    const gateway = new AIGateway({
      router: new ProviderRouter(Object.values(providers)),
      requestTimeoutMs: 1400, // 500 ms pause + the 1000 ms minimum for another call = 1500 > 1400
      clock: () => t,
      sleep: async (ms) => void (sleeps.push(ms), (t += ms)),
      random: () => 0.5,
    });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(sleeps).toEqual([]);
    expect(providers.google.calls).toHaveLength(1);
    expect(r.providerId).toBe('openai');
    expect(providers.openai.calls[0]!.timeoutMs).toBe(1400);
  });

  it.each([
    ['maxRetries', { maxRetries: -1 }],
    ['maxRetries', { maxRetries: 11 }],
    ['maxRetries', { maxRetries: 1.5 }],
    ['maxRetries', { maxRetries: Number.NaN }],
    ['retry.jitter', { retry: { jitter: 2 } }],
    ['retry.baseDelayMs', { retry: { baseDelayMs: -1 } }],
    ['requestTimeoutMs', { requestTimeoutMs: 0 }],
    ['requestTimeoutMs', { requestTimeoutMs: Number.POSITIVE_INFINITY }],
  ])('refuses a nonsensical %s', (_name, bad) => {
    expect(() => new AIGateway({ router: new ProviderRouter([]), ...bad })).toThrow(RangeError);
  });

  it('retries show up in the log as attempt 1, 2, 3 of the same provider, with the category and no content', async () => {
    const { logger, entries } = capture();
    const { providers, gateway } = setup({ logger });
    providers.google.set({ fail: httpError('google', 503) });
    await gateway.generate('insight', 'normal', input, ctx);
    const google = entries.filter((e) => e.entry.provider === 'google');
    expect(google.map((e) => e.entry.attempt)).toEqual([1, 2, 3]);
    expect(google.every((e) => e.entry.category === 'provider_unavailable' && e.entry.fallback === false)).toBe(true);
    expect(entries.at(-1)!.entry).toMatchObject({ provider: 'openai', outcome: 'ok', attempt: 1, fallback: true });
  });
});

describe('the time budget of a whole request', () => {
  const fake = () => vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date', 'performance'] });
  const hanging = () => new (class extends MockProvider {
    override async generate(r: Parameters<MockProvider['generate']>[0]): Promise<AIGenerationResult> {
      this.calls.push(r);
      return new Promise<never>((_, reject) => {
        // Honours the deadline like an adapter does: the deadline arrives as a timeout error.
        setTimeout(() => reject(new ProviderError(this.id, `timeout after ${r.timeoutMs} ms`, undefined, true, { kind: 'timeout' })), r.timeoutMs);
      });
    }
  })('google');

  it('the fallback gets what is left of the budget, not a fresh full slice', async () => {
    fake();
    const google = hanging();
    const openai = new MockProvider('openai');
    const gateway = new AIGateway({ router: new ProviderRouter([google, openai]), timeoutMs: 20_000, requestTimeoutMs: 30_000 });
    const pending = gateway.generate('insight', 'normal', input, ctx);
    await vi.advanceTimersByTimeAsync(20_000);
    const r = await pending;
    expect(google.calls[0]!.timeoutMs).toBe(20_000);
    expect(openai.calls[0]!.timeoutMs).toBe(10_000);
    expect(r.providerId).toBe('openai');
  });

  it('with less than a second left no fallback call is started, and nobody is blamed for it', async () => {
    fake();
    const google = hanging();
    const openai = new MockProvider('openai');
    const router = new ProviderRouter([google, openai]);
    const gateway = new AIGateway({ router, timeoutMs: 20_000, requestTimeoutMs: 20_500 });
    const pending = gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(20_000);
    const e = (await pending) as AIGatewayError;
    expect(e).toMatchObject({ code: 'all_providers_failed', attempts: [{ providerId: 'google', kind: 'timeout' }] });
    expect(openai.calls).toHaveLength(0);
    expect(router.health().find((h) => h.id === 'openai')).toMatchObject({ consecutiveFailures: 0, inCooldown: false });
  });

  it('two hanging providers end exactly at the request budget, not at providers x slice', async () => {
    fake();
    const google = hanging();
    const openai = new (class extends MockProvider {
      override async generate(r: Parameters<MockProvider['generate']>[0]): Promise<AIGenerationResult> {
        this.calls.push(r);
        return new Promise<never>((_, reject) => setTimeout(() => reject(new ProviderError(this.id, 't', undefined, true, { kind: 'timeout' })), r.timeoutMs));
      }
    })('openai');
    const gateway = new AIGateway({ router: new ProviderRouter([google, openai]), timeoutMs: 20_000, requestTimeoutMs: 25_000 });
    const started = Date.now();
    const pending = gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(25_000);
    const e = (await pending) as AIGatewayError;
    expect(Date.now() - started).toBe(25_000);
    expect(e.attempts.map((a) => a.kind)).toEqual(['timeout', 'timeout']);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('defaults: 20 s per call, 60 s per request', () => {
    const { gateway } = setup();
    expect(gateway.status()).toMatchObject({ attemptTimeoutMs: 20_000, requestTimeoutMs: 60_000 });
  });
});

describe('which provider is asked first', () => {
  it('the default provider leads for every task, the task routing order continues behind it', async () => {
    const { providers, gateway } = setup({ defaultProvider: 'xai' });
    for (const task of ['insight', 'weekly_summary', 'monthly_summary', 'roast'] as const) {
      const r = await gateway.generate(task, 'normal', input, ctx);
      expect(r.providerId, task).toBe('xai');
    }
    providers.xai.set({ fail: httpError('xai', 503) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r).toMatchObject({ providerId: 'google', fallbacks: ['xai'] }); // the next in the insight routing order
  });

  it('without a default the task routing decides, as before', async () => {
    const { gateway } = setup();
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
    expect((await gateway.generate('roast', 'roast', input, ctx)).providerId).toBe('xai');
  });

  it('a default that is not configured is ignored instead of failing every request', async () => {
    const providers = { openai: new MockProvider('openai'), google: new MockProvider('google') };
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)), defaultProvider: 'xai' });
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
  });

  it('a default that is cooling down sits behind the healthy providers, so a dead default does not take every request with it', async () => {
    const { providers, gateway, router } = setup({ defaultProvider: 'openai' });
    providers.openai.set({ fail: httpError('openai', 503) });
    await gateway.generate('insight', 'normal', input, ctx); // openai fails, google answers as the fallback
    expect(router.inCooldown('openai')).toBe(true);
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r).toMatchObject({ providerId: 'google', fallbacks: [] });
    expect(providers.openai.calls).toHaveLength(3); // only the first request paid (call + 2 retries)
  });

  it('a provider chosen by the backend wins over the default', async () => {
    const { gateway } = setup({ defaultProvider: 'openai' });
    const r = await gateway.generate('insight', 'normal', input, ctx, { provider: 'xai' });
    expect(r.providerId).toBe('xai');
  });

  it('a provider chosen by the backend that is not configured is an error, not a silent switch', async () => {
    const providers = { openai: new MockProvider('openai') };
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)) });
    await expect(gateway.generate('insight', 'normal', input, ctx, { provider: 'xai' })).rejects.toMatchObject({ code: 'no_provider' });
    expect(providers.openai.calls).toHaveLength(0);
  });

  it('with the fallback switched off the chosen provider is the only one asked', async () => {
    const { providers, gateway } = setup({ fallback: { enabled: false } });
    providers.google.set({ fail: httpError('google', 503) });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.attempts).toHaveLength(1);
    expect(providers.google.calls).toHaveLength(3); // still retried
    for (const id of ['openai', 'xai', 'anthropic'] as const) expect(providers[id].calls).toHaveLength(0);
  });

  it('with onRateLimit off a 429 does not go to the other provider (it is still retried and the provider is demoted)', async () => {
    const { providers, gateway, router } = setup({ fallback: { onRateLimit: false } });
    providers.google.set({ fail: httpError('google', 429) });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e).toMatchObject({ attempts: [{ providerId: 'google', category: 'rate_limit' }] });
    expect(providers.openai.calls).toHaveLength(0);
    expect(router.inCooldown('google')).toBe(true);
    // while a 503 still falls back
    providers.google.set({ fail: httpError('google', 503) });
    providers.google.calls.length = 0;
    const next = await gateway.generate('weekly_summary', 'normal', input, ctx).catch((x: unknown) => x);
    expect(next).toMatchObject({ providerId: expect.any(String) });
  });
});

describe('backend-only model override', () => {
  it('goes to the chosen provider only; its fallback keeps using its own configured models', async () => {
    const { providers, gateway } = setup();
    providers.xai.set({ fail: httpError('xai', 503) });
    const r = await gateway.generate('insight', 'normal', input, ctx, { provider: 'xai', model: 'grok-special-1' });
    expect(providers.xai.calls[0]!.model).toBe('grok-special-1');
    expect(r.providerId).toBe('google');
    expect(providers.google.calls[0]!.model).toBeUndefined();
  });

  it('without an override the request carries no model (the configured one is used)', async () => {
    const { providers, gateway } = setup();
    await gateway.generate('insight', 'normal', input, ctx);
    expect(providers.google.calls[0]!.model).toBeUndefined();
  });

  it.each([
    ['a model without a provider', { model: 'gpt-x' }],
    ['a model name with a space', { provider: 'openai', model: 'gpt x' }],
    ['an empty model name', { provider: 'openai', model: '' }],
    ['a model name that is a path', { provider: 'openai', model: '../../etc' }],
    ['a model name of 200 characters', { provider: 'openai', model: 'm'.repeat(200) }],
  ] as const)('refuses %s before any provider is called', async (_name, options) => {
    const { providers, gateway } = setup();
    await expect(gateway.generate('insight', 'normal', input, ctx, options)).rejects.toMatchObject({ code: 'invalid_input' });
    expect(Object.values(providers).every((p) => p.calls.length === 0)).toBe(true);
  });
});

describe('spend limits', () => {
  const reader = (spent: Partial<Record<string, number>> = {}): SpendReader & { asked: [string, string | undefined][] } => {
    const asked: [string, string | undefined][] = [];
    return {
      asked,
      async spentUsd(sinceDay, provider) {
        asked.push([sinceDay, provider]);
        return spent[provider ? `${provider}@${sinceDay}` : sinceDay] ?? 0;
      },
    };
  };
  const NOW = new Date('2026-10-13T12:00:00Z');

  describe('createBudgetGuard', () => {
    it('is undefined when nothing is limited, so nothing is queried', () => {
      expect(createBudgetGuard({}, reader())).toBeUndefined();
      expect(createBudgetGuard({ providerDailyUsd: {} }, reader())).toBeUndefined();
    });

    it('asks for the UTC day, the UTC month and each limited provider, nothing else', async () => {
      const r = reader();
      const guard = createBudgetGuard({ dailyUsd: 5, monthlyUsd: 100, providerDailyUsd: { openai: 2 } }, r)!;
      await guard.check(NOW);
      expect(r.asked.sort()).toEqual([['2026-10-01', undefined], ['2026-10-13', 'openai'], ['2026-10-13', undefined]].sort());
    });

    it('a UTC midnight is a new day and a new month', async () => {
      const r = reader();
      await createBudgetGuard({ dailyUsd: 1, monthlyUsd: 1 }, r)!.check(new Date('2026-11-01T00:00:00Z'));
      expect(r.asked.map(([d]) => d).sort()).toEqual(['2026-11-01', '2026-11-01']);
    });

    it('reports the daily and the monthly limit once spend reaches it (>=), and the provider limits separately', async () => {
      const guard = createBudgetGuard({ dailyUsd: 5, monthlyUsd: 100, providerDailyUsd: { openai: 2, xai: 1 } }, reader({ '2026-10-13': 4.99, '2026-10-01': 99.99 }))!;
      expect((await guard.check(NOW)).exceeded).toBeUndefined();
      expect((await createBudgetGuard({ dailyUsd: 5 }, reader({ '2026-10-13': 5 }))!.check(NOW)).exceeded).toBe('daily');
      expect((await createBudgetGuard({ monthlyUsd: 100 }, reader({ '2026-10-01': 100.01 }))!.check(NOW)).exceeded).toBe('monthly');
      const perProvider = await createBudgetGuard({ providerDailyUsd: { openai: 2, xai: 1 } }, reader({ 'openai@2026-10-13': 2, 'xai@2026-10-13': 0.5 }))!.check(NOW);
      expect([...perProvider.exhaustedProviders]).toEqual(['openai']);
    });

    it('a limit of 0 switches the provider (or everything) off', async () => {
      expect((await createBudgetGuard({ dailyUsd: 0 }, reader())!.check(NOW)).exceeded).toBe('daily');
      expect([...(await createBudgetGuard({ providerDailyUsd: { xai: 0 } }, reader())!.check(NOW)).exhaustedProviders]).toEqual(['xai']);
    });
  });

  const guardWith = (check: BudgetGuard['check']): BudgetGuard => ({ check });

  it('a used-up daily or monthly budget stops the request before any provider is called', async () => {
    for (const exceeded of ['daily', 'monthly'] as const) {
      const { providers, gateway } = setup({ budget: guardWith(async () => ({ exceeded, exhaustedProviders: new Set() })) });
      await expect(gateway.generate('insight', 'normal', input, ctx)).rejects.toMatchObject({ code: 'budget_exceeded', message: `AI ${exceeded} budget is used up` });
      expect(Object.values(providers).every((p) => p.calls.length === 0)).toBe(true);
    }
  });

  it('a provider at its own limit is skipped and the others keep answering: one provider never blocks the app', async () => {
    const { providers, gateway } = setup({ budget: guardWith(async () => ({ exhaustedProviders: new Set<AIProviderId>(['openai']) })) });
    const r = await gateway.generate('weekly_summary', 'normal', input, ctx); // openai leads this task
    expect(r.providerId).toBe('google');
    expect(providers.openai.calls).toHaveLength(0);
  });

  it('a provider at its limit is not used as the fallback either, and not even when the backend asked for it', async () => {
    const { providers, gateway } = setup({ budget: guardWith(async () => ({ exhaustedProviders: new Set<AIProviderId>(['openai']) })) });
    providers.google.set({ fail: httpError('google', 503) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.providerId).toBe('xai'); // google failed, openai (the usual next) is exhausted
    const asked = await gateway.generate('insight', 'normal', input, ctx, { provider: 'openai' });
    expect(asked.providerId).not.toBe('openai');
    expect(providers.openai.calls).toHaveLength(0);
  });

  it('every configured provider at its limit is a spent budget, not "no provider"', async () => {
    const providers = { openai: new MockProvider('openai'), xai: new MockProvider('xai') };
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)), budget: guardWith(async () => ({ exhaustedProviders: new Set<AIProviderId>(['openai', 'xai']) })) });
    await expect(gateway.generate('insight', 'normal', input, ctx)).rejects.toMatchObject({ code: 'budget_exceeded' });
  });

  it('a budget check that cannot be read fails open and says so (a broken spend table must not switch AI off)', async () => {
    const { logger, entries } = capture();
    const { gateway } = setup({ logger, budget: guardWith(() => Promise.reject(new Error('db down SENTINEL-DB'))) });
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
    expect(entries.find((e) => e.entry.event === 'ai.budget_check_failed')).toMatchObject({ level: 'warn', entry: { error: 'Error' } });
    expect(JSON.stringify(entries)).not.toContain('SENTINEL-DB');
  });

  it('is evaluated with the injected clock', async () => {
    const seen: Date[] = [];
    const { gateway } = setup({ budget: guardWith(async (now) => (seen.push(now), { exhaustedProviders: new Set() })) });
    await gateway.generate('insight', 'normal', input, ctx);
    expect(seen).toEqual([new Date(1_000_000)]);
  });
});

describe('cancellation', () => {
  it('a signal that is already aborted calls nobody', async () => {
    const { providers, gateway } = setup();
    await expect(gateway.generate('insight', 'normal', input, ctx, { signal: AbortSignal.abort() })).rejects.toMatchObject({ code: 'aborted' });
    expect(Object.values(providers).every((p) => p.calls.length === 0)).toBe(true);
  });

  it('aborting during a call ends the request: no retry, no fallback, and the provider is not blamed', async () => {
    const controller = new AbortController();
    const waiting = new MockProvider('google');
    waiting.generate = (r) => {
      waiting.calls.push(r);
      return new Promise((_, reject) => r.signal?.addEventListener('abort', () => reject(new ProviderError('google', 'aborted by the caller', undefined, false, { kind: 'aborted' }))));
    };
    const openai = new MockProvider('openai');
    const { sleeps, sleep, random } = instant();
    const router = new ProviderRouter([waiting, openai]);
    const gateway = new AIGateway({ router, sleep, random });
    const pending = gateway.generate('insight', 'normal', input, ctx, { signal: controller.signal }).catch((e: unknown) => e);
    await Promise.resolve();
    controller.abort();
    const e = (await pending) as AIGatewayError;
    expect(e).toMatchObject({ code: 'aborted', attempts: [{ providerId: 'google', kind: 'aborted', category: 'aborted' }] });
    expect(waiting.calls).toHaveLength(1);
    expect(openai.calls).toHaveLength(0);
    expect(sleeps).toEqual([]);
    expect(router.health().find((h) => h.id === 'google')).toMatchObject({ consecutiveFailures: 0, inCooldown: false });
  });

  it('aborting during the pause before a retry stops there', async () => {
    const controller = new AbortController();
    const providers = { google: new MockProvider('google', { fail: httpError('google', 503) }), openai: new MockProvider('openai') };
    const gateway = new AIGateway({
      router: new ProviderRouter(Object.values(providers)),
      random: () => 0.5,
      sleep: async () => controller.abort(),
    });
    const e = (await gateway.generate('insight', 'normal', input, ctx, { signal: controller.signal }).catch((x: unknown) => x)) as AIGatewayError;
    expect(e).toMatchObject({ code: 'aborted' });
    expect(providers.google.calls).toHaveLength(1);
    expect(providers.openai.calls).toHaveLength(0);
  });
});

describe('usage: what the provider itself reports', () => {
  const reporting = (id: AIProviderId, extra: Partial<AIGenerationResult>): AIProvider => ({
    id,
    healthCheck: async () => ({ providerId: id, ok: true }),
    generate: async () => ({ providerId: id, model: 'some-new-model', text: json, inputTokens: 1000, outputTokens: 500, latencyMs: 12, ...extra }),
  });

  it('a charge reported by the provider is the cost, labelled as such, and beats model prices and flat estimates', async () => {
    const usage = new MemoryUsageSink();
    const gateway = new AIGateway({
      router: new ProviderRouter([reporting('xai', { costUsd: 0.0123 })]),
      usage,
      modelPrices: { 'some-new-model': { input: 10, output: 20 } },
    });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage).toMatchObject({ estimatedCostUsd: 0.0123, costBasis: 'provider_reported' });
  });

  it('a reported charge is still known when the token counts are not', async () => {
    const gateway = new AIGateway({ router: new ProviderRouter([reporting('xai', { costUsd: 0.5, inputTokens: 0, outputTokens: 0, usageReported: false })]) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage).toMatchObject({ estimatedCostUsd: 0.5, costBasis: 'provider_reported', usageReported: false });
  });

  it('the provider request id reaches the usage record and the log, and nothing else of the response does', async () => {
    const { logger, entries } = capture();
    const gateway = new AIGateway({ router: new ProviderRouter([reporting('openai', { requestId: 'req_abc123' })]), logger });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage.providerRequestId).toBe('req_abc123');
    expect(entries[0]!.entry).toMatchObject({ outcome: 'ok', requestId: 'req_abc123' });
  });

  it('a failed call logs the request id the provider gave for the failure', async () => {
    const { logger, entries } = capture();
    const failing = new MockProvider('openai', { fail: new ProviderError('openai', 'HTTP 400', 400, undefined, { requestId: 'req_failed_9' }) });
    const gateway = new AIGateway({ router: new ProviderRouter([failing]), logger, ...instant() });
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(entries[0]!.entry).toMatchObject({ outcome: 'http', httpStatus: 400, category: 'invalid_request', requestId: 'req_failed_9' });
  });
});

describe('status (no provider is called, no key is shown)', () => {
  it('lists all four providers with their configuration and health', async () => {
    const providers = { openai: new MockProvider('openai', { fail: httpError('openai', 503) }), xai: new MockProvider('xai') };
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers), { cooldownMs: 30_000 }), defaultProvider: 'xai', ...instant(), maxRetries: 1 });
    expect(gateway.status().providers.map((p) => [p.id, p.configured])).toEqual([['openai', true], ['anthropic', false], ['google', false], ['xai', true]]);

    await gateway.generate('insight', 'normal', input, ctx, { provider: 'openai' });
    const status = gateway.status();
    expect(status.providers.find((p) => p.id === 'openai')).toMatchObject({ configured: true, inCooldown: true, consecutiveFailures: 1 });
    expect(status.providers.find((p) => p.id === 'xai')).toMatchObject({ configured: true, inCooldown: false });
    expect(status).toMatchObject({ defaultProvider: 'xai', fallbackEnabled: true, fallbackOnRateLimit: true, maxRetries: 1, budgetEnforced: false });
  });

  it('says what the defaults are when nothing is configured', () => {
    expect(setup().gateway.status()).toMatchObject({ defaultProvider: null, fallbackEnabled: true, maxRetries: 2, attemptTimeoutMs: 20_000, requestTimeoutMs: 60_000 });
  });

  it('never carries a key, whichever adapter is behind it', async () => {
    const { fetchImpl } = fakeFetch({ body: {} });
    const { specs } = await import('./helpers/doubles.js');
    const gateway = new AIGateway({ router: new ProviderRouter(specs.map((s) => s.make(fetchImpl))) });
    const serialised = JSON.stringify(gateway.status());
    expect(serialised).not.toMatch(/k-(openai|xai|anthropic|google)|Bearer|api[-_]?key/i);
    expect(IDS.every((id) => serialised.includes(id))).toBe(true);
  });
});
