// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { schemaUrl } from '../cloud-support.js';
import { DATABASE_URL } from './helpers.js';

/**
 * Migration 0006 on real data. The shared test schema is never touched: both scenarios run in schemas of their own
 * (connection option `search_path`), and the migrations before 0006 are copied to a scratch directory so the
 * "legacy" database really is a database that has never seen 0006 (an upgrade, not a fresh install).
 */
const MIGRATIONS = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'src', 'database', 'migrations');
const TARGET = '0006_battery_capacity_semantics.sql';

const tag = `${process.pid}_${Date.now().toString(36)}`;
const UPGRADE_SCHEMA = `wb_bat_up_${tag}`;
const FRESH_SCHEMA = `wb_bat_fresh_${tag}`;

const DESIGN_SOURCES = ['manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual', 'unknown'];

interface LegacyRow {
  label: string;
  source: string | null;
  mah: number | null;
  wh: number | null;
}

/** One legacy row per old source, plus the awkward combinations the old API accepted. */
const LEGACY: LegacyRow[] = [
  { label: 'localDatabase', source: 'localDatabase', mah: 3274, wh: 12.7 },
  { label: 'backendDatabase', source: 'backendDatabase', mah: 4575, wh: 17.6 },
  { label: 'manual', source: 'manual', mah: 4000, wh: null },
  { label: 'unknown', source: 'unknown', mah: null, wh: null },
  { label: 'unknown with a number', source: 'unknown', mah: 3333.3, wh: 11.1 },
  { label: 'system', source: 'system', mah: 3600.5, wh: 13.9 },
  { label: 'system without Wh', source: 'system', mah: 3501.5, wh: null },
  { label: 'system with Wh only', source: 'system', mah: null, wh: 13.7 },
  { label: 'estimated', source: 'estimated', mah: 2800, wh: null },
  { label: 'estimated with Wh', source: 'estimated', mah: 2900.5, wh: 11.2 },
  { label: 'no source, with a number', source: null, mah: 3500, wh: 13.5 },
  { label: 'no source, Wh only', source: null, mah: null, wh: 13.4 },
  { label: 'all null', source: null, mah: null, wh: null },
  { label: 'local without mAh, Wh only', source: 'localDatabase', mah: null, wh: 12.3 },
  { label: 'manual without numbers', source: 'manual', mah: null, wh: null },
];

