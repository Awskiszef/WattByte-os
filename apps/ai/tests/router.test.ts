// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import { DEFAULT_ROUTING, MockProvider, ProviderRouter, AI_PROVIDER_IDS, AI_TASKS, type AIProviderId } from '../src/index.js';

function make(opts: ConstructorParameters<typeof ProviderRouter>[1] = {}, ids: readonly AIProviderId[] = AI_PROVIDER_IDS) {
  let now = 1_000_000;
  const router = new ProviderRouter(ids.map((id) => new MockProvider(id)), { now: () => now, ...opts });
  return { router, tick: (ms: number) => (now += ms) };
}
const order = (r: ProviderRouter, task: (typeof AI_TASKS)[number]) => r.order(task).map((p) => p.id);

describe('routing order', () => {
  it.each(AI_TASKS.map((t) => [t, DEFAULT_ROUTING[t]] as const))('%s follows the documented order', (task, expected) => {
    expect(order(make().router, task)).toEqual([...expected]);
  });

  it('skips providers that are not configured and keeps the rest in order', () => {
    expect(order(make({}, ['anthropic', 'openai']).router, 'insight')).toEqual(['openai', 'anthropic']);
    expect(order(make({}, []).router, 'insight')).toEqual([]);
  });

  it('honours a custom routing table', () => {
    const routing = { ...DEFAULT_ROUTING, insight: ['xai', 'anthropic'] as const };
    expect(order(make({ routing }).router, 'insight')).toEqual(['xai', 'anthropic']);
  });

  it('never fans out: order() is a plain list tried one at a time', () => {
    expect(new Set(order(make().router, 'roast')).size).toBe(4);
  });
});

describe('preferred provider and exclusions', () => {
  it('a preferred provider leads, the rest keep the task order behind it', () => {
    const { router } = make();
    expect(order(router, 'insight')).toEqual(['google', 'openai', 'xai', 'anthropic']);
    expect(router.order('insight', { prefer: 'xai' }).map((p) => p.id)).toEqual(['xai', 'google', 'openai', 'anthropic']);
    expect(router.order('roast', { prefer: 'anthropic' }).map((p) => p.id)).toEqual(['anthropic', 'xai', 'openai', 'google']);
  });

  it('a preferred provider that is not configured changes nothing', () => {
    const { router } = make({}, ['openai', 'google']);
    expect(router.order('insight', { prefer: 'xai' }).map((p) => p.id)).toEqual(['google', 'openai']);
  });

  it('a preferred provider outside the task\'s table is still used when configured', () => {
    const routing = { ...DEFAULT_ROUTING, insight: ['google'] as const };
    const { router } = make({ routing });
    expect(router.order('insight', { prefer: 'xai' }).map((p) => p.id)).toEqual(['xai', 'google']);
  });

  it('a preferred provider that is cooling down is left out while others are healthy (the default must not be a single point of failure)', () => {
    const { router } = make();
    router.markFailure('xai');
    expect(router.order('insight', { prefer: 'xai' }).map((p) => p.id)).toEqual(['google', 'openai', 'anthropic']);
  });

  it('when only cooling providers are left, the preferred one is probed first', () => {
    const { router } = make({}, ['xai', 'google']);
    router.markFailure('google');
    router.markFailure('xai');
    expect(router.order('insight', { prefer: 'xai' }).map((p) => p.id)).toEqual(['xai', 'google']);
  });

  it('excluded providers are gone, even when preferred', () => {
    const { router } = make();
    expect(router.order('insight', { exclude: new Set(['google']) }).map((p) => p.id)).toEqual(['openai', 'xai', 'anthropic']);
    expect(router.order('insight', { prefer: 'xai', exclude: new Set(['xai']) }).map((p) => p.id)).toEqual(['google', 'openai', 'anthropic']);
    expect(router.order('insight', { exclude: new Set(['google', 'openai', 'xai', 'anthropic']) })).toEqual([]);
  });

  it('is a pure view: asking for an order does not change the next one', () => {
    const { router } = make();
    router.order('insight', { prefer: 'xai', exclude: new Set(['openai']) });
    expect(order(router, 'insight')).toEqual(['google', 'openai', 'xai', 'anthropic']);
  });
});

