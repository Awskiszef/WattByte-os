// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomBytes, randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import type { App } from '../src/app.js';
import type { Repositories } from '../src/database/repositories.js';
import { TokenService } from '../src/modules/auth/tokens.js';

/**
 * The refresh-token reuse rule, stated once and checked against every implementation:
 *
 *   gap = (time the token is presented again) - (time it was rotated)
 *   gap <  grace, successor unused -> a client retry after a lost response: the SAME successor is returned (status
 *                                      `replayed`, 200 over HTTP), nothing is revoked
 *   gap >= grace, or successor used -> suspected theft: rejected AND the token's FAMILY (one device) is revoked, no
 *                                      other device of the user is touched
 *   revoked without a successor    -> 401, nothing else is touched
 *
 * With a grace of 10 s: 9.9 s is a retry, 10.0 s is theft (the boundary belongs to theft), 10.1 s is theft.
 */
export const GRACE_MS = 10_000;
export const ABSOLUTE_MS = 90 * 86_400_000;
export const GAPS = [
  { gapMs: 9_900, theft: false },
  { gapMs: 10_000, theft: true },
  { gapMs: 10_100, theft: true },
] as const;

export interface Harness {
  repos: Repositories;
  newUser(): Promise<string>;
  /** Makes the stored revocation time of a session exactly `at` (PostgreSQL stamps `revoked_at` from its own clock). */
  pinRevokedAt(refreshHash: string, at: Date): Promise<void>;
}

const hash = (token: string): string => TokenService.hashRefresh(token);
/**
 * The simulated rotation time is anchored to the real clock at load, not to a calendar date. The PostgreSQL suites share one
 * database with the retention test, whose global purge deletes sessions revoked more than SESSION_RETENTION_DAYS ago: a pinned
 * `revoked_at` in the past is purged (and the assertions fail or flake) once real time passes that window (H-11).
 * Everything below is relative to T0, so the boundary arithmetic is unchanged.
 */
const T0 = new Date();
const FAR = new Date(T0.getTime() + 365 * 86_400_000);
/** Unique per process: the PostgreSQL database outlives test runs and refresh hashes are unique. */
const RUN = randomUUID().slice(0, 12);
const token = (label: string, n: number): string => `${RUN}-${label}-${n}-`.padEnd(43, 'x');

