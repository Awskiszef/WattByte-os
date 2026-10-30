// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  AI_TASKS,
  AIGateway,
  AIGatewayError,
  DEFAULT_ROUTING,
  GoogleProvider,
  MemoryUsageSink,
  MockProvider,
  ProviderError,
  ProviderRouter,
  TASK_TIER,
  type AIGenerationResult,
  type AIProvider,
  type AIProviderId,
  type AIErrorCategory,
  type AITask,
  type GatewayLogger,
  type GatewayOptions,
  type ProviderErrorKind,
} from '../src/index.js';
import { OUTPUT, ctx, fakeFetch, gatewayInput as input, json, specs } from './helpers/doubles.js';
import { capture, httpError, instant, scripted, setup, trace } from './helpers/gateway.js';

afterEach(() => {
  vi.useRealTimers();
});

describe('AIGateway basics', () => {
  it('routes each task to its preferred provider and records usage', async () => {
    const { gateway, usage } = setup();
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
    expect((await gateway.generate('weekly_summary', 'friendly', input, ctx)).providerId).toBe('openai');
    expect((await gateway.generate('monthly_summary', 'normal', input, ctx)).providerId).toBe('anthropic');
    expect((await gateway.generate('roast', 'roast', input, ctx)).providerId).toBe('xai');
    expect(usage.records).toHaveLength(4);
    expect(usage.records[0]).toMatchObject({ userRef: 'user-ref-7f3a', task: 'insight', providerId: 'google', costBasis: 'provider_estimate', usageReported: true });
    expect(usage.records[0]!.estimatedCostUsd).toBeGreaterThan(0);
  });

  it('accepts fenced JSON and forces the requested tone', async () => {
    const { providers, gateway } = setup();
    providers.google.set({
      text: '```json\n{"title":"Heavy month","message":"34% more than last month.","tone":"normal","severity":"notice","emoji":"💀"}\n```',
    });
    const r = await gateway.generate('insight', 'funny', input, ctx);
    expect(r.output).toEqual({ title: 'Heavy month', message: '34% more than last month.', tone: 'funny', severity: 'notice', emoji: '💀' });
  });

  it('gives premium users a larger output budget', async () => {
    const { providers, gateway } = setup();
    await gateway.generate('insight', 'normal', input, ctx);
    await gateway.generate('insight', 'normal', input, { ...ctx, plan: 'premium' });
    expect(providers.google.calls[0]!.maxOutputTokens).toBeLessThan(providers.google.calls[1]!.maxOutputTokens);
  });

  it('is a timestamped record: createdAt comes from the injected clock', async () => {
    const { gateway, usage } = setup();
    await gateway.generate('insight', 'normal', input, ctx);
    expect(usage.records[0]!.createdAt).toEqual(new Date(1_000_000));
  });
});

describe('input privacy', () => {
  it.each(['email', 'userId', 'deviceId', 'token', 'ip', 'name'])('refuses input that carries %s', async (key) => {
    const { gateway, providers } = setup();
    await expect(gateway.generate('insight', 'normal', { ...input, [key]: 'x' }, ctx)).rejects.toMatchObject({ code: 'invalid_input' });
    expect(Object.values(providers).every((p) => p.calls.length === 0)).toBe(true);
  });

  it('never puts the opaque user reference into a prompt', async () => {
    const { gateway, providers } = setup();
    await gateway.generate('insight', 'normal', input, ctx);
    const sent = providers.google.calls[0]!;
    expect(sent.system + sent.user).not.toContain(ctx.userRef);
  });
});

describe('tier selection', () => {
  it('maps tasks to tiers: insight/roast fast, weekly/monthly quality', () => {
    expect(TASK_TIER).toEqual({ insight: 'fast', roast: 'fast', weekly_summary: 'quality', monthly_summary: 'quality' });
  });

  it.each(AI_TASKS)('%s reaches the provider with its tier (premium)', async (task) => {
    const { gateway, providers } = setup();
    await gateway.generate(task, task === 'roast' ? 'roast' : 'normal', input, { ...ctx, plan: 'premium' });
    const first = providers[DEFAULT_ROUTING[task][0]!];
    expect(first.calls[0]!.tier).toBe(TASK_TIER[task]);
    expect(first.calls[0]!.task).toBe(task);
  });

  it.each(AI_TASKS)('%s on the free plan always uses the fast tier: accounts cost nothing to create (B-08)', async (task) => {
    const { gateway, providers } = setup();
    await gateway.generate(task, task === 'roast' ? 'roast' : 'normal', input, { ...ctx, plan: 'free' });
    expect(providers[DEFAULT_ROUTING[task][0]!].calls[0]!.tier).toBe('fast');
  });

  describe.each(specs)('with the real $name adapter', (spec) => {
    const modelFor = async (task: AITask, cfg: { fast?: string; quality?: string }) => {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      const gateway = new AIGateway({ router: new ProviderRouter([spec.make(fetchImpl, { models: cfg })], { routing: Object.fromEntries(AI_TASKS.map((t) => [t, [spec.name]])) as never }) });
      await gateway.generate(task, 'normal', input, { ...ctx, plan: 'premium' });
      return calls[0]!.url + JSON.stringify(calls[0]!.body);
    };

    it.each([
      ['insight', 'F-model'],
      ['roast', 'F-model'],
      ['weekly_summary', 'Q-model'],
      ['monthly_summary', 'Q-model'],
    ] as const)('%s uses the %s when both are configured', async (task, expected) => {
      expect(await modelFor(task, { fast: 'F-model', quality: 'Q-model' })).toContain(expected);
    });

    it.each(AI_TASKS)('%s falls back to the only configured model (fast only / quality only)', async (task) => {
      expect(await modelFor(task, { fast: 'only-fast' })).toContain('only-fast');
      expect(await modelFor(task, { quality: 'only-quality' })).toContain('only-quality');
    });
  });
});

