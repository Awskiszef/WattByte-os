import { AppConfigDto } from '@wattbyte/contracts';
import { describe, expect, it } from 'vitest';

import { type BuiltApp, buildTestApp, expectErrorBody, sampleAiInput, sampleDay, seedUser } from './support.js';

const AI_ROUTES = ['insight', 'weekly-summary', 'monthly-summary', 'roast'].map((p) => `/api/v1/ai/${p}`);

async function withApp<T>(env: Record<string, string>, fn: (ctx: BuiltApp) => Promise<T>): Promise<T> {
  const ctx = await buildTestApp({ env });
  try {
    return await fn(ctx);
  } finally {
    await ctx.app.close();
  }
}

describe('GET /api/v1/config', () => {
  it('is public, matches the contract, and reports the defaults', async () => {
    await withApp({}, async ({ app }) => {
      const res = await app.inject({ method: 'GET', url: '/api/v1/config' });
      expect(res.statusCode).toBe(200);
      const body = AppConfigDto.parse(res.json());
      expect(body).toEqual({
        environment: 'development',
        features: { ai: true, subscriptions: false, cloudSync: true },
        ai: { dailyLimits: { free: 2, premium: 10 } }, // the test app's AI_FREE_DAILY_LIMIT / AI_PREMIUM_DAILY_LIMIT
      });
      expect(res.headers['cache-control']).toBe('no-store');
    });
  });

  it('daily limits come from the environment, never from a constant', async () => {
    await withApp({ AI_FREE_DAILY_LIMIT: '7', AI_PREMIUM_DAILY_LIMIT: '123' }, async ({ app }) => {
      expect((await app.inject({ url: '/api/v1/config' })).json().ai.dailyLimits).toEqual({ free: 7, premium: 123 });
    });
    await withApp({ AI_FREE_DAILY_LIMIT: '0' }, async ({ app }) => {
      expect((await app.inject({ url: '/api/v1/config' })).json().ai.dailyLimits.free).toBe(0);
    });
  });

  it('reports the deployment (APP_ENV) and contains nothing secret', async () => {
    const env = { NODE_ENV: 'production', APP_ENV: 'staging', DATABASE_URL: 'postgres://app:db-secret-pass@db.internal:5432/x', DATABASE_SSL: '1', TRUST_PROXY_HOPS: '1', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd', OPENAI_API_KEY: 'sk-openai-secret-value', OPENAI_FAST_MODEL: 'm' };
    await withApp(env, async ({ app }) => {
      const res = await app.inject({ url: '/api/v1/config' });
      expect(res.json().environment).toBe('staging');
      for (const secret of ['db-secret-pass', 'sk-openai-secret-value', 'k3J9xQ2v', 'db.internal']) expect(res.body).not.toContain(secret);
      expect(Object.keys(res.json()).sort()).toEqual(['ai', 'environment', 'features']);
    });
  });

  it('is in the OpenAPI document with a named component', async () => {
    await withApp({}, async ({ app }) => {
      const spec = app.swagger() as { paths: Record<string, { get?: { security?: unknown } }>; components: { schemas: Record<string, unknown> } };
      expect(spec.paths['/api/v1/config']?.get).toBeDefined();
      expect(spec.paths['/api/v1/config']?.get?.security).toBeUndefined();
      expect(spec.components.schemas).toHaveProperty('AppConfigDto');
    });
  });
});

describe('FEATURE_* flags (every combination)', () => {
  const combos: { FEATURE_AI: '0' | '1'; FEATURE_CLOUD_SYNC: '0' | '1'; FEATURE_SUBSCRIPTIONS: '0' | '1' }[] = [];
  for (const ai of ['0', '1'] as const) for (const cloud of ['0', '1'] as const) for (const subs of ['0', '1'] as const) combos.push({ FEATURE_AI: ai, FEATURE_CLOUD_SYNC: cloud, FEATURE_SUBSCRIPTIONS: subs });

  it.each(combos)('ai=$FEATURE_AI cloudSync=$FEATURE_CLOUD_SYNC subscriptions=$FEATURE_SUBSCRIPTIONS', async (flags) => {
    await withApp({ ...flags, AI_FREE_DAILY_LIMIT: '10' }, async ({ app, repos }) => {
      const aiOn = flags.FEATURE_AI === '1';
      const cloudOn = flags.FEATURE_CLOUD_SYNC === '1';

      // /config tells the client
      expect((await app.inject({ url: '/api/v1/config' })).json().features).toEqual({ ai: aiOn, subscriptions: flags.FEATURE_SUBSCRIPTIONS === '1', cloudSync: cloudOn });

      const u = await seedUser(repos, 'flags@b.co');
      await app.inject({ method: 'POST', url: '/api/v1/devices', headers: u.headers, payload: { installationId: 'install-flags-1', platform: 'ios' } });

      // AI routes
      for (const url of AI_ROUTES) {
        const res = await app.inject({ method: 'POST', url, headers: u.headers, payload: { input: sampleAiInput } });
        if (aiOn) {
          expect(res.statusCode, url).toBe(200);
        } else {
          expect(res.statusCode, url).toBe(503);
          expectErrorBody(res.json(), 'feature_disabled');
        }
      }

      // usage sync and daily
      const sync = await app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: u.headers, payload: { installationId: 'install-flags-1', days: [sampleDay('2026-10-12')] } });
      const daily = await app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: u.headers });
      if (cloudOn) {
        expect(sync.statusCode).toBe(200);
        expect(daily.statusCode).toBe(200);
      } else {
        for (const res of [sync, daily]) {
          expect(res.statusCode).toBe(503);
          expectErrorBody(res.json(), 'feature_disabled');
        }
      }

      // everything else is unaffected by any flag
      for (const url of ['/api/v1/me', '/api/v1/devices', '/api/v1/me/settings']) expect((await app.inject({ url, headers: u.headers })).statusCode, url).toBe(200);
      expect((await app.inject({ url: '/health' })).statusCode).toBe(200);
      expect((await app.inject({ url: '/ready' })).statusCode).toBe(200);
    });
  });

  it('a disabled feature consumes no quota and calls no provider', async () => {
    await withApp({ FEATURE_AI: '0' }, async ({ app, providers, memory, repos }) => {
      const u = await seedUser(repos, 'noquota@b.co');
      for (let i = 0; i < 5; i++) expect((await app.inject({ method: 'POST', url: AI_ROUTES[0]!, headers: u.headers, payload: { input: sampleAiInput } })).statusCode).toBe(503);
      expect(Object.values(providers).reduce((n, p) => n + p.calls.length, 0)).toBe(0);
      expect(await memory.ai.reserve(u.userId, new Date().toISOString().slice(0, 10), 2)).toBe(1); // nothing was reserved before
    });
  });

  it('a disabled feature is still behind authentication (401 for anonymous callers, not 503)', async () => {
    await withApp({ FEATURE_AI: '0', FEATURE_CLOUD_SYNC: '0' }, async ({ app }) => {
      for (const [method, url] of [['POST', AI_ROUTES[0]!], ['POST', '/api/v1/usage/sync'], ['GET', '/api/v1/usage/daily']] as const) {
        const res = await app.inject({ method, url, ...(method === 'POST' ? { payload: {} } : {}) });
        expect(res.statusCode, url).toBe(401);
      }
    });
  });

  it('a disabled feature does not read or validate the body (503 before 400)', async () => {
    await withApp({ FEATURE_AI: '0' }, async ({ app, repos }) => {
      const u = await seedUser(repos, 'body@b.co');
      const res = await app.inject({ method: 'POST', url: AI_ROUTES[0]!, headers: { ...u.headers, 'content-type': 'application/json' }, payload: '{not json' });
      expect(res.statusCode).toBe(503);
      expectErrorBody(res.json(), 'feature_disabled');
    });
  });

  it('re-enabling works without code changes (a restart with the flag on)', async () => {
    await withApp({ FEATURE_AI: '1' }, async ({ app, repos }) => {
      const u = await seedUser(repos, 'on@b.co');
      expect((await app.inject({ method: 'POST', url: AI_ROUTES[0]!, headers: u.headers, payload: { input: sampleAiInput } })).statusCode).toBe(200);
    });
  });
});
