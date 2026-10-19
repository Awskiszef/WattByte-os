import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, registerUser, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

const day = (date: string, mobile: number, wifi: number) => ({
  date,
  mobileBytes: mobile,
  wifiBytes: wifi,
  chargedWh: 12.7,
  wallWh: 14.941,
  chargingSessions: 1,
  estimatedCost: 0.0172,
  currency: 'PLN',
});

describe('devices + usage sync', () => {
  it('requires a registered device, then upserts idempotently and merges devices per day', async () => {
    const reg = await registerUser(ctx.app);

    const noDevice = await ctx.app.inject({
      method: 'POST',
      url: '/api/v1/usage/sync',
      headers: reg.headers,
      payload: { installationId: 'inst-aaaaaaaa', days: [day('2026-10-13', 100, 900)] },
    });
    expect(noDevice.statusCode).toBe(404);

    for (const installationId of ['inst-aaaaaaaa', 'inst-bbbbbbbb']) {
      const dev = await ctx.app.inject({
        method: 'POST',
        url: '/api/v1/devices',
        headers: reg.headers,
        payload: { installationId, platform: 'android', model: 'Pixel' },
      });
      expect(dev.statusCode).toBe(201);
    }
    // Re-registering the same installation does not create a second device.
    await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: reg.headers, payload: { installationId: 'inst-aaaaaaaa', platform: 'android' } });
    const list = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: reg.headers });
    expect(list.json().devices).toHaveLength(2);

    const sync = (installationId: string, days: unknown[]) =>
      ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: reg.headers, payload: { installationId, days } });

    const a1 = await sync('inst-aaaaaaaa', [day('2026-10-13', 100, 900), day('2026-10-12', 50, 50)]);
    expect(a1.statusCode).toBe(200);
    expect(a1.json()).toEqual({ accepted: 2, dates: ['2026-10-12', '2026-10-13'] });
    const a2 = await sync('inst-aaaaaaaa', [day('2026-10-13', 120, 900)]); // same day again: replaces, no duplicate
    expect(a2.statusCode).toBe(200);
    await sync('inst-bbbbbbbb', [day('2026-10-13', 10, 10)]);

    const daily = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: reg.headers });
    expect(daily.statusCode).toBe(200);
    const days = daily.json().days as { date: string; mobileBytes: number; wifiBytes: number; chargingSessions: number; wallWh: number }[];
    expect(days.map((d) => d.date)).toEqual(['2026-10-12', '2026-10-13']);
    expect(days[1]).toMatchObject({ mobileBytes: 130, wifiBytes: 910, chargingSessions: 2, wallWh: 29.882 });
  });

  it('validates ranges and dates', async () => {
    const reg = await registerUser(ctx.app);
    const bad = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-13-01&to=2026-10-31', headers: reg.headers });
    expect(bad.statusCode).toBe(400);
    const reversed = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-31&to=2026-10-01', headers: reg.headers });
    expect(reversed.statusCode).toBe(400);
    expect(reversed.json().error.code).toBe('invalid_range');
  });

  it('users cannot see each other', async () => {
    const a = await registerUser(ctx.app, 'a@b.co');
    const b = await registerUser(ctx.app, 'b@b.co');
    await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: a.headers, payload: { installationId: 'inst-aaaaaaaa', platform: 'ios' } });
    await ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: a.headers, payload: { installationId: 'inst-aaaaaaaa', days: [day('2026-10-13', 1, 1)] } });
    const other = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: b.headers });
    expect(other.json().days).toEqual([]);
  });
});
