import Fastify from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ForeignKeyViolation, UniqueViolation } from '../src/database/memory.js';
import { errorHandler, HttpError } from '../src/errors/http-error.js';
import { type BuiltApp, buildTestApp, expectErrorBody, LogCapture, pgStyleError, sampleAiInput, seedUser } from './support.js';

const json = { 'content-type': 'application/json' };

let ctx: BuiltApp;
beforeEach(async () => {
  ctx = await buildTestApp();
});
afterEach(() => ctx.app.close());

/** Strings that must never reach a client: SQL, constraint names, SQLSTATE, stack frames, library internals. */
const INTERNAL_DETAIL = /users_email_key|23505|duplicate key|SELECT |INSERT |sessions|nbtinsert|_bt_check|FST_ERR|node_modules|\.ts:\d+|at .*\(.*\)/i;

describe('error contract: every failure is { error: { code, message } } with a stable code', () => {
  it('unknown route: 404 not_found, for any method', async () => {
    for (const [method, url] of [
      ['GET', '/nope'],
      ['GET', '/api/v1/nope'],
      ['POST', '/api/v2/auth/login'],
      ['DELETE', '/api/v1/devices/specifications/a/b'],
    ] as const) {
      const res = await ctx.app.inject({ method, url });
      expect(res.statusCode, `${method} ${url}`).toBe(404);
      expectErrorBody(res.json(), 'not_found');
      expect(res.headers['x-request-id']).toBeTruthy();
    }
  });

  it('known path, wrong method: 405 method_not_allowed with an allow header', async () => {
    const put = await ctx.app.inject({ method: 'PUT', url: '/api/v1/auth/login', payload: {} });
    expect(put.statusCode).toBe(405);
    expectErrorBody(put.json(), 'method_not_allowed');
    expect(put.headers.allow).toBe('POST');

    const del = await ctx.app.inject({ method: 'DELETE', url: '/health' });
    expect(del.statusCode).toBe(405);
    expectErrorBody(del.json(), 'method_not_allowed');
    expect(del.headers.allow).toMatch(/GET/);

    // A parameterised path counts as known too.
    const post = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices/specifications/iPhone16,1' });
    expect(post.statusCode).toBe(405);
    expect(post.headers.allow).toMatch(/GET/);

    // The path exists, but this method has a route: the router must not claim 405 for it.
    const ok = await ctx.app.inject({ method: 'GET', url: '/health' });
    expect(ok.statusCode).toBe(200);
  });

  it('malformed JSON: 400 invalid_json', async () => {
    for (const payload of ['{bad', '{"email": "a@b.co",', 'null null', '[1,2']) {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload });
      expect(res.statusCode, payload).toBe(400);
      expectErrorBody(res.json(), 'invalid_json');
    }
    const empty = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: '' });
    expect(empty.statusCode).toBe(400);
    expectErrorBody(empty.json(), 'invalid_json');
  });

  it('oversized body: 413 payload_too_large (the limit is 16 KiB; /usage/sync 64 KiB)', async () => {
    const big = JSON.stringify({ email: 'a@b.co', password: 'x'.repeat(16_385) });
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: big });
    expect(res.statusCode).toBe(413);
    expectErrorBody(res.json(), 'payload_too_large');

    // Just under the limit is parsed and then rejected by validation (password max 200), not by the size check.
    const under = JSON.stringify({ email: 'a@b.co', password: 'x'.repeat(16_000) });
    const res2 = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: under });
    expect(res2.statusCode).toBe(400);
    expectErrorBody(res2.json(), 'validation');
  });

  it('unsupported media type: 415 unsupported_media_type (text/plain included)', async () => {
    for (const [type, payload] of [
      ['text/plain', 'email=a@b.co'],
      ['application/xml', '<a/>'],
      ['application/x-www-form-urlencoded', 'email=a%40b.co&password=password123'],
      ['multipart/form-data; boundary=x', '--x--'],
    ] as const) {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: { 'content-type': type }, payload });
      expect(res.statusCode, type).toBe(415);
      expectErrorBody(res.json(), 'unsupported_media_type');
    }
  });

  it('validation: 400 validation for body, query and params', async () => {
    const body = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'nope', password: 'short' } });
    expect(body.statusCode).toBe(400);
    expectErrorBody(body.json(), 'validation');

    const u = await seedUser(ctx.repos, 'v@b.co');
    const query = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-13-45&to=x', headers: u.headers });
    expect(query.statusCode).toBe(400);
    expectErrorBody(query.json(), 'validation');

    const params = await ctx.app.inject({ method: 'DELETE', url: '/api/v1/devices/not-a-uuid', headers: u.headers });
    expect(params.statusCode).toBe(400);
    expectErrorBody(params.json(), 'validation');

    // A body that is not an object at all.
    const wrongType = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: '"just a string"' });
    expect(wrongType.statusCode).toBe(400);
    expectErrorBody(wrongType.json(), 'validation');
  });

  it('a malformed URL does not echo the URL back', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/%E0%A4%A' });
    expect(res.statusCode).toBe(400);
    expectErrorBody(res.json(), 'bad_request');
    expect(res.body).not.toContain('specifications');
    expect(res.headers['x-request-id']).toBeTruthy();
  });

  it('401 / 404 / 409 from the application keep their route-specific codes', async () => {
    const anon = await ctx.app.inject({ method: 'GET', url: '/api/v1/me' });
    expect(anon.statusCode).toBe(401);
    expectErrorBody(anon.json(), 'unauthorized');

    const bad = await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: 'Bearer nonsense' } });
    expect(bad.statusCode).toBe(401);
    expectErrorBody(bad.json(), 'invalid_token');

    const wrong = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'nobody@b.co', password: 'password123' } });
    expect(wrong.statusCode).toBe(401);
    expectErrorBody(wrong.json(), 'invalid_credentials');

    const u = await seedUser(ctx.repos, 'x@b.co');
    const missing = await ctx.app.inject({ method: 'DELETE', url: '/api/v1/devices/00000000-0000-4000-8000-000000000000', headers: u.headers });
    expect(missing.statusCode).toBe(404);
    expectErrorBody(missing.json(), 'device_not_found');

    const dup = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'X@b.co', password: 'password123' } });
    expect(dup.statusCode).toBe(409);
    expectErrorBody(dup.json(), 'email_taken');
  });

  it('every error response carries x-request-id', async () => {
    const u = await seedUser(ctx.repos, 'rid@b.co');
    const responses = await Promise.all([
      ctx.app.inject({ method: 'GET', url: '/nope' }),
      ctx.app.inject({ method: 'GET', url: '/api/v1/me' }),
      ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: '{bad' }),
      ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: {} }),
      ctx.app.inject({ method: 'PUT', url: '/health' }),
      ctx.app.inject({ method: 'DELETE', url: '/api/v1/devices/zzz', headers: u.headers }),
    ]);
    for (const r of responses) {
      expect(r.statusCode).toBeGreaterThanOrEqual(400);
      expect(r.headers['x-request-id'], r.body).toMatch(/^[A-Za-z0-9._-]{8,64}$/);
    }
  });
});

