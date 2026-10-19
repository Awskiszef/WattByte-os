import { createHash } from 'node:crypto';

import type { InjectOptions } from 'fastify';
import { SignJWT } from 'jose';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { TEST_SECRET, type BuiltApp, buildTestApp, expectErrorBody, register, sampleAiInput, sampleDay, seedUser } from './support.js';

let ctx: BuiltApp;
beforeEach(async () => {
  ctx = await buildTestApp();
});
afterEach(() => ctx.app.close());

const key = new TextEncoder().encode(TEST_SECRET);
const b64 = (v: unknown): string => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');
const now = (): number => Math.floor(Date.now() / 1000);
const me = (authorization?: string) =>
  ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: authorization === undefined ? {} : { authorization } });

/** A token the server would accept, except for the one thing the test changes. */
function forge(opts: { secret?: Uint8Array; alg?: 'HS256' | 'HS384' | 'HS512'; iss?: string; aud?: string; sub?: string; exp?: number | null; iat?: number | null; plan?: string } = {}) {
  const jwt = new SignJWT({ plan: opts.plan ?? 'free' })
    .setProtectedHeader({ alg: opts.alg ?? 'HS256', typ: 'JWT' })
    .setSubject(opts.sub ?? '00000000-0000-4000-8000-0000000000aa')
    .setIssuer(opts.iss ?? 'wattbyte')
    .setAudience(opts.aud ?? 'wattbyte-mobile');
  if (opts.iat !== null) jwt.setIssuedAt(opts.iat ?? now());
  if (opts.exp !== null) jwt.setExpirationTime(opts.exp ?? now() + 600);
  return jwt.sign(opts.secret ?? key);
}