describe.skipIf(!DATABASE_URL)('migration 0006 battery capacity semantics (PostgreSQL)', () => {
  let admin: pg.Pool;
  let upgrade: pg.Pool;
  let fresh: pg.Pool;
  let scratch: string;
  let ids: Map<string, string>;
  let appliedByUpgrade: string[];
  let appliedByFresh: string[];

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 1 });
    await admin.query(`CREATE SCHEMA ${UPGRADE_SCHEMA}`);
    await admin.query(`CREATE SCHEMA ${FRESH_SCHEMA}`);
    upgrade = new pg.Pool({ connectionString: schemaUrl(UPGRADE_SCHEMA), max: 2 });
    fresh = new pg.Pool({ connectionString: schemaUrl(FRESH_SCHEMA), max: 2 });

    // The database as it was before 0006: every earlier migration, none of 0006 or later.
    scratch = mkdtempSync(path.join(tmpdir(), 'wb-mig-'));
    const before = path.join(scratch, 'before');
    mkdirSync(before);
    for (const f of readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql') && n < TARGET)) cpSync(path.join(MIGRATIONS, f), path.join(before, f));
    const applied = await migrate(schemaUrl(UPGRADE_SCHEMA), before);
    expect(applied.length).toBeGreaterThanOrEqual(5);
    expect(applied).not.toContain(TARGET);
    const oldColumns = await upgrade.query(`SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'devices'`, [UPGRADE_SCHEMA]);
    expect(oldColumns.rows.map((r) => r.column_name)).toEqual(expect.arrayContaining(['battery_capacity_mah', 'battery_capacity_wh', 'battery_specification_source']));

    // Legacy rows, written exactly as the old API wrote them.
    const user = (await upgrade.query(`INSERT INTO users(email) VALUES ('legacy@test.wattbyte') RETURNING id`)).rows[0] as { id: string };
    ids = new Map();
    for (const [i, row] of LEGACY.entries()) {
      const res = await upgrade.query(
        `INSERT INTO devices(user_id, installation_id, platform, model_identifier, battery_capacity_mah, battery_capacity_wh, battery_specification_source)
         VALUES ($1, $2, 'android', $3, $4, $5, $6) RETURNING id`,
        [user.id, `legacy-install-${i}`, `model-${i}`, row.mah, row.wh, row.source],
      );
      ids.set(row.label, (res.rows[0] as { id: string }).id);
    }

    // The upgrade: only the missing migration runs. The fresh install runs everything on an empty schema.
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

  interface Migrated {
    design_capacity_mah: string | null;
    design_capacity_wh: string | null;
    design_capacity_source: string | null;
    estimated_full_charge_capacity_mah: string | null;
    estimated_full_charge_capacity_wh: string | null;
    full_charge_capacity_source: string | null;
    full_charge_capacity_confidence: string | null;
  }
  const num = (v: string | null): number | null => (v == null ? null : Number(v));
  const migrated = async (label: string): Promise<Migrated> => {
    const res = await upgrade.query(`SELECT * FROM devices WHERE id = $1`, [ids.get(label)]);
    expect(res.rows, label).toHaveLength(1);
    return res.rows[0] as Migrated;
  };
  const design = (r: Migrated) => ({ mah: num(r.design_capacity_mah), wh: num(r.design_capacity_wh), source: r.design_capacity_source });
  const estimate = (r: Migrated) => ({
    mah: num(r.estimated_full_charge_capacity_mah),
    wh: num(r.estimated_full_charge_capacity_wh),
    source: r.full_charge_capacity_source,
    confidence: r.full_charge_capacity_confidence,
  });
  const NO_ESTIMATE = { mah: null, wh: null, source: null, confidence: null };
  const EMPTY_DESIGN = { mah: null, wh: null, source: null };

  it('applied the new migration first to the legacy database, and every migration to the fresh one', () => {
    // 0006 is the first of whatever is still to apply (later migrations may exist; they run on this history too).
    expect(appliedByUpgrade[0]).toBe(TARGET);
    expect(appliedByFresh).toContain(TARGET);
    expect(appliedByFresh.length).toBeGreaterThanOrEqual(6);
  });

  it('keeps every legacy row (nothing is deleted or duplicated)', async () => {
    const res = await upgrade.query(`SELECT count(*)::int AS n FROM devices`);
    expect((res.rows[0] as { n: number }).n).toBe(LEGACY.length);
  });

  describe('catalog and manual sources stay design capacity', () => {
    it('localDatabase -> localDeviceDatabase, mAh and Wh kept, no estimate', async () => {
      const r = await migrated('localDatabase');
      expect(design(r)).toEqual({ mah: 3274, wh: 12.7, source: 'localDeviceDatabase' });
      expect(estimate(r)).toEqual(NO_ESTIMATE);
    });

    it('backendDatabase -> backendDeviceDatabase, mAh and Wh kept, no estimate', async () => {
      const r = await migrated('backendDatabase');
      expect(design(r)).toEqual({ mah: 4575, wh: 17.6, source: 'backendDeviceDatabase' });
      expect(estimate(r)).toEqual(NO_ESTIMATE);
    });

    it('manual stays manual, numbers kept', async () => {
      const r = await migrated('manual');
      expect(design(r)).toEqual({ mah: 4000, wh: null, source: 'manual' });
      expect(estimate(r)).toEqual(NO_ESTIMATE);
    });

    it('manual and local rows without numbers keep their source; a lone design Wh is dropped (Wh needs mAh)', async () => {
      expect(design(await migrated('manual without numbers'))).toEqual({ mah: null, wh: null, source: 'manual' });
      expect(design(await migrated('local without mAh, Wh only'))).toEqual({ mah: null, wh: null, source: 'localDeviceDatabase' });
    });

    it('unknown stays unknown and carries no numbers, even when the old row had some', async () => {
      expect(design(await migrated('unknown'))).toEqual({ mah: null, wh: null, source: 'unknown' });
      const withNumber = await migrated('unknown with a number');
      expect(design(withNumber)).toEqual({ mah: null, wh: null, source: 'unknown' });
      expect(estimate(withNumber)).toEqual(NO_ESTIMATE);
    });
  });

  describe('a system measurement is NEVER a design capacity', () => {
    it('system -> estimate androidChargeCounter / high, design cleared', async () => {
      const r = await migrated('system');
      expect(estimate(r)).toEqual({ mah: 3600.5, wh: 13.9, source: 'androidChargeCounter', confidence: 'high' });
      expect(design(r)).toEqual(EMPTY_DESIGN);
      expect(estimate(await migrated('system without Wh'))).toEqual({ mah: 3501.5, wh: null, source: 'androidChargeCounter', confidence: 'high' });
      expect(design(await migrated('system without Wh'))).toEqual(EMPTY_DESIGN);
    });

    it('estimated -> estimate androidChargeCounter / low, design cleared', async () => {
      expect(estimate(await migrated('estimated'))).toEqual({ mah: 2800, wh: null, source: 'androidChargeCounter', confidence: 'low' });
      expect(design(await migrated('estimated'))).toEqual(EMPTY_DESIGN);
      expect(estimate(await migrated('estimated with Wh'))).toEqual({ mah: 2900.5, wh: 11.2, source: 'androidChargeCounter', confidence: 'low' });
      expect(design(await migrated('estimated with Wh'))).toEqual(EMPTY_DESIGN);
    });

    it('a system row with Wh only has no mAh to extrapolate from: no estimate is invented, design cleared', async () => {
      const r = await migrated('system with Wh only');
      expect(estimate(r)).toEqual(NO_ESTIMATE);
      expect(design(r)).toEqual(EMPTY_DESIGN);
    });

    it('a number without a source is not promoted to design capacity', async () => {
      for (const label of ['no source, with a number', 'no source, Wh only']) {
        const r = await migrated(label);
        expect(design(r), label).toEqual(EMPTY_DESIGN);
        expect(estimate(r), label).toEqual(NO_ESTIMATE);
      }
    });

    it('no measurement value appears in any design column, and every design number has a design source', async () => {
      // 3600.5, 3501.5, 2800 and 2900.5 are the measurements of the legacy rows; no design row has these values.
      const leaked = await upgrade.query(
        `SELECT count(*)::int AS n FROM devices WHERE design_capacity_mah IN (3600.5, 3501.5, 2800, 2900.5, 3333.3, 3500)
            OR design_capacity_wh IN (13.9, 13.7, 11.2, 11.1, 13.5, 13.4)`,
      );
      expect((leaked.rows[0] as { n: number }).n).toBe(0);
      const sources = await upgrade.query(`SELECT DISTINCT design_capacity_source AS s FROM devices WHERE design_capacity_mah IS NOT NULL OR design_capacity_wh IS NOT NULL`);
      for (const row of sources.rows as { s: string | null }[]) expect(DESIGN_SOURCES.filter((s) => s !== 'unknown')).toContain(row.s);
      const bySource = await upgrade.query(`SELECT DISTINCT design_capacity_source AS s FROM devices`);
      for (const row of bySource.rows as { s: string | null }[]) {
        if (row.s !== null) expect(DESIGN_SOURCES).toContain(row.s);
      }
      // The estimate columns hold exactly the four rows that had a mAh measurement.
      const estimates = await upgrade.query(`SELECT count(*)::int AS n FROM devices WHERE estimated_full_charge_capacity_mah IS NOT NULL`);
      expect((estimates.rows[0] as { n: number }).n).toBe(4);
    });

    it('rows that never had a battery stay empty', async () => {
      const r = await migrated('all null');
      expect(design(r)).toEqual(EMPTY_DESIGN);
      expect(estimate(r)).toEqual(NO_ESTIMATE);
    });
  });

  describe('the old columns and constraints are gone, the new ones named', () => {
    const columns = async (pool: pg.Pool, schema: string) =>
      (
        await pool.query(
          `SELECT column_name, data_type, numeric_precision, numeric_scale, is_nullable FROM information_schema.columns
            WHERE table_schema = $1 AND table_name = 'devices' ORDER BY column_name`,
          [schema],
        )
      ).rows;
    const constraints = async (pool: pg.Pool, schema: string) =>
      (
        await pool.query(
          `SELECT c.conname, pg_get_constraintdef(c.oid) AS def FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = $1 AND t.relname = 'devices' AND c.contype = 'c' ORDER BY c.conname`,
          [schema],
        )
      ).rows as { conname: string; def: string }[];

    it('renamed the design columns and added the estimate columns, all nullable, with the documented types', async () => {
      const cols = new Map((await columns(upgrade, UPGRADE_SCHEMA)).map((c) => [c.column_name as string, c]));
      for (const old of ['battery_capacity_mah', 'battery_capacity_wh', 'battery_specification_source']) expect(cols.has(old), old).toBe(false);
      const expected: [string, string, number | null, number | null][] = [
        ['design_capacity_mah', 'numeric', 8, 1],
        ['design_capacity_wh', 'numeric', 8, 3],
        ['design_capacity_source', 'text', null, null],
        ['estimated_full_charge_capacity_mah', 'numeric', 8, 1],
        ['estimated_full_charge_capacity_wh', 'numeric', 8, 3],
        ['full_charge_capacity_source', 'text', null, null],
        ['full_charge_capacity_confidence', 'text', null, null],
      ];
      for (const [name, type, precision, scale] of expected) {
        const c = cols.get(name);
        expect(c, name).toBeDefined();
        expect(c?.data_type, name).toBe(type);
        expect(c?.numeric_precision ?? null, name).toBe(precision);
        expect(c?.numeric_scale ?? null, name).toBe(scale);
        expect(c?.is_nullable, name).toBe('YES');
      }
    });

    it('dropped the old source CHECK (it would reject the new strings) and renamed the positive checks', async () => {
      const names = (await constraints(upgrade, UPGRADE_SCHEMA)).map((c) => c.conname);
      expect(names).not.toContain('devices_battery_specification_source_check');
      expect(names).not.toContain('devices_battery_capacity_mah_check');
      expect(names).not.toContain('devices_battery_capacity_wh_check');
      expect(names).toEqual(
        expect.arrayContaining([
          'devices_design_capacity_source_valid',
          'devices_design_capacity_unknown_has_no_numbers',
          'devices_design_capacity_numbers_need_source',
          'devices_design_capacity_wh_needs_mah',
          'devices_design_capacity_mah_positive',
          'devices_design_capacity_wh_positive',
          'devices_estimated_full_charge_capacity_mah_positive',
          'devices_estimated_full_charge_capacity_wh_positive',
          'devices_full_charge_capacity_source_valid',
          'devices_full_charge_capacity_confidence_valid',
          'devices_estimated_full_charge_capacity_needs_source',
          'devices_estimated_full_charge_capacity_needs_confidence',
          'devices_estimated_full_charge_capacity_wh_needs_mah',
          'devices_full_charge_capacity_confidence_needs_estimate',
          'devices_full_charge_capacity_measured_source_needs_estimate',
        ]),
      );
    });

    it('an upgraded database and a fresh install end with the same devices table', async () => {
      expect(await columns(upgrade, UPGRADE_SCHEMA)).toEqual(await columns(fresh, FRESH_SCHEMA));
      expect(await constraints(upgrade, UPGRADE_SCHEMA)).toEqual(await constraints(fresh, FRESH_SCHEMA));
    });

    it('is recorded once and not applied again', async () => {
      expect(await migrate(schemaUrl(UPGRADE_SCHEMA), MIGRATIONS)).toEqual([]);
      expect(await migrate(schemaUrl(FRESH_SCHEMA), MIGRATIONS)).toEqual([]);
      const rows = await upgrade.query(`SELECT name FROM schema_migrations WHERE name = $1`, [TARGET]);
      expect(rows.rows).toHaveLength(1);
    });
  });

  describe('the CHECK constraints keep every group coherent', () => {
    let userId: string;
    let n = 0;
    beforeAll(async () => {
      userId = ((await fresh.query(`INSERT INTO users(email) VALUES ('checks@test.wattbyte') RETURNING id`)).rows[0] as { id: string }).id;
    });

    type Column =
      | 'design_capacity_mah'
      | 'design_capacity_wh'
      | 'design_capacity_source'
      | 'estimated_full_charge_capacity_mah'
      | 'estimated_full_charge_capacity_wh'
      | 'full_charge_capacity_source'
      | 'full_charge_capacity_confidence';
    type Values = Partial<Record<Column, string | number | null>>;

    const insert = (values: Values) => {
      const cols = Object.keys(values);
      const params = Object.values(values);
      return fresh.query(
        `INSERT INTO devices(user_id, installation_id, platform${cols.map((c) => `, ${c}`).join('')})
         VALUES ($1, $2, 'ios'${cols.map((_, i) => `, $${i + 3}`).join('')})`,
        [userId, `check-${n++}`, ...params],
      );
    };
    /** The statement must fail with a check violation of one of `constraints`. */
    const rejected = async (values: Values, constraints: string[]) => {
      const err = await insert(values).then(
        () => null,
        (e: unknown) => e as { code?: string; constraint?: string },
      );
      expect(err, JSON.stringify(values)).not.toBeNull();
      expect(err?.code, JSON.stringify(values)).toBe('23514');
      expect(constraints, JSON.stringify(values)).toContain(err?.constraint);
    };

    it('accepts coherent rows', async () => {
      await insert({});
      await insert({ design_capacity_source: 'unknown' });
      await insert({ design_capacity_mah: 4000, design_capacity_source: 'manual' });
      await insert({ design_capacity_mah: 3274, design_capacity_wh: 12.7, design_capacity_source: 'localDeviceDatabase' });
      await insert({ design_capacity_mah: 4575, design_capacity_source: 'manufacturerSpecification' });
      await insert({ design_capacity_mah: 4575, design_capacity_wh: 17.6, design_capacity_source: 'backendDeviceDatabase' });
      await insert({ full_charge_capacity_source: 'unknown' });
      await insert({ estimated_full_charge_capacity_mah: 3600, full_charge_capacity_source: 'androidChargeCounter', full_charge_capacity_confidence: 'low' });
      await insert({
        design_capacity_mah: 4000, design_capacity_source: 'localDeviceDatabase',
        estimated_full_charge_capacity_mah: 3600, estimated_full_charge_capacity_wh: 13.8, full_charge_capacity_source: 'androidChargeCounter', full_charge_capacity_confidence: 'high',
      });
    });

    it('rejects design values that are not coherent', async () => {
      await rejected({ design_capacity_mah: 4000 }, ['devices_design_capacity_numbers_need_source']);
      await rejected({ design_capacity_mah: 4000, design_capacity_wh: 15 }, ['devices_design_capacity_numbers_need_source']);
      await rejected({ design_capacity_wh: 15 }, ['devices_design_capacity_numbers_need_source']);
      await rejected({ design_capacity_source: 'unknown', design_capacity_mah: 4000 }, ['devices_design_capacity_unknown_has_no_numbers']);
      await rejected({ design_capacity_source: 'unknown', design_capacity_wh: 15 }, ['devices_design_capacity_unknown_has_no_numbers']);
      await rejected({ design_capacity_source: 'manual', design_capacity_wh: 15 }, ['devices_design_capacity_wh_needs_mah']);
      await rejected({ design_capacity_mah: 0, design_capacity_source: 'manual' }, ['devices_design_capacity_mah_positive']);
      await rejected({ design_capacity_mah: -4000, design_capacity_source: 'manual' }, ['devices_design_capacity_mah_positive']);
      await rejected({ design_capacity_mah: 4000, design_capacity_wh: 0, design_capacity_source: 'manual' }, ['devices_design_capacity_wh_positive']);
    });

    it('rejects the old and the measurement source names as a design source', async () => {
      for (const source of ['system', 'estimated', 'localDatabase', 'backendDatabase', 'androidChargeCounter', 'measured', '']) {
        await rejected({ design_capacity_mah: 4000, design_capacity_source: source }, ['devices_design_capacity_source_valid']);
      }
    });

    it('rejects estimates that are not coherent', async () => {
      const reading = { estimated_full_charge_capacity_mah: 3600, full_charge_capacity_source: 'androidChargeCounter', full_charge_capacity_confidence: 'high' } as const;
      // A number needs the measured source and a confidence.
      await rejected({ estimated_full_charge_capacity_mah: 3600, full_charge_capacity_confidence: 'high' }, ['devices_estimated_full_charge_capacity_needs_source']);
      await rejected({ estimated_full_charge_capacity_mah: 3600, full_charge_capacity_source: 'unknown', full_charge_capacity_confidence: 'high' }, ['devices_estimated_full_charge_capacity_needs_source']);
      await rejected({ estimated_full_charge_capacity_mah: 3600, full_charge_capacity_source: 'androidChargeCounter' }, ['devices_estimated_full_charge_capacity_needs_confidence']);
      await rejected({ estimated_full_charge_capacity_mah: 3600 }, ['devices_estimated_full_charge_capacity_needs_confidence', 'devices_estimated_full_charge_capacity_needs_source']);
      // Wh needs mAh (the other checks fail too for a Wh-only row; any of them stops it).
      await rejected({ estimated_full_charge_capacity_wh: 13.8, full_charge_capacity_source: 'androidChargeCounter', full_charge_capacity_confidence: 'high' }, [
        'devices_estimated_full_charge_capacity_wh_needs_mah',
        'devices_full_charge_capacity_confidence_needs_estimate',
        'devices_full_charge_capacity_measured_source_needs_estimate',
      ]);
      // Provenance without a value.
      await rejected({ full_charge_capacity_source: 'androidChargeCounter' }, ['devices_full_charge_capacity_measured_source_needs_estimate']);
      await rejected({ full_charge_capacity_confidence: 'high' }, ['devices_full_charge_capacity_confidence_needs_estimate']);
      // Enums and positivity.
      // (A design source next to an estimate number also breaks "number needs the measured source"; either check stops it.)
      const notAnEstimateSource = ['devices_full_charge_capacity_source_valid', 'devices_estimated_full_charge_capacity_needs_source'];
      await rejected({ ...reading, full_charge_capacity_source: 'manual' }, notAnEstimateSource);
      await rejected({ ...reading, full_charge_capacity_source: 'localDeviceDatabase' }, notAnEstimateSource);
      // Without a number the source CHECK is the only one that applies.
      await rejected({ full_charge_capacity_source: 'manual' }, ['devices_full_charge_capacity_source_valid']);
      for (const confidence of ['none', 'exact', 'HIGH', '']) {
        await rejected({ ...reading, full_charge_capacity_confidence: confidence }, ['devices_full_charge_capacity_confidence_valid']);
      }
      await rejected({ ...reading, estimated_full_charge_capacity_mah: 0 }, ['devices_estimated_full_charge_capacity_mah_positive']);
      await rejected({ ...reading, estimated_full_charge_capacity_mah: -3600 }, ['devices_estimated_full_charge_capacity_mah_positive']);
      await rejected({ ...reading, estimated_full_charge_capacity_wh: 0 }, ['devices_estimated_full_charge_capacity_wh_positive']);
    });
  });
});
