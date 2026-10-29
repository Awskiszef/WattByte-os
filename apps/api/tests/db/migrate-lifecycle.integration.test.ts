import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

import { checksumOf, latestMigrationName, MigrationError, migrate, migrationStatus } from '../../src/database/migrate.js';
import { schemaUrl } from '../cloud-support.js';
import { DATABASE_URL } from './helpers.js';

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

/**
 * C-07: the migration runner's safety rails, against a real server, each in a private schema (the shared test schema is
 * never touched). Advisory locks are per database, so a test that holds the migration lock only delays other files' migrate().
 */
const REAL = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'src', 'database', 'migrations');

describe.skipIf(!DATABASE_URL)('migration runner safety rails (PostgreSQL)', () => {
  let admin: pg.Pool;
  let scratch: string;
  let schema: string;
  let dir: string;
  let seq = 0;

  const url = () => schemaUrl(schema);
  const write = (name: string, sql: string) => writeFileSync(path.join(dir, name), sql);
  const rows = async () => (await admin.query(`SELECT name, checksum FROM ${schema}.schema_migrations ORDER BY name`)).rows as { name: string; checksum: string | null }[];

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 2 });
    scratch = mkdtempSync(path.join(tmpdir(), 'wb-mig-life-'));
  });
  beforeEach(async () => {
    seq += 1;
    schema = `wb_mig_life_${process.pid}_${Date.now().toString(36)}_${seq}`;
    await admin.query(`CREATE SCHEMA ${schema}`);
    dir = path.join(scratch, `m${seq}`);
    mkdirSync(dir);
    write('0001_t.sql', 'CREATE TABLE t (id int PRIMARY KEY);');
  });
  afterAll(async () => {
    const left = (await admin.query("SELECT nspname FROM pg_namespace WHERE nspname LIKE $1", [`wb_mig_life_${process.pid}_%`])).rows as { nspname: string }[];
    for (const r of left) await admin.query(`DROP SCHEMA IF EXISTS ${r.nspname} CASCADE`);
    await admin.end();
    rmSync(scratch, { recursive: true, force: true });
  });

  it('records the sha256 of every applied file', async () => {
    expect(await migrate(url(), dir)).toEqual(['0001_t.sql']);
    expect(await rows()).toEqual([{ name: '0001_t.sql', checksum: checksumOf('CREATE TABLE t (id int PRIMARY KEY);') }]);
    expect(await migrate(url(), dir)).toEqual([]);
  });

  it('a file edited after it was applied stops the run before anything else is applied', async () => {
    await migrate(url(), dir);
    write('0001_t.sql', 'CREATE TABLE t (id int PRIMARY KEY, extra int);');
    write('0002_next.sql', 'CREATE TABLE next_t (id int);');
    const failure = await migrate(url(), dir).then(() => undefined, (e: unknown) => e);
    expect(failure).toBeInstanceOf(MigrationError);
    expect(String(failure)).toContain('0001_t.sql');
    expect((await rows()).map((r) => r.name)).toEqual(['0001_t.sql']);
    expect((await admin.query(`SELECT to_regclass('${schema}.next_t') AS t`)).rows[0].t).toBeNull();
    expect((await migrationStatus(url(), dir)).modified).toEqual(['0001_t.sql']);
  });

  it('a checkout with Windows line endings is not an edited migration', async () => {
    write('0001_t.sql', 'CREATE TABLE t (\n  id int PRIMARY KEY\n);\n');
    await migrate(url(), dir);
    write('0001_t.sql', 'CREATE TABLE t (\r\n  id int PRIMARY KEY\r\n);\r\n');
    expect(await migrate(url(), dir)).toEqual([]);
  });

  it('a database migrated before checksums existed gets them recorded, and the rest is applied', async () => {
    await migrate(url(), dir);
    await admin.query(`ALTER TABLE ${schema}.schema_migrations DROP COLUMN checksum`);
    write('0002_next.sql', 'CREATE TABLE next_t (id int);');
    expect((await migrationStatus(url(), dir)).unverified).toEqual(['0001_t.sql']);
    expect(await migrate(url(), dir)).toEqual(['0002_next.sql']);
    const recorded = await rows();
    expect(recorded.map((r) => r.checksum)).toEqual([checksumOf('CREATE TABLE t (id int PRIMARY KEY);'), checksumOf('CREATE TABLE next_t (id int);')]);
  });

  it('a migration that cannot get its lock fails within lock_timeout, rolls back and records nothing', async () => {
    await migrate(url(), dir);
    write('0002_alter.sql', 'ALTER TABLE t ADD COLUMN c int;');
    const holder = new pg.Client({ connectionString: url() });
    await holder.connect();
    try {
      await holder.query('BEGIN');
      await holder.query('LOCK TABLE t IN ACCESS SHARE MODE');
      const started = Date.now();
      await expect(migrate(url(), dir, undefined, { lockTimeoutMs: 300 })).rejects.toThrow(/lock timeout/);
      expect(Date.now() - started).toBeLessThan(5_000);
      expect((await rows()).map((r) => r.name)).toEqual(['0001_t.sql']);
    } finally {
      await holder.query('ROLLBACK').catch(() => undefined);
      await holder.end();
    }
    expect(await migrate(url(), dir)).toEqual(['0002_alter.sql']);
  });

  it('a migration that runs too long is cancelled by statement_timeout', async () => {
    write('0002_slow.sql', 'SELECT pg_sleep(10);');
    const started = Date.now();
    await expect(migrate(url(), dir, undefined, { statementTimeoutMs: 300 })).rejects.toThrow(/statement timeout/);
    expect(Date.now() - started).toBeLessThan(6_000);
    expect((await rows()).map((r) => r.name)).toEqual(['0001_t.sql']);
  });

  it('-- migrate:no-transaction runs outside a transaction (CREATE INDEX CONCURRENTLY) and is recorded', async () => {
    await migrate(url(), dir);
    write('0002_idx.sql', '-- migrate:no-transaction\nCREATE INDEX CONCURRENTLY IF NOT EXISTS t_id_idx ON t (id);\n');
    expect(await migrate(url(), dir)).toEqual(['0002_idx.sql']);
    expect((await admin.query(`SELECT 1 FROM pg_indexes WHERE schemaname = '${schema}' AND indexname = 't_id_idx'`)).rowCount).toBe(1);
    // and the same statement WITHOUT the marker is what PostgreSQL refuses inside a transaction
    write('0003_idx2.sql', 'CREATE INDEX CONCURRENTLY IF NOT EXISTS t_id_idx2 ON t (id);\n');
    await expect(migrate(url(), dir)).rejects.toThrow(/CONCURRENTLY cannot run inside a transaction block/);
  });

  it('a schema ahead of this build is reported, not an error', async () => {
    await migrate(url(), dir);
    await admin.query(`INSERT INTO ${schema}.schema_migrations(name, checksum) VALUES ('0099_from_newer_release.sql', 'x')`);
    const log: string[] = [];
    expect(await migrate(url(), dir, undefined, { log: (m) => log.push(m) })).toEqual([]);
    expect(log.join('\n')).toContain('0099_from_newer_release.sql');
    expect((await migrationStatus(url(), dir)).unknown).toEqual(['0099_from_newer_release.sql']);
  });

  it('dryRun reports the pending files and creates nothing', async () => {
    expect(await migrate(url(), dir, undefined, { dryRun: true })).toEqual(['0001_t.sql']);
    expect((await admin.query(`SELECT to_regclass('${schema}.schema_migrations') AS t`)).rows[0].t).toBeNull();
    expect((await admin.query(`SELECT to_regclass('${schema}.t') AS t`)).rows[0].t).toBeNull();
  });

  it('does not wait for ever behind another migrator that holds the lock', async () => {
    const holder = new pg.Client({ connectionString: DATABASE_URL });
    await holder.connect();
    try {
      await holder.query('SELECT pg_advisory_lock(727274)');
      const started = Date.now();
      await expect(migrate(url(), dir, undefined, { lockWaitMs: 500 })).rejects.toThrow(/holds the lock/);
      expect(Date.now() - started).toBeLessThan(5_000);
    } finally {
      await holder.query('SELECT pg_advisory_unlock(727274)').catch(() => undefined);
      await holder.end();
    }
  });

  it('the real migration set applies, and the newest file is what /ready will require', async () => {
    const real = path.join(scratch, 'real');
    mkdirSync(real);
    for (const f of readdirSync(REAL).filter((n) => n.endsWith('.sql'))) cpSync(path.join(REAL, f), path.join(real, f));
    const applied = await migrate(url(), real);
    expect(applied.at(-1)).toBe(await latestMigrationName(real));
    expect(readFileSync(path.join(real, applied[0]!), 'utf8').length).toBeGreaterThan(0);
    expect(await migrate(url(), real)).toEqual([]);
  });
});