describe('routing and fallback order', () => {
  it.each(AI_TASKS)('%s: the first provider of the routing order answers and nobody else is asked', async (task) => {
    const { providers, gateway } = setup();
    const order = trace(providers);
    const r = await gateway.generate(task, 'normal', input, ctx);
    expect(order).toEqual([DEFAULT_ROUTING[task][0]]);
    expect(r).toMatchObject({ providerId: DEFAULT_ROUTING[task][0], fallbacks: [] });
  });

  it.each(AI_TASKS)('%s: when the first provider is down the SECOND answers and the third and fourth are never asked', async (task) => {
    const { providers, gateway } = setup();
    const order = trace(providers);
    const [a, b, c, d] = DEFAULT_ROUTING[task];
    providers[a!].set({ fail: true });
    const r = await gateway.generate(task, 'normal', input, ctx);
    expect(r.providerId).toBe(b);
    expect(r.fallbacks).toEqual([a]);
    expect(new Set(order)).toEqual(new Set([a, b]));
    expect(providers[c!].calls).toHaveLength(0);
    expect(providers[d!].calls).toHaveLength(0);
  });

  it('a provider that is not configured is skipped without any attempt', async () => {
    const providers = { openai: new MockProvider('openai'), xai: new MockProvider('xai') };
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.providerId).toBe('openai');
    expect(r.fallbacks).toEqual([]);
  });

  it('with no provider configured at all the error is no_provider, not a provider failure', async () => {
    const gateway = new AIGateway({ router: new ProviderRouter([]) });
    await expect(gateway.generate('insight', 'normal', input, ctx)).rejects.toMatchObject({ code: 'no_provider', message: 'no AI provider is configured', attempts: [] });
  });

  const err = (status: number, extra: Partial<ConstructorParameters<typeof ProviderError>[4]> = {}) => () => httpError('google', status, extra.retryAfterMs);
  const kind = (k: ProviderErrorKind, status?: number) => () => new ProviderError('google', `${k} failure`, status, k === 'timeout' || k === 'network', { kind: k });

  /**
   * Every failure the gateway distinguishes, the category it is reported as, and whether the request may go
   * to the other provider. The rule: a failure that is the provider's (down, slow, overloaded) may; a failure
   * that would repeat or hide a defect (bad request, bad key, refusal, unusable answer) may not.
   */
  const failures: [string, () => ProviderError | { text: string }, ProviderErrorKind, AIErrorCategory, boolean][] = [
    ['HTTP 400', err(400), 'http', 'invalid_request', false],
    ['HTTP 401 (bad or revoked key)', err(401), 'http', 'authentication', false],
    ['HTTP 403', err(403), 'http', 'authentication', false],
    ['HTTP 404 (wrong model name)', err(404), 'http', 'invalid_request', false],
    ['HTTP 422', err(422), 'http', 'invalid_request', false],
    ['HTTP 408', err(408), 'http', 'timeout', true],
    ['HTTP 429', err(429), 'http', 'rate_limit', true],
    ['HTTP 429 with a long Retry-After', err(429, { retryAfterMs: 20_000 }), 'http', 'rate_limit', true],
    ['HTTP 500', err(500), 'http', 'provider_unavailable', true],
    ['HTTP 502', err(502), 'http', 'provider_unavailable', true],
    ['HTTP 503', err(503), 'http', 'provider_unavailable', true],
    ['HTTP 529 (overloaded)', err(529), 'http', 'provider_unavailable', true],
    ['timeout', kind('timeout'), 'timeout', 'timeout', true],
    ['network error', kind('network'), 'network', 'provider_unavailable', true],
    ['non-JSON 2xx body', kind('invalid_response', 200), 'invalid_response', 'response', true],
    ['refusal from the provider', kind('refusal'), 'refusal', 'response', false],
    ['empty output', () => ({ text: '' }), 'empty_output', 'response', false],
    ['whitespace-only output', () => ({ text: ' \n ' }), 'empty_output', 'response', false],
    ['prose instead of JSON', () => ({ text: 'Sure! You used a lot of data.' }), 'invalid_output', 'response', false],
    ['truncated JSON', () => ({ text: '{"title":"Heavy","message":"cut' }), 'invalid_output', 'response', false],
    ['wrong schema', () => ({ text: JSON.stringify({ title: 'only a title' }) }), 'invalid_output', 'response', false],
    ['missing field', () => ({ text: JSON.stringify({ title: 'x', message: 'y', severity: 'info' }) }), 'invalid_output', 'response', false],
    ['unknown severity', () => ({ text: JSON.stringify({ ...OUTPUT, severity: 'catastrophe' }) }), 'invalid_output', 'response', false],
  ];

  it.each(failures)('%s -> kind %s? category %s, the other provider is asked: %s', async (_name, make, expectedKind, category, fallsBack) => {
    const { providers, gateway } = setup();
    const f = make();
    providers.google.set(f instanceof ProviderError ? { fail: f } : f);
    const outcome = await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e);
    if (fallsBack) {
      expect(outcome).toMatchObject({ providerId: 'openai', fallbacks: ['google'], output: { tone: 'normal' } });
      expect(providers.xai.calls).toHaveLength(0);
      expect(providers.anthropic.calls).toHaveLength(0);
    } else {
      expect(outcome).toBeInstanceOf(AIGatewayError);
      expect(outcome).toMatchObject({ code: 'all_providers_failed', attempts: [{ providerId: 'google', kind: expectedKind, category }] });
      // No second paid call for something that would fail the same way (or hide a defect).
      for (const id of ['openai', 'xai', 'anthropic'] as const) expect(providers[id].calls, id).toHaveLength(0);
    }
    // An availability failure demotes the provider at once: it is not paid for again on the next request. An unusable
    // answer from a provider that is otherwise up does not (D-08): one bad answer is not an outage.
    expect(providers.google.calls.length).toBeGreaterThan(0);
    const callsBefore = providers.google.calls.length;
    const availability = category !== 'response' || expectedKind === 'invalid_response';
    expect(gateway.status().providers.find((p) => p.id === 'google')).toMatchObject({ configured: true, inCooldown: availability });
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(providers.google.calls.length).toBe(availability ? callsBefore : callsBefore + 1);
  });

  it('a failure that may fall back stops after ONE fallback, even when that one fails too and more providers are healthy', async () => {
    const { providers, gateway } = setup();
    const order = trace(providers);
    for (const id of ['google', 'openai'] as const) providers[id].set({ fail: true });
    const err2 = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;
    expect(err2.code).toBe('all_providers_failed');
    expect(err2.attempts.map((a) => a.providerId)).toEqual(['google', 'openai']);
    expect(new Set(order)).toEqual(new Set(['google', 'openai']));
    expect(providers.xai.calls).toHaveLength(0);
    expect(providers.anthropic.calls).toHaveLength(0);
  });

  it('the fallback runs in both directions: OpenAI -> xAI and xAI -> OpenAI', async () => {
    for (const [first, second] of [['openai', 'xai'], ['xai', 'openai']] as const) {
      const providers = { openai: new MockProvider('openai'), xai: new MockProvider('xai') };
      const routing = Object.fromEntries(AI_TASKS.map((t) => [t, [first, second]])) as never;
      const { sleep, random } = instant();
      const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers), { routing }), sleep, random });
      providers[first].set({ fail: httpError(first, 503) });
      const r = await gateway.generate('insight', 'normal', input, ctx);
      expect(r).toMatchObject({ providerId: second, fallbacks: [first] });
    }
  });

  it('no endless loop: two providers that both keep failing end in exactly one error after one call chain', async () => {
    const providers = { openai: new MockProvider('openai', { fail: httpError('openai', 503) }), xai: new MockProvider('xai', { fail: httpError('xai', 503) }) };
    const { sleep, random } = instant();
    const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers), { cooldownMs: 0 }), sleep, random, maxRetries: 2 });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.attempts).toHaveLength(2);
    // 1 call + 2 retries on each of the two providers, and nothing more.
    expect(providers.openai.calls.length + providers.xai.calls.length).toBe(6);
  });
});

