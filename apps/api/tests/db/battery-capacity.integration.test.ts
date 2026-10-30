// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import pg from 'pg';
import { afterAll, vi } from 'vitest';

import { describeBatteryCapacity } from '../battery-capacity-suite.js';
import { postgresAvailable, postgresFixtureIn } from '../cloud-support.js';
import { DATABASE_URL } from './helpers.js';

// Own schema (created and migrated by the fixture): this file never touches the tables of other files.
const SCHEMA = 'wb_battery_capacity';

// Every register runs a scrypt hash (N=2^16); on a loaded machine it takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The behaviour suite shared with the in-memory repositories: the SQL upsert must agree with the memory twin.
describeBatteryCapacity('PostgreSQL', postgresFixtureIn(SCHEMA), postgresAvailable);

afterAll(async () => {
  if (!DATABASE_URL) return;
  const admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
  try {
    await admin.query(`DROP SCHEMA IF EXISTS ${SCHEMA} CASCADE`);
  } finally {
    await admin.end();
  }
});