describe('error contract: rate limiting', () => {
  it('429 rate_limited with retry-after on a credential endpoint', async () => {
    const limited = await buildTestApp({ authRateLimitMax: 2 });
    try {
      const attempt = () => limited.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'a@b.co', password: 'password123' } });
      expect((await attempt()).statusCode).toBe(401);
      expect((await attempt()).statusCode).toBe(401);
      const third = await attempt();
      expect(third.statusCode).toBe(429);
      expectErrorBody(third.json(), 'rate_limited');
      expect(Number(third.headers['retry-after'])).toBeGreaterThan(0);
      expect(third.headers['x-request-id']).toBeTruthy();
    } finally {
      await limited.app.close();
    }
  });

  it('429 on the global limiter too, and unknown routes are limited as well (no free scanning)', async () => {
    const limited = await buildTestApp({ rateLimitMax: 3 });
    try {
      for (let i = 0; i < 3; i++) expect((await limited.app.inject({ method: 'GET', url: '/nope' })).statusCode).toBe(404);
      const res = await limited.app.inject({ method: 'GET', url: '/nope' });
      expect(res.statusCode).toBe(429);
      expectErrorBody(res.json(), 'rate_limited');
      expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
    } finally {
      await limited.app.close();
    }
  });

  it('the daily AI quota answers 429 ai_quota_exceeded with a retry-after until the next UTC midnight', async () => {
    const u = await seedUser(ctx.repos, 'quota@b.co');
    const call = () => ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u.headers, payload: { input: sampleAiInput } });
    expect((await call()).statusCode).toBe(200);
    expect((await call()).statusCode).toBe(200);
    const third = await call();
    expect(third.statusCode).toBe(429);
    expectErrorBody(third.json(), 'ai_quota_exceeded');
    const retry = Number(third.headers['retry-after']);
    expect(retry).toBeGreaterThanOrEqual(1);
    expect(retry).toBeLessThanOrEqual(86_400);
  });
});