describe.each(specs)('structured output and HTTP status through the real $name adapter', (spec) => {
  /** The adapter under test first, a healthy mock second: what the caller gets after a failure. */
  const chain = (reply: Parameters<typeof fakeFetch>[0], opts: Partial<GatewayOptions> = {}) => {
    const { fetchImpl, calls } = fakeFetch(reply);
    const fallback = new MockProvider(spec.name === 'openai' ? 'anthropic' : 'openai');
    const router = new ProviderRouter([spec.make(fetchImpl), fallback], {
      routing: Object.fromEntries(AI_TASKS.map((t) => [t, [spec.name, fallback.id]])) as never,
      now: () => 0,
    });
    const { sleeps, sleep, random } = instant();
    return { gateway: new AIGateway({ router, sleep, random, ...opts }), router, calls, fallback, sleeps };
  };

  it.each([
    ['prose instead of JSON', 'Sure! Here is an insight.', 'invalid_output'],
    ['empty text', '', 'empty_output'],
    ['truncated JSON', '{"title":"Heavy","message":"cut', 'invalid_output'],
    ['a different schema', JSON.stringify({ title: 'only a title' }), 'invalid_output'],
    ['an unknown severity', JSON.stringify({ ...OUTPUT, severity: 'catastrophe' }), 'invalid_output'],
    ['a missing field', JSON.stringify({ title: 'x', message: 'y', severity: 'info' }), 'invalid_output'],
  ] as const)('%s is rejected, classified, and NOT sent to the other provider (a rejected answer is already billed)', async (_name, text, kind) => {
    const { gateway, fallback, calls } = chain({ body: spec.success(text) });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e).toMatchObject({ code: 'all_providers_failed', attempts: [{ providerId: spec.name, kind, category: 'response' }] });
    expect(calls).toHaveLength(1); // and not retried either
    expect(fallback.calls).toHaveLength(0);
  });

  it.each(spec.refusals.map((body, i) => [i, body] as const))('refusal variant %i is a refusal: no retry, no fallback', async (_i, body) => {
    const { gateway, fallback, calls } = chain({ body });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.attempts).toMatchObject([{ providerId: spec.name, kind: 'refusal', category: 'response' }]);
    expect(calls).toHaveLength(1);
    expect(fallback.calls).toHaveLength(0);
  });

  it.each([400, 401, 403, 404, 422])('HTTP %i is the request\'s or the key\'s fault: one call, no retry, no fallback, but the provider is demoted', async (status) => {
    const { gateway, router, fallback, calls } = chain({ status, body: { error: { type: 'x_error', message: 'SENTINEL' } } });
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e).toMatchObject({ code: 'all_providers_failed', attempts: [{ providerId: spec.name, kind: 'http', status }] });
    expect(calls).toHaveLength(1);
    expect(fallback.calls).toHaveLength(0);
    expect(router.inCooldown(spec.name)).toBe(true);
    // The next request does not pay for it again: the provider is out and the other one answers.
    const next = await gateway.generate('insight', 'normal', input, ctx);
    expect(next.providerId).toBe(fallback.id);
    expect(calls).toHaveLength(1);
  });

  it.each([408, 429, 500, 502, 503, 504, 529])('HTTP %i is retried with backoff, then the other provider answers and this one is demoted', async (status) => {
    const { gateway, router, fallback, calls, sleeps } = chain({ status, body: { error: { type: 'x_error', message: 'SENTINEL' } } });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r).toMatchObject({ providerId: fallback.id, fallbacks: [spec.name] });
    expect(calls).toHaveLength(3); // the call and two retries
    expect(sleeps).toEqual([500, 1000]);
    expect(router.inCooldown(spec.name)).toBe(true);
  });

  it('a 429 with Retry-After keeps the provider out for as long as it asked, read from the real header', async () => {
    const { gateway, router } = chain({ status: 429, headers: { 'retry-after': '300' }, body: {} });
    await gateway.generate('insight', 'normal', input, ctx);
    expect(router.health().find((h) => h.id === spec.name)).toMatchObject({ inCooldown: true, retryInMs: 300_000 });
  });

  it('a 429 with a short Retry-After is waited for, then retried', async () => {
    const { gateway, calls, sleeps } = chain((n) => (n === 1 ? { status: 429, headers: { 'retry-after': '2' }, body: {} } : { body: spec.success(json) }));
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.providerId).toBe(spec.name);
    expect(calls).toHaveLength(2);
    expect(sleeps).toEqual([2000]);
  });

  it('an account without quota (429 insufficient_quota) is not waited for: straight to the other provider', async () => {
    const { gateway, calls, fallback, sleeps } = chain({ status: 429, body: { error: { type: 'insufficient_quota', code: 'insufficient_quota', message: 'x' } } });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.providerId).toBe(fallback.id);
    expect(calls).toHaveLength(1);
    expect(sleeps).toEqual([]);
  });
});

