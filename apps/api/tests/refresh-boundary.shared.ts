import { randomBytes, randomUUID } from 'node:crypto';

import { describe, expect, it } from 'vitest';

import type { App } from '../src/app.js';
import type { Repositories } from '../src/database/repositories.js';
import { TokenService } from '../src/modules/auth/tokens.js';

/**
 * The refresh-token reuse rule, stated once and checked against every implementation:
 *
 *   gap = (time the token is presented again) - (time it was rotated)
 *   gap <  grace  -> a client retry: rejected (401 refresh_token_reused), no other session is touched
 *   gap >= grace  -> suspected theft: rejected AND every session of the user is revoked
 *
 * With the default grace of 10 s: 9.9 s is a retry, 10.0 s is theft (the boundary belongs to theft), 10.1 s is theft.
 */
export const GRACE_MS = 10_000;
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
const T0 = new Date('2026-10-13T12:00:00.000Z');
const FAR = new Date('2027-10-13T12:00:00.000Z');
/** Unique per process: the PostgreSQL database outlives test runs and refresh hashes are unique. */
const RUN = randomUUID().slice(0, 12);
const token = (label: string, n: number): string => `${RUN}-${label}-${n}-`.padEnd(43, 'x');

/** Repository level: `rotate({ now })` is deterministic, so the boundary is exact to the millisecond. */
export function defineRotateBoundaryTests(makeHarness: () => Promise<Harness>): void {
  describe.each(GAPS)('rotate(): token presented again $gapMs ms after its rotation', ({ gapMs, theft }) => {
    it(theft ? 'is theft: rejected and every session of the user is revoked' : 'is a retry: rejected, other sessions untouched', async () => {
      const h = await makeHarness();
      const userId = await h.newUser();
      const n = gapMs;
      const otherDevice = await h.repos.sessions.create({ userId, refreshHash: hash(token('other', n)), expiresAt: FAR });
      await h.repos.sessions.create({ userId, refreshHash: hash(token('old', n)), expiresAt: FAR });

      const rotated = await h.repos.sessions.rotate({
        oldHash: hash(token('old', n)),
        newHash: hash(token('new', n)),
        newExpiresAt: FAR,
        now: T0,
        graceMs: GRACE_MS,
      });
      expect(rotated).toEqual({ status: 'ok', userId });
      await h.pinRevokedAt(hash(token('old', n)), T0);

      const again = await h.repos.sessions.rotate({
        oldHash: hash(token('old', n)),
        newHash: hash(token('attacker', n)),
        newExpiresAt: FAR,
        now: new Date(T0.getTime() + gapMs),
        graceMs: GRACE_MS,
      });
      expect(again).toEqual({ status: 'reused', userId, familyRevoked: theft });

      const successor = await h.repos.sessions.findByHash(hash(token('new', n)));
      const other = await h.repos.sessions.findByHash(hash(token('other', n)));
      expect(other?.id).toBe(otherDevice.id);
      if (theft) {
        expect(successor?.revokedAt).not.toBeNull();
        expect(other?.revokedAt).not.toBeNull();
      } else {
        expect(successor?.revokedAt).toBeNull();
        expect(other?.revokedAt).toBeNull();
      }
      // A rejected reuse never mints a session.
      expect(await h.repos.sessions.findByHash(hash(token('attacker', n)))).toBeNull();
    });
  });

  it('the boundary is strict to the millisecond: grace - 1 ms is a retry, grace is theft, grace + 1 ms is theft', async () => {
    const h = await makeHarness();
    const results: boolean[] = [];
    for (const delta of [-1, 0, 1]) {
      const userId = await h.newUser();
      await h.repos.sessions.create({ userId, refreshHash: hash(token('old', delta + 10)), expiresAt: FAR });
      await h.repos.sessions.rotate({ oldHash: hash(token('old', delta + 10)), newHash: hash(token('new', delta + 10)), newExpiresAt: FAR, now: T0, graceMs: GRACE_MS });
      await h.pinRevokedAt(hash(token('old', delta + 10)), T0);
      const r = await h.repos.sessions.rotate({
        oldHash: hash(token('old', delta + 10)),
        newHash: hash(token('x', delta + 10)),
        newExpiresAt: FAR,
        now: new Date(T0.getTime() + GRACE_MS + delta),
        graceMs: GRACE_MS,
      });
      expect(r.status).toBe('reused');
      results.push(r.status === 'reused' && r.familyRevoked);
    }
    expect(results).toEqual([false, true, true]);
  });

  it('grace 0 disables the retry window: even the same instant is theft', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    await h.repos.sessions.create({ userId, refreshHash: hash(token('old', 0)), expiresAt: FAR });
    await h.repos.sessions.rotate({ oldHash: hash(token('old', 0)), newHash: hash(token('new', 0)), newExpiresAt: FAR, now: T0, graceMs: 0 });
    await h.pinRevokedAt(hash(token('old', 0)), T0);
    const r = await h.repos.sessions.rotate({ oldHash: hash(token('old', 0)), newHash: hash(token('x', 0)), newExpiresAt: FAR, now: T0, graceMs: 0 });
    expect(r).toEqual({ status: 'reused', userId, familyRevoked: true });
  });

  it('a session revoked by logout (no successor) is never a retry, however recent', async () => {
    const h = await makeHarness();
    const userId = await h.newUser();
    const s = await h.repos.sessions.create({ userId, refreshHash: hash(token('old', 77)), expiresAt: FAR });
    await h.repos.sessions.create({ userId, refreshHash: hash(token('keep', 77)), expiresAt: FAR });
    await h.repos.sessions.revoke(s.id);
    await h.pinRevokedAt(hash(token('old', 77)), T0);
    const r = await h.repos.sessions.rotate({ oldHash: hash(token('old', 77)), newHash: hash(token('x', 77)), newExpiresAt: FAR, now: new Date(T0.getTime() + 1), graceMs: GRACE_MS });
    expect(r).toEqual({ status: 'reused', userId, familyRevoked: true });
  });
}