/** Repository level: `rotate({ now })` is deterministic, so the boundary is exact to the millisecond. */
export function defineRotateBoundaryTests(makeHarness: () => Promise<Harness>): void {
  const rotate = (h: Harness, oldToken: string, newToken: string, now: Date, graceMs = GRACE_MS) =>
    h.repos.sessions.rotate({ oldHash: hash(oldToken), newHash: hash(newToken), newExpiresAt: FAR, now, graceMs, absoluteLifetimeMs: ABSOLUTE_MS });

  describe.each(GAPS)('rotate(): token presented again $gapMs ms after its rotation', ({ gapMs, theft }) => {
    it(
      theft ? 'is theft: rejected and ITS FAMILY is revoked, the same user\'s other device is not' : 'is a retry: the same successor again, nothing revoked',
      async () => {
        const h = await makeHarness();
        const userId = await h.newUser();
        const n = gapMs;
        const phone = await h.repos.sessions.create({ userId, refreshHash: hash(token('old', n)), expiresAt: FAR });
        const otherDevice = await h.repos.sessions.create({ userId, refreshHash: hash(token('other', n)), expiresAt: FAR });

        const rotated = await rotate(h, token('old', n), token('new', n), T0);
        expect(rotated).toEqual({ status: 'ok', userId, familyId: phone.familyId });
        await h.pinRevokedAt(hash(token('old', n)), T0);

        // The retry carries the same successor hash (the service derives it from the old token).
        const again = await rotate(h, token('old', n), token('new', n), new Date(T0.getTime() + gapMs));
        const successor = await h.repos.sessions.findByHash(hash(token('new', n)));
        const other = await h.repos.sessions.findByHash(hash(token('other', n)));
        expect(other?.id).toBe(otherDevice.id);
        expect(other?.revokedAt).toBeNull(); // another device is never touched

        if (theft) {
          expect(again).toEqual({ status: 'reused', userId, familyRevoked: true });
          expect(successor?.revokedAt).not.toBeNull(); // the family of the stolen token dies with it
        } else {
          expect(again).toEqual({ status: 'replayed', userId, familyId: phone.familyId });
          expect(successor?.revokedAt).toBeNull();
        }
        // Neither outcome mints a session: there is still exactly one live token in the phone's family.
        expect(await h.repos.sessions.familyLive(phone.familyId, T0)).toBe(!theft);
      },
    );
  });

  it('the boundary is strict to the millisecond: grace - 1 ms is a retry, grace is theft, grace + 1 ms is theft', async () => {
    const h = await makeHarness();
    const results: string[] = [];
    for (const delta of [-1, 0, 1]) {
      const userId = await h.newUser();
      const n = delta + 10;
      await h.repos.sessions.create({ userId, refreshHash: hash(token('old', n)), expiresAt: FAR });
      await rotate(h, token('old', n), token('new', n), T0);
      await h.pinRevokedAt(hash(token('old', n)), T0);
      results.push((await rotate(h, token('old', n), token('new', n), new Date(T0.getTime() + GRACE_MS + delta))).status);
    }
    expect(results).toEqual(['replayed', 'reused', 'reused']);
  });

  it('grace 0 disables the retry window: even the same instant is theft', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    await h.repos.sessions.create({ userId, refreshHash: hash(token('old', 0)), expiresAt: FAR });
    await rotate(h, token('old', 0), token('new', 0), T0, 0);
    await h.pinRevokedAt(hash(token('old', 0)), T0);
    expect(await rotate(h, token('old', 0), token('new', 0), T0, 0)).toEqual({ status: 'reused', userId, familyRevoked: true });
  });

  it('a retry can only ever receive the successor that was issued: a different successor hash is theft, not a second mint', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    await h.repos.sessions.create({ userId, refreshHash: hash(token('old', 1)), expiresAt: FAR });
    await rotate(h, token('old', 1), token('new', 1), T0);
    await h.pinRevokedAt(hash(token('old', 1)), T0);
    const attack = await rotate(h, token('old', 1), token('attacker', 1), new Date(T0.getTime() + 1));
    expect(attack.status).toBe('reused');
    expect(await h.repos.sessions.findByHash(hash(token('attacker', 1)))).toBeNull();
  });

  it('once the successor has been used, the old token is theft even inside the grace window', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    await h.repos.sessions.create({ userId, refreshHash: hash(token('a', 2)), expiresAt: FAR });
    await rotate(h, token('a', 2), token('b', 2), T0);
    await h.pinRevokedAt(hash(token('a', 2)), T0);
    expect((await rotate(h, token('b', 2), token('c', 2), new Date(T0.getTime() + 1_000))).status).toBe('ok'); // the device moved on
    await h.pinRevokedAt(hash(token('b', 2)), new Date(T0.getTime() + 1_000));
    expect((await rotate(h, token('a', 2), token('b', 2), new Date(T0.getTime() + 2_000))).status).toBe('reused');
    expect((await h.repos.sessions.findByHash(hash(token('c', 2))))?.revokedAt).not.toBeNull();
  });

  it('a session revoked by logout (no successor) is "revoked": 401, however recent, and nothing else is touched', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    const s = await h.repos.sessions.create({ userId, refreshHash: hash(token('old', 77)), expiresAt: FAR });
    await h.repos.sessions.create({ userId, refreshHash: hash(token('keep', 77)), expiresAt: FAR });
    await h.repos.sessions.revoke(s.id);
    await h.pinRevokedAt(hash(token('old', 77)), T0);
    expect(await rotate(h, token('old', 77), token('x', 77), new Date(T0.getTime() + 1))).toEqual({ status: 'revoked' });
    expect((await h.repos.sessions.findByHash(hash(token('keep', 77))))?.revokedAt).toBeNull();
  });

  it('concurrent presentations of one token: exactly one rotates, the rest are retries with the same successor', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    await h.repos.sessions.create({ userId, refreshHash: hash(token('race', 3)), expiresAt: FAR });
    const results = await Promise.all(Array.from({ length: 8 }, () => rotate(h, token('race', 3), token('next', 3), T0)));
    expect(results.filter((r) => r.status === 'ok')).toHaveLength(1);
    expect(results.filter((r) => r.status === 'replayed')).toHaveLength(7);
  });

  describe('families', () => {
    it('revokeFamily ends one device (rotated chain included) and leaves the user\'s other devices alone; familyLive follows', async () => {
      const h = await makeHarness();
      const userId = await h.newUser();
      const a = await h.repos.sessions.create({ userId, refreshHash: hash(token('fa', 4)), expiresAt: FAR });
      const b = await h.repos.sessions.create({ userId, refreshHash: hash(token('fb', 4)), expiresAt: FAR });
      await rotate(h, token('fa', 4), token('fa2', 4), T0);
      await rotate(h, token('fa2', 4), token('fa3', 4), new Date(T0.getTime() + 5_000));
      expect(await h.repos.sessions.familyLive(a.familyId, T0)).toBe(true);
      await h.repos.sessions.revokeFamily(a.familyId);
      await h.repos.sessions.revokeFamily(a.familyId); // idempotent
      expect(await h.repos.sessions.familyLive(a.familyId, T0)).toBe(false);
      expect((await h.repos.sessions.findByHash(hash(token('fa3', 4))))?.revokedAt).not.toBeNull();
      expect(await h.repos.sessions.familyLive(b.familyId, T0)).toBe(true);
    });

    it('listFamilies shows one entry per live device with its sign-in time; expired and revoked ones are gone', async () => {
      const h = await makeHarness();
      const userId = await h.newUser();
      const live = await h.repos.sessions.create({ userId, refreshHash: hash(token('l1', 5)), expiresAt: FAR });
      await h.repos.sessions.create({ userId, refreshHash: hash(token('l2', 5)), expiresAt: new Date(T0.getTime() - 1_000) });
      const gone = await h.repos.sessions.create({ userId, refreshHash: hash(token('l3', 5)), expiresAt: FAR });
      await h.repos.sessions.revokeFamily(gone.familyId);
      const list = await h.repos.sessions.listFamilies(userId, T0);
      expect(list.map((f) => f.id)).toEqual([live.familyId]);
      expect(list[0]!.expiresAt.getTime()).toBe(FAR.getTime());
    });

    it('a family cannot be extended beyond its absolute lifetime by rotating', async () => {
      const h = await makeHarness();
      const userId = await h.newUser();
      const started = new Date(T0.getTime() - ABSOLUTE_MS + 10_000);
      await h.repos.sessions.create({ userId, refreshHash: hash(token('abs', 6)), expiresAt: FAR, familyStartedAt: started });
      const ok = await rotate(h, token('abs', 6), token('abs2', 6), new Date(started.getTime() + ABSOLUTE_MS - 1));
      expect(ok.status).toBe('ok');
      // the successor inherits the family's start: at the lifetime it is over
      expect((await rotate(h, token('abs2', 6), token('abs3', 6), new Date(started.getTime() + ABSOLUTE_MS))).status).toBe('expired');
    });
  });
}

