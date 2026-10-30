// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomInt } from 'node:crypto';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { PostgresRepositories } from '../../src/database/postgres.js';
import { DATABASE_URL } from './helpers.js';

/**
 * reserveSpend() takes the plan row and then the provider row of the spend tables; settling a hold (adjustSpend) took them
 * the other way round and without the advisory lock, so a reservation and a settlement running together could deadlock:
 * PostgreSQL aborted one of them, the gateway logged "ai spend ledger unavailable" and answered 503 to a user whose
 * request was valid (seen as a flaky 100-concurrent-requests test). Both paths now lock plan row first, provider row second.
 */
describe.skipIf(!DATABASE_URL)('AI spend ledger lock order (PostgreSQL)', () => {
  let admin: pg.Pool;
  let repos: PostgresRepositories;
  // A day nobody else uses: tests share the database.
  const day = `${2200 + randomInt(0, 700)}-0${randomInt(1, 10)}-1${randomInt(0, 10)}`;
  const provider = 'openai';
  const plan = 'free';

  beforeAll(async () => {
    await migrate(DATABASE_URL!);
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 3 });
    repos = new PostgresRepositories(DATABASE_URL!, { max: 3 });
    await admin.query('INSERT INTO ai_spend_daily(day, provider, requests, cost_usd) VALUES ($1::date, $2, 1, 1)', [day, provider]);
    await admin.query('INSERT INTO ai_spend_plan_daily(day, plan, cost_usd) VALUES ($1::date, $2, 1)', [day, plan]);
  });
  afterAll(async () => {
    await admin.query('DELETE FROM ai_spend_daily WHERE day = $1::date', [day]);
    await admin.query('DELETE FROM ai_spend_plan_daily WHERE day = $1::date', [day]);
    await repos.close();
    await admin.end();
  });

  it('a settlement that meets a reservation holding the plan row waits for it instead of deadlocking', async () => {
    const reservation = await admin.connect();
    try {
      // What reserveSpend() holds in the middle of its transaction: the plan row, about to take the provider row.
      await reservation.query('BEGIN');
      await reservation.query('UPDATE ai_spend_plan_daily SET cost_usd = cost_usd + 1 WHERE day = $1::date AND plan = $2', [day, plan]);

      const settlement = repos.ai.adjustSpend({ day, provider, plan, deltaUsd: -0.5, deltaRequests: 0 });
      const settled = settlement.then(() => 'ok' as const, (e: unknown) => e);
      // Give the settlement time to reach (and block on) its first row lock.
      await new Promise((r) => setTimeout(r, 300));

      await reservation.query('UPDATE ai_spend_daily SET cost_usd = cost_usd + 1 WHERE day = $1::date AND provider = $2', [day, provider]);
      await reservation.query('COMMIT');

      expect(await settled).toBe('ok');
    } finally {
      await reservation.query('ROLLBACK').catch(() => undefined);
      reservation.release();
    }
    const rows = (await admin.query('SELECT (SELECT cost_usd FROM ai_spend_daily WHERE day = $1::date AND provider = $2) AS provider_usd, (SELECT cost_usd FROM ai_spend_plan_daily WHERE day = $1::date AND plan = $3) AS plan_usd', [day, provider, plan])).rows[0] as { provider_usd: string; plan_usd: string };
    expect(Number(rows.provider_usd)).toBeCloseTo(1.5);
    expect(Number(rows.plan_usd)).toBeCloseTo(1.5);
  });

  it('many reservations and settlements together never deadlock', async () => {
    const limits = { dailyUsd: undefined, monthlyUsd: undefined, providerDailyUsd: undefined, planDailyUsd: undefined };
    const work = Array.from({ length: 60 }, async (_, i) => {
      if (i % 2 === 0) return repos.ai.reserveSpend({ day, provider, plan, usd: 0.01, limits });
      return repos.ai.adjustSpend({ day, provider, plan, deltaUsd: -0.005, deltaRequests: 0 });
    });
    await expect(Promise.all(work)).resolves.toHaveLength(60);
  });
});
