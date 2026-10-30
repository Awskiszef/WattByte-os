// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from 'vitest';

import { configurePasswordHashing, hashPassword, passwordHashingLoad, verifyPassword } from '../src/modules/auth/password.js';
import { type BuiltApp, buildTestApp } from './support.js';

afterEach(() => configurePasswordHashing({ concurrency: 2, maxQueue: 8 }));

describe('password hashing is bounded (A-04)', () => {
  it('runs `concurrency` hashes, queues `maxQueue`, and refuses the rest at once with 503 busy + Retry-After', async () => {
    configurePasswordHashing({ concurrency: 1, maxQueue: 1 });
    const started = [hashPassword('password-one'), hashPassword('password-two'), hashPassword('password-three'), hashPassword('password-four')];
    expect(passwordHashingLoad()).toEqual({ running: 1, waiting: 1 });
    const settled = await Promise.allSettled(started);
    expect(settled.map((s) => s.status)).toEqual(['fulfilled', 'fulfilled', 'rejected', 'rejected']);
    const refused = (settled[2] as PromiseRejectedResult).reason as { status: number; code: string; retryAfterSec: number };
    expect(refused).toMatchObject({ status: 503, code: 'busy', retryAfterSec: 2 });
    expect(passwordHashingLoad()).toEqual({ running: 0, waiting: 0 }); // every slot came back
  });

  it('a failing hash returns its slot too', async () => {
    configurePasswordHashing({ concurrency: 1, maxQueue: 0 });
    expect(await verifyPassword('x', 'not-a-hash')).toBe(false); // malformed: no slot used at all
    await expect(verifyPassword('x', 'scrypt$65536$8$1$AAAA$BBBB')).resolves.toBe(false); // runs, wrong key
    expect(passwordHashingLoad()).toEqual({ running: 0, waiting: 0 });
    await expect(hashPassword('password-after')).resolves.toMatch(/^scrypt\$/);
  });

  it('a burst of registrations is answered, not queued without bound: 201 for the ones served, 503 busy for the rest', async () => {
    const built: BuiltApp = await buildTestApp({ env: { SCRYPT_CONCURRENCY: '1', SCRYPT_MAX_QUEUE: '0' } });
    try {
      const responses = await Promise.all(
        Array.from({ length: 4 }, (_, i) =>
          built.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: `burst-${i}@test.wattbyte`, password: 'password123' } }),
        ),
      );
      const codes = responses.map((r) => r.statusCode).sort();
      expect(codes.filter((c) => c === 201)).toHaveLength(1);
      expect(codes.filter((c) => c === 503)).toHaveLength(3);
      const busy = responses.find((r) => r.statusCode === 503)!;
      expect(busy.json().error.code).toBe('busy');
      expect(busy.headers['retry-after']).toBe('2');
    } finally {
      await built.app.close();
    }
  });
});