describe('concurrent requests share one router safely', () => {
  it('25 parallel requests while the first provider is down all get an answer, and the cooldown stays bounded', async () => {
    const { providers, gateway, router } = setup({ cooldownMs: 60_000 });
    providers.google.set({ fail: true });
    const results = await Promise.all(Array.from({ length: 25 }, () => gateway.generate('insight', 'normal', input, ctx)));
    expect(results.every((r) => r.providerId === 'openai' && r.fallbacks.length === 1)).toBe(true);
    const health = router.health().find((h) => h.id === 'google')!;
    expect(health.consecutiveFailures).toBe(25);
    expect(health.retryInMs).toBe(600_000); // doubling is capped, never overflows
    expect(Number.isFinite(health.retryInMs)).toBe(true);
  });

  it('a success of one request does not hide the failure of another provider', async () => {
    const { providers, gateway, router } = setup();
    providers.xai.set({ fail: true });
    await Promise.all([gateway.generate('roast', 'roast', input, ctx), gateway.generate('insight', 'normal', input, ctx), gateway.generate('weekly_summary', 'normal', input, ctx)]);
    expect(router.inCooldown('xai')).toBe(true);
    expect(router.inCooldown('google')).toBe(false);
    expect(router.inCooldown('openai')).toBe(false);
  });
});

