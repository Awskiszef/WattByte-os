// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomInt, randomUUID } from 'node:crypto';

import { DailyUsageDto, LIMITS } from '@wattbyte/contracts';
import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import type { DailyUsageRow } from '../../src/database/repositories.js';
import { PostgresRepositories } from '../../src/database/postgres.js';
import { mergeByDate } from '../../src/modules/usage/merge.js';
import { DATABASE_URL, uniqueEmail } from './helpers.js';

/**
 * C-04: GET /usage/daily summed in SQL (one row per day, however many devices), and POST /usage/sync written as one statement.
 * The SQL totals are held to the JavaScript reference (mergeByDate) on randomised data.
 */
describe.skipIf(!DATABASE_URL)('daily usage totals and batched upsert (PostgreSQL)', () => {
  let admin: pg.Pool;
  let repos: PostgresRepositories;
  let userId: string;
  const devices: string[] = [];
  const DEVICES = 40;
  const DAYS = 60;

  const dayOf = (i: number) => new Date(Date.UTC(2031, 0, 1 + i)).toISOString().slice(0, 10);

  beforeAll(async () => {
    await migrate(DATABASE_URL!);
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 3 });
    repos = new PostgresRepositories(DATABASE_URL!, { max: 3 });
    userId = (await admin.query('INSERT INTO users(email) VALUES ($1) RETURNING id', [uniqueEmail('totals')])).rows[0].id as string;
    for (let d = 0; d < DEVICES; d += 1) {
      devices.push((await admin.query("INSERT INTO devices(user_id, installation_id, platform) VALUES ($1, $2, 'android') RETURNING id", [userId, `totals-${d}-${randomUUID()}`])).rows[0].id as string);
    }
    const rows: DailyUsageRow[] = [];
    for (const deviceId of devices) {
      for (let i = 0; i < DAYS; i += 1) {
        // Skip some days per device so a date has a different set of contributors.
        if (randomInt(0, 4) === 0) continue;
        rows.push({
          userId, deviceId, date: dayOf(i),
          mobileBytes: randomInt(0, 5_000_000_000), wifiBytes: randomInt(0, 9_000_000_000),
          chargedWh: randomInt(0, 40_000) / 1000, wallWh: randomInt(0, 50_000) / 1000,
          chargingSessions: randomInt(0, 6), estimatedCost: randomInt(0, 90_000) / 10_000,
          // A fifth of the rows come from a phone set to another currency (C-13).
          currency: randomInt(0, 5) === 0 ? 'EUR' : 'PLN', dataEstimated: randomInt(0, 5) === 0, energyEstimated: randomInt(0, 2) === 0,
        });
      }
    }
    expect(await repos.usage.upsertDaily(rows)).toBe(rows.length);
  });
  afterAll(async () => {
    await admin.query('DELETE FROM users WHERE id = $1', [userId]);
    await repos.close();
    await admin.end();
  });

  it('SQL totals equal the reference merge of every row, in one row per day', async () => {
    const from = dayOf(0);
    const to = dayOf(DAYS - 1);
    const reference = mergeByDate(await repos.usage.listDaily(userId, from, to));
    const totals = await repos.usage.listDailyTotals(userId, from, to);
    expect(totals).toHaveLength(reference.length);
    expect(totals.length).toBeLessThanOrEqual(DAYS);
    totals.forEach((t, i) => {
      const r = reference[i]!;
      expect(t.date).toBe(r.date);
      expect(t.mobileBytes).toBe(r.mobileBytes);
      expect(t.wifiBytes).toBe(r.wifiBytes);
      expect(t.chargingSessions).toBe(r.chargingSessions);
      expect(t.chargedWh).toBeCloseTo(r.chargedWh, 3);
      expect(t.wallWh).toBeCloseTo(r.wallWh, 3);
      expect(t.estimatedCost).toBeCloseTo(r.estimatedCost, 4);
      expect(t.currency).toBe(r.currency);
      expect(t.dataEstimated).toBe(r.dataEstimated);
      expect(t.energyEstimated).toBe(r.energyEstimated);
    });
  });

  it('a day with two currencies keeps one currency and its cost only, never the sum of both (C-13)', async () => {
    const day = dayOf(400);
    const base = { userId, mobileBytes: 1, wifiBytes: 1, chargedWh: 1, wallWh: 1, chargingSessions: 1, dataEstimated: false, energyEstimated: true };
    await repos.usage.upsertDaily([
      { ...base, deviceId: devices[2]!, date: day, estimatedCost: 3, currency: 'PLN' },
      { ...base, deviceId: devices[3]!, date: day, estimatedCost: 5, currency: 'EUR' },
      { ...base, deviceId: devices[4]!, date: day, estimatedCost: 1, currency: 'EUR' },
    ]);
    const [total] = await repos.usage.listDailyTotals(userId, day, day);
    expect(total).toMatchObject({ currency: 'EUR', estimatedCost: 6, mobileBytes: 3, chargingSessions: 3 });
    expect(total).toEqual(mergeByDate(await repos.usage.listDaily(userId, day, day))[0]);
  });

  it('implausible rows are capped at the contract maximum instead of failing the response (C-13)', async () => {
    const day = dayOf(401);
    const huge = { userId, mobileBytes: 9_000_000_000_000, wifiBytes: 1, chargedWh: 90_000, wallWh: 1, chargingSessions: 900, estimatedCost: 90_000, currency: 'PLN', dataEstimated: false, energyEstimated: true };
    await repos.usage.upsertDaily([
      { ...huge, deviceId: devices[5]!, date: day },
      { ...huge, deviceId: devices[6]!, date: day },
    ]);
    const [total] = await repos.usage.listDailyTotals(userId, day, day);
    expect(total).toMatchObject({ mobileBytes: LIMITS.bytesPerDay, chargedWh: LIMITS.whPerDay, chargingSessions: LIMITS.sessionsPerDay, estimatedCost: LIMITS.costPerDay });
    expect(total).toEqual(mergeByDate(await repos.usage.listDaily(userId, day, day))[0]);
    expect(() => DailyUsageDto.parse(total)).not.toThrow();
  });

  it('honours the range and the owner', async () => {
    const some = await repos.usage.listDailyTotals(userId, dayOf(10), dayOf(19));
    expect(some.map((d) => d.date).every((d) => d >= dayOf(10) && d <= dayOf(19))).toBe(true);
    expect(await repos.usage.listDailyTotals(randomUUID(), dayOf(0), dayOf(DAYS))).toEqual([]);
  });

  it('upsertDaily is one atomic statement: updates on conflict, last duplicate wins, a bad row writes nothing', async () => {
    const deviceId = devices[0]!;
    const base = { userId, deviceId, mobileBytes: 1, wifiBytes: 2, chargedWh: 1, wallWh: 2, chargingSessions: 1, estimatedCost: 0.5, currency: 'PLN', dataEstimated: false, energyEstimated: true };
    const date = dayOf(200);
    expect(await repos.usage.upsertDaily([{ ...base, date, mobileBytes: 10 }, { ...base, date, mobileBytes: 99 }])).toBe(2);
    const stored = (await repos.usage.listDaily(userId, date, date)).filter((r) => r.deviceId === deviceId);
    expect(stored).toHaveLength(1);
    expect(stored[0]!.mobileBytes).toBe(99);
    expect(await repos.usage.upsertDaily([{ ...base, date, mobileBytes: 5 }])).toBe(1);
    expect((await repos.usage.listDaily(userId, date, date)).find((r) => r.deviceId === deviceId)!.mobileBytes).toBe(5);

    const other = dayOf(201);
    await expect(repos.usage.upsertDaily([{ ...base, date: other }, { ...base, date: dayOf(202), deviceId: randomUUID() }])).rejects.toThrow();
    expect(await repos.usage.listDaily(userId, other, other)).toEqual([]);
    expect(await repos.usage.upsertDaily([])).toBe(0);
  });

  it('a 92-day sync is a single statement on the pool, not 92 inserts', async () => {
    const deviceId = devices[1]!;
    const rows: DailyUsageRow[] = Array.from({ length: 92 }, (_, i) => ({ userId, deviceId, date: dayOf(300 + i), mobileBytes: i, wifiBytes: i, chargedWh: 1, wallWh: 1, chargingSessions: 1, estimatedCost: 0.1, currency: 'PLN', dataEstimated: false, energyEstimated: true }));
    const queries: string[] = [];
    const pool = (repos as unknown as { pool: pg.Pool }).pool;
    const original = pool.query.bind(pool) as (...a: unknown[]) => unknown;
    (pool as unknown as { query: unknown }).query = (...args: unknown[]) => {
      queries.push(String(typeof args[0] === 'string' ? args[0] : (args[0] as { text?: string })?.text).slice(0, 40));
      return original(...args);
    };
    try {
      expect(await repos.usage.upsertDaily(rows)).toBe(92);
    } finally {
      (pool as unknown as { query: unknown }).query = original;
    }
    expect(queries.filter((q) => q.includes('INSERT INTO daily_usage'))).toHaveLength(1);
  });
});
