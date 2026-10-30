// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

describe.skipIf(!DATABASE_URL)('refresh token rotation (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ REFRESH_REUSE_GRACE_SEC: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const refresh = (token: string) => ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: token } });

  it('10 concurrent refreshes with one token: one rotation, nine retries with the same successor, one live session', async () => {
    const reg = await register(ctx.app, uniqueEmail('race'));
    const results = await Promise.all(Array.from({ length: 10 }, () => refresh(reg.tokens.refreshToken)));
    expect(results.map((r) => r.statusCode)).toEqual(Array(10).fill(200));
    expect(new Set(results.map((r) => r.json().tokens.refreshToken as string)).size).toBe(1);

    const live = await ctx.pool.query('SELECT count(*)::int AS n FROM sessions WHERE user_id = $1 AND revoked_at IS NULL', [reg.user.id]);
    expect(live.rows[0].n).toBe(1);
    const families = await ctx.pool.query('SELECT count(DISTINCT family_id)::int AS n FROM sessions WHERE user_id = $1', [reg.user.id]);
    expect(families.rows[0].n).toBe(1); // the rotation stayed inside the sign-in's family

    // The winner's new token still works: a concurrent retry did not cost the user the session.
    const next = results[0]!.json().tokens.refreshToken as string;
    expect((await refresh(next)).statusCode).toBe(200);
  });

  it('presenting an old rotated token after the grace window revokes that device\'s family', async () => {
    const strict = await makePgApp({ REFRESH_REUSE_GRACE_SEC: '0' });
    try {
      const reg = await register(strict.app, uniqueEmail('theft'));
      const rot = await strict.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: reg.tokens.refreshToken } });
      const stolen = reg.tokens.refreshToken;
      const next = rot.json().tokens.refreshToken as string;
      const reuse = await strict.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: stolen } });
      expect(reuse.statusCode).toBe(401);
      expect(reuse.json().error.message).toMatch(/revoked/);
      const afterTheft = await strict.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: next } });
      expect(afterTheft.statusCode).toBe(401);
    } finally {
      await closePgApp(strict);
    }
  });

  it('logout with a stale token ends the whole device, a second device stays; the session list and sign-out of one device work (A-06, A-07)', async () => {
    const email = uniqueEmail('stale-logout');
    const reg = await register(ctx.app, email);
    const rotated = await refresh(reg.tokens.refreshToken);
    const current = rotated.json().tokens as { accessToken: string; refreshToken: string };
    const second = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password: 'password123' } });
    const tablet = second.json().tokens as { accessToken: string; refreshToken: string };

    const list = await ctx.app.inject({ method: 'GET', url: '/api/v1/me/sessions', headers: { authorization: `Bearer ${current.accessToken}` } });
    expect(list.statusCode).toBe(200);
    expect(list.json().sessions).toHaveLength(2);
    expect((list.json().sessions as { current: boolean }[]).filter((x) => x.current)).toHaveLength(1);

    // the phone signs out with the token it was given at sign-in (stale since the first rotation)
    const out = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: reg.tokens.refreshToken } });
    expect(out.statusCode).toBe(204);
    expect((await refresh(current.refreshToken)).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: `Bearer ${current.accessToken}` } })).statusCode).toBe(401);
    expect((await refresh(tablet.refreshToken)).statusCode).toBe(200);

    const remaining = await ctx.app.inject({ method: 'GET', url: '/api/v1/me/sessions', headers: { authorization: `Bearer ${tablet.accessToken}` } });
    expect(remaining.json().sessions).toHaveLength(1);
    const id = remaining.json().sessions[0].id as string;
    expect((await ctx.app.inject({ method: 'DELETE', url: `/api/v1/me/sessions/${id}`, headers: { authorization: `Bearer ${tablet.accessToken}` } })).statusCode).toBe(204);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: `Bearer ${tablet.accessToken}` } })).statusCode).toBe(401);
  });

  it('sign out everywhere and a password change against the real schema (tokens_valid_after)', async () => {
    const email = uniqueEmail('out-all');
    const reg = await register(ctx.app, email);
    await new Promise((r) => setTimeout(r, 1_100)); // the cut-off has second resolution
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/me/password', headers: { authorization: `Bearer ${reg.tokens.accessToken}` }, payload: { currentPassword: 'password123', newPassword: 'a-brand-new-password' } });
    expect(res.statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: `Bearer ${reg.tokens.accessToken}` } })).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me', headers: { authorization: `Bearer ${res.json().tokens.accessToken}` } })).statusCode).toBe(200);
    expect((await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password: 'a-brand-new-password' } })).statusCode).toBe(200);
  });

  it('unknown and expired tokens are rejected', async () => {
    expect((await refresh('x'.repeat(43))).statusCode).toBe(401);
    const reg = await register(ctx.app, uniqueEmail('exp'));
    await ctx.pool.query("UPDATE sessions SET expires_at = now() - interval '1 minute' WHERE user_id = $1", [reg.user.id]);
    const res = await refresh(reg.tokens.refreshToken);
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('refresh_token_expired');
  });
});