describe('cooldown after failures', () => {
  it('a failed provider sits out for cooldownMs and comes back after it', async () => {
    const { providers, gateway, tick } = setup({ cooldownMs: 60_000 });
    providers.xai.set({ fail: true });
    const first = await gateway.generate('roast', 'roast', input, ctx);
    expect(first.providerId).toBe('openai');
    expect(first.fallbacks).toEqual(['xai']);
    expect(providers.anthropic.calls).toHaveLength(0);
    // The transient failure was retried twice before the router was told: one demotion per request, not per call.
    expect(providers.xai.calls).toHaveLength(3);

    providers.xai.set({ fail: false });
    const second = await gateway.generate('roast', 'roast', input, ctx);
    expect(second.providerId).toBe('openai'); // still cooling down, not even asked
    expect(second.fallbacks).toEqual([]);
    expect(providers.xai.calls).toHaveLength(3);

    tick(61_000);
    expect((await gateway.generate('roast', 'roast', input, ctx)).providerId).toBe('xai');
  });

  it.each([
    ['HTTP 400', () => ({ fail: httpError('google', 400) })],
    ['HTTP 401 (bad key)', () => ({ fail: httpError('google', 401) })],
    ['HTTP 429', () => ({ fail: httpError('google', 429) })],
    ['HTTP 503', () => ({ fail: httpError('google', 503) })],
    ['timeout', () => ({ fail: new ProviderError('google', 't', undefined, true, { kind: 'timeout' }) })],
  ])('%s demotes the provider at once: a broken provider must not be paid for on every request', async (_name, behaviour) => {
    const { providers, gateway, router } = setup();
    providers.google.set(behaviour());
    // Failures that may not fall back surface as an error on THIS request; the next one is already served by another provider.
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(router.inCooldown('google')).toBe(true);
    const callsAfterFirst = providers.google.calls.length;
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('openai');
    expect(providers.google.calls).toHaveLength(callsAfterFirst);
  });

  it.each([
    ['refusal', () => ({ fail: new ProviderError('google', 'r', undefined, false, { kind: 'refusal' }) })],
    ['malformed output', () => ({ text: 'not json' })],
    ['empty output', () => ({ text: '' })],
  ])('%s is a property of one answer: one does not demote the provider, a persistent run of them does (D-08)', async (_name, behaviour) => {
    const { providers, gateway, router } = setup();
    providers.google.set(behaviour());
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(router.inCooldown('google')).toBe(false); // a bad answer is not an outage: the next request asks it again
    for (let i = 0; i < 8; i++) await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(router.inCooldown('google')).toBe(true); // ... but a provider that gets it wrong every time is parked
    const callsAfter = providers.google.calls.length;
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('openai');
    expect(providers.google.calls).toHaveLength(callsAfter);
  });

  it('repeated failures lengthen the cooldown; a success resets it', async () => {
    const { providers, gateway, router, tick } = setup({ cooldownMs: 10_000 });
    const retryIn = () => router.health().find((h) => h.id === 'google')!.retryInMs;
    providers.google.set({ fail: true });
    await gateway.generate('insight', 'normal', input, ctx);
    expect(retryIn()).toBe(10_000);
    tick(10_000);
    await gateway.generate('insight', 'normal', input, ctx); // probe fails again
    expect(retryIn()).toBe(20_000);
    tick(20_000);
    providers.google.set({ fail: false });
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
    expect(router.health().find((h) => h.id === 'google')).toMatchObject({ consecutiveFailures: 0, inCooldown: false });
  });

  it('a retry that succeeds never reaches the router: no demotion, no failure streak', async () => {
    const flaky = scripted('google', [httpError('google', 503), 'ok']);
    const router = new ProviderRouter([flaky, new MockProvider('openai')]);
    const r = await new AIGateway({ router, ...instant() }).generate('insight', 'normal', input, ctx);
    expect(r).toMatchObject({ providerId: 'google', fallbacks: [] });
    expect(flaky.calls).toHaveLength(2);
    expect(router.health().every((h) => h.consecutiveFailures === 0 && !h.inCooldown)).toBe(true);
  });

  it('honours Retry-After from a 429 when it is longer than the cooldown', async () => {
    const { providers, gateway, router, tick } = setup({ cooldownMs: 10_000 });
    providers.google.set({ fail: httpError('google', 429, 120_000) });
    await gateway.generate('insight', 'normal', input, ctx);
    tick(60_000);
    expect(router.inCooldown('google')).toBe(true);
    tick(60_000);
    expect(router.inCooldown('google')).toBe(false);
  });

  it('a cooling provider is the last choice: while a healthy one exists it is neither first nor the fallback', async () => {
    const { providers, gateway } = setup();
    providers.google.set({ fail: true });
    await gateway.generate('insight', 'normal', input, ctx); // google now cools down
    providers.google.set({ fail: false });
    for (const id of ['openai', 'xai'] as const) providers[id].set({ fail: true });
    const googleCalls = providers.google.calls.length;
    const err = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;
    // openai fails, the one fallback (xai) fails: the cooling google is not dragged in as a third paid call.
    expect(err.attempts.map((a) => a.providerId)).toEqual(['openai', 'xai']);
    expect(providers.google.calls).toHaveLength(googleCalls);
  });

  it('a provider that is cooling down is still tried when it is the only one left (an outage is not "no provider")', async () => {
    const only = new MockProvider('google');
    const router = new ProviderRouter([only], { cooldownMs: 60_000, now: () => 0 });
    router.markFailure('google');
    const gateway = new AIGateway({ router, ...instant() });
    expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('google');
  });
});

