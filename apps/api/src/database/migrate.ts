import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

import pg from 'pg';

import { isMainModule } from '../util/is-main.js';
import { resolveDatabaseConnection } from './connection.js';

const MIGRATION_LOCK_KEY = 727_274;

/** First line of a migration that cannot run inside a transaction (CREATE INDEX CONCURRENTLY, ALTER TYPE ... ADD VALUE). */
export const NO_TRANSACTION_MARKER = '-- migrate:no-transaction';

export interface MigrationFile {
  name: string;
  sql: string;
  /** sha256 of the file with line endings normalised (a checkout with CRLF must not look like an edited migration). */
  checksum: string;
  transactional: boolean;
}

export interface MigrateOptions {
  /** A DDL statement that cannot get its lock within this time fails (and, in a transaction, rolls back) instead of queueing behind traffic and blocking every query that follows it. */
  lockTimeoutMs?: number;
  /** One migration may not run longer than this. */
  statementTimeoutMs?: number;
  /** How long to wait for another migrator that holds the migration lock. */
  lockWaitMs?: number;
  /** Progress lines (names only, never SQL or connection details). */
  log?: (message: string) => void;
  /** Only report what would be applied: nothing is created, applied or recorded. */
  dryRun?: boolean;
}

export interface MigrationStatus {
  /** In the directory, not applied yet (in the order they would run). */
  pending: string[];
  /** Applied, and the file is unchanged. */
  applied: string[];
  /** Applied, but the file now differs from what was applied. A migration is never edited after release: add a new one. */
  modified: string[];
  /** Applied by a newer release; this build has no file for them (rolling deploy). */
  unknown: string[];
  /** Applied before checksums existed; their checksum is recorded the first time `migrate` runs. */
  unverified: string[];
}

export class MigrationError extends Error {
  constructor(message: string, readonly status?: MigrationStatus) {
    super(message);
    this.name = 'MigrationError';
  }
}

export const DEFAULT_MIGRATE_OPTIONS = { lockTimeoutMs: 10_000, statementTimeoutMs: 600_000, lockWaitMs: 60_000 } as const;

export function checksumOf(sql: string): string {
  return createHash('sha256').update(sql.replace(/\r\n/g, '\n')).digest('hex');
}

export async function readMigrations(dir = defaultDir()): Promise<MigrationFile[]> {
  const names = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  return Promise.all(
    names.map(async (name) => {
      const sql = await readFile(path.join(dir, name), 'utf8');
      return { name, sql, checksum: checksumOf(sql), transactional: !sql.trimStart().startsWith(NO_TRANSACTION_MARKER) };
    }),
  );
}

/** Name of the newest migration this build ships: what the schema must have reached for the API to serve (see /ready). */
export async function latestMigrationName(dir = defaultDir()): Promise<string | undefined> {
  const files = await readMigrations(dir);
  return files.at(-1)?.name;
}

interface AppliedRow {
  name: string;
  checksum: string | null;
}

async function ensureTable(client: pg.Client): Promise<void> {
  await client.query('CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
  await client.query('ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum text');
}

function classify(files: MigrationFile[], applied: AppliedRow[]): MigrationStatus {
  const byName = new Map(files.map((f) => [f.name, f]));
  const status: MigrationStatus = { pending: [], applied: [], modified: [], unknown: [], unverified: [] };
  const done = new Set(applied.map((a) => a.name));
  for (const a of applied) {
    const file = byName.get(a.name);
    if (!file) status.unknown.push(a.name);
    else if (a.checksum === null) status.unverified.push(a.name);
    else if (a.checksum !== file.checksum) status.modified.push(a.name);
    else status.applied.push(a.name);
  }
  for (const f of files) if (!done.has(f.name)) status.pending.push(f.name);
  return status;
}

/** Waits for the migration lock without blocking for ever behind a stuck migrator. */
async function acquireLock(client: pg.Client, waitMs: number): Promise<void> {
  const deadline = Date.now() + waitMs;
  for (;;) {
    const res = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [MIGRATION_LOCK_KEY]);
    if ((res.rows[0] as { locked: boolean }).locked) return;
    if (Date.now() >= deadline) throw new MigrationError(`another migration run holds the lock (waited ${Math.round(waitMs / 1000)} s)`);
    await sleep(250);
  }
}

async function readApplied(client: pg.Client): Promise<AppliedRow[]> {
  return (await client.query('SELECT name, checksum FROM schema_migrations ORDER BY name')).rows as AppliedRow[];
}

/**
 * Applies `migrations/*.sql` in name order, once each. Rails (C-07):
 *  - each migration runs under `lock_timeout` and `statement_timeout`;
 *  - the sha256 of every applied file is recorded; a file edited after it was applied stops the run (nothing is applied);
 *  - concurrent migrators are serialised by an advisory lock that is waited for with a limit;
 *  - a file starting with `-- migrate:no-transaction` runs outside a transaction (it must be idempotent: IF NOT EXISTS).
 * Usage: `pnpm --filter @wattbyte/api migrate` with DATABASE_URL set (`--status` only reports).
 */
