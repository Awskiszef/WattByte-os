import { createBudgetGuard, ProviderError } from '@wattbyte/ai';
import { afterEach, describe, expect, it } from 'vitest';

import { utcDayKey } from '../src/modules/ai/service.js';
import { makeApp, registerUser, sampleInput, type TestContext } from './helpers.js';
import { seedUser } from './support.js';

let ctx: TestContext | undefined;
afterEach(async () => {
  await ctx?.app.close();
  ctx = undefined;
});

const insight = (c: TestContext, headers: Record<string, string>) =>
  c.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers, payload: { input: sampleInput } });
const today = () => utcDayKey(new Date());

describe('billed answers that are rejected (D-01)', () => {
  it('prose instead of JSON: 503 for the user, but the call is on the spend ledger and the quota slot stays used', async () => {
    ctx = await makeApp({ AI_FREE_DAILY_LIMIT: '2' });
    const reg = await registerUser(ctx.app);
    ctx.providers.google.set({ text: 'Sure! Here is a thought in plain prose.' });

    const first = await insight(ctx, reg.headers);
    expect(first.statusCode).toBe(503);
    expect(first.json().error.code).toBe('ai_unavailable');
    expect(await ctx.repos.ai.spentUsd(today(), 'google')).toBeGreaterThan(0); // booked although nothing was delivered

    // A client that repeats the failing request burns its allowance instead of the operator's money: 2 per day.
    expect((await insight(ctx, reg.headers)).statusCode).toBe(503);
    const third = await insight(ctx, reg.headers);
    expect(third.statusCode).toBe(429);
    expect(third.json().error.code).toBe('ai_quota_exceeded');
  });

  it('a failure that was provably not billed (no connection, 401, 5xx) gives the slot AND the held spend back', async () => {
    ctx = await makeApp({ AI_FREE_DAILY_LIMIT: '2' });
    const reg = await registerUser(ctx.app);
    for (const id of ['google', 'openai', 'anthropic', 'xai'] as const) ctx.providers[id].set({ fail: new ProviderError(id, 'HTTP 503', 503) });
    expect((await insight(ctx, reg.headers)).statusCode).toBe(503);
    expect(await ctx.repos.ai.spentUsd(today())).toBeCloseTo(0, 9);
    expect(await ctx.repos.ai.reserve(reg.user.id, today(), 2)).toBe(1); // the slot was released
  });
});

describe('the spend of a delivered answer is its real cost, not the worst case held beforehand', () => {
  it('spend equals the cost of the logged answer', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    expect((await insight(ctx, reg.headers)).statusCode).toBe(200);
    const logged = (await ctx.repos.cloud.exportData(reg.user.id, 10))!.aiGenerations;
    expect(logged).toHaveLength(1);
    expect(await ctx.repos.ai.spentUsd(today())).toBeCloseTo(logged[0]!.estimatedCostUsd, 6);
  });
});

describe('bookkeeping after the provider call cannot turn into an error or lose the answer (D-04)', () => {
  it('a usage log that cannot be written still returns the answer the user was charged a slot for', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    ctx.repos.ai.insert = () => Promise.reject(new Error('db down SENTINEL-DB'));
    const res = await insight(ctx, reg.headers);
    expect(res.statusCode).toBe(200);
    expect(res.json().output.title).toBeTruthy();
    expect(res.body).not.toContain('SENTINEL-DB');
    expect(await ctx.repos.ai.spentUsd(today())).toBeGreaterThan(0); // the spend was booked by the ledger anyway
  });

  it('a quota release that fails does not replace the real answer (503 ai_unavailable) with a 500', async () => {
    ctx = await makeApp();
    const reg = await registerUser(ctx.app);
    for (const id of ['google', 'openai', 'anthropic', 'xai'] as const) ctx.providers[id].set({ fail: new ProviderError(id, 'HTTP 503', 503) });
    ctx.repos.ai.release = () => Promise.reject(new Error('db down SENTINEL-DB'));
    const res = await insight(ctx, reg.headers);
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe('ai_unavailable');
  });
});

describe('a spend limit that cannot be read stops the call (D-06)', () => {
  it('answers 503 and calls no provider, and gives the slot back', async () => {
    ctx = await makeApp({ AI_BUDGET_DAILY_USD: '5' }, { gatewayOptions: (repos) => ({ budget: createBudgetGuard({ dailyUsd: 5 }, repos.ai) }) });
    const reg = await registerUser(ctx.app);
    ctx.repos.ai.spentUsd = () => Promise.reject(new Error('db down SENTINEL-DB'));
    const res = await insight(ctx, reg.headers);
    expect(res.statusCode).toBe(503);
    expect(res.body).not.toContain('SENTINEL-DB');
    expect(Object.values(ctx.providers).every((p) => p.calls.length === 0)).toBe(true);
    expect(await ctx.repos.ai.reserve(reg.user.id, today(), 2)).toBe(1);
  });
});

describe('the limits hold under concurrency (D-06)', () => {
  it('twenty simultaneous requests against a daily budget that fits only a few: no overshoot', async () => {
    // Probe the worst-case hold of one call, then allow exactly three of them.
    const probe = await makeApp({ AI_BUDGET_DAILY_USD: '1000' });
    const regProbe = await registerUser(probe.app);
    const held: number[] = [];
    const original = probe.repos.ai.reserveSpend.bind(probe.repos.ai);
    probe.repos.ai.reserveSpend = async (r) => (held.push(r.usd), original(r));
    await insight(probe, regProbe.headers);
    await probe.app.close();
    const hold = held[0]!;

    ctx = await makeApp({ AI_BUDGET_DAILY_USD: String(hold * 3.5), AI_FREE_DAILY_LIMIT: '100' });
    // Accounts are created directly: twenty simultaneous registrations would meet the password-hashing limiter (A-04).
    const users = await Promise.all(Array.from({ length: 20 }, (_, i) => seedUser(ctx!.repos, `ledger-${i}@test.wattbyte`)));
    // Hold every provider call open until all twenty requests have asked the ledger: the holds overlap, as they do
    // with real (slow) providers. Without overlap each call would settle to its small real cost before the next one asked.
    let open!: () => void;
    const gate = new Promise<void>((resolve) => (open = resolve));
    const delegate = ctx.providers.google.generate.bind(ctx.providers.google);
    ctx.providers.google.generate = async (request) => (await gate, delegate(request));
    let asked = 0;
    const reserveSpend = ctx.repos.ai.reserveSpend.bind(ctx.repos.ai);
    ctx.repos.ai.reserveSpend = async (r) => {
      const res = await reserveSpend(r);
      if (++asked === 20) open();
      return res;
    };
    const responses = await Promise.all(users.map((u) => insight(ctx!, u.headers)));
    const ok = responses.filter((r) => r.statusCode === 200).length;
    expect(ok).toBe(3);
    expect(responses.filter((r) => r.statusCode === 503)).toHaveLength(17);
    expect(Object.values(ctx.providers).reduce((n, p) => n + p.calls.length, 0)).toBe(3);
    // After settling, the real costs are far below the holds; the ledger shows the sum of the three real answers.
    expect(await ctx.repos.ai.spentUsd(today())).toBeLessThanOrEqual(hold * 3.5);
  });
});