describe('all providers failing', () => {
  it('is ONE typed error with a generic message and content-free per-provider reasons (the provider and its one fallback)', async () => {
    const { providers, gateway } = setup();
    providers.google.set({ fail: new ProviderError('google', 'timeout after 20000 ms', undefined, true, { kind: 'timeout' }) });
    providers.openai.set({ fail: httpError('openai', 429, 5000) });
    const err = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;

    expect(err).toBeInstanceOf(AIGatewayError);
    expect(err).toMatchObject({ name: 'AIGatewayError', code: 'all_providers_failed', message: 'all AI providers failed' });
    expect(err.attempts).toEqual([
      { providerId: 'google', kind: 'timeout', category: 'timeout', status: undefined },
      { providerId: 'openai', kind: 'http', category: 'rate_limit', status: 429 },
    ]);
    expect(err.causes).toHaveLength(2);
    for (const forbidden of ['HTTP', 'timeout', 'ECONNRESET', 'openai', 'google', 'anthropic', 'xai']) expect(err.message).not.toContain(forbidden);
  });

  it.each(specs)('through the real $name adapter, nothing the provider said (prompt echoes included) survives in the error', async (spec) => {
    const echo = 'SENTINEL-ECHO your prompt: period: 2026-10 mobile data: 187.4 GB';
    for (const status of [400, 503]) {
      const adapters = [spec.make(fakeFetch({ status, body: { error: { message: echo, type: 'invalid_request_error' } } }).fetchImpl)];
      const gateway = new AIGateway({ router: new ProviderRouter(adapters), ...instant() });
      const err = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;

      expect(err.code).toBe('all_providers_failed');
      const everything = JSON.stringify({ m: err.message, a: err.attempts, c: err.causes.map((c) => c.message), s: err.stack });
      expect(everything).not.toContain('SENTINEL-ECHO');
      expect(everything).not.toContain('187.4');
      expect(everything).not.toMatch(/k-(openai|xai|anthropic|google)/);
      expect(err.causes.map((c) => c.message)).toEqual([`${spec.name}: HTTP ${status} (invalid_request_error)`]);
    }
  });

  it('an unexpected exception inside a provider is contained, classified, its message dropped, and not sent to another provider', async () => {
    const { providers, gateway } = setup();
    providers.google.generate = () => Promise.reject(new TypeError('Cannot read properties of undefined (SENTINEL-SECRET)'));
    const err = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;
    expect(err.attempts).toEqual([{ providerId: 'google', kind: 'unexpected', category: 'response', status: undefined }]);
    expect(JSON.stringify(err.causes.map((c) => c.message))).not.toContain('SENTINEL-SECRET');
    expect(providers.openai.calls).toHaveLength(0);
  });
});

