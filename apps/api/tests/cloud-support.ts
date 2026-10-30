// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Shared fixtures for the cloud-data suites (delete, export, delete-account). Each suite runs on the
 * in-memory repositories and on PostgreSQL through the same `CloudFixture` interface, so both
 * implementations are held to one behaviour.
 */
import { randomUUID } from 'node:crypto';

import { AI_PROVIDER_IDS, AIGateway, MockProvider, ProviderRouter } from '@wattbyte/ai';
import pg from 'pg';

import { type App, buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { migrate } from '../src/database/migrate.js';
import type { Repositories } from '../src/database/repositories.js';
import { PostgresRepositories } from '../src/database/postgres.js';
import { makeApp, sampleInput } from './helpers.js';
import { DATABASE_URL, uniqueEmail } from './db/helpers.js';
import { spendLedger } from '../src/modules/ai/gateway.js';

export interface Auth {
  userId: string;
  email: string;
  accessToken: string;
  refreshToken: string;
  headers: { authorization: string };
}

export interface CloudFixture {
  kind: 'memory' | 'postgres';
  app: App;
  repos: Repositories;
  /** Stored rows by table for a user, counted at the storage level (SQL on PostgreSQL). */
  rowCount(table: string, userId: string): Promise<number>;
  /** Charging summaries, monthly summaries and subscriptions: no route writes them yet. */
  seedSummaries(userId: string, deviceId: string): Promise<void>;
  seedSubscription(userId: string): Promise<void>;
  /** `count` consecutive daily rows ending 2026-10-12, inserted without going through the API. */
  bulkDailyUsage(userId: string, deviceId: string, count: number): Promise<void>;
  email(prefix: string): string;
  close(): Promise<void>;
}

export type FixtureFactory = (overrides?: Record<string, string>) => Promise<CloudFixture>;

/** Free plan allows 2 AI generations per day, enough to fill the log and the quota. */
const BASE: Record<string, string> = { AI_FREE_DAILY_LIMIT: '2', AI_RATE_LIMIT_PER_MIN: '1000', CLOUD_WRITE_RATE_LIMIT_PER_MIN: '10000' };

let emailCounter = 0;

export const memoryFixture: FixtureFactory = async (overrides = {}) => {
  const ctx = await makeApp({ ...BASE, ...overrides });
  const { repos } = ctx;
  return {
    kind: 'memory',
    app: ctx.app,
    repos,
    // Memory has no SQL; the export is the storage-level view (cap lifted).
    rowCount: async (table, userId) => {
      const data = await repos.cloud.exportData(userId, Number.MAX_SAFE_INTEGER);
      if (!data) return 0;
      const byTable: Record<string, number> = {
        daily_usage: data.dailyUsage.length,
        charging_summaries: data.chargingSummaries.length,
        monthly_summaries: data.monthlySummaries.length,
        ai_generations: data.aiGenerations.length,
        devices: data.devices.length,
        subscriptions: data.subscriptions.length,
        user_settings: data.settings ? 1 : 0,
      };
      const n = byTable[table];
      if (n === undefined) throw new Error(`memory fixture cannot count ${table}`);
      return n;
    },
    seedSummaries: async (userId, deviceId) => {
      for (const [i, started] of ['2026-10-10T21:00:00.000Z', '2026-10-11T22:30:00.000Z'].entries()) {
        repos.seed.chargingSummary({
          userId,
          deviceId,
          startedAt: new Date(started),
          endedAt: new Date(new Date(started).getTime() + 3_600_000),
          startPercent: 20 + i,
          endPercent: 80 + i,
          mah: 2400.5,
          mahEstimated: i === 0,
          batteryWh: 9.24,
          wallWh: 10.871,
          estimatedCost: 0.0138,
          createdAt: new Date('2026-10-12T08:00:00.000Z'),
        });
      }
      repos.seed.monthlySummary({
        userId,
        month: '2026-09',
        mobileBytes: 5_000_000,
        wifiBytes: 90_000_000,
        wallWh: 410.25,
        chargingSessions: 31,
        estimatedCost: 0.5201,
        currency: 'PLN',
        computedAt: new Date('2026-10-01T00:05:00.000Z'),
      });
    },
    seedSubscription: async (userId) => {
      repos.seed.subscription({
        userId,
        store: 'app_store',
        productId: 'wattbyte.premium.monthly',
        originalTransactionId: `tx-${randomUUID()}`,
        status: 'active',
        expiresAt: new Date('2026-11-12T00:00:00.000Z'),
        createdAt: new Date('2026-10-12T09:00:00.000Z'),
        updatedAt: new Date('2026-10-12T09:00:00.000Z'),
      });
    },
    bulkDailyUsage: async (userId, deviceId, count) => {
      await repos.usage.upsertDaily(dailyRows(userId, deviceId, count));
    },
    email: (prefix) => `${prefix}-${emailCounter++}@test.wattbyte`,
    close: () => ctx.app.close(),
  };
};

/**
 * A connection string whose connections all use `schema` first (`search_path`). The cloud suites write and delete
 * thousands of rows and test files run in parallel on one database: each file gets a schema of its own, so they never
 * disturb tests that count whole tables in `public`, and those never disturb them.
 */
export function schemaUrl(schema: string): string {
  if (!DATABASE_URL) throw new Error('TEST_DATABASE_URL is not set');
  if (!/^[a-z][a-z0-9_]*$/.test(schema)) throw new Error('bad schema name');
  const url = new URL(DATABASE_URL);
  url.searchParams.set('options', `-c search_path=${schema}`);
  return url.toString();
}

const prepared = new Map<string, Promise<void>>();

/** Creates the schema and applies every migration to it, once per process. */
function prepareSchema(schema: string): Promise<void> {
  let ready = prepared.get(schema);
  if (!ready) {
    ready = (async () => {
      const admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
      try {
        await admin.query(`CREATE SCHEMA IF NOT EXISTS ${schema}`);
      } finally {
        await admin.end();
      }
      await migrate(schemaUrl(schema));
    })();
    prepared.set(schema, ready);
  }
  return ready;
}

/** Requires TEST_DATABASE_URL; every call builds its own app and pools on the given schema of that database. */
export function postgresFixtureIn(schema: string): FixtureFactory {
  return async (overrides = {}) => {
    await prepareSchema(schema);
    const url = schemaUrl(schema);
    const env = loadEnv({
      NODE_ENV: 'test',
      JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret',
      DATABASE_URL: url,
      ...BASE,
      ...overrides,
    });
    const repos = new PostgresRepositories(url);
    const gateway = new AIGateway({ router: new ProviderRouter(AI_PROVIDER_IDS.map((id) => new MockProvider(id)), { cooldownMs: 0 }), sleep: async () => undefined, ledger: spendLedger(env, repos) });
    const app = await buildApp({ env, repos, gateway, providerIds: [], logger: false, rateLimitMax: 100_000, aiRateLimitMax: 100_000, authRateLimitMax: 100_000, refreshRateLimitMax: 100_000 });
    await app.ready();
    const pool = new pg.Pool({ connectionString: url, max: 2 });
    return {
      kind: 'postgres',
      app,
      repos,
      rowCount: async (table, userId) => {
        if (!/^[a-z_]+$/.test(table)) throw new Error('bad table name');
        const res = await pool.query(`SELECT count(*)::int AS n FROM ${table} WHERE user_id = $1`, [userId]);
        return (res.rows[0] as { n: number }).n;
      },
      seedSummaries: async (userId, deviceId) => {
        for (const [i, started] of ['2026-10-10T21:00:00.000Z', '2026-10-11T22:30:00.000Z'].entries()) {
          await pool.query(
            `INSERT INTO charging_summaries(user_id, device_id, started_at, ended_at, start_percent, end_percent, mah, mah_estimated,
               battery_wh, wall_wh, estimated_cost, created_at)
             VALUES ($1, $2, $3::timestamptz, $3::timestamptz + interval '1 hour', $4, $5, 2400.5, $6, 9.24, 10.871, 0.0138, '2026-10-12T08:00:00.000Z')`,
            [userId, deviceId, started, 20 + i, 80 + i, i === 0],
          );
        }
        await pool.query(
          `INSERT INTO monthly_summaries(user_id, month, mobile_bytes, wifi_bytes, wall_wh, charging_sessions, estimated_cost, currency, computed_at)
           VALUES ($1, '2026-09', 5000000, 90000000, 410.25, 31, 0.5201, 'PLN', '2026-10-01T00:05:00.000Z')`,
          [userId],
        );
      },
      seedSubscription: async (userId) => {
        await pool.query(
          `INSERT INTO subscriptions(user_id, store, product_id, original_tx_id, status, expires_at, created_at, updated_at)
           VALUES ($1, 'app_store', 'wattbyte.premium.monthly', $2, 'active', '2026-11-12T00:00:00.000Z', '2026-10-12T09:00:00.000Z', '2026-10-12T09:00:00.000Z')`,
          [userId, `tx-${randomUUID()}`],
        );
      },
      bulkDailyUsage: async (userId, deviceId, count) => {
        await pool.query(
          `INSERT INTO daily_usage(user_id, device_id, date, mobile_bytes, wifi_bytes, charged_wh, wall_wh, charging_sessions, estimated_cost, currency)
           SELECT $1::uuid, $2::uuid, ('2026-10-12'::date - g), 1000, 2000, 5, 6, 1, 0.01, 'PLN' FROM generate_series(0, $3::int - 1) AS g`,
          [userId, deviceId, count],
        );
      },
      email: (prefix) => uniqueEmail(prefix),
      close: async () => {
        await app.close();
        await repos.close();
        await pool.end();
      },
    };
  };
}

export const postgresAvailable = Boolean(DATABASE_URL);

/** A second pool on the same schema for tests that talk SQL next to the fixture (triggers, the catalog). */
export function sqlPool(schema: string): pg.Pool {
  return new pg.Pool({ connectionString: schemaUrl(schema), max: 2 });
}

export function isPostgres(repos: Repositories): repos is PostgresRepositories {
  return repos instanceof PostgresRepositories;
}

function dailyRows(userId: string, deviceId: string, count: number) {
  const base = Date.UTC(2026, 9, 12);
  return Array.from({ length: count }, (_, i) => ({
    userId,
    deviceId,
    date: new Date(base - i * 86_400_000).toISOString().slice(0, 10),
    mobileBytes: 1000,
    wifiBytes: 2000,
    chargedWh: 5,
    wallWh: 6,
    chargingSessions: 1,
    estimatedCost: 0.01,
    currency: 'PLN',
    dataEstimated: false,
    energyEstimated: true,
  }));
}

// ------------------------------------------------------------------ account builders

export const SYNCED_DAYS = [
  { date: '2026-10-10', mobileBytes: 1000, wifiBytes: 5000, chargedWh: 12.5, wallWh: 14.706, chargingSessions: 2, estimatedCost: 0.0169, currency: 'PLN', dataEstimated: false, energyEstimated: true },
  { date: '2026-10-11', mobileBytes: 2000, wifiBytes: 6000, chargedWh: 8.25, wallWh: 9.706, chargingSessions: 1, estimatedCost: 0.0112, currency: 'PLN', dataEstimated: true, energyEstimated: false },
  { date: '2026-10-12', mobileBytes: 3000, wifiBytes: 7000, chargedWh: 0, wallWh: 0, chargingSessions: 0, estimatedCost: 0, currency: 'PLN', dataEstimated: false, energyEstimated: true },
] as const;

export const BATTERY = {
  modelIdentifier: 'iPhone16,1',
  designCapacityMah: 3274,
  designCapacityWh: 12.7,
  designCapacitySource: 'localDeviceDatabase',
  estimatedFullChargeCapacityMah: 3190.5,
  estimatedFullChargeCapacityWh: 12.2,
  fullChargeCapacitySource: 'androidChargeCounter',
  fullChargeCapacityConfidence: 'high',
} as const;

export interface Account extends Auth {
  deviceId: string;
  installationId: string;
  password: string;
}

export async function registerAccount(fx: CloudFixture, label: string): Promise<Auth & { password: string }> {
  const email = fx.email(label);
  const password = 'correct horse battery';
  const res = await fx.app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password, displayName: `User ${label}` } });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  const body = res.json() as { user: { id: string }; tokens: { accessToken: string; refreshToken: string } };
  return {
    userId: body.user.id,
    email,
    password,
    accessToken: body.tokens.accessToken,
    refreshToken: body.tokens.refreshToken,
    headers: { authorization: `Bearer ${body.tokens.accessToken}` },
  };
}

