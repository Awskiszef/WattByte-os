import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';

import { isMainModule } from '../util/is-main.js';

/**
 * Applies `migrations/*.sql` in name order, once each, each in a transaction.
 * Usage: `pnpm --filter @wattbyte/api migrate` with DATABASE_URL set.
 */
export async function migrate(connectionString: string, dir = defaultDir()): Promise<string[]> {
  const client = new pg.Client({ connectionString });
  await client.connect();
  const applied: string[] = [];
  try {
    // Serialise concurrent migrators (several instances starting together).
    await client.query('SELECT pg_advisory_lock(727274)');
    await client.query(
      'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
    );
    const done = new Set((await client.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name as string));
    const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      if (done.has(file)) continue;
      const sql = await readFile(path.join(dir, file), 'utf8');
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations(name) VALUES ($1)', [file]);
        await client.query('COMMIT');
        applied.push(file);
      } catch (e) {
        await client.query('ROLLBACK');
        throw e;
      }
    }
    return applied;
  } finally {
    await client.query('SELECT pg_advisory_unlock(727274)').catch(() => undefined);
    await client.end();
  }
}

function defaultDir(): string {
  return path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations');
}

if (isMainModule(import.meta.url)) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is not set');
    process.exit(1);
  }
  migrate(url)
    .then((applied) => {
      console.warn(applied.length ? `applied: ${applied.join(', ')}` : 'schema up to date');
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
