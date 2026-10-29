import pg from 'pg';
import { describe, expect, it } from 'vitest';

import { latestMigrationName } from '../../src/database/migrate.js';
import { DATABASE_URL } from './helpers.js';

/**
 * Every PostgreSQL suite is `describe.skipIf(!TEST_DATABASE_URL)`: without the variable they disappear and the run is
 * green (H-08). Where the PostgreSQL suites are REQUIRED (CI sets REQUIRE_PG_TESTS=1) this file turns "skipped" into a failure,
 * and proves the database behind the variable is really reachable and migrated.
 */
const required = process.env.REQUIRE_PG_TESTS === '1';

if (!DATABASE_URL && !required) {
  console.warn('TEST_DATABASE_URL is not set: the PostgreSQL integration suites (tests/db/*) are SKIPPED, not passed.');
}

describe('PostgreSQL suites are not silently skipped', () => {
  it.runIf(required)('TEST_DATABASE_URL is set where the suites are required (REQUIRE_PG_TESTS=1)', () => {
    expect(DATABASE_URL, 'REQUIRE_PG_TESTS=1 but TEST_DATABASE_URL is not set: the tests/db suites would be skipped').toBeTruthy();
  });

  it.runIf(required && !!DATABASE_URL)('the database answers and has every migration of this build', async () => {
    const pool = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    try {
      const { migrate } = await import('../../src/database/migrate.js');
      await migrate(DATABASE_URL!);
      const latest = (await pool.query('SELECT max(name) AS latest FROM schema_migrations')).rows[0] as { latest: string };
      expect(latest.latest).toBe(await latestMigrationName());
    } finally {
      await pool.end();
    }
  });
});