export async function must(res: { statusCode: number; body: string }, expected: number | number[], what: string): Promise<void> {
  const ok = Array.isArray(expected) ? expected.includes(res.statusCode) : res.statusCode === expected;
  if (!ok) throw new Error(`${what}: expected ${String(expected)}, got ${res.statusCode} ${res.body.slice(0, 300)}`);
}

/**
 * A fully populated account: a device with a battery specification, 3 synced days, saved settings
 * (unless `settings: false`), 2 AI generations (which also fills the free daily quota), 2 charging
 * summaries, 1 monthly summary and 1 store subscription.
 */
export async function seedAccount(fx: CloudFixture, label: string, options: { settings?: boolean } = {}): Promise<Account> {
  const auth = await registerAccount(fx, label);
  const installationId = `install-${label}-${randomUUID().slice(0, 12)}`;
  const dev = await fx.app.inject({
    method: 'POST',
    url: '/api/v1/devices',
    headers: auth.headers,
    payload: { installationId, platform: 'ios', model: 'iPhone 15 Pro', ...BATTERY },
  });
  await must(dev, 201, 'register device');
  const deviceId = (dev.json() as { id: string }).id;
  if (options.settings ?? true) {
    await must(
      await fx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: auth.headers, payload: { countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 } }),
      200,
      'save settings',
    );
  }
  await must(
    await fx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: auth.headers, payload: { installationId, days: SYNCED_DAYS } }),
    200,
    'sync usage',
  );
  for (let i = 0; i < 2; i++) {
    await must(
      await fx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: auth.headers, payload: { input: sampleInput } }),
      200,
      `ai generation ${i + 1}`,
    );
  }
  await fx.seedSummaries(auth.userId, deviceId);
  await fx.seedSubscription(auth.userId);
  return { ...auth, deviceId, installationId };
}

