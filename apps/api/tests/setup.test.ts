import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, registerUser, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

describe('account settings', () => {
  it('defaults before the first save, partial updates keep the rest, manual mode needs a price', async () => {
    const reg = await registerUser(ctx.app);
    const initial = await ctx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers: reg.headers });
    expect(initial.statusCode).toBe(200);
    expect(initial.json()).toMatchObject({ countryCode: null, currencyCode: null, electricityPriceMode: 'automatic', manualElectricityPrice: null });

    const first = await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: reg.headers, payload: { countryCode: 'PL', currencyCode: 'PLN' } });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({ countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'automatic' });

    const noPrice = await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: reg.headers, payload: { electricityPriceMode: 'manual' } });
    expect(noPrice.statusCode).toBe(400);
    expect(noPrice.json().error.code).toBe('manual_price_required');

    const manual = await ctx.app.inject({
      method: 'PUT', url: '/api/v1/me/settings', headers: reg.headers, payload: { electricityPriceMode: 'manual', manualElectricityPrice: 0.95 },
    });
    expect(manual.json()).toMatchObject({ countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 });

    for (const payload of [{ countryCode: 'Poland' }, { currencyCode: 'zl' }, { manualElectricityPrice: -1 }, { manualElectricityPrice: 1e9 }]) {
      const res = await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: reg.headers, payload });
      expect(res.statusCode, JSON.stringify(payload)).toBe(400);
    }
    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/me/settings' })).statusCode).toBe(401);
  });
});

describe('device-bound battery capacity', () => {
  it('is stored on the registration and kept when a later registration omits it', async () => {
    const reg = await registerUser(ctx.app);
    const first = await ctx.app.inject({
      method: 'POST', url: '/api/v1/devices', headers: reg.headers,
      payload: {
        installationId: 'inst-aaaaaaaa', platform: 'ios', model: 'iPhone', modelIdentifier: 'iPhone16,1',
        designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase',
      },
    });
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({
      modelIdentifier: 'iPhone16,1', designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase',
      estimatedFullChargeCapacityMah: null, estimatedFullChargeCapacityWh: null, fullChargeCapacitySource: null, fullChargeCapacityConfidence: null,
    });

    // The sync path re-registers with the minimum payload; the setup data must survive.
    const again = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: reg.headers, payload: { installationId: 'inst-aaaaaaaa', platform: 'ios' } });
    expect(again.json()).toMatchObject({ id: first.json().id, designCapacityMah: 3274, designCapacitySource: 'localDeviceDatabase' });

    const bad = await ctx.app.inject({
      method: 'POST', url: '/api/v1/devices', headers: reg.headers,
      payload: { installationId: 'inst-aaaaaaaa', platform: 'ios', designCapacityMah: 0, designCapacitySource: 'guess' },
    });
    expect(bad.statusCode).toBe(400);

    const list = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: reg.headers });
    expect(list.json().devices).toHaveLength(1);
    expect(list.json().devices[0].designCapacityMah).toBe(3274);
  });

  it('serves the shared catalog publicly and answers 404 for unknown models', async () => {
    const known = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/iPhone16,1' });
    expect(known.statusCode).toBe(200);
    expect(known.json()).toMatchObject({ manufacturer: 'Apple', model: 'iPhone 15 Pro', designCapacityMah: 3274, designCapacityWh: 12.7 });
    const samsung = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/SM-S921B' });
    expect(samsung.json().model).toBe('Galaxy S24');
    const unknown = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/iPhone19,2' });
    expect(unknown.statusCode).toBe(404);
    expect(unknown.json().error.code).toBe('device_specification_unknown');
    expect((await ctx.app.inject({ method: 'GET', url: `/api/v1/devices/specifications/${'x'.repeat(65)}` })).statusCode).toBe(400);
  });
});

describe('GET /api/v1/region', () => {
  it('answers null unless a configured proxy header carries a real country code', async () => {
    const off = await ctx.app.inject({ method: 'GET', url: '/api/v1/region', headers: { 'cf-ipcountry': 'PL' } });
    expect(off.json()).toEqual({ countryCode: null, source: 'none' });
    await ctx.app.close();

    ctx = await makeApp({ COUNTRY_HEADER: 'cf-ipcountry', TRUST_PROXY_HOPS: '1' });
    const on = await ctx.app.inject({ method: 'GET', url: '/api/v1/region', headers: { 'cf-ipcountry': 'pl' } });
    expect(on.json()).toEqual({ countryCode: 'PL', source: 'backendCountry' });
    for (const v of ['XX', 'T1', 'Poland', '']) {
      const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/region', headers: { 'cf-ipcountry': v } });
      expect(res.json().countryCode, v).toBeNull();
    }
  });
});
