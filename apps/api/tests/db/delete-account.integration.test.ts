import type pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { describeDeleteAccount } from '../cloud-account-suite.js';
import { type CloudFixture, postgresAvailable, postgresFixtureIn, seedAccount, sqlPool } from '../cloud-support.js';

// Own schema, so the catalog queries below see exactly this suite's tables (and parallel files do not interfere).
const SCHEMA = 'wb_cloud_account';
const postgresFixture = postgresFixtureIn(SCHEMA);

// Every register and login runs a scrypt hash (N=2^16); on a loaded machine a populated account takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// Behaviour: tokens, other users, deleting twice (shared with the in-memory run).
describeDeleteAccount('PostgreSQL', postgresFixture, postgresAvailable);

/**
 * Tables that hold no per-user rows, by design. Anything else without a `user_id` column must be looked at.
 * `ai_spend_daily` is a total per day and provider: no user id, nothing that points at a person, kept on purpose
 * after an erasure (a spend limit that a user could reset by deleting their data would be no limit).
 */
const NOT_PER_USER = ['ai_spend_daily', 'electricity_prices', 'schema_migrations', 'users'];

describe.skipIf(!postgresAvailable)('DELETE /me (PostgreSQL schema)', () => {
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

  async function tablesWithUserId(): Promise<string[]> {
    const res = await sql.query(
      `SELECT c.table_name FROM information_schema.columns c
         JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
        WHERE c.table_schema = current_schema() AND c.column_name = 'user_id' ORDER BY 1`,
    );
    return res.rows.map((r) => (r as { table_name: string }).table_name);
  }

  async function perTable(tables: string[], userId: string): Promise<Record<string, number>> {
    const entries = await Promise.all(
      tables.map(async (t) => [t, ((await sql.query(`SELECT count(*)::int AS n FROM "${t}" WHERE user_id = $1`, [userId])).rows[0] as { n: number }).n] as const),
    );
    return Object.fromEntries(entries);
  }

  it('the schema is understood: every table either has a user_id or is known to hold no user data', async () => {
    const withUser = await tablesWithUserId();
    expect(withUser).toEqual(
      expect.arrayContaining(['ai_generations', 'ai_quota_usage', 'charging_summaries', 'daily_usage', 'devices', 'monthly_summaries', 'sessions', 'subscriptions', 'user_settings']),
    );
    const all = (await sql.query(`SELECT table_name FROM information_schema.tables WHERE table_schema = current_schema() AND table_type = 'BASE TABLE' ORDER BY 1`)).rows.map(
      (r) => (r as { table_name: string }).table_name,
    );
    const others = all.filter((t) => !withUser.includes(t));
    expect(others.sort(), 'a table without user_id appeared: does it hold user data? then it must be erased by DELETE /me and exported by /me/export').toEqual(NOT_PER_USER);
  });

  it('every table with a user_id column cascades from users on delete', async () => {
    const withUser = await tablesWithUserId();
    const fks = await sql.query(
      `SELECT c.conrelid::regclass::text AS tbl, c.confdeltype AS rule
         FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
        WHERE c.contype = 'f' AND c.confrelid = 'users'::regclass AND a.attname = 'user_id'`,
    );
    const rule = new Map(fks.rows.map((r) => [(r as { tbl: string }).tbl, (r as { rule: string }).rule]));
    for (const t of withUser) expect(rule.get(t), `${t}.user_id -> users(id) must be ON DELETE CASCADE`).toBe('c');
  });

  it('DELETE /me leaves zero rows in EVERY table that has a user_id, and the other user keeps all of theirs', async () => {
    const withUser = await tablesWithUserId();
    const a = await seedAccount(fx, 'schema-gone');
    const b = await seedAccount(fx, 'schema-kept');
    // A second session so the sessions table holds more than the registration.
    await fx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: a.email, password: a.password } });

    const before = await perTable(withUser, a.userId);
    for (const t of ['ai_generations', 'ai_quota_usage', 'charging_summaries', 'daily_usage', 'devices', 'monthly_summaries', 'sessions', 'subscriptions', 'user_settings']) {
      expect(before[t], `${t} was populated before the delete`).toBeGreaterThan(0);
    }
    expect(before.sessions).toBe(2);
    const bBefore = await perTable(withUser, b.userId);

    expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);

    const after = await perTable(withUser, a.userId);
    expect(after, 'rows left for the deleted user, by table').toEqual(Object.fromEntries(withUser.map((t) => [t, 0])));
    expect((await sql.query('SELECT 1 FROM users WHERE id = $1', [a.userId])).rowCount).toBe(0);
    expect(await perTable(withUser, b.userId)).toEqual(bBefore);
    expect((await sql.query('SELECT 1 FROM users WHERE id = $1', [b.userId])).rowCount).toBe(1);
  });
});
