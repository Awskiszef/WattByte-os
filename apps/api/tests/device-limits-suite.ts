import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import type { App } from '../src/app.js';
import { registerUser } from './helpers.js';

export interface DeviceLimitFixture {
  app: App;
  email(prefix: string): string;
  close(): Promise<void>;
}

const CAP = 4;
const WRITE_LIMIT = 6;

/** C-04 on the HTTP surface; run on the in-memory repositories and on PostgreSQL with the same expectations. */
export function describeDeviceLimits(label: string, make: (overrides: Record<string, string>) => Promise<DeviceLimitFixture>, enabled = true): void {
  describe.skipIf(!enabled)(`device cap and per-account write limit (${label})`, () => {
    let fx: DeviceLimitFixture;
    beforeAll(async () => {
      fx = await make({ MAX_DEVICES_PER_ACCOUNT: String(CAP), CLOUD_WRITE_RATE_LIMIT_PER_MIN: String(WRITE_LIMIT) });
    });
    afterAll(() => fx.close());

    const register = (headers: { authorization: string }, installationId: string, extra: Record<string, unknown> = {}, remoteAddress?: string) =>
      fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers, remoteAddress, payload: { installationId, platform: 'android', ...extra } });
    const id = (n: number | string) => `inst-${String(n).padStart(8, '0')}`;

    it(`the ${CAP + 1}th installation is refused with 409 device_limit_reached; known ones can always be refreshed`, async () => {
      const user = await registerUser(fx.app, fx.email('cap'));
      // Spread over time-independent addresses so the per-address limiter plays no part.
      for (let i = 1; i <= CAP; i += 1) expect((await register(user.headers, id(i))).statusCode).toBe(201);
      const refused = await register(user.headers, id(CAP + 1));
      expect(refused.statusCode).toBe(409);
      expect(refused.json()).toMatchObject({ error: { code: 'device_limit_reached' } });
      // An installation the account already has is refreshed (and its capacity data updated), at the cap.
      const refreshed = await register(user.headers, id(1), { model: 'Pixel 9' });
      expect(refreshed.statusCode).toBe(201);
      expect(refreshed.json()).toMatchObject({ installationId: id(1), model: 'Pixel 9' });
      expect(((await fx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: user.headers })).json() as { devices: unknown[] }).devices).toHaveLength(CAP);
    });

    it('removing a device frees a slot, and another account is not affected', async () => {
      const user = await registerUser(fx.app, fx.email('free'));
      const other = await registerUser(fx.app, fx.email('other'));
      const created: string[] = [];
      for (let i = 1; i <= CAP; i += 1) created.push((await register(user.headers, id(100 + i))).json().id as string);
      expect((await register(user.headers, id(200))).statusCode).toBe(409);
      expect((await register(other.headers, id(100 + 1))).statusCode).toBe(201);
      expect((await fx.app.inject({ method: 'DELETE', url: `/api/v1/devices/${created[0]}`, headers: user.headers })).statusCode).toBe(204);
      expect((await register(user.headers, id(200))).statusCode).toBe(201);
    });

    it('concurrent registrations of new installations never exceed the cap (atomic check and insert)', async () => {
      // Its own app: a high write budget, so the cap, not the limiter, decides.
      const racing = await make({ MAX_DEVICES_PER_ACCOUNT: '3', CLOUD_WRITE_RATE_LIMIT_PER_MIN: '1000' });
      try {
        const user = await registerUser(racing.app, racing.email('race'));
        const burst = await Promise.all(
          Array.from({ length: 20 }, (_, i) => racing.app.inject({ method: 'POST', url: '/api/v1/devices', headers: user.headers, payload: { installationId: id(300 + i), platform: 'ios' } })),
        );
        expect(burst.filter((r) => r.statusCode === 201)).toHaveLength(3);
        expect(burst.filter((r) => r.statusCode === 409)).toHaveLength(17);
        expect(((await racing.app.inject({ method: 'GET', url: '/api/v1/devices', headers: user.headers })).json() as { devices: unknown[] }).devices).toHaveLength(3);
      } finally {
        await racing.close();
      }
    });

    it(`registrations and syncs share one budget of ${WRITE_LIMIT} per minute per ACCOUNT, whatever the address`, async () => {
      const user = await registerUser(fx.app, fx.email('limit'));
      const other = await registerUser(fx.app, fx.email('limit-other'));
      const statuses: number[] = [];
      for (let i = 0; i < WRITE_LIMIT + 3; i += 1) {
        // A different source address every time: a per-address limiter would never trigger.
        statuses.push((await register(user.headers, id(400), {}, `10.1.${i}.1`)).statusCode);
      }
      expect(statuses.filter((s) => s === 429)).toHaveLength(3);
      expect(statuses.slice(0, WRITE_LIMIT).every((s) => s === 201)).toBe(true);
      const sync = await fx.app.inject({
        method: 'POST', url: '/api/v1/usage/sync', headers: user.headers, remoteAddress: '10.9.9.9',
        payload: { installationId: id(400), days: [{ date: '2026-10-01', mobileBytes: 1, wifiBytes: 1, chargedWh: 1, wallWh: 1, chargingSessions: 1, estimatedCost: 0.01, currency: 'PLN' }] },
      });
      expect(sync.statusCode).toBe(429);
      expect((await register(other.headers, id(400), {}, '10.1.0.1')).statusCode).toBe(201);
    });
  });
}
