// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import {
  AIGateway,
  MemoryUsageSink,
  MockProvider,
  ProviderError,
  ProviderRouter,
  type AIProviderId,
  type GatewayLogger,
  type GatewayOptions,
} from '../../src/index.js';

export const IDS: readonly AIProviderId[] = ['openai', 'anthropic', 'google', 'xai'];

export function capture() {
  const entries: { level: 'info' | 'warn'; entry: Record<string, unknown>; message?: string }[] = [];
  const logger: GatewayLogger = {
    info: (entry, message) => void entries.push({ level: 'info', entry, message }),
    warn: (entry, message) => void entries.push({ level: 'warn', entry, message }),
  };
  return { logger, entries };
}

/** No real pause between retries, and no jitter: `sleeps` records what the gateway asked for. */
export const instant = () => {
  const sleeps: number[] = [];
  return { sleeps, sleep: (ms: number) => Promise.resolve(void sleeps.push(ms)), random: () => 0.5 };
};

export function setup(opts: Partial<Omit<GatewayOptions, 'router'>> & { cooldownMs?: number } = {}) {
  const providers = Object.fromEntries(IDS.map((id) => [id, new MockProvider(id)])) as Record<AIProviderId, MockProvider>;
  let now = 1_000_000;
  const { cooldownMs, ...rest } = opts;
  const router = new ProviderRouter(Object.values(providers), { cooldownMs: cooldownMs ?? 60_000, now: () => now });
  const usage = new MemoryUsageSink();
  const { sleeps, sleep, random } = instant();
  const gateway = new AIGateway({ router, usage, now: () => new Date(now), sleep, random, ...rest });
  return { providers, router, usage, gateway, sleeps, tick: (ms: number) => (now += ms) };
}

/** Records the order in which providers are asked. */
export function trace(providers: Record<AIProviderId, MockProvider>): AIProviderId[] {
  const order: AIProviderId[] = [];
  for (const p of Object.values(providers)) {
    const original = p.generate.bind(p);
    p.generate = async (r) => {
      order.push(p.id);
      return original(r);
    };
  }
  return order;
}

/** A provider that answers from a script: one entry per call, the last one repeats. 'ok' delegates to a healthy mock. */
export function scripted(id: AIProviderId, script: (ProviderError | 'ok')[]): MockProvider {
  const mock = new MockProvider(id);
  const healthy = mock.generate.bind(mock);
  let call = 0;
  mock.generate = async (r) => {
    const step = script[Math.min(call, script.length - 1)];
    call += 1;
    if (step instanceof ProviderError) {
      mock.calls.push(r);
      throw step;
    }
    return healthy(r);
  };
  return mock;
}

export const httpError = (id: AIProviderId, status: number, retryAfterMs?: number) =>
  new ProviderError(id, `HTTP ${status}`, status, undefined, { retryAfterMs });

