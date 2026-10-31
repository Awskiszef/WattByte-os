// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Runs the API test suite WITH the PostgreSQL suites (audit E-16): the local equivalent of the CI `node` job's database part.
//
//   pnpm db:up && pnpm test:db          (WB_PG_PORT=55432 pnpm db:up && WB_PG_PORT=55432 pnpm test:db)
//
// Creates the `wattbyte_test` database next to the development one when it does not exist yet (an old volume predates
// infrastructure/docker/initdb), exports TEST_DATABASE_URL and REQUIRE_PG_TESTS=1 (a missing database fails instead of
// skipping) and runs `pnpm --filter @wattbyte/api test`. Extra arguments go to vitest. The development database is not touched.
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** `{ adminUrl, testUrl }` for the docker-compose database on `port` (the throw-away local credentials). */
export function localUrls(env = process.env) {
  const port = env.WB_PG_PORT || '5432';
  return {
    adminUrl: env.TEST_DB_ADMIN_URL || `postgres://wattbyte:wattbyte@localhost:${port}/wattbyte`,
    testUrl: env.TEST_DATABASE_URL || `postgres://wattbyte:wattbyte@localhost:${port}/wattbyte_test`,
  };
}

export async function ensureTestDatabase(adminUrl, name = 'wattbyte_test') {
  if (!/^[a-z0-9_]+$/.test(name)) throw new Error(`unsafe database name ${name}`);
  const pg = createRequire(path.join(root, 'apps', 'api', 'package.json'))('pg');
  const { Client } = pg.default ?? pg;
  const client = new Client({ connectionString: adminUrl, connectionTimeoutMillis: 5000 });
  await client.connect();
  try {
    const exists = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [name]);
    if (exists.rowCount === 0) {
      await client.query(`CREATE DATABASE ${name}`);
      return true;
    }
    return false;
  } finally {
    await client.end();
  }
}

if (isMainModule(import.meta.url)) {
  const { adminUrl, testUrl } = localUrls();
  try {
    const created = await ensureTestDatabase(adminUrl);
    console.log(created ? 'created database wattbyte_test' : 'database wattbyte_test exists');
  } catch (e) {
    console.error(`cannot reach the local PostgreSQL (${e instanceof Error ? e.message || e.code || e.errors?.[0]?.code || e.name : e}); start it with "pnpm db:up" (WB_PG_PORT must match)`);
    process.exit(2);
  }
  const res = spawnSync('pnpm', ['--filter', '@wattbyte/api', 'test', ...process.argv.slice(2)], {
    cwd: root,
    stdio: 'inherit',
    env: { ...process.env, TEST_DATABASE_URL: testUrl, REQUIRE_PG_TESTS: '1' },
  });
  process.exit(res.status ?? 1);
}