describe('timeout end to end', () => {
  it('a provider that never answers is aborted at the configured timeout, the router moves on, no timer is left', async () => {
    vi.useFakeTimers();
    const { fetchImpl, calls } = fakeFetch({ hangIgnoringSignal: true });
    const google = new GoogleProvider({ apiKey: 'k-google', models: { fast: 'm' }, fetchImpl });
    const openai = new MockProvider('openai');
    const { logger, entries } = capture();
    const gateway = new AIGateway({ router: new ProviderRouter([google, openai]), timeoutMs: 7000, logger });

    const pending = gateway.generate('insight', 'normal', input, ctx);
    await vi.advanceTimersByTimeAsync(6999);
    expect(calls).toHaveLength(1);
    expect(openai.calls).toHaveLength(0); // not before the timeout
    await vi.advanceTimersByTimeAsync(1);
    const r = await pending;

    expect(r.providerId).toBe('openai');
    expect(r.fallbacks).toEqual(['google']);
    expect(openai.calls[0]!.timeoutMs).toBe(7000);
    expect(entries.map((e) => e.entry.outcome)).toEqual(['timeout', 'ok']);
    expect(entries[0]!.entry).toMatchObject({ provider: 'google', model: 'm', task: 'insight' });
    expect(vi.getTimerCount()).toBe(0);
  });

  it('with real timers: gives up at the timeout, not much later, and answers from the fallback', async () => {
    const { fetchImpl } = fakeFetch({ hang: true });
    const google = new GoogleProvider({ apiKey: 'k', models: { fast: 'm' }, fetchImpl });
    const gateway = new AIGateway({ router: new ProviderRouter([google, new MockProvider('openai')]), timeoutMs: 120 });
    const started = Date.now();
    const r = await gateway.generate('insight', 'normal', input, ctx);
    const elapsed = Date.now() - started;
    expect(r.providerId).toBe('openai');
    expect(elapsed).toBeGreaterThanOrEqual(110);
    expect(elapsed).toBeLessThan(4000);
  });

  it('every provider hanging ends as one all_providers_failed after TWO timeouts (the provider and its one fallback), typed as timeout', async () => {
    vi.useFakeTimers();
    const adapters = specs.map((spec) => spec.make(fakeFetch({ hang: true }).fetchImpl));
    const routing = Object.fromEntries(AI_TASKS.map((t) => [t, specs.map((s) => s.name)])) as never;
    const gateway = new AIGateway({ router: new ProviderRouter(adapters, { routing }), timeoutMs: 1000 });
    const pending = gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(2000);
    const err = (await pending) as AIGatewayError;
    expect(err.code).toBe('all_providers_failed');
    expect(err.attempts.map((a) => [a.kind, a.category])).toEqual([['timeout', 'timeout'], ['timeout', 'timeout']]);
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each([0, -5, NaN, Infinity])('refuses a nonsensical timeout (%s) instead of timing out instantly or never', (timeoutMs) => {
    expect(() => new AIGateway({ router: new ProviderRouter([]), timeoutMs })).toThrow(RangeError);
  });

  it('passes its timeout to every provider as the per-attempt limit (default 20 s)', async () => {
    const { providers, gateway } = setup();
    await gateway.generate('insight', 'normal', input, ctx);
    expect(providers.google.calls[0]!.timeoutMs).toBe(20_000);
    const custom = setup({ timeoutMs: 3500 });
    await custom.gateway.generate('insight', 'normal', input, ctx);
    expect(custom.providers.google.calls[0]!.timeoutMs).toBe(3500);
  });
});

describe('usage and cost', () => {
  const reporting = (id: AIProviderId, extra: Partial<AIGenerationResult> = {}): AIProvider => ({
    id,
    healthCheck: async () => ({ providerId: id, ok: true }),
    generate: async () => ({ providerId: id, model: 'some-new-model', text: json, inputTokens: 1000, outputTokens: 500, latencyMs: 12, ...extra }),
  });
  const gatewayFor = (p: AIProvider, extra: Partial<ConstructorParameters<typeof AIGateway>[0]> = {}) => {
    const usage = new MemoryUsageSink();
    return { usage, gateway: new AIGateway({ router: new ProviderRouter([p]), usage, ...extra }) };
  };

  it('records the tokens and an estimate labelled as provider_estimate for a model without a price', async () => {
    const { usage, gateway } = gatewayFor(reporting('openai'));
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage).toMatchObject({ inputTokens: 1000, outputTokens: 500, estimatedCostUsd: 0.0012, costBasis: 'provider_estimate', usageReported: true, model: 'some-new-model', latencyMs: 12 });
    expect(usage.records).toEqual([r.usage]);
  });

  it('uses a configured per-model price and says so', async () => {
    const { gateway } = gatewayFor(reporting('openai'), { modelPrices: { 'some-new-model': { input: 10, output: 20 } } });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage).toMatchObject({ estimatedCostUsd: 0.02, costBasis: 'model_price' });
  });

  it('a provider that sends no usage yields unknown cost and usageReported=false, not a free call', async () => {
    const { logger, entries } = capture();
    const { gateway } = gatewayFor(reporting('openai', { inputTokens: 0, outputTokens: 0, usageReported: false }), { logger });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    // "No data" is booked at the worst case, never as $0 (D-07).
    expect(r.usage).toMatchObject({ inputTokens: 0, outputTokens: 0, costBasis: 'conservative_estimate', usageReported: false });
    expect(r.usage.estimatedCostUsd).toBeGreaterThan(0);
    expect(entries[0]!.entry).not.toHaveProperty('inputTokens'); // unreported is not logged as 0
  });

  it.each(specs)('end to end with the real $name adapter: wire usage -> UsageRecord', async (spec) => {
    const { fetchImpl } = fakeFetch({ body: spec.success('```json\n' + json + '\n```') });
    const gateway = new AIGateway({ router: new ProviderRouter([spec.make(fetchImpl)]) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.output).toEqual(OUTPUT);
    expect(r.usage).toMatchObject({ providerId: spec.name, inputTokens: spec.tokens.input, outputTokens: spec.tokens.output, costBasis: 'provider_estimate', usageReported: true });
    expect(r.usage.estimatedCostUsd).toBeGreaterThanOrEqual(0);
    expect(Number.isFinite(r.usage.estimatedCostUsd)).toBe(true);
  });

  it.each(specs)('end to end with the real $name adapter: missing wire usage -> unknown cost', async (spec) => {
    const { fetchImpl } = fakeFetch({ body: spec.success(json, null) });
    const gateway = new AIGateway({ router: new ProviderRouter([spec.make(fetchImpl)]) });
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.usage).toMatchObject({ inputTokens: 0, outputTokens: 0, costBasis: 'conservative_estimate', usageReported: false });
    expect(r.usage.estimatedCostUsd).toBeGreaterThan(0);
  });

  it('a usage sink that throws neither fails the request nor triggers another paid call, and is reported', async () => {
    const { logger, entries } = capture();
    const { providers, router, gateway } = (() => {
      const providers = { google: new MockProvider('google'), openai: new MockProvider('openai') };
      const router = new ProviderRouter(Object.values(providers));
      const gateway = new AIGateway({ router, logger, usage: { record: () => Promise.reject(new Error('db down SENTINEL-DB')) } });
      return { providers, router, gateway };
    })();
    const r = await gateway.generate('insight', 'normal', input, ctx);
    expect(r.providerId).toBe('google');
    expect(providers.openai.calls).toHaveLength(0);
    expect(router.inCooldown('google')).toBe(false);
    const warning = entries.find((e) => e.entry.event === 'ai.usage_record_failed');
    expect(warning).toMatchObject({ level: 'warn', entry: { provider: 'google', error: 'Error' } });
    expect(JSON.stringify(entries)).not.toContain('SENTINEL-DB');
  });

  it('a rejected answer is still logged with the tokens it cost', async () => {
    const { logger, entries } = capture();
    const { fetchImpl } = fakeFetch({ body: specs[0]!.success('prose, no json') });
    const gateway = new AIGateway({ router: new ProviderRouter([specs[0]!.make(fetchImpl)]), logger });
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(entries[0]).toMatchObject({ level: 'warn', entry: { outcome: 'invalid_output', provider: 'openai', inputTokens: 11, outputTokens: 7 } });
  });
});

