// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * `DELETE /me` end to end: what is gone, what is untouched, and that the dead account's tokens
 * open nothing. Shared by the in-memory run (cloud-delete-account.test.ts) and the PostgreSQL run
 * (db/delete-account.integration.test.ts).
 */
import { randomUUID } from 'node:crypto';

import type { InjectOptions } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { sampleInput } from './helpers.js';
import { type Account, type CloudFixture, exportBody, type FixtureFactory, getExport, registerAccount, seedAccount, SYNCED_DAYS } from './cloud-support.js';
import type { App } from '../src/app.js';

// ------------------------------------------------------------------ route enumeration

const UNKNOWN_UUID = '00000000-0000-4000-8000-0000000000aa';

interface Sample {
  /** Path parameters and query string are filled in here. */
  url?: (a: Account) => string;
  payload?: (a: Account) => unknown;
  /** Statuses a LIVE account may get (the control run); a deleted account must always get 401. */
  live: number[];
  /** Skipped in the control run because it would delete the control account. */
  destructive?: boolean;
}

/**
 * One valid request per authenticated route. A route that has none fails the enumeration test below on
 * purpose: adding an authenticated route means adding it here, which puts it under the deleted-account check.
 */
const AUTHENTICATED: Record<string, Sample> = {
  'GET /api/v1/me': { live: [200] },
  'PATCH /api/v1/me': { payload: () => ({ displayName: 'Renamed' }), live: [200] },
  'DELETE /api/v1/me': { live: [204], destructive: true },
  'GET /api/v1/me/sessions': { live: [200] },
  'DELETE /api/v1/me/sessions/{id}': { url: () => `/api/v1/me/sessions/${UNKNOWN_UUID}`, live: [404] },
  // A wrong current password: shape-valid, no side effect.
  'POST /api/v1/me/password': { payload: () => ({ currentPassword: 'definitely not the password', newPassword: 'another long password' }), live: [401] },
  'POST /api/v1/auth/logout-all': { live: [204], destructive: true },
  'GET /api/v1/me/settings': { live: [200] },
  // No country on purpose: a saved country would send the price route below to a price source.
  'PUT /api/v1/me/settings': { payload: () => ({ currencyCode: 'PLN' }), live: [200] },
  'DELETE /api/v1/me/cloud-data': { live: [200], destructive: true },
  'GET /api/v1/me/export': { live: [200] },
  'GET /api/v1/devices': { live: [200] },
  'POST /api/v1/devices': { payload: () => ({ installationId: 'install-after-delete', platform: 'ios' }), live: [201] },
  'DELETE /api/v1/devices/{id}': { url: () => `/api/v1/devices/${UNKNOWN_UUID}`, live: [404] },
  'POST /api/v1/usage/sync': { payload: (a) => ({ installationId: a.installationId, days: SYNCED_DAYS }), live: [200] },
  'GET /api/v1/usage/daily': { url: () => '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', live: [200] },
  // No country in the query and none saved: answered before any price source is contacted.
  'GET /api/v1/electricity-price': { live: [400] },
  'POST /api/v1/ai/insight': { payload: () => ({ input: sampleInput }), live: [200, 429] },
  'POST /api/v1/ai/weekly-summary': { payload: () => ({ input: sampleInput }), live: [200, 429] },
  'POST /api/v1/ai/monthly-summary': { payload: () => ({ input: sampleInput }), live: [200, 429] },
  'POST /api/v1/ai/roast': { payload: () => ({ input: sampleInput }), live: [200, 429] },
};

/** Routes that need no token, so a deleted account's token cannot matter. */
const PUBLIC = new Set([
  'GET /health',
  'GET /ready',
  'GET /api/v1/config',
  'GET /api/v1/region',
  'GET /api/v1/devices/specifications/{identifier}',
  'POST /api/v1/auth/register',
  'POST /api/v1/auth/login',
  'POST /api/v1/auth/refresh',
  'POST /api/v1/auth/logout',
  'POST /api/v1/auth/apple',
  'POST /api/v1/auth/google',
]);

