import { ProviderError } from '@wattbyte/ai';
import { afterEach, describe, expect, it } from 'vitest';

import { generateRequestId, REQUEST_ID_PATTERN } from '../src/observability/request-id.js';
import { loggablePath, LOG_CENSOR } from '../src/observability/logging.js';
import { type BuiltApp, buildTestApp, LogCapture, pgStyleError, sampleAiInput, sampleDay, seedUser } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  await Promise.all(apps.splice(0).map((c) => c.app.close()));
});
async function make(opts: Parameters<typeof buildTestApp>[0] = {}): Promise<BuiltApp> {
  const ctx = await buildTestApp(opts);
  apps.push(ctx);
  return ctx;
}

describe('x-request-id', () => {
  it('is generated (a UUID) when the caller sends none, on success and on error', async () => {
    const { app } = await make();
    const ok = await app.inject({ method: 'GET', url: '/health' });
    const missing = await app.inject({ method: 'GET', url: '/nope' });
    for (const res of [ok, missing]) {
      expect(res.headers['x-request-id']).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    }
    expect(ok.headers['x-request-id']).not.toBe(missing.headers['x-request-id']);
  });

  it('echoes a well formed incoming id (8-64 of A-Za-z0-9._-), also on errors', async () => {
    const { app } = await make();
    for (const id of ['abcdefgh', 'req-2026.10.13_x', 'A'.repeat(64), 'a1b2c3d4-e5f6-7890-abcd-ef1234567890']) {
      const ok = await app.inject({ method: 'GET', url: '/health', headers: { 'x-request-id': id } });
      expect(ok.headers['x-request-id']).toBe(id);
      const err = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { 'x-request-id': id } });
      expect(err.statusCode).toBe(401);
      expect(err.headers['x-request-id']).toBe(id);
    }
  });

  it('replaces a malformed incoming id with a UUID (length, characters, repetition)', async () => {
    const { app } = await make();
    const bad = ['short', 'abcdefg', 'A'.repeat(65), 'has space in it', '<script>alert(1)</script>', 'semi;colon=1', 'ünïcödé-id-123', 'a,b,c,d,e,f,g,h', '../../etc/passwd'];
    for (const id of bad) {
      const res = await app.inject({ method: 'GET', url: '/health', headers: { 'x-request-id': id } });
      const out = res.headers['x-request-id'] as string;
      expect(out, id).not.toBe(id);
      expect(out, id).toMatch(/^[0-9a-f-]{36}$/);
    }
    // A repeated header is joined with ", " by Node and therefore fails the pattern.
    const twice = await app.inject({ method: 'GET', url: '/health', headers: { 'x-request-id': ['validid-1', 'validid-2'] } });
    expect(twice.headers['x-request-id']).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('the pattern is exactly ^[A-Za-z0-9._-]{8,64}$', () => {
    expect(REQUEST_ID_PATTERN.source).toBe('^[A-Za-z0-9._-]{8,64}$');
    expect(generateRequestId({ headers: { 'x-request-id': 'abcdefgh' } } as never)).toBe('abcdefgh');
    expect(generateRequestId({ headers: {} } as never)).toMatch(/^[0-9a-f-]{36}$/);
  });

  it('appears in every log line of that request', async () => {
    const log = new LogCapture();
    const { app } = await make({ logStream: log });
    await app.inject({ method: 'GET', url: '/health', headers: { 'x-request-id': 'trace-me-0001' } });
    const mine = log.records().filter((r) => r.reqId === 'trace-me-0001');
    expect(mine.length).toBeGreaterThanOrEqual(2); // incoming request + request completed
    expect(mine.some((r) => (r.res as { statusCode?: number } | undefined)?.statusCode === 200)).toBe(true);
  });
});

