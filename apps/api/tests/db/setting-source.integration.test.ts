import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { schemaUrl } from '../cloud-support.js';
import { describeSettingSources } from '../setting-source-suite.js';
import { closePgApp, DATABASE_URL, makePgApp, register, uniqueEmail } from './helpers.js';

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The behaviour suite shared with the in-memory repositories.
describeSettingSources(
  'PostgreSQL',
  async () => {
    const ctx = await makePgApp();
    return {
      app: ctx.app,
      register: async (prefix) => ({ authorization: `Bearer ${(await register(ctx.app, uniqueEmail(prefix))).tokens.accessToken}` }),
      close: () => closePgApp(ctx),
    };
  },
  Boolean(DATABASE_URL),
);

/**
 * Migration 0007 on real data. The shared test schema is never touched: the upgrade runs in a schema of its own with every
 * migration before 0007 applied first, so the "legacy" database really has never seen 0007 (an upgrade, not a fresh install).
 */
const MIGRATIONS = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'src', 'database', 'migrations');
const TARGET = '0007_setting_sources.sql';
const tag = `${process.pid}_${Date.now().toString(36)}`;
const UPGRADE_SCHEMA = `wb_src_up_${tag}`;
const FRESH_SCHEMA = `wb_src_fresh_${tag}`;

describe.skipIf(!DATABASE_URL)('migration 0007 setting sources (PostgreSQL)', () => {
  let admin: pg.Pool;
  let upgrade: pg.Pool;
  let fresh: pg.Pool;
  let scratch: string;
  let appliedByUpgrade: string[];
  let appliedByFresh: string[];
  let legacyUser: string;

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    await admin.query(`CREATE SCHEMA ${UPGRADE_SCHEMA}`);
    await admin.query(`CREATE SCHEMA ${FRESH_SCHEMA}`);
    upgrade = new pg.Pool({ connectionString: schemaUrl(UPGRADE_SCHEMA), max: 2 });
    fresh = new pg.Pool({ connectionString: schemaUrl(FRESH_SCHEMA), max: 2 });

    scratch = mkdtempSync(path.join(tmpdir(), 'wb-mig-src-'));
    const before = path.join(scratch, 'before');
    mkdirSync(before);
    for (const f of readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql') && n < TARGET)) cpSync(path.join(MIGRATIONS, f), path.join(before, f));
    const applied = await migrate(schemaUrl(UPGRADE_SCHEMA), before);
    expect(applied).not.toContain(TARGET);
    const old = await upgrade.query(`SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'user_settings'`, [UPGRADE_SCHEMA]);
    expect(old.rows.map((r) => r.column_name)).not.toContain('currency_source');

    // A settings row exactly as the previous API wrote it: values, no origins.
    legacyUser = ((await upgrade.query(`INSERT INTO users(email) VALUES ('legacy-src@test.wattbyte') RETURNING id`)).rows[0] as { id: string }).id;
    await upgrade.query(
      `INSERT INTO user_settings(user_id, country_code, currency, electricity_price_mode, manual_price_per_kwh) VALUES ($1, 'PL', 'PLN', 'manual', 0.95)`,
      [legacyUser],
    );

    appliedByUpgrade = await migrate(schemaUrl(UPGRADE_SCHEMA), MIGRATIONS);
    appliedByFresh = await migrate(schemaUrl(FRESH_SCHEMA), MIGRATIONS);
  });

  afterAll(async () => {
    await upgrade?.end();
    await fresh?.end();
    await admin?.query(`DROP SCHEMA IF EXISTS ${UPGRADE_SCHEMA} CASCADE`);
    await admin?.query(`DROP SCHEMA IF EXISTS ${FRESH_SCHEMA} CASCADE`);
    await admin?.end();
    if (scratch) rmSync(scratch, { recursive: true, force: true });
  });

  it('applies the new migration (and any later one) to the legacy database, and every migration to the fresh one', () => {
    // Not a fixed list: the next migration must not break this test (H-09).
    const fromTarget = readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql') && n >= TARGET).sort();
    expect(appliedByUpgrade).toEqual(fromTarget);
    expect(appliedByFresh).toContain(TARGET);
  });

  it('keeps the legacy row untouched and gives it NULL origins: nothing is inferred about how the old values were chosen', async () => {
    const res = await upgrade.query(`SELECT * FROM user_settings WHERE user_id = $1`, [legacyUser]);
    expect(res.rows).toHaveLength(1);
    expect(res.rows[0]).toMatchObject({
      country_code: 'PL',
      currency: 'PLN',
      electricity_price_mode: 'manual',
      country_code_source: null,
      currency_source: null,
      electricity_price_source: null,
    });
    expect(Number(res.rows[0].manual_price_per_kwh)).toBe(0.95);
  });

  it('the columns are nullable, and the database itself refuses an origin outside the contract (accountSynced included)', async () => {
    const cols = await fresh.query(
      `SELECT column_name, is_nullable FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'user_settings' AND column_name IN ('country_code_source', 'currency_source', 'electricity_price_source')`,
      [FRESH_SCHEMA],
    );
    expect(cols.rows).toHaveLength(3);
    expect(cols.rows.every((r) => r.is_nullable === 'YES')).toBe(true);
    const user = ((await fresh.query(`INSERT INTO users(email) VALUES ('check-src@test.wattbyte') RETURNING id`)).rows[0] as { id: string }).id;
    for (const column of ['country_code_source', 'currency_source', 'electricity_price_source']) {
      for (const bad of ['accountSynced', 'automatic', '']) {
        await expect(fresh.query(`INSERT INTO user_settings(user_id, ${column}) VALUES ($1, $2)`, [user, bad]), `${column}=${bad}`).rejects.toThrow(/check constraint/);
      }
      for (const good of ['detected', 'manual', 'migratedManual']) {
        await fresh.query(`DELETE FROM user_settings WHERE user_id = $1`, [user]);
        await fresh.query(`INSERT INTO user_settings(user_id, ${column}) VALUES ($1, $2)`, [user, good]);
      }
    }
  });
});
