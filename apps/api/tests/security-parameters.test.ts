import { decodeJwt } from 'jose';
import { describe, expect, it } from 'vitest';

import { loadEnv } from '../src/config/env.js';
import { hashPassword, verifyPassword } from '../src/modules/auth/password.js';
import { TokenService } from '../src/modules/auth/tokens.js';

/**
 * A-09: security-relevant parameters, pinned. A change to any of these numbers must be a conscious one: it shows up
 * here and in docs/security.md, not only in a diff of a default.
 */
const dev = { NODE_ENV: 'development', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd' };

describe('defaults that protect the API', () => {
  it('token lifetimes, reuse window, limits and proxy trust', () => {
    const env = loadEnv(dev);
    expect({
      ACCESS_TOKEN_TTL_SEC: env.ACCESS_TOKEN_TTL_SEC,
      REFRESH_TOKEN_TTL_DAYS: env.REFRESH_TOKEN_TTL_DAYS,
      REFRESH_REUSE_GRACE_SEC: env.REFRESH_REUSE_GRACE_SEC,
      SESSION_ABSOLUTE_LIFETIME_DAYS: env.SESSION_ABSOLUTE_LIFETIME_DAYS,
      TRUST_PROXY_HOPS: env.TRUST_PROXY_HOPS,
      TRUST_PROXY_CIDRS: env.TRUST_PROXY_CIDRS,
      RATE_LIMIT_PER_MIN: env.RATE_LIMIT_PER_MIN,
      AUTH_RATE_LIMIT_PER_MIN: env.AUTH_RATE_LIMIT_PER_MIN,
      REFRESH_RATE_LIMIT_PER_MIN: env.REFRESH_RATE_LIMIT_PER_MIN,
      AI_RATE_LIMIT_PER_MIN: env.AI_RATE_LIMIT_PER_MIN,
      SCRYPT_CONCURRENCY: env.SCRYPT_CONCURRENCY,
      SCRYPT_MAX_QUEUE: env.SCRYPT_MAX_QUEUE,
      DATABASE_SSL: env.DATABASE_SSL,
    }).toEqual({
      ACCESS_TOKEN_TTL_SEC: 900,
      REFRESH_TOKEN_TTL_DAYS: 30,
      REFRESH_REUSE_GRACE_SEC: 60,
      SESSION_ABSOLUTE_LIFETIME_DAYS: 90,
      TRUST_PROXY_HOPS: 0,
      TRUST_PROXY_CIDRS: undefined,
      RATE_LIMIT_PER_MIN: 120,
      AUTH_RATE_LIMIT_PER_MIN: 10,
      REFRESH_RATE_LIMIT_PER_MIN: 60,
      AI_RATE_LIMIT_PER_MIN: 20,
      SCRYPT_CONCURRENCY: 2,
      SCRYPT_MAX_QUEUE: 8,
      DATABASE_SSL: '0',
    });
  });

  it('JWT_SECRET must have 32 characters: 31 is refused, 32 is accepted', () => {
    expect(() => loadEnv({ ...dev, JWT_SECRET: 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p' })).toThrow(/at least 32 characters/);
    expect(loadEnv({ ...dev, JWT_SECRET: 'a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6' }).JWT_SECRET).toHaveLength(32);
  });

  it('the overrides reach the services that use them', () => {
    const env = loadEnv({ ...dev, ACCESS_TOKEN_TTL_SEC: '1200', REFRESH_TOKEN_TTL_DAYS: '7', REFRESH_REUSE_GRACE_SEC: '0' });
    expect([env.ACCESS_TOKEN_TTL_SEC, env.REFRESH_TOKEN_TTL_DAYS, env.REFRESH_REUSE_GRACE_SEC]).toEqual([1200, 7, 0]);
  });
});

describe('tokens', () => {
  const now = new Date('2026-10-29T12:00:00.000Z');
  const user = { userId: '8d0e3b0e-6a5d-4a7e-9b8e-1f3b6f1c2d3e', plan: 'free' as const };

  it.each([900, 1200])('an access token lives exactly ACCESS_TOKEN_TTL_SEC (%i s)', async (ttl) => {
    const service = new TokenService(dev.JWT_SECRET, ttl, 30);
    const claims = decodeJwt(await service.signAccess(user, now));
    expect(claims.exp! - claims.iat!).toBe(ttl);
    expect(claims.iat).toBe(now.getTime() / 1000);
    expect(claims).toMatchObject({ iss: 'wattbyte', aud: 'wattbyte-mobile', sub: user.userId, plan: 'free' });
    expect(service.accessTtl).toBe(ttl);
  });

  it('a refresh session expires exactly REFRESH_TOKEN_TTL_DAYS after it starts', () => {
    expect(new TokenService(dev.JWT_SECRET, 900, 30).refreshExpiry(now)).toEqual(new Date('2026-11-28T12:00:00.000Z'));
    expect(new TokenService(dev.JWT_SECRET, 900, 7).refreshExpiry(now)).toEqual(new Date('2026-11-05T12:00:00.000Z'));
  });

  it('an access token is not accepted after its expiry, or with another secret', async () => {
    const service = new TokenService(dev.JWT_SECRET, 900, 30);
    const issued = await service.signAccess(user, new Date(Date.now() - 901_000));
    expect(await service.verifyAccess(issued)).toBeNull();
    const fresh = await service.signAccess(user);
    expect(await service.verifyAccess(fresh)).toMatchObject(user);
    expect(await new TokenService('another-secret-another-secret-another!', 900, 30).verifyAccess(fresh)).toBeNull();
  });
});

describe('passwords', () => {
  it('are normalised (NFKC) before hashing: a composed and a decomposed form, and a ligature, are the same password', async () => {
    const stored = await hashPassword('Café-fish-1'); // é as one code point
    expect(await verifyPassword('Café-fish-1', stored)).toBe(true); // e + combining acute
    expect(await verifyPassword('Café-ﬁsh-1', stored)).toBe(true); // ﬁ ligature -> fi
    expect(await verifyPassword('Café-fish-2', stored)).toBe(false);
  });

  it('use scrypt N=2^16, r=8, p=1 with a random salt per hash, and refuse hostile stored parameters', async () => {
    const a = await hashPassword('same-password-1');
    const b = await hashPassword('same-password-1');
    expect(a.split('$').slice(0, 4)).toEqual(['scrypt', '65536', '8', '1']);
    expect(a).not.toBe(b);
    expect(await verifyPassword('same-password-1', 'scrypt$1048577$8$1$AAAA$BBBB')).toBe(false); // N above 2^20
    expect(await verifyPassword('same-password-1', 'scrypt$65536$33$1$AAAA$BBBB')).toBe(false); // r above 32
  });
});
