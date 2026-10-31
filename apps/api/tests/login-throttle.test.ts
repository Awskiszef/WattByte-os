// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomUUID } from 'node:crypto';

import { afterEach, describe, expect, it } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { BASE_LOCK_SEC, LOCK_AFTER, lockSeconds, loginThrottleKey, MAX_LOCK_SEC } from '../src/modules/auth/login-throttle.js';
import { hashPassword } from '../src/modules/auth/password.js';
import { defineLoginThrottleRepositoryTests } from './login-throttle-suite.js';
import { type BuiltApp, buildTestApp } from './support.js';

defineLoginThrottleRepositoryTests('memory', async () => ({ repo: new MemoryRepositories().loginThrottle, key: () => randomUUID() }));

describe('policy', () => {
  it('lock durations: none below the threshold, 15 s, 30 s, 60 s ... capped at 15 min', () => {
    expect([1, 2, 3, 4].map(lockSeconds)).toEqual([0, 0, 0, 0]);
    expect([5, 6, 7, 8].map(lockSeconds)).toEqual([BASE_LOCK_SEC, 2 * BASE_LOCK_SEC, 4 * BASE_LOCK_SEC, 8 * BASE_LOCK_SEC]);
    expect(lockSeconds(50)).toBe(MAX_LOCK_SEC);
    expect(LOCK_AFTER).toBe(5);
  });

  it('the key is a hash of the normalised e-mail: case and padding do not matter, the address is not in it', () => {
    expect(loginThrottleKey('  Victim@Example.COM ')).toBe(loginThrottleKey('victim@example.com'));
    expect(loginThrottleKey('victim@example.com')).toMatch(/^[0-9a-f]{64}$/);
    expect(loginThrottleKey('victim@example.com')).not.toContain('victim');
  });
});

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});

describe('POST /auth/login per-account throttle (A-02)', () => {
  const PASSWORD = 'correct-horse-battery';
  async function make() {
    let clock = new Date('2026-10-29T12:00:00.000Z');
    const built = await buildTestApp({ now: () => clock });
    apps.push(built);
    await built.memory.users.create({ email: 'victim@b.co', passwordHash: await hashPassword(PASSWORD) });
    let n = 0;
    // A new source address for every attempt: the throttle must not depend on the IP.
    const login = (email: string, password: string) =>
      built.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email, password }, remoteAddress: `198.51.100.${(n++ % 250) + 1}` });
    return { ...built, login, advance: (sec: number) => void (clock = new Date(clock.getTime() + sec * 1000)) };
  }

  it('locks after 5 wrong passwords whatever the source address; the right password is refused during the lock', async () => {
    const t = await make();
    for (let i = 0; i < LOCK_AFTER; i++) expect((await t.login('victim@b.co', `wrong-${i}-password`)).statusCode).toBe(401);
    const locked = await t.login('victim@b.co', PASSWORD);
    expect(locked.statusCode).toBe(429);
    expect(locked.json().error.code).toBe('rate_limited');
    expect(Number(locked.headers['retry-after'])).toBe(BASE_LOCK_SEC);
  });

  it('is no existence oracle: an unknown e-mail is locked exactly like a known one', async () => {
    const t = await make();
    for (let i = 0; i < LOCK_AFTER; i++) expect((await t.login('nobody@b.co', `wrong-${i}-password`)).statusCode).toBe(401);
    const locked = await t.login('nobody@b.co', 'whatever-password');
    expect(locked.statusCode).toBe(429);
    expect(locked.json().error.message).toBe((await (async () => {
      for (let i = 0; i < LOCK_AFTER; i++) await t.login('victim@b.co', `wrong-${i}-password`);
      return t.login('victim@b.co', 'x'.repeat(10));
    })()).json().error.message);
  });

  it('attempts refused during the lock are not counted; after it expires one failure doubles the lock', async () => {
    const t = await make();
    for (let i = 0; i < LOCK_AFTER; i++) await t.login('victim@b.co', `wrong-${i}-password`);
    for (let i = 0; i < 20; i++) expect((await t.login('victim@b.co', 'hammering-password')).statusCode).toBe(429);
    t.advance(BASE_LOCK_SEC + 1);
    expect((await t.login('victim@b.co', 'wrong-again-password')).statusCode).toBe(401);
    const locked = await t.login('victim@b.co', PASSWORD);
    expect(locked.statusCode).toBe(429);
    expect(Number(locked.headers['retry-after'])).toBe(2 * BASE_LOCK_SEC);
  });

  it('a correct password clears the failures; the e-mail is normalised (case)', async () => {
    const t = await make();
    for (let i = 0; i < LOCK_AFTER - 1; i++) await t.login('Victim@B.co', `wrong-${i}-password`);
    expect((await t.login('victim@b.co', PASSWORD)).statusCode).toBe(200);
    // four failures were forgotten: four more do not lock
    for (let i = 0; i < LOCK_AFTER - 1; i++) expect((await t.login('victim@b.co', `wrong-${i}-password`)).statusCode).toBe(401);
    expect((await t.login('victim@b.co', PASSWORD)).statusCode).toBe(200);
  });

  it('another account is not affected by the lock', async () => {
    const t = await make();
    await t.memory.users.create({ email: 'other@b.co', passwordHash: await hashPassword(PASSWORD) });
    for (let i = 0; i < LOCK_AFTER; i++) await t.login('victim@b.co', `wrong-${i}-password`);
    expect((await t.login('other@b.co', PASSWORD)).statusCode).toBe(200);
  });
});
