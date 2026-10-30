// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * The battery-capacity behaviour of `POST /devices`, `GET /devices` and `GET /me/export`, written once and run
 * against every repository implementation (battery-capacity.test.ts on memory, db/battery-capacity.integration.test.ts
 * on PostgreSQL). It pins docs/BATTERY_CAPACITY.md: design capacity (the model) and the estimated full-charge
 * capacity (this battery) are two groups, each stored atomically, and a measurement is never a design capacity.
 */
import type { CloudExportDocument } from '@wattbyte/contracts';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { type Auth, type CloudFixture, type FixtureFactory, getExport, registerAccount } from './cloud-support.js';

const DESIGN = { designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase' } as const;
const ESTIMATE = {
  estimatedFullChargeCapacityMah: 3190.5,
  estimatedFullChargeCapacityWh: 12.2,
  fullChargeCapacitySource: 'androidChargeCounter',
  fullChargeCapacityConfidence: 'high',
} as const;
const NO_DESIGN = { designCapacityMah: null, designCapacityWh: null, designCapacitySource: null } as const;
const NO_ESTIMATE = {
  estimatedFullChargeCapacityMah: null,
  estimatedFullChargeCapacityWh: null,
  fullChargeCapacitySource: null,
  fullChargeCapacityConfidence: null,
} as const;
const ALL_NULL = { ...NO_DESIGN, ...NO_ESTIMATE } as const;

type DeviceBody = Record<string, unknown> & { id: string };

export function describeBatteryCapacity(label: string, make: FixtureFactory, enabled = true): void {
  describe.skipIf(!enabled)(`battery capacity semantics (${label})`, () => {
    let fx: CloudFixture;
    let auth: Auth;
    let counter = 0;
    beforeAll(async () => {
      fx = await make();
      auth = await registerAccount(fx, 'battery');
    });
    afterAll(() => fx.close());

    /** A fresh installation per test: its stored battery state starts empty. */
    const newInstall = () => `install-battery-${label.replaceAll(/\W/g, '').toLowerCase()}-${process.pid}-${counter++}`;
    const post = (installationId: string, extra: Record<string, unknown> = {}) =>
      fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: auth.headers, payload: { installationId, platform: 'android', ...extra } });
    const listed = async (installationId: string): Promise<DeviceBody> => {
      const res = await fx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: auth.headers });
      expect(res.statusCode).toBe(200);
      const device = (res.json() as { devices: (DeviceBody & { installationId: string })[] }).devices.find((d) => d.installationId === installationId);
      expect(device, `device ${installationId} is listed`).toBeDefined();
      return device!;
    };
    const register = async (installationId: string, extra: Record<string, unknown>): Promise<DeviceBody> => {
      const res = await post(installationId, extra);
      expect(res.statusCode, res.body).toBe(201);
      return res.json() as DeviceBody;
    };
    const expectRejected = async (installationId: string, extra: Record<string, unknown>, what: string) => {
      const res = await post(installationId, extra);
      expect(res.statusCode, `${what}: ${res.body}`).toBe(400);
      expect(res.json().error.code, what).toBe('validation');
    };

    it('registers design capacity and an estimate together, and reads both back from POST, GET /devices and the export', async () => {
      const id = newInstall();
      const created = await register(id, { model: 'Pixel 8', modelIdentifier: 'Pixel 8', ...DESIGN, ...ESTIMATE });
      expect(created).toMatchObject({ modelIdentifier: 'Pixel 8', ...DESIGN, ...ESTIMATE });
      // The old names are gone from the wire, not merely deprecated.
      expect(Object.keys(created).filter((k) => /^battery/.test(k))).toEqual([]);

      expect(await listed(id)).toMatchObject({ id: created.id, ...DESIGN, ...ESTIMATE });

      const exported = (await getExport(fx, auth.headers)).json() as CloudExportDocument;
      const row = exported.devices.find((d) => d.installationId === id);
      expect(row).toMatchObject({ id: created.id, ...DESIGN, ...ESTIMATE });
      expect(Object.keys(row ?? {}).filter((k) => /^battery/.test(k))).toEqual([]);
    });

    it('an estimate alone never produces a design capacity (the charge counter is not the nominal capacity)', async () => {
      const id = newInstall();
      const created = await register(id, { ...ESTIMATE });
      expect(created).toMatchObject({ ...NO_DESIGN, ...ESTIMATE });
      expect(await listed(id)).toMatchObject({ ...NO_DESIGN, ...ESTIMATE });
    });

    it('accepts the explicit "nothing known" markers and a design capacity from every source', async () => {
      for (const source of ['manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual'] as const) {
        const created = await register(newInstall(), { designCapacityMah: 4000, designCapacitySource: source });
        expect(created, source).toMatchObject({ designCapacityMah: 4000, designCapacityWh: null, designCapacitySource: source });
      }
      const unknown = await register(newInstall(), { designCapacitySource: 'unknown', fullChargeCapacitySource: 'unknown' });
      expect(unknown).toMatchObject({ designCapacityMah: null, designCapacityWh: null, designCapacitySource: 'unknown', ...NO_ESTIMATE, fullChargeCapacitySource: 'unknown' });
    });

    it('a design capacity without a source is a 400, and nothing is stored', async () => {
      const id = newInstall();
      await expectRejected(id, { designCapacityMah: 3274 }, 'mAh without source');
      await expectRejected(id, { designCapacityMah: 3274, designCapacityWh: 12.7 }, 'mAh and Wh without source');
      await expectRejected(id, { designCapacityMah: 3274, designCapacitySource: null }, 'mAh with a null source');
      const res = await fx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: auth.headers });
      expect((res.json() as { devices: { installationId: string }[] }).devices.some((d) => d.installationId === id)).toBe(false);
    });

    it('design source unknown with numbers is a 400; a known source without mAh and Wh without mAh are too', async () => {
      const id = newInstall();
      await expectRejected(id, { designCapacitySource: 'unknown', designCapacityMah: 3274 }, 'unknown + mAh');
      await expectRejected(id, { designCapacitySource: 'unknown', designCapacityWh: 12.7 }, 'unknown + Wh');
      await expectRejected(id, { designCapacitySource: 'manual' }, 'manual without a number');
      await expectRejected(id, { designCapacitySource: 'manual', designCapacityWh: 12.7 }, 'Wh without mAh');
    });

    it('the old charge-counter semantics cannot be expressed as a design capacity (enum)', async () => {
      const id = newInstall();
      for (const source of ['androidChargeCounter', 'system', 'estimated', 'localDatabase', 'backendDatabase', 'measured', 'guess', '']) {
        await expectRejected(id, { designCapacityMah: 4000, designCapacitySource: source }, `design source ${source || '(empty)'}`);
      }
      // And the other way round: a design source is not an estimate source.
      for (const source of ['manual', 'localDeviceDatabase', 'system', 'estimated']) {
        await expectRejected(id, { ...ESTIMATE, fullChargeCapacitySource: source }, `full-charge source ${source}`);
      }
      await expectRejected(id, { ...ESTIMATE, fullChargeCapacityConfidence: 'none' }, 'confidence none');
      await expectRejected(id, { ...ESTIMATE, fullChargeCapacityConfidence: 'exact' }, 'confidence exact');
    });

    it('rejects non-finite, zero and negative numbers (NaN / Infinity cannot be sent as JSON, null or a string are not numbers)', async () => {
      const id = newInstall();
      for (const [name, extra] of [
        ['negative design mAh', { designCapacityMah: -3000, designCapacitySource: 'manual' }],
        ['zero design mAh', { designCapacityMah: 0, designCapacitySource: 'manual' }],
        ['design mAh as string', { designCapacityMah: '3000', designCapacitySource: 'manual' }],
        ['design mAh above the bound', { designCapacityMah: 1e9, designCapacitySource: 'manual' }],
        ['negative estimate mAh', { ...ESTIMATE, estimatedFullChargeCapacityMah: -3000 }],
        ['zero estimate mAh', { ...ESTIMATE, estimatedFullChargeCapacityMah: 0 }],
        ['estimate mAh above the bound', { ...ESTIMATE, estimatedFullChargeCapacityMah: 1e9 }],
        ['negative estimate Wh', { ...ESTIMATE, estimatedFullChargeCapacityWh: -1 }],
        // numeric(8,3) overflows at 1e5: without the schema bound PostgreSQL would answer 500 and memory 201.
        ['design Wh above the bound', { designCapacityMah: 4000, designCapacityWh: 1e6, designCapacitySource: 'manual' }],
        ['design Wh just above the bound', { designCapacityMah: 4000, designCapacityWh: 200.5, designCapacitySource: 'manual' }],
        ['estimate Wh above the bound', { ...ESTIMATE, estimatedFullChargeCapacityWh: 1e6 }],
        ['estimate Wh just above the bound', { ...ESTIMATE, estimatedFullChargeCapacityWh: 200.5 }],
      ] as const) {
        const res = await post(id, extra);
        expect(res.statusCode, name).toBe(400);
      }
      // NaN / Infinity serialise to null in JSON.stringify, and the route reads null as "not given", so a raw body
      // with the JSON-invalid tokens is the only way to send them: it must be refused as malformed JSON.
      for (const token of ['NaN', 'Infinity', '-Infinity']) {
        const res = await fx.app.inject({
          method: 'POST',
          url: '/api/v1/devices',
          headers: { ...auth.headers, 'content-type': 'application/json' },
          payload: `{"installationId":"${id}","platform":"android","estimatedFullChargeCapacityMah":${token}}`,
        });
        expect(res.statusCode, token).toBe(400);
      }
    });

    it('an estimate needs source androidChargeCounter and a confidence', async () => {
      const id = newInstall();
      await expectRejected(id, { estimatedFullChargeCapacityMah: 3190.5 }, 'mAh without source and confidence');
      await expectRejected(id, { estimatedFullChargeCapacityMah: 3190.5, fullChargeCapacityConfidence: 'high' }, 'mAh without source');
      await expectRejected(id, { estimatedFullChargeCapacityMah: 3190.5, fullChargeCapacitySource: 'androidChargeCounter' }, 'mAh without confidence');
      await expectRejected(id, { estimatedFullChargeCapacityMah: 3190.5, fullChargeCapacitySource: 'unknown', fullChargeCapacityConfidence: 'high' }, 'source unknown with numbers');
      await expectRejected(id, { estimatedFullChargeCapacityMah: 3190.5, fullChargeCapacitySource: 'unknown' }, 'source unknown with numbers, no confidence');
    });

    it('a confidence or a measured source without estimated mAh is a 400, and Wh needs mAh', async () => {
      const id = newInstall();
      await expectRejected(id, { fullChargeCapacityConfidence: 'high' }, 'confidence alone');
      await expectRejected(id, { fullChargeCapacitySource: 'androidChargeCounter' }, 'source alone');
      await expectRejected(id, { fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }, 'source and confidence, no number');
      await expectRejected(id, { fullChargeCapacitySource: 'unknown', fullChargeCapacityConfidence: 'low' }, 'unknown with confidence');
      await expectRejected(id, { estimatedFullChargeCapacityWh: 12.2, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }, 'Wh without mAh');
    });

    it('accepts every confidence level', async () => {
      for (const confidence of ['low', 'medium', 'high'] as const) {
        const created = await register(newInstall(), { estimatedFullChargeCapacityMah: 3000, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: confidence });
        expect(created, confidence).toMatchObject({ estimatedFullChargeCapacityMah: 3000, estimatedFullChargeCapacityWh: null, fullChargeCapacityConfidence: confidence });
      }
    });

    it('a rejected request leaves the stored device untouched', async () => {
      const id = newInstall();
      await register(id, { ...DESIGN, ...ESTIMATE });
      await expectRejected(id, { designCapacitySource: 'manual', designCapacityMah: 5000, designCapacityWh: 99, estimatedFullChargeCapacityMah: 1 }, 'incoherent estimate');
      expect(await listed(id)).toMatchObject({ ...DESIGN, ...ESTIMATE });
    });

    describe('each group is stored atomically', () => {
      it('a new design group replaces the whole stored group (nulls included), the estimate stays', async () => {
        const id = newInstall();
        await register(id, { ...DESIGN, ...ESTIMATE });
        const manual = await register(id, { designCapacityMah: 3000, designCapacitySource: 'manual' });
        expect(manual).toMatchObject({ designCapacityMah: 3000, designCapacityWh: null, designCapacitySource: 'manual', ...ESTIMATE });
        expect(await listed(id)).toMatchObject({ designCapacityMah: 3000, designCapacityWh: null, designCapacitySource: 'manual', ...ESTIMATE });
      });

      it('design source unknown clears the numbers of the design group only', async () => {
        const id = newInstall();
        await register(id, { ...DESIGN, ...ESTIMATE });
        const cleared = await register(id, { designCapacitySource: 'unknown' });
        expect(cleared).toMatchObject({ designCapacityMah: null, designCapacityWh: null, designCapacitySource: 'unknown', ...ESTIMATE });
      });

      it('omitting a group, or sending nulls for it, keeps the stored group untouched', async () => {
        const id = newInstall();
        const first = await register(id, { model: 'Pixel 8', ...DESIGN, ...ESTIMATE });
        expect(await register(id, {})).toMatchObject({ id: first.id, model: 'Pixel 8', ...DESIGN, ...ESTIMATE });
        // A group with a null source is "not given", whatever else the request carries.
        expect(await register(id, { designCapacitySource: null, fullChargeCapacitySource: null })).toMatchObject({ ...DESIGN, ...ESTIMATE });
      });

      it('a request in which every battery field is null changes nothing', async () => {
        const id = newInstall();
        const first = await register(id, { ...DESIGN, ...ESTIMATE });
        const again = await register(id, ALL_NULL);
        expect(again).toMatchObject({ id: first.id, ...DESIGN, ...ESTIMATE });
        expect(await listed(id)).toMatchObject({ ...DESIGN, ...ESTIMATE });
        // Same on a device that never had a battery group: it stays empty.
        const empty = newInstall();
        expect(await register(empty, ALL_NULL)).toMatchObject(ALL_NULL);
        expect(await register(empty, ALL_NULL)).toMatchObject(ALL_NULL);
      });

      it('changing only the estimate leaves the design group untouched, and the estimate is replaced as a whole', async () => {
        const id = newInstall();
        await register(id, { ...DESIGN, ...ESTIMATE });
        const lower = await register(id, { estimatedFullChargeCapacityMah: 3100, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'low' });
        expect(lower).toMatchObject({
          ...DESIGN,
          estimatedFullChargeCapacityMah: 3100,
          estimatedFullChargeCapacityWh: null, // not carried over from the previous estimate
          fullChargeCapacitySource: 'androidChargeCounter',
          fullChargeCapacityConfidence: 'low',
        });
      });

      it('estimate source unknown clears the estimate and leaves the design group untouched', async () => {
        const id = newInstall();
        await register(id, { ...DESIGN, ...ESTIMATE });
        const cleared = await register(id, { fullChargeCapacitySource: 'unknown' });
        expect(cleared).toMatchObject({ ...DESIGN, ...NO_ESTIMATE, fullChargeCapacitySource: 'unknown' });
        // A later real estimate replaces the marker.
        const again = await register(id, { ...ESTIMATE });
        expect(again).toMatchObject({ ...DESIGN, ...ESTIMATE });
      });

      it('an installation only ever changes its own battery state', async () => {
        const a = newInstall();
        const b = newInstall();
        await register(a, { ...DESIGN, ...ESTIMATE });
        await register(b, { designCapacityMah: 5000, designCapacitySource: 'manual' });
        expect(await listed(a)).toMatchObject({ ...DESIGN, ...ESTIMATE });
        expect(await listed(b)).toMatchObject({ designCapacityMah: 5000, designCapacitySource: 'manual', ...NO_ESTIMATE });
      });
    });

    describe('repository contract (the same on every implementation)', () => {
      it('values of a group whose source is not given are ignored, they neither fail nor overwrite', async () => {
        const id = newInstall();
        await register(id, { ...DESIGN, ...ESTIMATE });
        // Straight to the repository: the route would have refused this input.
        const row = await fx.repos.devices.upsert({
          userId: auth.userId,
          installationId: id,
          platform: 'android',
          designCapacityMah: 1,
          designCapacityWh: 1,
          estimatedFullChargeCapacityMah: 1,
          estimatedFullChargeCapacityWh: 1,
          fullChargeCapacityConfidence: 'low',
        });
        expect(row).toMatchObject({ ...DESIGN, ...ESTIMATE });
        const fresh = await fx.repos.devices.upsert({ userId: auth.userId, installationId: newInstall(), platform: 'ios', designCapacityMah: 1, fullChargeCapacityConfidence: 'low' });
        expect(fresh).toMatchObject(ALL_NULL);
      });

      it('findForUser and listForUser return the same groups as the upsert', async () => {
        const id = newInstall();
        const row = await fx.repos.devices.upsert({ userId: auth.userId, installationId: id, platform: 'ios', ...DESIGN, ...ESTIMATE });
        expect(row).toMatchObject({ ...DESIGN, ...ESTIMATE });
        expect(await fx.repos.devices.findForUser(auth.userId, id)).toMatchObject({ ...DESIGN, ...ESTIMATE });
        expect((await fx.repos.devices.listForUser(auth.userId)).find((d) => d.installationId === id)).toMatchObject({ ...DESIGN, ...ESTIMATE });
      });
    });
  });
}