describe('cooldown', () => {
  it('leaves a failed provider out while others are healthy, and restores it after the cooldown', () => {
    const { router, tick } = make({ cooldownMs: 60_000 });
    router.markFailure('google');
    expect(router.inCooldown('google')).toBe(true);
    expect(order(router, 'insight')).toEqual(['openai', 'xai', 'anthropic']);
    tick(59_999);
    expect(router.inCooldown('google')).toBe(true);
    tick(1);
    expect(router.inCooldown('google')).toBe(false);
    expect(order(router, 'insight')).toEqual(['google', 'openai', 'xai', 'anthropic']);
  });

  it('with everything cooling, ONE probe per probeIntervalMs gets through (in routing order); the rest fail fast (D-09)', () => {
    const { router, tick } = make({ cooldownMs: 60_000, probeIntervalMs: 5_000 }, ['google', 'openai']);
    router.markFailure('google');
    router.markFailure('openai');
    expect(order(router, 'insight')).toEqual(['google', 'openai']); // the first request probes
    expect(order(router, 'insight')).toEqual([]); // and the next ones do not pay for another failure
    expect(router.coolingDown.sort()).toEqual(['google', 'openai']);
    tick(5_000);
    expect(order(router, 'insight')).toEqual(['google', 'openai']); // a new probe after the interval
  });

  it('an unusable answer (content failure) is not an outage: it only counts when it is the rule (D-08)', () => {
    const { router } = make({ cooldownMs: 60_000 });
    for (let i = 0; i < 5; i++) router.markFailure('google', { content: true });
    expect(router.inCooldown('google')).toBe(false); // not enough samples to call it the rule
    router.markSuccess('google');
    for (let i = 0; i < 9; i++) router.markFailure('google', { content: true });
    expect(router.inCooldown('google')).toBe(true); // 9 of the last 10 answers unusable
    router.markSuccess('google');
    expect(router.inCooldown('google')).toBe(false);
  });

  it('an availability failure always counts, whatever the answers before it were', () => {
    const { router } = make({ cooldownMs: 60_000 });
    for (let i = 0; i < 8; i++) router.markSuccess('google');
    router.markFailure('google');
    expect(router.inCooldown('google')).toBe(true);
  });

  it('a success clears the cooldown and the failure streak', () => {
    const { router } = make({ cooldownMs: 1000 });
    router.markFailure('xai');
    router.markFailure('xai');
    router.markSuccess('xai');
    expect(router.inCooldown('xai')).toBe(false);
    expect(router.health().find((h) => h.id === 'xai')).toMatchObject({ consecutiveFailures: 0, retryInMs: 0 });
  });

  it('repeated failures double the cooldown up to the cap, measured from the latest failure', () => {
    const { router, tick } = make({ cooldownMs: 1000, maxCooldownMs: 5000 });
    const retryIn = () => router.health().find((h) => h.id === 'openai')!.retryInMs;
    router.markFailure('openai');
    expect(retryIn()).toBe(1000);
    tick(1000);
    router.markFailure('openai'); // second consecutive failure
    expect(retryIn()).toBe(2000);
    tick(2000);
    router.markFailure('openai');
    expect(retryIn()).toBe(4000);
    tick(4000);
    router.markFailure('openai');
    expect(retryIn()).toBe(5000); // capped
    expect(router.health().find((h) => h.id === 'openai')!.consecutiveFailures).toBe(4);
  });

  it('Retry-After stretches the cooldown, and is capped like everything else', () => {
    const { router } = make({ cooldownMs: 1000, maxCooldownMs: 30_000 });
    const retryIn = () => router.health().find((h) => h.id === 'openai')!.retryInMs;
    router.markFailure('openai', { retryAfterMs: 10_000 });
    expect(retryIn()).toBe(10_000);
    router.markSuccess('openai');
    router.markFailure('openai', { retryAfterMs: 500 }); // shorter than the cooldown: the cooldown wins
    expect(retryIn()).toBe(1000);
    router.markSuccess('openai');
    router.markFailure('openai', { retryAfterMs: 3_600_000 });
    expect(retryIn()).toBe(30_000);
  });

  it('cooldownMs: 0 disables the breaker (what the API tests rely on)', () => {
    const { router } = make({ cooldownMs: 0 });
    router.markFailure('google', { retryAfterMs: 60_000 });
    expect(router.inCooldown('google')).toBe(false);
    expect(order(router, 'insight')[0]).toBe('google');
  });

  it('a failure of one provider never affects another', () => {
    const { router } = make();
    router.markFailure('anthropic');
    expect(router.health().filter((h) => h.inCooldown).map((h) => h.id)).toEqual(['anthropic']);
  });

  it.each([-1, NaN, Infinity])('rejects an invalid cooldown %s', (bad) => {
    expect(() => make({ cooldownMs: bad })).toThrow(RangeError);
    expect(() => make({ maxCooldownMs: bad })).toThrow(RangeError);
  });

  it('exposes the configured providers', () => {
    expect(make({}, ['xai', 'openai']).router.configured).toEqual(['xai', 'openai']);
    expect(make().router.provider('google')?.id).toBe('google');
    expect(make({}, ['xai']).router.provider('google')).toBeUndefined();
  });
});
