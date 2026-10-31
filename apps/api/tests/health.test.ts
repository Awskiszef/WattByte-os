// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

describe('ops', () => {
  it('health and readiness', async () => {
    const health = await ctx.app.inject({ method: 'GET', url: '/health' });
    expect(health.statusCode).toBe(200);
    expect(health.json()).toMatchObject({ status: 'ok', version: expect.any(String) });

    const ready = await ctx.app.inject({ method: 'GET', url: '/ready' });
    expect(ready.statusCode).toBe(200);
    expect(ready.json()).toMatchObject({ status: 'ok', database: 'ok', aiProviders: ['openai', 'anthropic', 'google', 'xai'] });
  });

  it('publishes an OpenAPI document covering every v1 route', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/openapi.json' });
    expect(res.statusCode).toBe(200);
    const spec = res.json() as { openapi: string; paths: Record<string, unknown> };
    expect(spec.openapi).toBe('3.0.3');
    for (const p of [
      '/api/v1/auth/register',
      '/api/v1/auth/login',
      '/api/v1/auth/refresh',
      '/api/v1/auth/logout',
      '/api/v1/me',
      '/api/v1/devices',
      '/api/v1/usage/sync',
      '/api/v1/usage/daily',
      '/api/v1/ai/insight',
      '/api/v1/ai/roast',
    ]) {
      expect(spec.paths, p).toHaveProperty(p);
    }
  });
});
