import { describe, expect, it } from 'vitest';

import type { LoginThrottleRepository } from '../src/database/repositories.js';
import { FAILURE_WINDOW_SEC, LOCK_AFTER, lockSeconds, MAX_LOCK_SEC } from '../src/modules/auth/login-throttle.js';

const at = (base: Date, sec: number): Date => new Date(base.getTime() + sec * 1000);

/** The per-account throttle semantics every implementation must share (memory and PostgreSQL). */
export function defineLoginThrottleRepositoryTests(name: string, make: () => Promise<{ repo: LoginThrottleRepository; key: () => string }>): void {
  describe(`login throttle repository (${name})`, () => {
    const t0 = new Date('2026-10-29T12:00:00.000Z');

    it('counts failures; the lock starts at the LOCK_AFTER-th and doubles with each further failure', async () => {
      const { repo, key } = await make();
      const k = key();
      expect(await repo.status(k, t0)).toEqual({ lockedUntil: null });
      for (let i = 1; i < LOCK_AFTER; i++) expect(await repo.recordFailure(k, t0)).toEqual({ failures: i, lockedUntil: null });
      const fifth = await repo.recordFailure(k, t0);
      expect(fifth.failures).toBe(LOCK_AFTER);
      expect(fifth.lockedUntil).toEqual(at(t0, lockSeconds(LOCK_AFTER)));
      const sixth = await repo.recordFailure(k, t0);
      expect(sixth.lockedUntil).toEqual(at(t0, lockSeconds(LOCK_AFTER + 1)));
      expect(lockSeconds(LOCK_AFTER + 1)).toBe(2 * lockSeconds(LOCK_AFTER));
      expect((await repo.status(k, at(t0, 1))).lockedUntil).toEqual(sixth.lockedUntil);
    });

    it('the lock expires by itself and is capped', async () => {
      const { repo, key } = await make();
      const k = key();
      let last = await repo.recordFailure(k, t0);
      for (let i = 1; i < LOCK_AFTER + 20; i++) last = await repo.recordFailure(k, t0);
      expect(last.lockedUntil).toEqual(at(t0, MAX_LOCK_SEC));
      expect((await repo.status(k, at(t0, MAX_LOCK_SEC - 1))).lockedUntil).not.toBeNull();
      expect(await repo.status(k, at(t0, MAX_LOCK_SEC))).toEqual({ lockedUntil: null });
    });

    it('a success (clear) forgets everything; keys are independent', async () => {
      const { repo, key } = await make();
      const a = key();
      const b = key();
      for (let i = 0; i < LOCK_AFTER; i++) await repo.recordFailure(a, t0);
      await repo.recordFailure(b, t0);
      expect((await repo.status(a, t0)).lockedUntil).not.toBeNull();
      expect(await repo.status(b, t0)).toEqual({ lockedUntil: null });
      await repo.clear(a);
      expect(await repo.status(a, t0)).toEqual({ lockedUntil: null });
      expect((await repo.recordFailure(a, t0)).failures).toBe(1);
    });

    it('failures older than the window do not count', async () => {
      const { repo, key } = await make();
      const k = key();
      for (let i = 0; i < LOCK_AFTER - 1; i++) await repo.recordFailure(k, t0);
      const later = at(t0, FAILURE_WINDOW_SEC + 1);
      expect(await repo.recordFailure(k, later)).toEqual({ failures: 1, lockedUntil: null });
    });

    it('purge removes rows untouched since the cutoff, and only those', async () => {
      const { repo, key } = await make();
      const old = key();
      const fresh = key();
      await repo.recordFailure(old, at(t0, -7200));
      await repo.recordFailure(fresh, t0);
      expect(await repo.purge(at(t0, -3600))).toBeGreaterThanOrEqual(1);
      expect((await repo.recordFailure(old, t0)).failures).toBe(1);
      expect((await repo.recordFailure(fresh, t0)).failures).toBe(2);
    });
  });
}
