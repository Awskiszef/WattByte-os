// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, registerUser, sampleInput, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

describe('ai gateway access', () => {
  it('answers with validated structured output and enforces the free quota', async () => {
    const reg = await registerUser(ctx.app);
    const call = () =>
      ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: reg.headers, payload: { mode: 'funny', locale: 'pl', input: sampleInput } });

    const first = await call();
    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({ provider: 'google', remainingToday: 1 });
    expect(first.json().output).toMatchObject({ tone: 'funny', severity: 'info' });

    const second = await call();
    expect(second.json().remainingToday).toBe(0);
    const third = await call();
    expect(third.statusCode).toBe(429);
    expect(third.json().error.code).toBe('ai_quota_exceeded');
  });

  it('roast always uses roast tone and the xai route', async () => {
    const reg = await registerUser(ctx.app);
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/roast', headers: reg.headers, payload: { mode: 'normal', input: sampleInput } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ provider: 'xai' });
    expect(res.json().output.tone).toBe('roast');
    expect(ctx.providers.xai.calls[0]!.mode).toBe('roast');
  });

  it('refuses personal data in the input and reports provider outages', async () => {
    const reg = await registerUser(ctx.app);
    const pii = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/ai/insight',
      headers: reg.headers,
      payload: { input: { ...sampleInput, email: 'a@b.co' } },
    });
    expect(pii.statusCode).toBe(400);

    for (const p of Object.values(ctx.providers)) p.set({ fail: true });
    const down = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: reg.headers, payload: { input: sampleInput } });
    expect(down.statusCode).toBe(503);
    expect(down.json().error.code).toBe('ai_unavailable');
  });

  it('never forwards identifiers to providers', async () => {
    const reg = await registerUser(ctx.app, 'secret.person@example.com');
    await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/weekly-summary', headers: reg.headers, payload: { input: sampleInput } });
    const sent = ctx.providers.openai.calls[0]!;
    expect(sent.user + sent.system).not.toContain('secret.person');
    expect(sent.user + sent.system).not.toContain(reg.user.id);
  });
});