describe('telemetry and PII hygiene', () => {
  const ALLOWED = new Set(['event', 'provider', 'model', 'task', 'outcome', 'category', 'httpStatus', 'attempt', 'fallback', 'latencyMs', 'inputTokens', 'outputTokens', 'requestId']);
  const SECRET_OUTPUT = 'SENTINEL-MODEL-TEXT';
  const SECRET_BODY = 'SENTINEL-PROVIDER-BODY your prompt was: period 2026-10';

  /** Every kind of attempt in one run, over the real adapters, with a logger attached. */
  async function scenario() {
    const { logger, entries } = capture();
    const reply = (i: number) =>
      [
        { body: specs[0]!.success(JSON.stringify({ ...OUTPUT, message: SECRET_OUTPUT })) }, // ok
        { status: 429, headers: { 'retry-after': '3' }, body: { error: { message: SECRET_BODY, type: 'rate_limit_error' } } },
        { body: specs[0]!.success(`prose ${SECRET_OUTPUT}`) }, // invalid output
        { body: specs[0]!.refusals[0] }, // refusal
        { networkError: new TypeError(`fetch failed ${SECRET_BODY}`) },
        { status: 500, raw: SECRET_BODY },
      ][i]!;
    for (let i = 0; i < 6; i += 1) {
      const { fetchImpl } = fakeFetch(reply(i));
      const gateway = new AIGateway({ router: new ProviderRouter([specs[0]!.make(fetchImpl)], { cooldownMs: 0 }), logger, maxRetries: 0, ...instant() });
      await gateway.generate('weekly_summary', 'friendly', input, { ...ctx, userRef: 'USER-REF-SENTINEL' }).catch(() => undefined);
    }
    const hang = fakeFetch({ hang: true });
    const google = specs.find((s) => s.name === 'google')!;
    const timed = new AIGateway({ router: new ProviderRouter([google.make(hang.fetchImpl)]), logger, timeoutMs: 30, ...instant() });
    await timed.generate('insight', 'normal', input, ctx).catch(() => undefined);
    return entries;
  }

  it('logs only provider, model, task, outcome, status, latency and token counts (assert on a captured logger)', async () => {
    const entries = await scenario();
    expect(entries.map((e) => e.entry.outcome)).toEqual(['ok', 'http', 'invalid_output', 'refusal', 'network', 'http', 'timeout']);
    for (const { entry } of entries) {
      for (const key of Object.keys(entry)) expect(ALLOWED.has(key), `unexpected log field: ${key}`).toBe(true);
      expect(entry.event).toBe('ai.attempt');
      expect(typeof entry.latencyMs).toBe('number');
      expect(Number.isFinite(entry.latencyMs as number)).toBe(true);
      for (const v of Object.values(entry)) expect(['string', 'number', 'boolean']).toContain(typeof v);
    }
    expect(entries[0]!.entry).toMatchObject({ provider: 'openai', task: 'weekly_summary', inputTokens: 11, outputTokens: 7, attempt: 1, fallback: false });
    expect(entries[1]!.entry).toMatchObject({ outcome: 'http', category: 'rate_limit', httpStatus: 429 });
    expect(entries[3]!.entry).toMatchObject({ outcome: 'refusal', inputTokens: 20, outputTokens: 9 });
    expect(entries[6]!.entry).toMatchObject({ provider: 'google', outcome: 'timeout' });
    expect(entries.filter((e) => e.level === 'info').map((e) => e.entry.outcome)).toEqual(['ok']);
  });

  it('never contains prompts, model text, provider bodies, user references or keys', async () => {
    const entries = await scenario();
    const serialised = JSON.stringify(entries);
    for (const forbidden of [
      SECRET_OUTPUT,
      'SENTINEL-PROVIDER-BODY',
      'USER-REF-SENTINEL',
      'user-ref-7f3a',
      'Heavy month', // output title
      'SYSTEM PROMPT',
      'You are WattByte', // system prompt
      '187.4', // an aggregate from the user prompt
      'PLN',
      'k-openai',
      'k-google',
      'Bearer',
      'authorization',
    ]) {
      expect(serialised, forbidden).not.toContain(forbidden);
    }
  });

  it('a logger that throws cannot break generation', async () => {
    const stderr = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    try {
      const boom: GatewayLogger = { info: () => { throw new Error('logger down'); }, warn: () => { throw new Error('logger down'); } };
      const providers = { google: new MockProvider('google', { fail: true }), openai: new MockProvider('openai') };
      const gateway = new AIGateway({ router: new ProviderRouter(Object.values(providers)), logger: boom });
      expect((await gateway.generate('insight', 'normal', input, ctx)).providerId).toBe('openai');
      expect(stderr).toHaveBeenCalledWith('ai gateway: logger failed', 'Error');
    } finally {
      stderr.mockRestore();
    }
  });

  it('works without a logger at all', async () => {
    const { gateway } = setup();
    await expect(gateway.generate('insight', 'normal', input, ctx)).resolves.toBeDefined();
  });
});