export interface HttpHarness extends Harness {
  app: App;
  setClock(at: Date): void;
}

/** HTTP level: the same rule through POST /auth/refresh with an injected clock (default grace 10 s). */
export function defineRefreshEndpointBoundaryTests(makeHarness: () => Promise<HttpHarness>): void {
  describe.each(GAPS)('POST /auth/refresh: token reused $gapMs ms after its rotation', ({ gapMs, theft }) => {
    it(theft ? 'answers refresh_token_reused and revokes every session' : 'answers refresh_token_reused and keeps the sessions', async () => {
      const h = await makeHarness();
      h.setClock(T0);
      // Two live sessions of one account (two devices), created directly: no scrypt, the endpoint under test is /auth/refresh.
      const userId = await h.newUser();
      const original = randomBytes(32).toString('base64url');
      const otherDevice = randomBytes(32).toString('base64url');
      await h.repos.sessions.create({ userId, refreshHash: hash(original), expiresAt: FAR });
      await h.repos.sessions.create({ userId, refreshHash: hash(otherDevice), expiresAt: FAR });

      const rotation = await h.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: original } });
      expect(rotation.statusCode).toBe(200);
      const successor = rotation.json().tokens.refreshToken as string;
      await h.pinRevokedAt(hash(original), T0);

      h.setClock(new Date(T0.getTime() + gapMs));
      const reuse = await h.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: original } });
      expect(reuse.statusCode).toBe(401);
      expect(reuse.json().error.code).toBe('refresh_token_reused');
      if (theft) expect(reuse.json().error.message).toMatch(/all sessions were revoked/);
      else expect(reuse.json().error.message).not.toMatch(/revoked/);

      const stillOk = [(await h.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: successor } })).statusCode, (await h.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: otherDevice } })).statusCode];
      expect(stillOk).toEqual(theft ? [401, 401] : [200, 200]);
    });
  });
}
