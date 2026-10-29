import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { schemaUrl } from '../cloud-support.js';
import { DATABASE_URL } from './helpers.js';

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

/**
 * Migration 0011 on a database that has live and rotated sessions: every chain (rotated token -> successor) becomes one
 * family that keeps the sign-in time of its first token; nothing is deleted. The shared test schema is never touched.
 */
const MIGRATIONS = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'src', 'database', 'migrations');
const TARGET = '0011_session_families.sql';
const SCHEMA = `wb_fam_up_${process.pid}_${Date.now().toString(36)}`;

describe.skipIf(!DATABASE_URL)('migration 0011 session families (PostgreSQL)', () => {
  let admin: pg.Pool;
  let db: pg.Pool;
  let scratch: string;
  const ids = {} as Record<string, string>;

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    await admin.query(`CREATE SCHEMA ${SCHEMA}`);
    db = new pg.Pool({ connectionString: schemaUrl(SCHEMA), max: 2 });
    scratch = mkdtempSync(path.join(tmpdir(), 'wb-mig-fam-'));
    const before = path.join(scratch, 'before');
    mkdirSync(before);
    for (const f of readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql') && n < TARGET)) cpSync(path.join(MIGRATIONS, f), path.join(before, f));
    await migrate(schemaUrl(SCHEMA), before);

    // A user with: device A (three rotations: a1 -> a2 -> a3 live), device B (b1 live, never rotated), and a rotated
    // session whose successor was purged (replaced_by is NULL, revoked): its own one-row family.
    const user = (await db.query(`INSERT INTO users(email) VALUES ('fam@test.wattbyte') RETURNING id`)).rows[0] as { id: string };
    const insert = async (name: string, createdDaysAgo: number, revoked: boolean): Promise<void> => {
      const r = await db.query(
        `INSERT INTO sessions(user_id, refresh_hash, expires_at, revoked_at, created_at)
         VALUES ($1, $2, now() + interval '30 days', ${revoked ? "now() - interval '1 day'" : 'NULL'}, now() - ($3 || ' days')::interval) RETURNING id`,
        [user.id, `hash-${name}-${SCHEMA}`, String(createdDaysAgo)],
      );
      ids[name] = (r.rows[0] as { id: string }).id;
    };
    await insert('a1', 20, true);
    await insert('a2', 10, true);
    await insert('a3', 1, false);
    await insert('b1', 5, false);
    await insert('orphan', 40, true);
    await db.query('UPDATE sessions SET replaced_by = $2 WHERE id = $1', [ids.a1, ids.a2]);
    await db.query('UPDATE sessions SET replaced_by = $2 WHERE id = $1', [ids.a2, ids.a3]);

    expect(await migrate(schemaUrl(SCHEMA), MIGRATIONS)).toContain(TARGET);
  });

  afterAll(async () => {
    await db?.end();
    await admin?.query(`DROP SCHEMA IF EXISTS ${SCHEMA} CASCADE`);
    await admin?.end();
    if (scratch) rmSync(scratch, { recursive: true, force: true });
  });

  const family = async (name: string) => (await db.query('SELECT family_id, family_started_at, created_at FROM sessions WHERE id = $1', [ids[name]])).rows[0] as { family_id: string; family_started_at: Date; created_at: Date };

  it('a rotated chain becomes one family that starts when its first token did', async () => {
    const [a1, a2, a3] = [await family('a1'), await family('a2'), await family('a3')];
    expect(a1.family_id).toBe(ids.a1); // the root names the family
    expect(a2.family_id).toBe(a1.family_id);
    expect(a3.family_id).toBe(a1.family_id);
    expect(a2.family_started_at).toEqual(a1.created_at);
    expect(a3.family_started_at).toEqual(a1.created_at);
  });

  it('an unrotated session and an orphan are families of their own; no row was lost; the columns are NOT NULL', async () => {
    expect((await family('b1')).family_id).toBe(ids.b1);
    expect((await family('orphan')).family_id).toBe(ids.orphan);
    expect((await db.query('SELECT count(*)::int AS n FROM sessions')).rows[0].n).toBe(5);
    const cols = await db.query(
      `SELECT column_name, is_nullable FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'sessions' AND column_name IN ('family_id', 'family_started_at')`,
      [SCHEMA],
    );
    expect(cols.rows.every((r) => r.is_nullable === 'NO')).toBe(true);
  });

  it('users get tokens_valid_after, empty for everybody', async () => {
    const r = await db.query('SELECT tokens_valid_after FROM users');
    expect(r.rows.every((u) => u.tokens_valid_after === null)).toBe(true);
  });
});
