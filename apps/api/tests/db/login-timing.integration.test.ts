import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]!;

describe.skipIf(!DATABASE_URL)('login timing (PostgreSQL)', () => {
  let ctx: PgContext;
  let email: string;
  beforeAll(async () => {
    ctx = await makePgApp();
    email = uniqueEmail('timing');
    await register(ctx.app, email);
  });
  afterAll(() => closePgApp(ctx));

  const attempt = async (address: string) => {
    const start = performance.now();
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: address, password: 'wrong-password' } });
    return { ms: performance.now() - start, res };
  };

  it('unknown and known accounts cost the same order of time and answer identically', async () => {
    await attempt(email); // warm-up: JIT, first scrypt, dummy hash
    await attempt('nobody@test.wattbyte');
    const known: number[] = [];
    const unknown: number[] = [];
    for (let i = 0; i < 7; i++) {
      const k = await attempt(email);
      const u = await attempt(`nobody-${i}@test.wattbyte`);
      known.push(k.ms);
      unknown.push(u.ms);
      for (const r of [k.res, u.res]) {
        expect(r.statusCode).toBe(401);
        expect(r.json()).toEqual({ error: { code: 'invalid_credentials', message: 'Wrong email or password' } });
      }
    }
    // Before the fix: unknown ~1 ms vs known ~115 ms. Now both run one scrypt verification.
    const ratio = median(unknown) / median(known);
    expect(ratio).toBeGreaterThan(0.5);
    expect(ratio).toBeLessThan(2);
    // 16 sequential scrypt verifications: about 2 s alone, more than the 5 s default when other suites hash in parallel.
  }, 30_000);
});