describe('error contract: nothing internal leaks', () => {
  it('an unexpected pg-style exception is a 500 internal with a generic message', async () => {
    const log = new LogCapture();
    const leaky = await buildTestApp({ logStream: log });
    try {
      leaky.memory.users.findByEmail = async (email) => {
        throw pgStyleError(email);
      };
      const res = await leaky.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'victim@leak.example', password: 'password123' } });
      expect(res.statusCode).toBe(500);
      expectErrorBody(res.json(), 'internal');
      expect(res.json().error.message).toBe('Internal error');
      expect(res.body).not.toMatch(INTERNAL_DETAIL);
      expect(res.body).not.toContain('victim@leak.example');
      expect(res.headers['x-request-id']).toBeTruthy();

      // The server-side log keeps what is needed to find the cause (type, SQLSTATE, frames) and nothing the database echoed.
      const logged = log.text();
      expect(logged).toContain('unhandled error');
      expect(logged).toContain('23505');
      expect(logged).not.toContain('victim@leak.example');
      expect(logged).not.toContain('users_email_key');
      expect(logged).not.toContain('duplicate key');
    } finally {
      await leaky.app.close();
    }
  });

  it('a failing repository on an authenticated route is the same generic 500', async () => {
    const u = await seedUser(ctx.repos, 'boom@b.co');
    ctx.memory.devices.listForUser = async () => {
      throw pgStyleError('boom@b.co');
    };
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: u.headers });
    expect(res.statusCode).toBe(500);
    expectErrorBody(res.json(), 'internal');
    expect(res.body).not.toMatch(INTERNAL_DETAIL);
  });

  it('a lost unique-key race is a 409 conflict, not a 500 with the constraint name', async () => {
    const u = await seedUser(ctx.repos, 'race@b.co');
    ctx.memory.devices.listForUser = async () => {
      throw new UniqueViolation('devices_user_id_installation_id_key');
    };
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: u.headers });
    expect(res.statusCode).toBe(409);
    expectErrorBody(res.json(), 'conflict');
    expect(res.body).not.toContain('devices_user_id');
  });

  it('a token of a deleted account (foreign key) is 401 account_not_found', async () => {
    const u = await seedUser(ctx.repos, 'gone@b.co');
    ctx.memory.devices.listForUser = async () => {
      throw new ForeignKeyViolation('devices_user_id_fkey');
    };
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: u.headers });
    expect(res.statusCode).toBe(401);
    expectErrorBody(res.json(), 'account_not_found');
    expect(res.body).not.toContain('devices_user_id_fkey');
  });

  it('provider failures are a 503 ai_unavailable without the provider text (which can echo the prompt)', async () => {
    const u = await seedUser(ctx.repos, 'ai503@b.co');
    const { ProviderError } = await import('@wattbyte/ai');
    for (const [id, provider] of Object.entries(ctx.providers)) {
      provider.set({ fail: new ProviderError(id as 'openai', 'HTTP 500 upstream said: PROMPT-ECHO-CANARY sk-live-0123456789', 500) });
    }
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u.headers, payload: { input: sampleAiInput } });
    expect(res.statusCode).toBe(503);
    expectErrorBody(res.json(), 'ai_unavailable');
    expect(res.body).not.toContain('PROMPT-ECHO-CANARY');
    expect(res.body).not.toContain('sk-live');
  });
});

describe('error handler unit contract (statuses no route currently produces)', () => {
  it('maps HttpError, framework errors and unknown errors', async () => {
    const app = Fastify();
    app.setErrorHandler(errorHandler);
    app.get('/forbidden', async () => {
      throw HttpError.forbidden();
    });
    app.get('/conflict', async () => {
      throw HttpError.conflict('email_taken', 'taken');
    });
    app.get('/teapot', async () => {
      throw Object.assign(new Error('internal wording of a plugin'), { statusCode: 418 });
    });
    app.get('/weird', async () => {
      throw Object.assign(new Error('boom'), { code: 'constructor' });
    });
    app.get('/fivehundred', async () => {
      throw Object.assign(new Error('x'), { statusCode: 502 });
    });
    await app.ready();
    try {
      const forbidden = await app.inject({ url: '/forbidden' });
      expect(forbidden.statusCode).toBe(403);
      expectErrorBody(forbidden.json(), 'forbidden');

      const conflict = await app.inject({ url: '/conflict' });
      expect(conflict.statusCode).toBe(409);
      expectErrorBody(conflict.json(), 'email_taken');

      // A bare 4xx from somewhere else gets the stable generic code, not the library's wording.
      const teapot = await app.inject({ url: '/teapot' });
      expect(teapot.statusCode).toBe(418);
      expectErrorBody(teapot.json(), 'bad_request');
      expect(teapot.body).not.toContain('plugin');

      // An error whose code collides with an Object.prototype member is still just an internal error.
      const weird = await app.inject({ url: '/weird' });
      expect(weird.statusCode).toBe(500);
      expectErrorBody(weird.json(), 'internal');

      const fivehundred = await app.inject({ url: '/fivehundred' });
      expect(fivehundred.statusCode).toBe(500);
      expectErrorBody(fivehundred.json(), 'internal');
    } finally {
      await app.close();
    }
  });
});