interface Operation {
  key: string;
  method: string;
  path: string;
  secured: boolean;
}

export function operationsOf(app: App): Operation[] {
  const spec = app.swagger() as unknown as { paths: Record<string, Record<string, { security?: { bearerAuth?: unknown }[] }>> };
  const ops: Operation[] = [];
  for (const [path, item] of Object.entries(spec.paths)) {
    for (const [method, op] of Object.entries(item)) {
      if (!['get', 'post', 'put', 'patch', 'delete'].includes(method)) continue;
      ops.push({ key: `${method.toUpperCase()} ${path}`, method: method.toUpperCase(), path, secured: Boolean(op.security?.some((s) => s.bearerAuth !== undefined)) });
    }
  }
  return ops;
}

function request(op: Operation, sample: Sample, a: Account): InjectOptions {
  const url = sample.url ? sample.url(a) : op.path;
  const body = sample.payload?.(a);
  return {
    method: op.method as InjectOptions['method'],
    url,
    headers: { authorization: a.headers.authorization },
    ...(body === undefined ? {} : { payload: body as object }),
  };
}

// ------------------------------------------------------------------ the suite

/** Per-user tables the in-memory fixture can count; the PostgreSQL run checks every `user_id` table from the catalog instead. */
const USER_TABLES = ['daily_usage', 'charging_summaries', 'monthly_summaries', 'ai_generations', 'devices', 'subscriptions', 'user_settings'] as const;