export interface HttpHarness extends Harness {
  app: App;
  setClock(at: Date): void;
}

/** HTTP level: the same rule through POST /auth/refresh with an injected clock (grace 10 s in these tests). */
export function defineRefreshEndpointBoundaryTests(makeHarness: () => Promise<HttpHarness>): void {
  const refresh = (h: HttpHarness, refreshToken: string) => h.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken } });

  describe.each(GAPS)('POST /auth/refresh: token presented again $gapMs ms after its rotation', ({ gapMs, theft }) => {
    it(theft ? 'answers refresh_token_reused and revokes that device only' : 'answers 200 with the SAME refresh token (a lost response is recoverable)', async () => {
      const h = await makeHarness();
      h.setClock(T0);
      // Two devices of one account, created directly: no scrypt, the endpoint under test is /auth/refresh.
      const userId = await h.newUser();
      const original = randomBytes(32).toString('base64url');
      const otherDevice = randomBytes(32).toString('base64url');
      await h.repos.sessions.create({ userId, refreshHash: hash(original), expiresAt: FAR });
      await h.repos.sessions.create({ userId, refreshHash: hash(otherDevice), expiresAt: FAR });

      const rotation = await refresh(h, original);
      expect(rotation.statusCode).toBe(200);
      const successor = rotation.json().tokens.refreshToken as string;
      await h.pinRevokedAt(hash(original), T0);

      h.setClock(new Date(T0.getTime() + gapMs));
      const again = await refresh(h, original);
      const other = await refresh(h, otherDevice);
      expect(other.statusCode).toBe(200); // the other device is never affected

      if (theft) {
        expect(again.statusCode).toBe(401);
        expect(again.json().error.code).toBe('refresh_token_reused');
        expect(again.json().error.message).toMatch(/session was revoked/);
        expect((await refresh(h, successor)).statusCode).toBe(401); // the phone's family is gone
      } else {
        expect(again.statusCode).toBe(200);
        expect(again.json().tokens.refreshToken).toBe(successor); // the same successor, not a new one
        expect((await refresh(h, successor)).statusCode).toBe(200); // and the device continues with it
      }
    });
  });
}
