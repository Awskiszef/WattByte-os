// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { randomUUID } from 'node:crypto';

import type pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { describeCloudData } from '../cloud-suite.js';
import { type CloudFixture, deleteCloudData, exportBody, postgresAvailable, postgresFixtureIn, seedAccount, sqlPool } from '../cloud-support.js';

// Own schema: these suites write thousands of rows in parallel with other files (see schemaUrl).
const SCHEMA = 'wb_cloud_data';
const postgresFixture = postgresFixtureIn(SCHEMA);

// Every register and login runs a scrypt hash (N=2^16); on a loaded machine a populated account takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The behaviour suite shared with the in-memory repositories.
describeCloudData('PostgreSQL', postgresFixture, postgresAvailable);

describe.skipIf(!postgresAvailable)('cloud data (PostgreSQL specifics)', () => {
  let fx: CloudFixture;
  let sql: pg.Pool;
  beforeAll(async () => {
    fx = await postgresFixture();
    sql = sqlPool(SCHEMA);
  });
  afterAll(async () => {
    await sql.end();
    await fx.close();
  });

  const count = async (table: string, userId: string): Promise<number> =>
    ((await sql.query(`SELECT count(*)::int AS n FROM ${table} WHERE user_id = $1`, [userId])).rows[0] as { n: number }).n;

  /** Makes DELETE FROM `table` fail for rows of one user, to prove the surrounding transaction rolls back. */
  async function failDeletesOn(table: string, userId: string): Promise<() => Promise<void>> {
    const trigger = `wb_block_${randomUUID().replaceAll('-', '').slice(0, 12)}`;
    await sql.query(`CREATE OR REPLACE FUNCTION wb_cloud_test_block() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'blocked by test'; END $$`);
    await sql.query(`CREATE TRIGGER ${trigger} BEFORE DELETE ON ${table} FOR EACH ROW WHEN (OLD.user_id = '${userId}') EXECUTE FUNCTION wb_cloud_test_block()`);
    return async () => {
      await sql.query(`DROP TRIGGER ${trigger} ON ${table}`);
    };
  }

  const TABLES = ['daily_usage', 'charging_summaries', 'monthly_summaries', 'ai_generations', 'ai_quota_usage', 'devices'] as const;
  const snapshot = async (userId: string) => Object.fromEntries(await Promise.all(TABLES.map(async (t) => [t, await count(t, userId)]))) as Record<(typeof TABLES)[number], number>;

  it('keeps the AI quota counters (no allowance reset), and only touches the given user\'s rows', async () => {
    const a = await seedAccount(fx, 'pg-quota-a');
    const b = await seedAccount(fx, 'pg-quota-b');
    expect(await snapshot(a.userId)).toEqual({ daily_usage: 3, charging_summaries: 2, monthly_summaries: 1, ai_generations: 2, ai_quota_usage: 1, devices: 1 });
    const used = (await sql.query('SELECT used FROM ai_quota_usage WHERE user_id = $1', [b.userId])).rows[0] as { used: number };
    expect(used.used).toBe(2);

    expect((await deleteCloudData(fx, a.headers, '?devices=true')).statusCode).toBe(200);
    expect(await snapshot(a.userId)).toEqual({ daily_usage: 0, charging_summaries: 0, monthly_summaries: 0, ai_generations: 0, ai_quota_usage: 1, devices: 0 });
    // Kept: the account, its sessions, settings and subscription.
    expect(await count('sessions', a.userId)).toBe(1);
    expect(await count('user_settings', a.userId)).toBe(1);
    expect(await count('subscriptions', a.userId)).toBe(1);
    expect((await sql.query('SELECT 1 FROM users WHERE id = $1', [a.userId])).rowCount).toBe(1);
    expect(await snapshot(b.userId)).toEqual({ daily_usage: 3, charging_summaries: 2, monthly_summaries: 1, ai_generations: 2, ai_quota_usage: 1, devices: 1 });
  });

  it('is one transaction: a failure on the last table restores every table', async () => {
    const a = await seedAccount(fx, 'pg-atomic');
    const before = await snapshot(a.userId);
    const restore = await failDeletesOn('devices', a.userId);
    try {
      await expect(fx.repos.cloud.deleteData(a.userId, { devices: true })).rejects.toThrow(/blocked by test/);
      expect(await snapshot(a.userId), 'usage, summaries, AI log and quota counters are all still there').toEqual(before);

      // The same through HTTP: a clean 500 error body, and still nothing deleted.
      const res = await deleteCloudData(fx, a.headers, '?devices=true');
      expect(res.statusCode).toBe(500);
      expect(res.json().error.code).toBe('internal');
      expect(await snapshot(a.userId)).toEqual(before);
    } finally {
      await restore();
    }
    expect((await fx.repos.cloud.deleteData(a.userId, { devices: true }))?.devices).toBe(1);
    expect(await snapshot(a.userId)).toEqual({ daily_usage: 0, charging_summaries: 0, monthly_summaries: 0, ai_generations: 0, ai_quota_usage: 1, devices: 0 });
  });

  it('is one transaction: a failure in the middle (AI log) also keeps the usage rows deleted before it', async () => {
    const a = await seedAccount(fx, 'pg-atomic-mid');
    const before = await snapshot(a.userId);
    const restore = await failDeletesOn('ai_generations', a.userId);
    try {
      await expect(fx.repos.cloud.deleteData(a.userId)).rejects.toThrow(/blocked by test/);
      expect(await snapshot(a.userId)).toEqual(before);
    } finally {
      await restore();
    }
  });

  it('an export is one snapshot: concurrent with a delete it is either complete or empty, never half', async () => {
    const a = await seedAccount(fx, 'pg-snapshot');
    const shape = (d: Awaited<ReturnType<typeof fx.repos.cloud.exportData>>) =>
      JSON.stringify([d?.dailyUsage.length, d?.chargingSummaries.length, d?.monthlySummaries.length, d?.aiGenerations.length]);
    const exports: Promise<string>[] = [];
    for (let i = 0; i < 60; i++) exports.push(fx.repos.cloud.exportData(a.userId, 100).then(shape));
    const erase = fx.repos.cloud.deleteData(a.userId);
    for (let i = 0; i < 60; i++) exports.push(fx.repos.cloud.exportData(a.userId, 100).then(shape));
    await erase;
    const seen = new Set(await Promise.all(exports));
    for (const s of seen) expect(['[3,2,1,2]', '[0,0,0,0]']).toContain(s);
    // Which of the concurrent exports ran after the commit depends on pool scheduling, so none of them is required to be empty.
    // What is guaranteed is checked once the delete has returned: a new export starts after the commit and sees nothing.
    expect(shape(await fx.repos.cloud.exportData(a.userId, 100)), 'after the delete committed, an export is empty').toBe('[0,0,0,0]');
  });

  it('an export keeps the snapshot it took when it started: a delete that commits while the export waits is not seen by it', async () => {
    const a = await seedAccount(fx, 'pg-snapshot-start');
    const shape = (d: Awaited<ReturnType<typeof fx.repos.cloud.exportData>>) =>
      JSON.stringify([d?.dailyUsage.length, d?.chargingSummaries.length, d?.monthlySummaries.length, d?.aiGenerations.length]);
    // exportData reads the account, the settings and then `devices` first. A lock on `devices` parks it there: its snapshot was taken by the
    // first statement and no collection has been read yet. deleteData does not touch `devices` here, so it commits while the export is parked.
    // Nothing depends on timing: the export is seen queued in pg_locks before the delete starts, and the lock is released after the commit.
    // A plain BEGIN (READ COMMITTED) or separate queries would read the collections after the commit and return [0,0,0,0].
    const holder = await sql.connect();
    let parked: ReturnType<typeof fx.repos.cloud.exportData> | undefined;
    try {
      await holder.query('BEGIN');
      await holder.query('LOCK TABLE devices IN ACCESS EXCLUSIVE MODE');
      parked = fx.repos.cloud.exportData(a.userId, 100);
      const queued = async (): Promise<number> =>
        ((await sql.query("SELECT count(*)::int AS n FROM pg_locks WHERE locktype = 'relation' AND relation = 'devices'::regclass AND NOT granted")).rows[0] as { n: number }).n;
      // A condition with a bound, not a delay: if the export never queues, the test fails with this message instead of hanging.
      for (let polls = 0; (await queued()) === 0; polls++) {
        if (polls >= 1000) throw new Error('the export did not queue for the lock on devices');
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      expect(await fx.repos.cloud.deleteData(a.userId), 'the delete commits while the export is parked').toEqual({
        dailyUsage: 3,
        chargingSummaries: 2,
        monthlySummaries: 1,
        aiGenerations: 2,
        devices: 0,
      });
      await holder.query('COMMIT');
      expect(shape(await parked), 'the export still sees what existed when it started').toBe('[3,2,1,2]');
    } finally {
      await holder.query('ROLLBACK').catch(() => undefined);
      holder.release();
      await parked?.catch(() => undefined);
    }
    expect(shape(await fx.repos.cloud.exportData(a.userId, 100)), 'an export that starts after the commit is empty').toBe('[0,0,0,0]');
  });

  it('an export does not write: the account row and its data are unchanged afterwards', async () => {
    const a = await seedAccount(fx, 'pg-readonly');
    const before = await exportBody(fx, a.headers);
    const row = (await sql.query('SELECT xmin::text AS x FROM users WHERE id = $1', [a.userId])).rows[0] as { x: string };
    for (let i = 0; i < 3; i++) await exportBody(fx, a.headers);
    expect(await exportBody(fx, a.headers)).toEqual(before);
    expect((await sql.query('SELECT xmin::text AS x FROM users WHERE id = $1', [a.userId])).rows[0]).toEqual(row);
  });
});