export function describeDeleteAccount(label: string, make: FixtureFactory, enabled = true): void {
  describe.skipIf(!enabled)(`DELETE /me (${label})`, () => {
    let fx: CloudFixture;
    beforeEach(async () => {
      fx = await make();
    });
    afterEach(() => fx.close());

    const login = (a: Account) => fx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: a.email, password: a.password } });
    const refresh = (token: string) => fx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: token } });

    it('every authenticated route is covered by this suite, and every other route is known to be public', () => {
      const ops = operationsOf(fx.app);
      expect(ops.length).toBeGreaterThan(15);
      const secured = ops.filter((o) => o.secured).map((o) => o.key);
      const open = ops.filter((o) => !o.secured).map((o) => o.key);
      const uncovered = secured.filter((k) => !(k in AUTHENTICATED));
      const unknownOpen = open.filter((k) => !PUBLIC.has(k));
      expect(uncovered, 'authenticated routes without a sample request in cloud-account-suite.ts (AUTHENTICATED)').toEqual([]);
      expect(unknownOpen, 'routes without bearer security that are not in the PUBLIC list: forgot `security`, or add them to PUBLIC').toEqual([]);
      const stale = [...Object.keys(AUTHENTICATED), ...PUBLIC].filter((k) => !ops.some((o) => o.key === k));
      expect(stale, 'samples for routes that no longer exist').toEqual([]);
    });

    it('the sample requests are valid: a live account gets the expected answers (control)', async () => {
      // No saved country: the price route then answers before it would contact a price source.
      const control = await seedAccount(fx, 'control', { settings: false });
      for (const op of operationsOf(fx.app).filter((o) => o.secured)) {
        const sample = AUTHENTICATED[op.key];
        if (!sample || sample.destructive) continue;
        const res = await fx.app.inject(request(op, sample, control));
        expect(sample.live, `${op.key} answered ${res.statusCode}: ${res.body.slice(0, 200)}`).toContain(res.statusCode);
      }
    });

    /** Two populated accounts, a second session for the first, then `DELETE /me` for the first. */
    async function deleteFirstAccount(label: string) {
      const a = await seedAccount(fx, `${label}-gone`);
      const b = await seedAccount(fx, `${label}-kept`);
      const secondSession = (await login(a)).json() as { tokens: { accessToken: string; refreshToken: string } };
      const bBefore = await exportBody(fx, b.headers);
      for (const t of USER_TABLES) expect(await fx.rowCount(t, a.userId), `${t} has rows before`).toBeGreaterThan(0);
      const res = await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers });
      expect(res.statusCode).toBe(204);
      return { a, b, secondSession, bBefore };
    }

    it('(a)(b) erases every row of the account and leaves the other account exactly as it was', async () => {
      const { a, b, bBefore } = await deleteFirstAccount('rows');
      for (const t of USER_TABLES) expect(await fx.rowCount(t, a.userId), `${t} is empty after`).toBe(0);
      expect(await fx.repos.users.findById(a.userId)).toBeNull();
      expect(await fx.repos.users.findByEmail(a.email)).toBeNull();

      expect(await exportBody(fx, b.headers)).toEqual(bBefore);
      expect((await fx.app.inject({ method: 'GET', url: '/api/v1/me', headers: b.headers })).json()).toMatchObject({ id: b.userId });
      expect((await login(b)).statusCode).toBe(200);
      expect((await refresh(b.refreshToken)).statusCode).toBe(200);

      // The e-mail is free again and a new account is a different, empty one.
      const again = await fx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email: a.email, password: a.password } });
      expect(again.statusCode).toBe(201);
      const reborn = (again.json() as { user: { id: string } }).user.id;
      expect(reborn).not.toBe(a.userId);
      for (const t of USER_TABLES) expect(await fx.rowCount(t, reborn), `${t} of the new account`).toBe(0);
    });

    it('(c) every refresh token of the deleted account is rejected, and so are its credentials', async () => {
      const { a, secondSession } = await deleteFirstAccount('refresh');
      for (const token of [a.refreshToken, secondSession.tokens.refreshToken]) {
        const dead = await refresh(token);
        expect(dead.statusCode).toBe(401);
        expect(dead.json().error.code).toBe('invalid_refresh_token');
      }
      const relogin = await login(a);
      expect(relogin.statusCode).toBe(401);
      expect(relogin.json().error.code).toBe('invalid_credentials');
      expect((await fx.app.inject({ method: 'POST', url: '/api/v1/auth/logout', payload: { refreshToken: a.refreshToken } })).statusCode, 'logout stays idempotent').toBe(204);
    });

    it('(c) the old access tokens open NO authenticated route (every swagger path answers 401)', async () => {
      const { a, secondSession } = await deleteFirstAccount('access');
      const failures: string[] = [];
      for (const op of operationsOf(fx.app).filter((o) => o.secured)) {
        const sample = AUTHENTICATED[op.key];
        if (!sample) throw new Error(`no sample for ${op.key}`);
        for (const token of [a.accessToken, secondSession.tokens.accessToken]) {
          const old = await fx.app.inject({ ...request(op, sample, a), headers: { authorization: `Bearer ${token}` } });
          if (old.statusCode !== 401) failures.push(`${op.key} -> ${old.statusCode} ${old.body.slice(0, 80)}`);
        }
      }
      expect(failures, 'routes that still answer a token of a deleted account').toEqual([]);
    });

    it('(d) deleting twice is safe: 401 or 204, never an error, and the other account is not affected', async () => {
      const a = await seedAccount(fx, 'twice');
      const b = await seedAccount(fx, 'twice-other');
      const bBefore = await exportBody(fx, b.headers);
      expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);
      for (let i = 0; i < 2; i++) {
        const again = await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers });
        expect([204, 401], `second delete answered ${again.statusCode}`).toContain(again.statusCode);
      }
      expect(await exportBody(fx, b.headers)).toEqual(bBefore);
    });

    it('a deleted account cannot use a token for cloud data, and a fresh export of a new account is empty', async () => {
      const a = await seedAccount(fx, 'cd');
      expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);
      expect((await getExport(fx, a.headers)).statusCode).toBe(401);
      const fresh = await registerAccount(fx, `cd-new-${randomUUID().slice(0, 6)}`);
      expect((await getExport(fx, fresh.headers)).json().dailyUsage).toEqual([]);
    });
  });
}
