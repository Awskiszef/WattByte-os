import { randomUUID } from 'node:crypto';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { LOCK_AFTER } from '../../src/modules/auth/login-throttle.js';
import { defineLoginThrottleRepositoryTests } from '../login-throttle-suite.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext } from './helpers.js';

describe.skipIf(!DATABASE_URL)('login throttle (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp();
  });
  afterAll(() => closePgApp(ctx));

  defineLoginThrottleRepositoryTests('PostgreSQL', async () => ({ repo: ctx.repos.loginThrottle, key: () => `test-${randomUUID()}` }));

  it('concurrent failures from many instances all count (one atomic statement, no lost update)', async () => {
    const key = `test-${randomUUID()}`;
    const now = new Date();
    const results = await Promise.all(Array.from({ length: 25 }, () => ctx.repos.loginThrottle.recordFailure(key, now)));
    expect(results.map((r) => r.failures).sort((a, b) => a - b)).toEqual(Array.from({ length: 25 }, (_, i) => i + 1));
    expect((await ctx.repos.loginThrottle.status(key, now)).lockedUntil).not.toBeNull();
    await ctx.repos.loginThrottle.clear(key);
  });

  it('end to end: five wrong passwords lock the account in the database, with the same answer as the in-memory run', async () => {
    const { register } = await import('./helpers.js');
    const email = `throttle-${randomUUID()}@test.wattbyte`;
    await register(ctx.app, email);
    for (let i = 0; i < LOCK_AFTER; i++) {
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password: `wrong-password-${i}` } });
      expect(res.statusCode).toBe(401);
    }
    const locked = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password: 'password123' } });
    expect(locked.statusCode).toBe(429);
    expect(locked.json().error.code).toBe('rate_limited');
    await ctx.repos.loginThrottle.clear((await import('../../src/modules/auth/login-throttle.js')).loginThrottleKey(email));
  });
});
