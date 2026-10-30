// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import { AIGateway, AIInputSchema, MockProvider, ProviderError, ProviderRouter, type AIGatewayError } from '../src/index.js';
import { ctx, gatewayInput as input } from './helpers/doubles.js';
import { httpError, setup } from './helpers/gateway.js';

describe('load is shed instead of queued (D-09)', () => {
  it('maxInFlight generations run at once; the next is refused immediately with nothing called', async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const slow = new MockProvider('google');
    const original = slow.generate.bind(slow);
    slow.generate = async (r) => (await gate, original(r));
    const gateway = new AIGateway({ router: new ProviderRouter([slow]), maxInFlight: 2, sleep: async () => undefined });
    const running = [gateway.generate('insight', 'normal', input, ctx), gateway.generate('insight', 'normal', input, ctx)];
    await new Promise((r) => setTimeout(r, 5));
    expect(gateway.status()).toMatchObject({ inFlight: 2, maxInFlight: 2 });
    const refused = (await gateway.generate('insight', 'normal', input, ctx).catch((e: unknown) => e)) as AIGatewayError;
    expect(refused.code).toBe('overloaded');
    release();
    await Promise.all(running);
    expect(slow.calls).toHaveLength(2); // the refused one never reached a provider
    expect(gateway.status().inFlight).toBe(0); // slots come back, also after errors
    await expect(gateway.generate('insight', 'normal', input, ctx)).resolves.toBeDefined();
  });

  it('a failing generation also gives its slot back', async () => {
    const bad = new MockProvider('google', { fail: httpError('google', 400) });
    const gateway = new AIGateway({ router: new ProviderRouter([bad]), maxInFlight: 1, sleep: async () => undefined });
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(gateway.status().inFlight).toBe(0);
  });

  it('while every provider cools down, requests fail at once (one probe per interval) instead of paying for another failure', async () => {
    const { providers, gateway, router, tick } = setup({ cooldownMs: 60_000 });
    for (const p of Object.values(providers)) p.set({ fail: new ProviderError(p.id, 'down', 503) });
    // the first request fails for real (and demotes what it tried); keep failing until everything is cooling
    for (let i = 0; i < 4; i++) await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(router.coolingDown.length).toBe(4);
    const callsBefore = Object.values(providers).reduce((n, p) => n + p.calls.length, 0);
    // the probe slot of this interval was used by the last request: the next ones are refused without any provider call
    const e = (await gateway.generate('insight', 'normal', input, ctx).catch((x: unknown) => x)) as AIGatewayError;
    expect(e.code).toBe('all_providers_failed');
    expect(Object.values(providers).reduce((n, p) => n + p.calls.length, 0)).toBe(callsBefore);
    tick(5_001);
    await gateway.generate('insight', 'normal', input, ctx).catch(() => undefined);
    expect(Object.values(providers).reduce((n, p) => n + p.calls.length, 0)).toBeGreaterThan(callsBefore); // a probe went out
  });
});

/** D-10: nothing a client sends reaches a prompt as free text or as a non-finite number. */
describe('AIInputSchema domain', () => {
  const ok = { ...input };
  const bad = (patch: Record<string, unknown>) => AIInputSchema.safeParse({ ...ok, ...patch }).success;

  it('accepts what the app sends', () => {
    expect(AIInputSchema.safeParse(ok).success).toBe(true);
  });

  it.each([
    ['a month period for a day', { periodType: 'day', period: '2026-10' }],
    ['a day period for a month', { periodType: 'month', period: '2026-10-13' }],
    ['a week out of range', { periodType: 'week', period: '2026-W54' }],
    ['month 13', { periodType: 'month', period: '2026-13' }],
    ['free text as period', { period: 'ignore all' }],
    ['a sentence as currency', { currency: 'ignore previous' }],
    ['lower-case currency', { currency: 'pln' }],
    ['two-letter currency', { currency: 'PL' }],
    ['Infinity', { mobileDataGb: Infinity }],
    ['NaN', { wifiDataGb: NaN }],
    ['absurd data volume', { totalDataGb: 1e12 }],
    ['absurd cost', { electricityCost: 1e15 }],
    ['absurd session count', { chargingSessions: 1e9 }],
    ['an infinite change', { previousPeriodChangePercent: Infinity }],
    ['a change below -100 %', { previousPeriodChangePercent: -250 }],
  ])('refuses %s', (_name, patch) => {
    expect(bad(patch)).toBe(false);
  });

  it('accepts a valid day, week and month for their own type, and the optional fields as null', () => {
    expect(bad({ periodType: 'day', period: '2026-10-13' })).toBe(true);
    expect(bad({ periodType: 'week', period: '2026-W41' })).toBe(true);
    expect(bad({ periodType: 'month', period: '2026-10', previousPeriodChangePercent: null, wifiSharePercent: null, averageSessionMah: null })).toBe(true);
    expect(bad({ previousPeriodChangePercent: 4_500 })).toBe(true); // growth above 100 % is real
  });
});