// ------------------------------------------------------------------ http helpers

export const getExport = (fx: CloudFixture, headers: Auth['headers'], query = '') =>
  fx.app.inject({ method: 'GET', url: `/api/v1/me/export${query}`, headers });

export const deleteCloudData = (fx: CloudFixture, headers: Auth['headers'], query = '') =>
  fx.app.inject({ method: 'DELETE', url: `/api/v1/me/cloud-data${query}`, headers });

/** The export without its timestamp, for "unchanged" comparisons. */
export async function exportBody(fx: CloudFixture, headers: Auth['headers']): Promise<Record<string, unknown>> {
  const res = await getExport(fx, headers);
  await must(res, 200, 'export');
  const { exportedAt: _ignored, ...rest } = res.json() as Record<string, unknown>;
  return rest;
}

// ------------------------------------------------------------------ RFC 4180 reader (test oracle)

/** Strict RFC 4180 parser: CRLF records, quoted fields with doubled quotes; throws on malformed input. */
export function parseCsv(text: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = '';
  let quoted = false;
  let i = 0;
  while (i < text.length) {
    const c = text[i]!;
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        quoted = false;
        i += 1;
        const next = text[i];
        if (next !== undefined && next !== ',' && next !== '\r') throw new Error(`junk after closing quote at ${i}`);
        continue;
      }
      field += c;
      i += 1;
      continue;
    }
    if (c === '"') {
      if (field !== '') throw new Error(`quote inside unquoted field at ${i}`);
      quoted = true;
      i += 1;
    } else if (c === ',') {
      record.push(field);
      field = '';
      i += 1;
    } else if (c === '\r') {
      if (text[i + 1] !== '\n') throw new Error(`bare CR at ${i}`);
      record.push(field);
      records.push(record);
      record = [];
      field = '';
      i += 2;
    } else if (c === '\n') {
      throw new Error(`bare LF at ${i}`);
    } else {
      field += c;
      i += 1;
    }
  }
  if (quoted) throw new Error('unterminated quoted field');
  if (field !== '' || record.length > 0) {
    record.push(field);
    records.push(record);
  }
  return records;
}