describe('logs never contain secrets, personal data or AI text', () => {
  const EMAIL = 'leaky.person@privacy-test.example';
  const PASSWORD = 'Sup3r-Secret-Passw0rd!';
  const NEW_PASSWORD_TRY = 'Wrong-Passw0rd-Guess';
  const AI_RESPONSE_CANARY = 'CANARY-AI-RESPONSE-TEXT-7731';
  const AI_INPUT_CANARY_GB = 987.654321;
  const PROVIDER_ERROR_CANARY = 'CANARY-PROVIDER-ECHO-5520';

  it('survives register, login, refresh, logout, an AI call, a sync and every kind of error', async () => {
    const log = new LogCapture();
    const { app, memory, providers } = await make({ logStream: log });
    const trigger = memory.users.findByEmail;
    memory.users.findByEmail = async (email) => {
      if (email.startsWith('boom.')) throw pgStyleError(email);
      return trigger(email);
    };
    for (const p of Object.values(providers)) p.set({ text: JSON.stringify({ title: 'T', message: AI_RESPONSE_CANARY, tone: 'normal', severity: 'info', emoji: '⚡' }) });

    const tokens: string[] = [];
    const keep = (...values: string[]) => tokens.push(...values);

    // register, login, refresh, logout
    const reg = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: EMAIL, password: PASSWORD, displayName: 'Leaky Person' } });
    expect(reg.statusCode).toBe(201);
    keep(reg.json().tokens.accessToken, reg.json().tokens.refreshToken);
    const login = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: EMAIL.toUpperCase(), password: PASSWORD } });
    expect(login.statusCode).toBe(200);
    keep(login.json().tokens.accessToken, login.json().tokens.refreshToken);
    const refresh = await app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: login.json().tokens.refreshToken } });
    expect(refresh.statusCode).toBe(200);
    keep(refresh.json().tokens.accessToken, refresh.json().tokens.refreshToken);
    const headers = { authorization: `Bearer ${refresh.json().tokens.accessToken}` };

    // AI call with distinctive aggregates
    const ai = await app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers, payload: { input: { ...sampleAiInput, mobileDataGb: AI_INPUT_CANARY_GB } } });
    expect(ai.statusCode).toBe(200);
    expect(ai.json().output.message).toBe(AI_RESPONSE_CANARY);

    // device + sync
    const dev = await app.inject({ method: 'POST', url: '/api/v1/devices', headers, payload: { installationId: 'install-privacy-1', platform: 'ios' } });
    expect(dev.statusCode).toBe(201);
    const sync = await app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers, payload: { installationId: 'install-privacy-1', days: [sampleDay('2026-10-12')] } });
    expect(sync.statusCode).toBe(200);

    // error paths, each with the email / password / a token in the request
    const wrong = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: EMAIL, password: NEW_PASSWORD_TRY } });
    expect(wrong.statusCode).toBe(401);
    const invalid = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: EMAIL.replace('@', ' '), password: PASSWORD } });
    expect(invalid.statusCode).toBe(400);
    const dup = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: EMAIL, password: PASSWORD } });
    expect(dup.statusCode).toBe(409);
    const malformed = await app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: { 'content-type': 'application/json' }, payload: `{"email":"${EMAIL}","password":"${PASSWORD}",` });
    expect(malformed.statusCode).toBe(400);
    const unknownRoute = await app.inject({ method: 'GET', url: `/api/v1/users/${EMAIL}/profile?email=${EMAIL}&token=${tokens[0]}` });
    expect(unknownRoute.statusCode).toBe(404);
    const reuse = await app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: login.json().tokens.refreshToken } });
    expect(reuse.statusCode).toBe(401);
    const badToken = await app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: `Bearer ${tokens[0]!.slice(0, -4)}xxxx` } });
    expect(badToken.statusCode).toBe(401);
    const boom = await app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: `boom.${EMAIL}`, password: PASSWORD } });
    expect(boom.statusCode).toBe(500);
    const badAi = await app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers, payload: { input: { ...sampleAiInput, email: EMAIL } } });
    expect(badAi.statusCode).toBe(400);
    const logout = await app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: refresh.json().tokens.refreshToken } });
    expect(logout.statusCode).toBe(204);

    // an AI failure whose provider text echoes the prompt
    for (const [id, p] of Object.entries(providers)) p.set({ fail: new ProviderError(id as 'openai', `HTTP 400 ${PROVIDER_ERROR_CANARY} ${AI_INPUT_CANARY_GB}`, 400) });
    const failing = await app.inject({ method: 'POST', url: '/api/v1/ai/weekly-summary', headers, payload: { input: { ...sampleAiInput, mobileDataGb: AI_INPUT_CANARY_GB } } });
    expect(failing.statusCode).toBe(503);

    const text = log.text();
    expect(log.lines.length).toBeGreaterThan(30);
    // every line is JSON (a stray console.log or a pretty-printed object would break log shipping)
    expect(() => log.records()).not.toThrow();

    const forbidden: [string, string][] = [
      ['the e-mail address', EMAIL],
      ['the e-mail local part', 'leaky.person'],
      ['the e-mail domain', 'privacy-test.example'],
      ['the password', PASSWORD],
      ['the wrong password', NEW_PASSWORD_TRY],
      ['the display name', 'Leaky Person'],
      ['an Authorization header', 'Bearer '],
      ['the word authorization', 'authorization'],
      ['the AI input value', String(AI_INPUT_CANARY_GB)],
      ['the AI response text', AI_RESPONSE_CANARY],
      ['the provider error text', PROVIDER_ERROR_CANARY],
      ['SQL / constraint names', 'users_email_key'],
      ['the installation id', 'install-privacy-1'],
    ];
    for (const [what, needle] of forbidden) expect(text, `log contains ${what}`).not.toContain(needle);

    // No part of any access or refresh token that was issued: whole token, JWT payload, JWT signature, refresh token halves.
    for (const token of tokens) {
      expect(text, 'whole token').not.toContain(token);
      for (const part of token.split('.')) if (part.length >= 16) expect(text, `token part ${part.slice(0, 8)}…`).not.toContain(part);
      if (!token.includes('.')) {
        expect(text).not.toContain(token.slice(0, 20));
        expect(text).not.toContain(token.slice(-20));
      }
    }

    // The log is still useful: request lines carry the id, the route pattern and the status, but no address or query.
    const completed = log.records().filter((r) => r.msg === 'request completed');
    expect(completed.length).toBeGreaterThanOrEqual(15);
    for (const r of completed) {
      expect(r.reqId).toMatch(/^[A-Za-z0-9._-]{8,64}$/);
      expect(r.res).toEqual({ statusCode: expect.any(Number) });
    }
    const incoming = log.records().filter((r) => r.msg === 'incoming request');
    for (const r of incoming) {
      const req = r.req as Record<string, unknown>;
      expect(Object.keys(req).sort()).toEqual(['method', 'route', 'url'].filter((k) => k in req).sort());
      expect(String(req.url)).not.toContain('?');
      expect(req).not.toHaveProperty('remoteAddress');
      expect(req).not.toHaveProperty('headers');
    }
    const probe = incoming.find((r) => String((r.req as { url: string }).url).includes('/profile'));
    expect((probe?.req as { url: string }).url).toBe('/api/v1/users/[email]/profile');
    const registration = incoming.find((r) => (r.req as { route?: string }).route === '/api/v1/auth/register');
    expect(registration).toBeDefined();
  });

  it('AI logging carries only provider id, model, latency, token counts and status', async () => {
    const log = new LogCapture();
    const { app, providers, repos } = await make({ logStream: log });
    const u = await seedUser(repos, 'ailog@b.co');
    const ok = await app.inject({ method: 'POST', url: '/api/v1/ai/roast', headers: u.headers, payload: { input: sampleAiInput } });
    expect(ok.statusCode).toBe(200);
    const generated = log.records().find((r) => r.msg === 'ai generation');
    expect(generated).toBeDefined();
    expect(Object.keys(generated!.ai as object).sort()).toEqual(['inputTokens', 'latencyMs', 'model', 'outputTokens', 'provider', 'status', 'task']);
    expect(generated!.ai).toMatchObject({ status: 'ok', provider: expect.any(String), model: expect.stringContaining('-mock'), latencyMs: expect.any(Number), inputTokens: expect.any(Number), outputTokens: expect.any(Number) });
    expect(JSON.stringify(generated)).not.toContain(u.userId);
    expect(generated!.reqId, 'AI lines belong to their request').toMatch(/^[0-9a-f-]{36}$/);

    for (const [id, p] of Object.entries(providers)) p.set({ fail: new ProviderError(id as 'openai', `HTTP 503 ${PROVIDER_ERROR_CANARY}`, 503) });
    const bad = await app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u.headers, payload: { input: sampleAiInput } });
    expect(bad.statusCode).toBe(503);
    const failed = log.records().find((r) => r.msg === 'ai generation failed');
    expect(failed).toBeDefined();
    const ai = failed!.ai as { status: string; attempts: { provider?: string; httpStatus?: number; kind: string; category?: string }[] };
    expect(ai.status).toBe('all_providers_failed');
    expect(ai.attempts.length).toBeGreaterThan(0);
    for (const a of ai.attempts) expect(Object.keys(a).sort()).toEqual(['category', 'httpStatus', 'kind', 'provider']);
    // A 503 is retried and then goes to ONE other provider, not to every provider there is.
    expect(ai.attempts.map((a) => a.category)).toEqual(['provider_unavailable', 'provider_unavailable']);
    expect(log.text()).not.toContain(PROVIDER_ERROR_CANARY);
  });

  it('redact censors secret-looking fields of anything logged by hand', async () => {
    const log = new LogCapture();
    const { app } = await make({ logStream: log });
    app.log.info(
      {
        headers: { authorization: 'Bearer abc.def.ghi', cookie: 'sid=1' },
        req: { headers: { authorization: 'Bearer abc.def.ghi', cookie: 'sid=1' } },
        body: { email: 'x@y.co' },
        password: 'hunter2hunter2',
        refreshToken: 'r'.repeat(43),
        user: { email: 'x@y.co', passwordHash: 'scrypt$1', token: 'tok' },
        ai: { prompt: 'secret prompt', input: { a: 1 }, output: { b: 2 } },
      },
      'manual log',
    );
    const text = log.text();
    for (const needle of ['abc.def.ghi', 'sid=1', 'x@y.co', 'hunter2', 'r'.repeat(43), 'scrypt$1', 'secret prompt']) expect(text).not.toContain(needle);
    expect(text).toContain(LOG_CENSOR);
  });

  it('loggablePath keeps the path, drops the query and masks e-mail-looking segments', () => {
    expect(loggablePath('/api/v1/usage/daily?from=2026-01-01&to=2026-01-31')).toBe('/api/v1/usage/daily');
    expect(loggablePath('/a/b@c.de/d?x=y#z')).toBe('/a/[email]/d');
    expect(loggablePath(undefined)).toBe('');
  });
});
