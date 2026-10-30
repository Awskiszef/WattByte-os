// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * The behaviour of `DELETE /me/cloud-data` and `GET /me/export`, written once and run against every
 * repository implementation (see cloud-data.test.ts and db/cloud-data.integration.test.ts).
 */
import { CLOUD_EXPORT_MAX_ROWS, CloudDataDeleteResponse, CloudExportDocument } from '@wattbyte/contracts';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { TokenService } from '../src/modules/auth/tokens.js';
import { CLOUD_DELETE_RATE_LIMIT_PER_MIN, CLOUD_EXPORT_RATE_LIMIT_PER_MIN } from '../src/modules/cloud/routes.js';
import { sampleInput } from './helpers.js';
import {
  type Account,
  BATTERY,
  type CloudFixture,
  deleteCloudData,
  exportBody,
  type FixtureFactory,
  getExport,
  must,
  parseCsv,
  registerAccount,
  seedAccount,
  SYNCED_DAYS,
} from './cloud-support.js';

const ZERO = { dailyUsage: 0, chargingSummaries: 0, monthlySummaries: 0, aiGenerations: 0, devices: 0 };

export function describeCloudData(label: string, make: FixtureFactory, enabled = true): void {
  describe.skipIf(!enabled)(`cloud data (${label})`, () => {
    // A fresh app per test: the export and delete routes have their own per-IP rate limits, which a shared app would exhaust.
    let fx: CloudFixture;
    beforeEach(async () => {
      fx = await make();
    });
    afterEach(() => fx.close());

    const ai = (a: Account) =>
      fx.app.inject({ method: 'POST', url: '/api/v1/ai/insight', headers: a.headers, payload: { input: sampleInput } });
    const sync = (a: Account, days: readonly unknown[] = SYNCED_DAYS) =>
      fx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: a.headers, payload: { installationId: a.installationId, days } });

    // ------------------------------------------------------------------ DELETE /me/cloud-data

    describe('DELETE /me/cloud-data', () => {
      it('erases usage, summaries and AI log; keeps the AI quota counters, account, sessions, subscriptions, settings and devices; sync resumes', async () => {
        const a = await seedAccount(fx, 'del-a');
        const b = await seedAccount(fx, 'del-b');
        const bBefore = await exportBody(fx, b.headers);
        expect((await ai(a)).statusCode, 'the free quota of 2 is used up').toBe(429);

        const res = await deleteCloudData(fx, a.headers);
        expect(res.statusCode).toBe(200);
        expect(res.headers['content-type']).toMatch(/^application\/json/);
        expect(res.json()).toEqual({ deleted: { dailyUsage: 3, chargingSummaries: 2, monthlySummaries: 1, aiGenerations: 2, devices: 0 } });
        expect(CloudDataDeleteResponse.safeParse(res.json()).success).toBe(true);

        // Storage level: nothing of the five kinds is left, the rest is.
        for (const t of ['daily_usage', 'charging_summaries', 'monthly_summaries', 'ai_generations']) {
          expect(await fx.rowCount(t, a.userId), t).toBe(0);
        }
        expect(await fx.rowCount('devices', a.userId)).toBe(1);
        expect(await fx.rowCount('subscriptions', a.userId)).toBe(1);
        expect(await fx.rowCount('user_settings', a.userId)).toBe(1);

        // The account is intact and signed in: /me, refresh token, settings, devices.
        expect((await fx.app.inject({ method: 'GET', url: '/api/v1/me', headers: a.headers })).json()).toMatchObject({ id: a.userId, email: a.email });
        const refreshed = await fx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: a.refreshToken } });
        expect(refreshed.statusCode, 'sessions survive').toBe(200);
        const settings = await fx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers: a.headers });
        expect(settings.json()).toMatchObject({ countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 });
        const devices = (await fx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: a.headers })).json() as { devices: { id: string; designCapacityMah: number }[] };
        expect(devices.devices.map((d) => d.id)).toEqual([a.deviceId]);
        expect(devices.devices[0]?.designCapacityMah).toBe(BATTERY.designCapacityMah);
        const daily = await fx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: a.headers });
        expect(daily.json()).toEqual({ days: [] });

        const exported = (await getExport(fx, a.headers)).json() as CloudExportDocument;
        expect(exported).toMatchObject({ dailyUsage: [], chargingSummaries: [], monthlySummaries: [], aiGenerations: [] });
        expect(exported.devices).toHaveLength(1);
        expect(exported.subscriptions).toHaveLength(1);
        expect(exported.settings.countryCode).toBe('PL');

        // Security property: deleting the cloud data must NOT hand back the daily AI allowance.
        expect((await ai(a)).statusCode, 'quota counters survive the deletion').toBe(429);

        // Sync resumes against the kept device without registering again.
        expect((await sync(a)).statusCode).toBe(200);
        expect((await fx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: a.headers })).json()).toMatchObject({
          days: [{ date: '2026-10-10' }, { date: '2026-10-11' }, { date: '2026-10-12' }],
        });

        // The other account did not change at all.
        expect(await exportBody(fx, b.headers)).toEqual(bBefore);
      });

      it('is idempotent: repeating it deletes nothing and answers zeros', async () => {
        const a = await seedAccount(fx, 'idem');
        expect((await deleteCloudData(fx, a.headers)).json().deleted.dailyUsage).toBe(3);
        for (let i = 0; i < 2; i++) {
          const again = await deleteCloudData(fx, a.headers);
          expect(again.statusCode).toBe(200);
          expect(again.json()).toEqual({ deleted: ZERO });
        }
        // An account that never synced anything is equally fine.
        const fresh = await registerAccount(fx, 'idem-empty');
        expect((await deleteCloudData(fx, fresh.headers)).json()).toEqual({ deleted: ZERO });
      });

      it('?devices=true also removes the devices; the rest of the account stays; the other account keeps its devices', async () => {
        const a = await seedAccount(fx, 'dev-a');
        const b = await seedAccount(fx, 'dev-b');
        const bBefore = await exportBody(fx, b.headers);

        const res = await deleteCloudData(fx, a.headers, '?devices=true');
        expect(res.statusCode).toBe(200);
        expect(res.json()).toEqual({ deleted: { dailyUsage: 3, chargingSummaries: 2, monthlySummaries: 1, aiGenerations: 2, devices: 1 } });
        expect(await fx.rowCount('devices', a.userId)).toBe(0);
        expect(await fx.rowCount('daily_usage', a.userId)).toBe(0);
        expect(await fx.rowCount('subscriptions', a.userId)).toBe(1);
        expect(await fx.rowCount('user_settings', a.userId)).toBe(1);
        expect((await fx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: a.headers })).json()).toEqual({ devices: [] });
        expect((await fx.app.inject({ method: 'POST', url: '/api/v1/auth/refresh', payload: { refreshToken: a.refreshToken } })).statusCode).toBe(200);

        // Sync needs the device again; registering it brings it back.
        const lost = await sync(a);
        expect(lost.statusCode).toBe(404);
        expect(lost.json().error.code).toBe('device_not_registered');
        await must(
          await fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: a.headers, payload: { installationId: a.installationId, platform: 'ios' } }),
          201,
          're-register',
        );
        expect((await sync(a)).statusCode).toBe(200);

        // Idempotent with devices=true as well.
        expect((await deleteCloudData(fx, a.headers, '?devices=true')).json().deleted.devices).toBe(1);
        expect((await deleteCloudData(fx, a.headers, '?devices=true')).json()).toEqual({ deleted: ZERO });

        expect(await exportBody(fx, b.headers)).toEqual(bBefore);
      });

      it('?devices=false behaves like the default; anything else is a 400', async () => {
        const a = await seedAccount(fx, 'flag');
        const explicit = await deleteCloudData(fx, a.headers, '?devices=false');
        expect(explicit.json().deleted).toMatchObject({ dailyUsage: 3, devices: 0 });
        expect(await fx.rowCount('devices', a.userId)).toBe(1);
        for (const q of ['?devices=maybe', '?devices=1', '?devices=TRUE', '?devices=']) {
          const bad = await deleteCloudData(fx, a.headers, q);
          expect(bad.statusCode, q).toBe(400);
        }
        expect(await fx.rowCount('devices', a.userId)).toBe(1);
      });

      it('requires a valid token, and a deleted account is a 401 for it', async () => {
        const a = await seedAccount(fx, 'auth');
        expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me/cloud-data' })).statusCode).toBe(401);
        expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me/cloud-data', headers: { authorization: 'Bearer nope' } })).statusCode).toBe(401);
        expect(await fx.rowCount('daily_usage', a.userId), 'rejected requests delete nothing').toBe(3);

        expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);
        const gone = await deleteCloudData(fx, a.headers);
        expect(gone.statusCode).toBe(401);
        expect(gone.json().error.code).toBe('account_not_found');
      });

      it('has its own, stricter rate limit than the global one', async () => {
        const limited = await make();
        try {
          const a = await registerAccount(limited, 'del-rate');
          const codes: number[] = [];
          for (let i = 0; i <= CLOUD_DELETE_RATE_LIMIT_PER_MIN; i++) codes.push((await deleteCloudData(limited, a.headers)).statusCode);
          expect(CLOUD_DELETE_RATE_LIMIT_PER_MIN, 'stricter than the global 120 / minute').toBeLessThan(120);
          expect(codes.slice(0, -1).every((c) => c === 200)).toBe(true);
          expect(codes.at(-1)).toBe(429);
        } finally {
          await limited.close();
        }
      });
    });

    // ------------------------------------------------------------------ GET /me/export

    describe('GET /me/export', () => {
      it('returns the whole account as a JSON attachment', async () => {
        const a = await seedAccount(fx, 'exp');
        const res = await getExport(fx, a.headers);
        expect(res.statusCode).toBe(200);
        expect(res.headers['content-type']).toMatch(/^application\/json/);
        expect(res.headers['content-disposition']).toMatch(/^attachment; filename="wattbyte-export-\d{4}-\d{2}-\d{2}\.json"$/);
        expect(res.headers['cache-control']).toBe('no-store');

        const doc = res.json() as CloudExportDocument;
        expect(CloudExportDocument.safeParse(doc).success).toBe(true);
        expect(res.headers['content-disposition']).toContain(`wattbyte-export-${doc.exportedAt.slice(0, 10)}.json`);
        expect(doc.schemaVersion).toBe(1);
        expect(Math.abs(Date.now() - Date.parse(doc.exportedAt))).toBeLessThan(60_000);
        expect(doc.account).toEqual({ id: a.userId, email: a.email, displayName: 'User exp', plan: 'free', createdAt: expect.any(String) });
        // Saved without origins (an older client): they are exported as unknown, never guessed.
        expect(doc.settings).toEqual({
          countryCode: 'PL',
          countryCodeSource: null,
          currencyCode: 'PLN',
          currencyCodeSource: null,
          electricityPriceMode: 'manual',
          manualElectricityPrice: 0.95,
          electricityPriceSource: null,
          updatedAt: expect.any(String),
        });
        expect(doc.devices).toEqual([
          {
            id: a.deviceId,
            installationId: a.installationId,
            platform: 'ios',
            model: 'iPhone 15 Pro',
            modelIdentifier: 'iPhone16,1',
            designCapacityMah: 3274,
            designCapacityWh: 12.7,
            designCapacitySource: 'localDeviceDatabase',
            estimatedFullChargeCapacityMah: 3190.5,
            estimatedFullChargeCapacityWh: 12.2,
            fullChargeCapacitySource: 'androidChargeCounter',
            fullChargeCapacityConfidence: 'high',
            createdAt: expect.any(String),
            lastSeenAt: expect.any(String),
          },
        ]);
        expect(doc.dailyUsage).toEqual(SYNCED_DAYS.map((d) => ({ deviceId: a.deviceId, ...d })));
        expect(doc.chargingSummaries).toEqual([
          {
            deviceId: a.deviceId,
            startedAt: '2026-10-10T21:00:00.000Z',
            endedAt: '2026-10-10T22:00:00.000Z',
            startPercent: 20,
            endPercent: 80,
            mah: 2400.5,
            mahEstimated: true,
            batteryWh: 9.24,
            wallWh: 10.871,
            estimatedCost: 0.0138,
            createdAt: '2026-10-12T08:00:00.000Z',
          },
          {
            deviceId: a.deviceId,
            startedAt: '2026-10-11T22:30:00.000Z',
            endedAt: '2026-10-11T23:30:00.000Z',
            startPercent: 21,
            endPercent: 81,
            mah: 2400.5,
            mahEstimated: false,
            batteryWh: 9.24,
            wallWh: 10.871,
            estimatedCost: 0.0138,
            createdAt: '2026-10-12T08:00:00.000Z',
          },
        ]);
        expect(doc.monthlySummaries).toEqual([
          { month: '2026-09', mobileBytes: 5_000_000, wifiBytes: 90_000_000, wallWh: 410.25, chargingSessions: 31, estimatedCost: 0.5201, currency: 'PLN', computedAt: '2026-10-01T00:05:00.000Z' },
        ]);
        // AI generations: metadata of the request, never what was sent or generated.
        expect(doc.aiGenerations).toHaveLength(2);
        for (const g of doc.aiGenerations) {
          expect(Object.keys(g).sort()).toEqual(['createdAt', 'estimatedCostUsd', 'inputTokens', 'latencyMs', 'mode', 'model', 'outputTokens', 'provider', 'task']);
          expect(g.task).toBe('insight');
          expect(g.mode).toBe('normal');
        }
        expect(doc.subscriptions).toEqual([
          {
            store: 'app_store',
            productId: 'wattbyte.premium.monthly',
            originalTransactionId: expect.stringMatching(/^tx-/),
            status: 'active',
            expiresAt: '2026-11-12T00:00:00.000Z',
            createdAt: '2026-10-12T09:00:00.000Z',
            updatedAt: '2026-10-12T09:00:00.000Z',
          },
        ]);
        expect(doc.limits).toEqual({
          maxRowsPerCollection: CLOUD_EXPORT_MAX_ROWS,
          truncated: { devices: false, dailyUsage: false, chargingSummaries: false, monthlySummaries: false, aiGenerations: false, subscriptions: false },
        });
        expect(Object.keys(doc).sort()).toEqual([
          'account', 'aiGenerations', 'chargingSummaries', 'dailyUsage', 'devices', 'exportedAt', 'limits', 'monthlySummaries', 'schemaVersion', 'settings', 'subscriptions',
        ]);
      });

      it('never contains credentials, session data or another account', async () => {
        const a = await seedAccount(fx, 'sec-a');
        const b = await seedAccount(fx, 'sec-b');
        const user = await fx.repos.users.findById(a.userId);
        expect(user?.passwordHash, 'the account has a password hash to look for').toBeTruthy();
        const forbidden = [
          user?.passwordHash ?? '',
          'scrypt$',
          'passwordHash',
          'password_hash',
          'refresh',
          'session',
          a.accessToken,
          a.refreshToken,
          TokenService.hashRefresh(a.refreshToken),
          a.password,
          // another account
          b.userId,
          b.email,
          b.deviceId,
          b.installationId,
          b.accessToken,
          b.refreshToken,
        ];
        for (const q of ['', '?format=csv']) {
          const res = await getExport(fx, a.headers, q);
          expect(res.statusCode).toBe(200);
          for (const needle of forbidden) expect(res.body.includes(needle), `${q || 'json'} must not contain "${needle.slice(0, 24)}"`).toBe(false);
        }
        const doc = (await getExport(fx, b.headers)).json() as CloudExportDocument;
        expect(doc.account.id).toBe(b.userId);
        expect(JSON.stringify(doc).includes(a.userId)).toBe(false);
        expect(JSON.stringify(doc).includes(a.deviceId)).toBe(false);
      });

      it('exports an account without data: defaults for settings, empty collections', async () => {
        const fresh = await registerAccount(fx, 'exp-empty');
        const doc = (await getExport(fx, fresh.headers)).json() as CloudExportDocument;
        expect(doc.account.id).toBe(fresh.userId);
        expect(doc.settings).toEqual({
          countryCode: null,
          countryCodeSource: null,
          currencyCode: null,
          currencyCodeSource: null,
          electricityPriceMode: 'automatic',
          manualElectricityPrice: null,
          electricityPriceSource: null,
          updatedAt: null,
        });
        expect([doc.devices, doc.dailyUsage, doc.chargingSummaries, doc.monthlySummaries, doc.aiGenerations, doc.subscriptions]).toEqual([[], [], [], [], [], []]);
      });

      it('?format=csv returns the daily usage as RFC 4180 text/csv; charset=utf-8', async () => {
        const a = await seedAccount(fx, 'csv');
        const res = await getExport(fx, a.headers, '?format=csv');
        expect(res.statusCode).toBe(200);
        expect(res.headers['content-type']).toBe('text/csv; charset=utf-8');
        expect(res.headers['content-disposition']).toMatch(/^attachment; filename="wattbyte-export-\d{4}-\d{2}-\d{2}\.csv"$/);
        expect(res.headers['x-wattbyte-truncated']).toBeUndefined();
        expect(res.rawPayload.subarray(0, 3).toString('hex'), 'no byte order mark').not.toBe('efbbbf');
        expect(res.body.endsWith('\r\n')).toBe(true);

        const rows = parseCsv(res.body);
        expect(rows[0]).toEqual(['date', 'deviceId', 'mobileBytes', 'wifiBytes', 'chargedWh', 'wallWh', 'chargingSessions', 'estimatedCost', 'currency', 'dataEstimated', 'energyEstimated']);
        expect(rows.slice(1)).toEqual(
          SYNCED_DAYS.map((d) => [d.date, a.deviceId, String(d.mobileBytes), String(d.wifiBytes), String(d.chargedWh), String(d.wallWh), String(d.chargingSessions), String(d.estimatedCost), d.currency, String(d.dataEstimated), String(d.energyEstimated)]),
        );
        // The same rows as the JSON document.
        const json = (await getExport(fx, a.headers)).json() as CloudExportDocument;
        expect(rows.length - 1).toBe(json.dailyUsage.length);
      });

      it('rejects an unknown format with 400', async () => {
        const a = await seedAccount(fx, 'exp-format');
        for (const q of ['?format=xml', '?format=', '?format=CSV']) expect((await getExport(fx, a.headers, q)).statusCode, q).toBe(400);
        expect((await getExport(fx, a.headers, '?format=json')).statusCode).toBe(200);
      });

      it('rejects anonymous callers and answers 401 account_not_found for a deleted account', async () => {
        const a = await seedAccount(fx, 'exp-auth');
        expect((await fx.app.inject({ method: 'GET', url: '/api/v1/me/export' })).statusCode).toBe(401);
        expect((await fx.app.inject({ method: 'GET', url: '/api/v1/me/export', headers: { authorization: 'Bearer nope' } })).statusCode).toBe(401);
        expect((await fx.app.inject({ method: 'DELETE', url: '/api/v1/me', headers: a.headers })).statusCode).toBe(204);
        for (const q of ['', '?format=csv']) {
          const gone = await getExport(fx, a.headers, q);
          expect(gone.statusCode, q).toBe(401);
          expect(gone.json().error.code).toBe('account_not_found');
        }
      });

      it(`caps every collection at ${CLOUD_EXPORT_MAX_ROWS} rows, keeps the newest and says so`, async () => {
        const a = await registerAccount(fx, 'cap');
        const dev = await fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: a.headers, payload: { installationId: 'install-cap-00001', platform: 'android' } });
        const deviceId = (dev.json() as { id: string }).id;
        await fx.bulkDailyUsage(a.userId, deviceId, CLOUD_EXPORT_MAX_ROWS + 1);

        const res = await getExport(fx, a.headers);
        expect(res.statusCode).toBe(200);
        const doc = res.json() as CloudExportDocument;
        expect(doc.dailyUsage).toHaveLength(CLOUD_EXPORT_MAX_ROWS);
        expect(doc.limits.truncated).toMatchObject({ dailyUsage: true, devices: false });
        // 2026-10-12 is the newest; the oldest of the 10 001 days is the one that was cut.
        expect(doc.dailyUsage.at(-1)?.date).toBe('2026-10-12');
        const oldest = new Date(Date.UTC(2026, 9, 12) - CLOUD_EXPORT_MAX_ROWS * 86_400_000).toISOString().slice(0, 10);
        expect(doc.dailyUsage.some((r) => r.date === oldest)).toBe(false);
        expect(doc.dailyUsage[0]?.date).toBe(new Date(Date.UTC(2026, 9, 12) - (CLOUD_EXPORT_MAX_ROWS - 1) * 86_400_000).toISOString().slice(0, 10));

        const csv = await getExport(fx, a.headers, '?format=csv');
        expect(csv.headers['x-wattbyte-truncated']).toBe('dailyUsage');
        expect(parseCsv(csv.body)).toHaveLength(CLOUD_EXPORT_MAX_ROWS + 1);

        // Exactly at the cap is not truncated.
        await fx.repos.cloud.deleteData(a.userId);
        await fx.bulkDailyUsage(a.userId, deviceId, CLOUD_EXPORT_MAX_ROWS);
        const exact = (await getExport(fx, a.headers)).json() as CloudExportDocument;
        expect(exact.dailyUsage).toHaveLength(CLOUD_EXPORT_MAX_ROWS);
        expect(exact.limits.truncated.dailyUsage).toBe(false);
      }, 60_000);

      it('has its own, stricter rate limit than the global one', async () => {
        const limited = await make();
        try {
          const a = await registerAccount(limited, 'exp-rate');
          const codes: number[] = [];
          for (let i = 0; i <= CLOUD_EXPORT_RATE_LIMIT_PER_MIN; i++) codes.push((await getExport(limited, a.headers)).statusCode);
          expect(CLOUD_EXPORT_RATE_LIMIT_PER_MIN, 'stricter than the global 120 / minute').toBeLessThan(120);
          expect(codes.slice(0, -1).every((c) => c === 200)).toBe(true);
          expect(codes.at(-1)).toBe(429);
        } finally {
          await limited.close();
        }
      });
    });

    // ------------------------------------------------------------------ repository contract

    describe('repos.cloud', () => {
      it('answers null for an account that does not exist', async () => {
        const unknown = '00000000-0000-4000-8000-000000000000';
        expect(await fx.repos.cloud.deleteData(unknown)).toBeNull();
        expect(await fx.repos.cloud.deleteData(unknown, { devices: true })).toBeNull();
        expect(await fx.repos.cloud.exportData(unknown, 10)).toBeNull();
      });

      it('exportData keeps the newest rows per collection and flags a cut', async () => {
        const a = await seedAccount(fx, 'repo-cap');
        const data = await fx.repos.cloud.exportData(a.userId, 2);
        expect(data?.dailyUsage.map((r) => r.date)).toEqual(['2026-10-11', '2026-10-12']);
        expect(data?.chargingSummaries).toHaveLength(2);
        expect(data?.truncated).toEqual({ devices: false, dailyUsage: true, chargingSummaries: false, monthlySummaries: false, aiGenerations: false, subscriptions: false });
        const one = await fx.repos.cloud.exportData(a.userId, 1);
        expect(one?.chargingSummaries.map((c) => c.startedAt.toISOString())).toEqual(['2026-10-11T22:30:00.000Z']);
        expect(one?.truncated).toMatchObject({ dailyUsage: true, chargingSummaries: true, aiGenerations: true, devices: false, monthlySummaries: false });
      });

      it('deleteData only reports and removes rows of the given user', async () => {
        const a = await seedAccount(fx, 'repo-a');
        const b = await seedAccount(fx, 'repo-b');
        expect(await fx.repos.cloud.deleteData(a.userId)).toEqual({ dailyUsage: 3, chargingSummaries: 2, monthlySummaries: 1, aiGenerations: 2, devices: 0 });
        for (const t of ['daily_usage', 'charging_summaries', 'monthly_summaries', 'ai_generations', 'devices', 'subscriptions']) {
          expect(await fx.rowCount(t, b.userId), `${t} of the other account`).toBeGreaterThan(0);
        }
        expect((await fx.repos.cloud.exportData(b.userId, 100))?.dailyUsage).toHaveLength(3);
      });
    });
  });
}