describe('JWT tampering', () => {
  it('accepts a token of the shape the server issues (control)', async () => {
    const u = await seedUser(ctx.repos, 'jwt@b.co');
    expect((await me(`Bearer ${u.accessToken}`)).statusCode).toBe(200);
    // and a forged-but-correctly-signed one for the same subject, so the failures below are about the one changed property
    const ok = await forge({ sub: u.userId });
    expect((await me(`Bearer ${ok}`)).statusCode).toBe(200);
  });

  it('rejects alg=none, in several spellings', async () => {
    const u = await seedUser(ctx.repos, 'none@b.co');
    const payload = { sub: u.userId, iss: 'wattbyte', aud: 'wattbyte-mobile', plan: 'premium', iat: now(), exp: now() + 600 };
    for (const alg of ['none', 'None', 'NONE', 'nOnE']) {
      expect((await me(`Bearer ${b64({ alg, typ: 'JWT' })}.${b64(payload)}.`)).statusCode, alg).toBe(401);
      expect((await me(`Bearer ${b64({ alg, typ: 'JWT' })}.${b64(payload)}.${b64('sig')}`)).statusCode, `${alg} + signature`).toBe(401);
    }
  });

  it('rejects the wrong secret, the wrong issuer, the wrong audience and a missing issuer/audience', async () => {
    const u = await seedUser(ctx.repos, 'claims@b.co');
    const other = new TextEncoder().encode('another-secret-another-secret-another-secret!');
    expect((await me(`Bearer ${await forge({ sub: u.userId, secret: other })}`)).statusCode).toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, iss: 'evil' })}`)).statusCode).toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, aud: 'someone-else' })}`)).statusCode).toBe(401);
    const noIss = await new SignJWT({ plan: 'free' }).setProtectedHeader({ alg: 'HS256' }).setSubject(u.userId).setAudience('wattbyte-mobile').setIssuedAt().setExpirationTime('10m').sign(key);
    expect((await me(`Bearer ${noIss}`)).statusCode).toBe(401);
  });

  it('rejects expired tokens, tokens without expiry, and an HS384/HS512 token signed with the right secret (algorithm is pinned)', async () => {
    const u = await seedUser(ctx.repos, 'exp@b.co');
    expect((await me(`Bearer ${await forge({ sub: u.userId, iat: now() - 7200, exp: now() - 3600 })}`)).statusCode).toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, exp: now() - 1 })}`)).statusCode).toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, exp: null })}`)).statusCode, 'no exp = valid forever').toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, alg: 'HS512' })}`)).statusCode).toBe(401);
    expect((await me(`Bearer ${await forge({ sub: u.userId, alg: 'HS384' })}`)).statusCode).toBe(401);
  });

  it('rejects a token whose subject is not a user id instead of failing inside the database', async () => {
    for (const sub of ['not-a-uuid', "1' OR '1'='1", '', '00000000-0000-0000-0000-00000000000g']) {
      const res = await me(`Bearer ${await forge({ sub })}`);
      expect(res.statusCode, sub).toBe(401);
      expectErrorBody(res.json(), 'invalid_token');
    }
  });

  it('rejects truncated, edited and malformed tokens', async () => {
    const u = await seedUser(ctx.repos, 'trunc@b.co');
    const t = u.accessToken;
    const [h, p, s] = t.split('.') as [string, string, string];
    const cases: Record<string, string> = {
      'last 5 chars missing': t.slice(0, -5),
      'signature missing': `${h}.${p}.`,
      'signature and dot missing': `${h}.${p}`,
      'header only': h,
      'payload edited to premium (old signature)': `${h}.${b64({ ...JSON.parse(Buffer.from(p, 'base64url').toString()), plan: 'premium' })}.${s}`,
      // First character: the last one of a 43-character signature only carries padding bits, and flipping those changes nothing.
      'signature flipped': `${h}.${p}.${s.startsWith('A') ? 'B' : 'A'}${s.slice(1)}`,
      'extra segment': `${t}.extra`,
      garbage: 'a.b.c',
      'four dots': '....',
      'empty after Bearer': '',
      'unicode': 'ключ.ключ.ключ',
      'very long': 'x'.repeat(8_000),
    };
    for (const [name, token] of Object.entries(cases)) {
      const res = await me(`Bearer ${token}`);
      expect(res.statusCode, name).toBe(401);
      expectErrorBody(res.json(), name === 'empty after Bearer' ? 'unauthorized' : 'invalid_token');
    }
  });
});

describe('Authorization header variants', () => {
  it('only a well formed Bearer credential gets in', async () => {
    const u = await seedUser(ctx.repos, 'hdr@b.co');
    const t = u.accessToken;
    const rejected: Record<string, string | undefined> = {
      'no header': undefined,
      'empty header': '',
      'scheme only': 'Bearer',
      'scheme and space only': 'Bearer ',
      'Basic scheme': `Basic ${Buffer.from('a@b.co:password123').toString('base64')}`,
      'Token scheme': `Token ${t}`,
      'raw token without scheme': t,
      'extra word after the token': `Bearer ${t} extra`,
      'two tokens': `Bearer ${t} ${t}`,
      'token twice, comma separated': `Bearer ${t},Bearer ${t}`,
      'tab separator': `Bearer\t${t}`,
      'scheme glued to token': `Bearer${t}`,
      'quoted token': `Bearer "${t}"`,
      'bearer-like prefix': `Bearerx ${t}`,
      'newline smuggling': `Bearer ${t}\nX-Admin: 1`.replace('\n', ' '),
    };
    for (const [name, value] of Object.entries(rejected)) {
      const res = await me(value);
      expect(res.statusCode, name).toBe(401);
      expect(res.json().error.code, name).toMatch(/^(unauthorized|invalid_token)$/);
    }
    // RFC 7235: the scheme is case-insensitive and may be followed by more than one space.
    for (const value of [`Bearer ${t}`, `bearer ${t}`, `BEARER ${t}`, `Bearer   ${t}`]) {
      expect((await me(value)).statusCode, value.slice(0, 12)).toBe(200);
    }
  });

  it('an access token is not a refresh token and vice versa', async () => {
    const u = await seedUser(ctx.repos, 'swap@b.co');
    expect((await me(`Bearer ${u.refreshToken}`)).statusCode).toBe(401);
    const refresh = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: u.accessToken } });
    expect(refresh.statusCode).toBe(401);
  });

  it('a token of a deleted account stops working everywhere it is used', async () => {
    const u = await seedUser(ctx.repos, 'deleted@b.co');
    expect((await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: u.headers })).statusCode).toBe(204);
    expect((await me(u.headers.authorization)).statusCode).toBe(401);
    const ai = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u.headers, payload: { input: sampleAiInput } });
    expect(ai.statusCode).toBe(401);
    const refresh = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: u.refreshToken } });
    expect(refresh.statusCode).toBe(401);
  });
});

describe('credentials input', () => {
  const reg = (email: string, password: string) => ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password } });

  it('password length is 8..200', async () => {
    expect((await reg('p7@b.co', 'a'.repeat(7))).statusCode).toBe(400);
    expect((await reg('p8@b.co', 'a'.repeat(8))).statusCode).toBe(201);
    expect((await reg('p200@b.co', 'a'.repeat(200))).statusCode).toBe(201);
    const over = await reg('p201@b.co', 'a'.repeat(201));
    expect(over.statusCode).toBe(400);
    expectErrorBody(over.json(), 'validation');
    // The 200-character password really is what is checked at login (no silent truncation).
    const ok = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'p200@b.co', password: 'a'.repeat(200) } });
    expect(ok.statusCode).toBe(200);
    const truncated = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'p200@b.co', password: 'a'.repeat(199) } });
    expect(truncated.statusCode).toBe(401);
  });

  it('e-mail is trimmed and case-folded; the same address in another case is the same account', async () => {
    const first = await reg('  Mixed.Case@Example.CO  ', 'password123');
    expect(first.statusCode).toBe(201);
    expect(first.json().user.email).toBe('mixed.case@example.co');
    expect((await reg('MIXED.CASE@EXAMPLE.CO', 'password123')).statusCode).toBe(409);
    const login = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'Mixed.Case@example.co', password: 'password123' } });
    expect(login.statusCode).toBe(200);
  });

  it('odd e-mail input is a clean 400 (never a 500): too long, unicode, whitespace, control characters, SQL-looking', async () => {
    const odd = [
      `${'a'.repeat(250)}@b.co`,
      `a@${'b'.repeat(250)}.co`,
      'ジョン@例え.jp',
      'user@münchen.de',
      'a b@c.co',
      'a@b.co\nbcc@evil.co',
      'a@b.co\u0000',
      '',
      '@',
      'a@',
      '@b.co',
      "'; DROP TABLE users; --",
      "' OR '1'='1",
      "a@b.co' OR '1'='1",
      'a@b.co; SELECT pg_sleep(10)',
      '"quoted"@b.co',
      '<script>alert(1)</script>@b.co',
    ];
    for (const email of odd) {
      const res = await reg(email, 'password123');
      expect(res.statusCode, JSON.stringify(email)).toBe(400);
      expectErrorBody(res.json(), 'validation');
    }
    // The same inputs at login: 400, not an authentication oracle and not a server error.
    for (const email of odd) {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password: 'password123' } });
      expect(res.statusCode, JSON.stringify(email)).toBe(400);
    }
  });

  it('wrong types for credentials are validation errors', async () => {
    for (const payload of [{ email: 5, password: 'password123' }, { email: ['a@b.co'], password: 'password123' }, { email: 'a@b.co', password: { $ne: null } }, { email: { $gt: '' }, password: 'password123' }]) {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload });
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
    }
  });

  it('login does not reveal which accounts exist', async () => {
    await reg('known@b.co', 'password123');
    const wrongPassword = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'known@b.co', password: 'not-the-password' } });
    const unknown = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'unknown@b.co', password: 'not-the-password' } });
    expect(wrongPassword.statusCode).toBe(401);
    expect(unknown.statusCode).toBe(401);
    expect(wrongPassword.json()).toEqual(unknown.json());
  });
});

describe('request size and shape', () => {
  it('a body over 1 MiB is rejected before parsing, with the contract error', async () => {
    const u = await seedUser(ctx.repos, 'big@b.co');
    const payload = JSON.stringify({ installationId: 'install-big-1', platform: 'ios', model: 'x'.repeat(1_100_000) });
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: { ...u.headers, 'content-type': 'application/json' }, payload });
    expect(res.statusCode).toBe(413);
    expectErrorBody(res.json(), 'payload_too_large');
  });

  it('an anonymous caller is rejected before the body is read or validated (401, not 400/413)', async () => {
    const huge = JSON.stringify({ blob: 'x'.repeat(1_200_000) });
    for (const [method, url] of [
      ['POST', '/api/v1/usage/sync'],
      ['POST', '/api/v1/ai/insight'],
      ['PUT', '/api/v1/me/settings'],
      ['POST', '/api/v1/devices'],
    ] as const) {
      const bad = await ctx.app.inject({ method, url, headers: { 'content-type': 'application/json' }, payload: '{not json' });
      expect(bad.statusCode, `${method} ${url} malformed`).toBe(401);
      const big = await ctx.app.inject({ method, url, headers: { 'content-type': 'application/json' }, payload: huge });
      expect(big.statusCode, `${method} ${url} oversized`).toBe(401);
      const wrongType = await ctx.app.inject({ method, url, headers: { 'content-type': 'text/plain' }, payload: 'x' });
      expect(wrongType.statusCode, `${method} ${url} text/plain`).toBe(401);
    }
  });

  it('prototype pollution payloads are rejected or ignored, never applied', async () => {
    const poisoned = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      headers: { 'content-type': 'application/json' },
      payload: '{"email":"proto@b.co","password":"password123","__proto__":{"plan":"premium"}}',
    });
    expect(poisoned.statusCode).toBe(400);
    expectErrorBody(poisoned.json(), 'invalid_json');
    const viaConstructor = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      headers: { 'content-type': 'application/json' },
      payload: '{"email":"proto2@b.co","password":"password123","constructor":{"prototype":{"plan":"premium"}}}',
    });
    // Either rejected or the extra keys ignored: the account is free either way.
    if (viaConstructor.statusCode === 201) expect(viaConstructor.json().user.plan).toBe('free');
    else expect(viaConstructor.statusCode).toBe(400);
    expect(({} as { plan?: string }).plan).toBeUndefined();
  });
});

describe('NUL characters are invalid input everywhere (PostgreSQL text cannot hold them)', () => {
  it('is a 400 validation error in bodies, nested values, object keys, query strings and path parameters', async () => {
    const u = await seedUser(ctx.repos, 'nul@b.co');
    const cases: [string, InjectOptions][] = [
      ['register displayName', { method: 'POST', url: '/api/v1/auth/register', payload: { email: 'nul2@b.co', password: 'password123', displayName: 'a\u0000b' } }],
      ['PATCH /me', { method: 'PATCH', url: '/api/v1/me', headers: u.headers, payload: { displayName: '\u0000' } }],
      ['device model', { method: 'POST', url: '/api/v1/devices', headers: u.headers, payload: { installationId: 'install-nul-1', platform: 'ios', model: 'x\u0000' } }],
      ['nested array value', { method: 'POST', url: '/api/v1/usage/sync', headers: u.headers, payload: { installationId: 'install-nul-1', days: [sampleDay('2026-10-10'), { ...sampleDay('2026-10-11'), currency: 'P\u0000N' }] } }],
      ['unknown key with NUL', { method: 'PATCH', url: '/api/v1/me', headers: u.headers, payload: { displayName: 'ok', 'k\u0000ey': 1 } }],
      ['query string', { method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01%00&to=2026-10-31', headers: u.headers }],
      ['path parameter', { method: 'DELETE', url: '/api/v1/devices/%00', headers: u.headers }],
    ];
    for (const [name, request] of cases) {
      const res = await ctx.app.inject(request);
      expect(res.statusCode, name).toBe(400);
      expectErrorBody(res.json(), 'validation');
    }
  });

  it('containsNul finds a NUL however deep, without recursion', async () => {
    const { containsNul } = await import('../src/middleware/input-guards.js');
    let deep: unknown = ['\u0000'];
    for (let i = 0; i < 50_000; i++) deep = [deep];
    expect(containsNul(deep)).toBe(true);
    expect(containsNul({ a: [{ b: 'x' }, { c: ['clean'] }], d: null, e: 5 })).toBe(false);
    expect(containsNul(undefined)).toBe(false);
    expect(containsNul('\u0000')).toBe(true);
  });
});

describe('mass assignment: a client never chooses its plan, limits, owner or role', () => {
  const FORBIDDEN = { plan: 'premium', isPremium: true, premium: true, role: 'admin', isAdmin: true, limit: 9999, dailyLimit: 9999, aiDailyLimit: 9999, remaining: 9999 };

  it('register ignores plan/role fields: the stored user and the issued token are free', async () => {
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'mass@b.co', password: 'password123', ...FORBIDDEN, id: '00000000-0000-4000-8000-000000000001', createdAt: '2001-01-01T00:00:00Z' } });
    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.user.plan).toBe('free');
    expect(body.user.id).not.toBe('00000000-0000-4000-8000-000000000001');
    expect(body.user.createdAt).not.toBe('2001-01-01T00:00:00.000Z');
    const stored = await ctx.memory.users.findById(body.user.id);
    expect(stored).toMatchObject({ plan: 'free' });
    const claims = JSON.parse(Buffer.from(body.tokens.accessToken.split('.')[1], 'base64url').toString());
    expect(claims.plan).toBe('free');
  });

  it('PATCH /me changes the display name and nothing else', async () => {
    const u = await seedUser(ctx.repos, 'patch@b.co');
    const other = await seedUser(ctx.repos, 'patch-victim@b.co');
    const res = await ctx.app.inject({
      method: 'PATCH',
      url: '/api/v1/me',
      headers: u.headers,
      payload: { displayName: 'New Name', ...FORBIDDEN, email: 'evil@b.co', id: other.userId, userId: other.userId, passwordHash: 'x' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: u.userId, email: 'patch@b.co', plan: 'free', displayName: 'New Name' });
    expect(await ctx.memory.users.findById(u.userId)).toMatchObject({ email: 'patch@b.co', plan: 'free', displayName: 'New Name' });
    expect(await ctx.memory.users.findById(other.userId)).toMatchObject({ email: 'patch-victim@b.co', plan: 'free', displayName: null });
    // The e-mail did not change, so the address stays unique (the "evil" one was never taken).
    expect(await ctx.memory.users.findByEmail('evil@b.co')).toBeNull();
  });

  it('PUT /me/settings stores the caller\'s preferences only', async () => {
    const u = await seedUser(ctx.repos, 'settings@b.co');
    const victim = await seedUser(ctx.repos, 'settings-victim@b.co');
    const res = await ctx.app.inject({
      method: 'PUT',
      url: '/api/v1/me/settings',
      headers: u.headers,
      payload: { countryCode: 'PL', currencyCode: 'PLN', ...FORBIDDEN, userId: victim.userId, user_id: victim.userId },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ countryCode: 'PL', currencyCode: 'PLN' });
    expect(await ctx.memory.settings.get(u.userId)).toMatchObject({ countryCode: 'PL' });
    expect(await ctx.memory.settings.get(victim.userId)).toBeNull();
    expect(await ctx.memory.users.findById(u.userId)).toMatchObject({ plan: 'free' });
  });

  it('POST /devices and usage sync ignore owner and plan fields from the body', async () => {
    const u = await seedUser(ctx.repos, 'devmass@b.co');
    const victim = await seedUser(ctx.repos, 'devmass-victim@b.co');
    const victimDevice = await ctx.memory.devices.upsert({ userId: victim.userId, installationId: 'victim-install-1', platform: 'ios' });

    const dev = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/devices',
      headers: u.headers,
      payload: { installationId: 'install-mass-1', platform: 'android', ...FORBIDDEN, userId: victim.userId, id: victimDevice.id },
    });
    expect(dev.statusCode).toBe(201);
    expect(dev.json().id).not.toBe(victimDevice.id);
    expect((await ctx.memory.devices.listForUser(u.userId)).map((d) => d.installationId)).toEqual(['install-mass-1']);
    expect((await ctx.memory.devices.listForUser(victim.userId)).map((d) => d.installationId)).toEqual(['victim-install-1']);

    const sync = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/usage/sync',
      headers: u.headers,
      payload: { installationId: 'install-mass-1', days: [{ ...sampleDay('2026-10-12'), ...FORBIDDEN, userId: victim.userId, deviceId: victimDevice.id }], userId: victim.userId },
    });
    expect(sync.statusCode).toBe(200);
    expect(await ctx.memory.usage.listDaily(victim.userId, '2026-01-01', '2026-12-31')).toEqual([]);
    const mine = await ctx.memory.usage.listDaily(u.userId, '2026-01-01', '2026-12-31');
    expect(mine).toHaveLength(1);
    expect(mine[0]).toMatchObject({ userId: u.userId, deviceId: dev.json().id });
  });

  it('AI requests cannot raise the quota or claim another plan', async () => {
    const u = await seedUser(ctx.repos, 'aimass@b.co');
    const call = () => ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u.headers, payload: { input: sampleAiInput, ...FORBIDDEN, userRef: 'someone-else', userId: 'someone-else', locale: 'en', mode: 'normal' } });
    const first = await call();
    expect(first.statusCode).toBe(200);
    expect(first.json().remainingToday).toBe(1); // the free limit of this test app is 2
    expect((await call()).statusCode).toBe(200);
    const third = await call();
    expect(third.statusCode).toBe(429);
    expectErrorBody(third.json(), 'ai_quota_exceeded');
    // Smuggling extra keys into the aggregates themselves is rejected before any provider is paid (strict schema).
    const before = Object.values(ctx.providers).reduce((n, p) => n + p.calls.length, 0);
    const u2 = await seedUser(ctx.repos, 'aimass2@b.co');
    const smuggle = await ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: u2.headers, payload: { input: { ...sampleAiInput, email: 'aimass2@b.co', userId: u2.userId, plan: 'premium' } } });
    expect(smuggle.statusCode).toBe(400);
    expect(Object.values(ctx.providers).reduce((n, p) => n + p.calls.length, 0)).toBe(before);
  });

  it('a premium claim cannot be obtained from any endpoint: every account created through the API is free', async () => {
    const u = await register(ctx.app, 'free@b.co', 'password123', FORBIDDEN);
    await ctx.app.inject({ method: 'PATCH', url: '/api/v1/me', headers: u.headers, payload: { displayName: 'x', ...FORBIDDEN } });
    await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: u.headers, payload: { ...FORBIDDEN } });
    await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: u.headers, payload: { installationId: 'install-free-1', platform: 'ios', ...FORBIDDEN } });
    const login = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'free@b.co', password: 'password123', ...FORBIDDEN } });
    expect(login.json().user.plan).toBe('free');
    const refreshed = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: login.json().tokens.refreshToken, ...FORBIDDEN } });
    expect(refreshed.json().user.plan).toBe('free');
    expect((await ctx.memory.users.findById(u.userId))?.plan).toBe('free');
  });
});

describe('IDOR: one user can not read or change another user\'s data', () => {
  it('devices, usage and settings are scoped to the token owner', async () => {
    const a = await seedUser(ctx.repos, 'idor-a@b.co');
    const b = await seedUser(ctx.repos, 'idor-b@b.co');

    const bDevice = (await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: b.headers, payload: { installationId: 'b-install-0001', platform: 'ios', model: 'iPhone B' } })).json() as { id: string };
    expect((await ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: b.headers, payload: { installationId: 'b-install-0001', days: [sampleDay('2026-10-10'), sampleDay('2026-10-11')] } })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: b.headers, payload: { countryCode: 'DE', currencyCode: 'EUR' } })).statusCode).toBe(200);

    // devices
    const aList = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: a.headers });
    expect(aList.json().devices).toEqual([]);
    const del = await ctx.app.inject({ method: 'DELETE', url: `/api/v1/devices/${bDevice.id}`, headers: a.headers });
    expect(del.statusCode).toBe(404);
    expectErrorBody(del.json(), 'device_not_found');
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: b.headers })).json().devices).toHaveLength(1);

    // usage: A can neither read B's days nor write to B's device by quoting its installation id
    const aDaily = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-01-01&to=2026-12-31', headers: a.headers });
    expect(aDaily.json().days).toEqual([]);
    const aSync = await ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: a.headers, payload: { installationId: 'b-install-0001', days: [{ ...sampleDay('2026-10-10'), mobileBytes: 999_999 }] } });
    expect(aSync.statusCode).toBe(404);
    expectErrorBody(aSync.json(), 'device_not_registered');
    const bDaily = (await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-01-01&to=2026-12-31', headers: b.headers })).json().days as { mobileBytes: number }[];
    expect(bDaily).toHaveLength(2);
    expect(bDaily.every((d) => d.mobileBytes === 1_000)).toBe(true);

    // A registering the same installation id gets its own device; B's data is unaffected
    const aDevice = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: a.headers, payload: { installationId: 'b-install-0001', platform: 'android' } });
    expect(aDevice.statusCode).toBe(201);
    expect(aDevice.json().id).not.toBe(bDevice.id);
    expect(aDevice.json().model).toBeNull();
    expect((await ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: a.headers, payload: { installationId: 'b-install-0001', days: [{ ...sampleDay('2026-10-10'), mobileBytes: 5 }] } })).statusCode).toBe(200);
    const bAfter = (await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-10&to=2026-10-10', headers: b.headers })).json().days as { mobileBytes: number }[];
    expect(bAfter[0]?.mobileBytes).toBe(1_000);

    // settings
    const aSettings = (await ctx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers: a.headers })).json();
    expect(aSettings.countryCode).toBeNull();
    await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: a.headers, payload: { countryCode: 'PL' } });
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers: b.headers })).json()).toMatchObject({ countryCode: 'DE', currencyCode: 'EUR' });

    // deleting A leaves B untouched
    expect((await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: b.headers })).json().devices).toHaveLength(1);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: b.headers })).statusCode).toBe(200);
  });

  it('the AI quota is per user', async () => {
    const a = await seedUser(ctx.repos, 'quota-a@b.co');
    const b = await seedUser(ctx.repos, 'quota-b@b.co');
    const call = (headers: { authorization: string }) => ctx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers, payload: { input: sampleAiInput } });
    expect((await call(a.headers)).statusCode).toBe(200);
    expect((await call(a.headers)).statusCode).toBe(200);
    expect((await call(a.headers)).statusCode).toBe(429);
    expect((await call(b.headers)).statusCode).toBe(200);
  });
});

describe('authentication is required on every route that is not explicitly public', () => {
  /** The complete public surface. Adding to this list is a security decision: it needs a reason. */
  const PUBLIC = new Set([
    'GET /health',
    'HEAD /health',
    'GET /ready',
    'HEAD /ready',
    'GET /openapi.json',
    'HEAD /openapi.json',
    'POST /api/v1/auth/register',
    'POST /api/v1/auth/login',
    'POST /api/v1/auth/refresh',
    'POST /api/v1/auth/logout',
    'POST /api/v1/auth/apple',
    'POST /api/v1/auth/google',
    'GET /api/v1/devices/specifications/:identifier',
    'HEAD /api/v1/devices/specifications/:identifier',
    'GET /api/v1/region',
    'HEAD /api/v1/region',
    'GET /api/v1/config',
    'HEAD /api/v1/config',
  ]);
  const concrete = (url: string): string => url.replace(/:[A-Za-z]+/g, '00000000-0000-4000-8000-000000000001');

  it('the route table matches what the OpenAPI document and printRoutes() list', async () => {
    const table = ctx.app.routeTable.all();
    expect(table.length).toBeGreaterThan(15);
    const spec = ctx.app.swagger() as { paths: Record<string, Record<string, unknown>> };
    for (const [path, methods] of Object.entries(spec.paths)) {
      for (const method of Object.keys(methods)) {
        const url = path.replace(/\{([^}]+)\}/g, ':$1');
        expect(table, `${method.toUpperCase()} ${url} documented but not in the route table`).toContainEqual({ method: method.toUpperCase(), url });
      }
    }
    const printed = ctx.app.printRoutes({ commonPrefix: false });
    for (const { url } of table) {
      const last = url.split('/').filter(Boolean).pop() ?? '';
      expect(printed, url).toContain(last.replace(/^:/, ':'));
    }
  });

  it('every public route is on the allow list, every other route answers 401 without a token and 401 with a bad one', async () => {
    const table = ctx.app.routeTable.all();
    const publicSeen = new Set<string>();
    const protectedSeen: string[] = [];
    for (const { method, url } of table) {
      const id = `${method} ${url}`;
      if (PUBLIC.has(id)) {
        publicSeen.add(id);
        continue;
      }
      protectedSeen.push(id);
      const hasBody = ['POST', 'PUT', 'PATCH'].includes(method);
      const base = { method: method as 'GET', url: concrete(url) };
      const anon = await ctx.app.inject({ ...base, ...(hasBody ? { headers: { 'content-type': 'application/json' }, payload: '{}' } : {}) });
      expect(anon.statusCode, `${id} without a token`).toBe(401);
      if (method !== 'HEAD') expectErrorBody(anon.json(), 'unauthorized');
      const bad = await ctx.app.inject({ ...base, headers: { authorization: 'Bearer not.a.token', ...(hasBody ? { 'content-type': 'application/json' } : {}) }, ...(hasBody ? { payload: '{}' } : {}) });
      expect(bad.statusCode, `${id} with a bad token`).toBe(401);
    }
    // Nothing on the allow list went missing (a renamed route must not leave a stale exception behind) ...
    expect([...PUBLIC].filter((id) => !publicSeen.has(id))).toEqual([]);
    // ... and the protected surface is what we think it is.
    for (const expected of ['GET /api/v1/me', 'PATCH /api/v1/me', 'DELETE /api/v1/me', 'GET /api/v1/me/settings', 'PUT /api/v1/me/settings', 'GET /api/v1/devices', 'POST /api/v1/devices', 'DELETE /api/v1/devices/:id', 'POST /api/v1/usage/sync', 'GET /api/v1/usage/daily', 'GET /api/v1/electricity-price', 'POST /api/v1/ai/insight', 'POST /api/v1/ai/weekly-summary', 'POST /api/v1/ai/monthly-summary', 'POST /api/v1/ai/roast']) {
      expect(protectedSeen, expected).toContain(expected);
    }
  });

  it('the public routes really are reachable without a token', async () => {
    expect((await ctx.app.inject({ method: 'GET', url: '/health' })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/ready' })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/openapi.json' })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/region' })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/config' })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/NoSuchModel' })).statusCode).toBe(404);
    expect((await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'a@b.co', password: 'password123' } })).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: 'x'.repeat(30) } })).statusCode).toBe(204);
  });

  it('deny by default: a route added without any auth code is protected', async () => {
    const { default: Fastify } = await import('fastify');
    const { authenticateUnlessPublic } = await import('../src/middleware/auth.js');
    const { TokenService } = await import('../src/modules/auth/tokens.js');
    const { errorHandler } = await import('../src/errors/http-error.js');
    const app = Fastify();
    app.setErrorHandler(errorHandler);
    app.addHook('preParsing', authenticateUnlessPublic(new TokenService(TEST_SECRET, 900, 30), { users: { findById: async () => null } as never }));
    app.get('/forgot-auth', async () => ({ secret: true }));
    app.get('/meant-public', { config: { public: true } }, async () => ({ ok: true }));
    await app.ready();
    try {
      expect((await app.inject({ url: '/forgot-auth' })).statusCode).toBe(401);
      expect((await app.inject({ url: '/meant-public' })).statusCode).toBe(200);
      // unknown paths are 404, not 401: nothing behind them to protect
      expect((await app.inject({ url: '/nowhere' })).statusCode).toBe(404);
    } finally {
      await app.close();
    }
  });
});

describe('rate limiting on credential endpoints', () => {
  it('login, register, refresh and the social sign-in stubs are throttled per IP; the limit applies to the 429 path too', async () => {
    const limited = await buildTestApp({ authRateLimitMax: 3 });
    try {
      const hit = (url: string, payload: unknown) => limited.app.inject({ method: 'POST', url, payload: payload as object });
      const cases: [string, unknown, number][] = [
        ['/api/v1/auth/login', { email: 'a@b.co', password: 'password123' }, 401],
        ['/api/v1/auth/refresh', { refreshToken: 'x'.repeat(30) }, 401],
        ['/api/v1/auth/register', { email: 'nope', password: 'x' }, 400],
        ['/api/v1/auth/apple', { idToken: 'x'.repeat(20) }, 501],
        ['/api/v1/auth/google', { idToken: 'x'.repeat(20) }, 501],
      ];
      for (const [url, payload, status] of cases) {
        for (let i = 0; i < 3; i++) expect((await hit(url, payload)).statusCode, `${url} #${i + 1}`).toBe(status);
        const blocked = await hit(url, payload);
        expect(blocked.statusCode, `${url} #4`).toBe(429);
        expectErrorBody(blocked.json(), 'rate_limited');
        expect(Number(blocked.headers['retry-after'])).toBeGreaterThan(0);
      }
    } finally {
      await limited.app.close();
    }
  });

  it('a blocked client can not get a token by guessing: the 4th password attempt is refused even when correct', async () => {
    const limited = await buildTestApp({ authRateLimitMax: 3 });
    try {
      // register is limited too, so create the account directly
      const { hashPassword } = await import('../src/modules/auth/password.js');
      await limited.memory.users.create({ email: 'victim@b.co', passwordHash: await hashPassword('correct-horse-battery') });
      const attempt = (password: string) => limited.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'victim@b.co', password } });
      for (const guess of ['guess-number-1', 'guess-number-2', 'guess-number-3']) expect((await attempt(guess)).statusCode).toBe(401);
      expect((await attempt('correct-horse-battery')).statusCode).toBe(429);
    } finally {
      await limited.app.close();
    }
  });
});

describe('secrets at rest', () => {
  it('refresh tokens are stored hashed, never in clear', async () => {
    const u = await register(ctx.app, 'hash@b.co');
    const stored = await ctx.memory.sessions.findByHash(createHash('sha256').update(u.refreshToken).digest('hex'));
    expect(stored?.userId).toBe(u.userId);
    expect(await ctx.memory.sessions.findByHash(u.refreshToken)).toBeNull();
    const user = await ctx.memory.users.findById(u.userId);
    expect(user?.passwordHash).toMatch(/^scrypt\$65536\$8\$1\$/);
    expect(user?.passwordHash).not.toContain('password123');
  });
});
