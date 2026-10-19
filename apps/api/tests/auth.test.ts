import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, registerUser, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

describe('auth', () => {
  it('registers, logs in and serves /me with a bearer token', async () => {
    const reg = await registerUser(ctx.app);
    expect(reg.user).toMatchObject({ email: 'a@b.co', plan: 'free', displayName: null });
    expect(reg.tokens.tokenType).toBe('Bearer');

    const me = await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: reg.headers });
    expect(me.statusCode).toBe(200);
    expect(me.json()).toMatchObject({ id: reg.user.id, email: 'a@b.co' });

    const login = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'A@B.co', password: 'password123' } });
    expect(login.statusCode).toBe(200);
  });

  it('rejects duplicates, bad credentials, bad input and missing tokens', async () => {
    await registerUser(ctx.app);
    const dup = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'a@b.co', password: 'password123' } });
    expect(dup.statusCode).toBe(409);
    expect(dup.json()).toEqual({ error: { code: 'email_taken', message: expect.any(String) } });

    const wrong = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: 'a@b.co', password: 'nope-nope' } });
    expect(wrong.statusCode).toBe(401);

    const invalid = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'not-an-email', password: 'short' } });
    expect(invalid.statusCode).toBe(400);
    expect(invalid.json().error.code).toBe('validation');

    const anon = await ctx.app.inject({ method: 'GET', url: '/api/v1/me' });
    expect(anon.statusCode).toBe(401);
  });

  it('rotates refresh tokens and revokes everything on reuse (outside the retry grace window)', async () => {
    await ctx.app.close();
    ctx = await makeApp({ REFRESH_REUSE_GRACE_SEC: '0' });
    const reg = await registerUser(ctx.app);
    const first = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(first.statusCode).toBe(200);
    const next = first.json().tokens.refreshToken as string;
    expect(next).not.toBe(reg.tokens.refreshToken);

    // Reusing the rotated token is treated as theft: the whole family dies.
    const reuse = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(reuse.statusCode).toBe(401);
    expect(reuse.json().error.code).toBe('refresh_token_reused');
    const afterReuse = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: next } });
    expect(afterReuse.statusCode).toBe(401);
  });

  it('a concurrent retry with a just-rotated token is rejected without logging the user out', async () => {
    const reg = await registerUser(ctx.app);
    const results = await Promise.all(
      Array.from({ length: 10 }, () => ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: reg.tokens.refreshToken } })),
    );
    expect(results.filter((r) => r.statusCode === 200)).toHaveLength(1);
    expect(results.filter((r) => r.statusCode === 401)).toHaveLength(9);
    const winner = results.find((r) => r.statusCode === 200)!.json().tokens.refreshToken as string;
    const again = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: winner } });
    expect(again.statusCode).toBe(200);
  });

  it('logout revokes the refresh token and is idempotent', async () => {
    const reg = await registerUser(ctx.app);
    const out = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(out.statusCode).toBe(204);
    const again = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(again.statusCode).toBe(204);
    const refresh = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(refresh.statusCode).toBe(401);
  });

  it('social sign-in is explicit about not being configured', async () => {
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/apple', payload: { idToken: 'x'.repeat(20) } });
    expect(res.statusCode).toBe(501);
    expect(res.json().error.code).toBe('not_configured');
  });

  it('DELETE /me erases the account', async () => {
    const reg = await registerUser(ctx.app);
    const del = await ctx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: reg.headers });
    expect(del.statusCode).toBe(204);
    const me = await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: reg.headers });
    expect(me.statusCode).toBe(401);
  });
});

describe('generated-client compatibility', () => {
  it('accepts null for absent optional fields (the Dart client sends null, not omission)', async () => {
    const ctx2 = await makeApp();
    try {
      const reg = await ctx2.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: 'null@b.co', password: 'password123', displayName: null } });
      expect(reg.statusCode).toBe(201);
      const token = reg.json().tokens.accessToken as string;
      const dev = await ctx2.app.inject({
        method: 'POST',
        url: '/api/v1/devices',
        headers: { authorization: `Bearer ${token}` },
        payload: { installationId: 'install-null-1', platform: 'android', model: null },
      });
      expect(dev.statusCode).toBe(201);
      expect(dev.json().model).toBeNull();
    } finally {
      await ctx2.app.close();
    }
  });
});