export async function migrate(
  connectionString: string,
  dir = defaultDir(),
  ssl?: pg.ClientConfig['ssl'],
  options: MigrateOptions = {},
): Promise<string[]> {
  const { lockTimeoutMs, statementTimeoutMs, lockWaitMs } = { ...DEFAULT_MIGRATE_OPTIONS, ...options };
  const log = options.log ?? (() => undefined);
  if (options.dryRun) {
    // Read-only: no table, no column, no lock, nothing recorded.
    const status = await migrationStatus(connectionString, dir, ssl);
    if (status.modified.length > 0) throw new MigrationError(`migration file(s) changed after they were applied: ${status.modified.join(', ')}.`, status);
    return status.pending;
  }
  const files = await readMigrations(dir);
  const client = new pg.Client({ connectionString, ssl });
  // An error on the idle session (server restart) must not become an unhandled 'error' event.
  client.on('error', () => undefined);
  await client.connect();
  const applied: string[] = [];
  let locked = false;
  try {
    await acquireLock(client, lockWaitMs);
    locked = true;
    await ensureTable(client);
    const status = classify(files, await readApplied(client));
    if (status.modified.length > 0) {
      throw new MigrationError(
        `migration file(s) changed after they were applied: ${status.modified.join(', ')}. Restore the original file and add a new migration instead.`,
        status,
      );
    }
    if (status.unknown.length > 0) log(`schema is ahead of this build (applied by a newer release): ${status.unknown.join(', ')}`);
    // First run after checksums were introduced: record what is on disk for what is already applied.
    const byName = new Map(files.map((f) => [f.name, f]));
    for (const name of status.unverified) {
      await client.query('UPDATE schema_migrations SET checksum = $2 WHERE name = $1 AND checksum IS NULL', [name, byName.get(name)!.checksum]);
      log(`recorded checksum of ${name}`);
    }

    for (const file of files.filter((f) => status.pending.includes(f.name))) {
      log(`applying ${file.name}`);
      if (file.transactional) {
        await client.query('BEGIN');
        try {
          await client.query(`SET LOCAL lock_timeout = ${Math.trunc(lockTimeoutMs)}`);
          await client.query(`SET LOCAL statement_timeout = ${Math.trunc(statementTimeoutMs)}`);
          await client.query(file.sql);
          await client.query('INSERT INTO schema_migrations(name, checksum) VALUES ($1, $2)', [file.name, file.checksum]);
          await client.query('COMMIT');
        } catch (e) {
          await client.query('ROLLBACK').catch(() => undefined);
          throw e;
        }
      } else {
        await client.query(`SET lock_timeout = ${Math.trunc(lockTimeoutMs)}`);
        await client.query(`SET statement_timeout = ${Math.trunc(statementTimeoutMs)}`);
        try {
          await client.query(file.sql);
        } finally {
          await client.query('RESET lock_timeout').catch(() => undefined);
          await client.query('RESET statement_timeout').catch(() => undefined);
        }
        await client.query('INSERT INTO schema_migrations(name, checksum) VALUES ($1, $2)', [file.name, file.checksum]);
      }
      applied.push(file.name);
    }
    return applied;
  } finally {
    if (locked) await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY]).catch(() => undefined);
    await client.end().catch(() => undefined);
  }
}

/** Read-only comparison of the database with the migration files (nothing is created, applied or recorded). */
export async function migrationStatus(connectionString: string, dir = defaultDir(), ssl?: pg.ClientConfig['ssl']): Promise<MigrationStatus> {
  const files = await readMigrations(dir);
  const client = new pg.Client({ connectionString, ssl });
  client.on('error', () => undefined);
  await client.connect();
  try {
    const exists = (await client.query("SELECT to_regclass('schema_migrations') IS NOT NULL AS present")).rows[0] as { present: boolean };
    if (!exists.present) return classify(files, []);
    const hasChecksum = (await client.query("SELECT 1 FROM information_schema.columns WHERE table_name = 'schema_migrations' AND column_name = 'checksum' AND table_schema = current_schema()")).rowCount;
    const rows = hasChecksum
      ? await readApplied(client)
      : ((await client.query('SELECT name FROM schema_migrations ORDER BY name')).rows as { name: string }[]).map((r) => ({ name: r.name, checksum: null }));
    return classify(files, rows);
  } finally {
    await client.end().catch(() => undefined);
  }
}

function defaultDir(): string {
  return path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations');
}

function envMs(name: string): number | undefined {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return undefined;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 1) throw new Error(`${name} must be a positive integer (milliseconds)`);
  return n;
}

if (isMainModule(import.meta.url)) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is not set');
    process.exit(1);
  }
  const statusOnly = process.argv.includes('--status');
  const dryRun = process.argv.includes('--dry-run');
  try {
    const db = resolveDatabaseConnection({ url, databaseSsl: process.env.DATABASE_SSL, caFile: process.env.DATABASE_SSL_CA_FILE });
    if (statusOnly) {
      const s = await migrationStatus(db.connectionString, undefined, db.ssl);
      console.warn(JSON.stringify(s, null, 2));
      process.exit(s.modified.length > 0 ? 1 : 0);
    }
    const applied = await migrate(db.connectionString, undefined, db.ssl, {
      lockTimeoutMs: envMs('MIGRATE_LOCK_TIMEOUT_MS'),
      statementTimeoutMs: envMs('MIGRATE_STATEMENT_TIMEOUT_MS'),
      lockWaitMs: envMs('MIGRATE_LOCK_WAIT_MS'),
      log: (m) => console.warn(m),
      dryRun,
    });
    if (dryRun) console.warn(applied.length ? `would apply: ${applied.join(', ')}` : 'schema up to date');
    else console.warn(applied.length ? `applied: ${applied.join(', ')}` : 'schema up to date');
  } catch (e) {
    console.error(e instanceof MigrationError ? e.message : e);
    process.exit(1);
  }
}
