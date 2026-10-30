// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { hashPassword } from '../../src/modules/auth/password.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, uniqueEmail } from './helpers.js';

const median = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]!;

describe.skipIf(!DATABASE_URL)('login timing (PostgreSQL)', () => {
  let ctx: PgContext;
  let emails: string[];
  beforeAll(async () => {
    ctx = await makePgApp();
    // Known accounts, one per attempt: repeated failures on ONE e-mail trip the per-account lock (A-02), which is
    // exactly what this timing comparison must not measure. Created directly: one hash, no per-account scrypt.
    const passwordHash = await hashPassword('password123');
    emails = [];
    for (let i = 0; i < 9; i++) {
      const email = uniqueEmail(`timing${i}`);
      await ctx.repos.users.create({ email, passwordHash });
      emails.push(email);
    }
  });
  afterAll(() => closePgApp(ctx));

  const attempt = async (address: string) => {
    const start = performance.now();
    const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: address, password: 'wrong-password' } });
    return { ms: performance.now() - start, res };
  };

  it('unknown and known accounts cost the same order of time and answer identically', async () => {
    await attempt(emails[0]!); // warm-up: JIT, first scrypt, dummy hash
    await attempt(uniqueEmail('nobody-warmup'));
    const known: number[] = [];
    const unknown: number[] = [];
    for (let i = 0; i < 7; i++) {
      const k = await attempt(emails[i + 1]!);
      // Unique per run: the throttle rows of the test database outlive runs, and a fixed address would end up locked.
      const u = await attempt(uniqueEmail(`nobody-${i}`));
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
