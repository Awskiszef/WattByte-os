// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterAll, describe, vi } from 'vitest';

import { PostgresRepositories } from '../../src/database/postgres.js';
import { defineRefreshEndpointBoundaryTests, defineRotateBoundaryTests } from '../refresh-boundary.shared.js';
import { buildTestApp } from '../support.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, uniqueEmail } from './helpers.js';

// Every test builds its app through makePgApp(), which runs migrate() and so queues for the database-wide advisory lock that other files
// hold or wait for; on a fresh database the first test also pays for the first migration. Like the other PostgreSQL suites that share the
// database, allow for a loaded machine instead of the 5 s default (3.7 s was measured with two suites running at once).
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

describe.skipIf(!DATABASE_URL)('refresh reuse boundary (PostgreSQL)', () => {
  const contexts: PgContext[] = [];
  const closers: (() => Promise<void>)[] = [];
  afterAll(async () => {
    for (const c of contexts) await closePgApp(c);
    for (const close of closers) await close();
  });

  async function pgHarness() {
    const ctx = await makePgApp();
    contexts.push(ctx);
    return {
      repos: ctx.repos,
      newUser: async () => (await ctx.repos.users.create({ email: uniqueEmail('boundary'), passwordHash: null })).id,
      // PostgreSQL stamps revoked_at from its own clock; the test needs the rotation time it simulates.
      pinRevokedAt: async (refreshHash: string, at: Date) => {
        await ctx.pool.query('UPDATE sessions SET revoked_at = $2 WHERE refresh_hash = $1', [refreshHash, at]);
      },
      pool: ctx.pool,
    };
  }

  defineRotateBoundaryTests(pgHarness);

  defineRefreshEndpointBoundaryTests(async () => {
    const base = await pgHarness();
    let clock = new Date();
    const repos = new PostgresRepositories(DATABASE_URL!);
    closers.push(() => repos.close());
    const ctx = await buildTestApp({ repos, now: () => clock, env: { REFRESH_REUSE_GRACE_SEC: '10' } });
    closers.push(() => ctx.app.close());
    return {
      app: ctx.app,
      repos,
      setClock: (at: Date) => {
        clock = at;
      },
      newUser: base.newUser,
      pinRevokedAt: base.pinRevokedAt,
    };
  });
});
