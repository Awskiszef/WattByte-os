import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

describe.skipIf(!DATABASE_URL)('refresh token rotation (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp({ REFRESH_REUSE_GRACE_SEC: '10' });
  });
  afterAll(() => closePgApp(ctx));

  const refresh = (token: string) => ctx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: token } });

  it('10 concurrent refreshes with one token: exactly 1 success, 9 rejected, 1 live session', async () => {
    const reg = await register(ctx.app, uniqueEmail('race'));
    const results = await Promise.all(Array.from({ length: 10 }, () => refresh(reg.tokens.refreshToken)));
    const ok = results.filter((r) => r.statusCode === 200);
    const rejected = results.filter((r) => r.statusCode === 401);
    expect(ok).toHaveLength(1);
    expect(rejected).toHaveLength(9);
    expect(rejected.every((r) => r.json().error.code === 'refresh_token_reused')).toBe(true);

    const live = await ctx.pool.query('SELECT count(*)::int AS n FROM sessions WHERE user_id = $1 AND revoked_at IS NULL', [reg.user.id]);
    expect(live.rows[0].n).toBe(1);

    // The winner's new token still works: a concurrent retry did not cost the user the session.
    const next = ok[0]!.json().tokens.refreshToken as string;
    expect((await refresh(next)).statusCode).toBe(200);
  });

  it('presenting an old rotated token after the grace window revokes every session', async () => {
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

  it('unknown and expired tokens are rejected', async () => {
    expect((await refresh('x'.repeat(43))).statusCode).toBe(401);
    const reg = await register(ctx.app, uniqueEmail('exp'));
    await ctx.pool.query("UPDATE sessions SET expires_at = now() - interval '1 minute' WHERE user_id = $1", [reg.user.id]);
    const res = await refresh(reg.tokens.refreshToken);
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('refresh_token_expired');
  });
});
