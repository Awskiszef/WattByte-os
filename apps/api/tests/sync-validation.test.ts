// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { makeApp, registerUser, type TestContext } from './helpers.js';

let ctx: TestContext;
beforeEach(async () => {
  ctx = await makeApp();
});
afterEach(() => ctx.app.close());

const day = {
  date: '2026-10-12',
  mobileBytes: 5,
  wifiBytes: 10,
  chargedWh: 10,
  wallWh: 12,
  chargingSessions: 1,
  estimatedCost: 0.01,
  currency: 'PLN',
};

describe('usage sync payload validation (no database needed)', () => {
  it('rejects malformed, out-of-range, non-finite and duplicate input with 400', async () => {
    const reg = await registerUser(ctx.app);
    await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: reg.headers, payload: { installationId: 'install-val-1', platform: 'android' } });
    const send = (payload: string | object) =>
      ctx.app.inject({
        method: 'POST',
        url: '/api/v1/usage/sync',
        headers: { ...reg.headers, 'content-type': 'application/json' },
        payload: typeof payload === 'string' ? payload : JSON.stringify(payload),
      });

    const cases: [string, object][] = [
      ['month 13', { ...day, date: '2026-13-45' }],
      ['feb 30', { ...day, date: '2026-02-30' }],
      ['future', { ...day, date: '2999-01-01' }],
      ['too old', { ...day, date: '1999-01-01' }],
      ['garbage date', { ...day, date: 'tomorrow' }],
      ['huge Wh', { ...day, chargedWh: 1e12 }],
      ['huge wall Wh', { ...day, wallWh: 1e300 }],
      ['huge cost', { ...day, estimatedCost: 1e9 }],
      ['max safe int bytes', { ...day, mobileBytes: Number.MAX_SAFE_INTEGER }],
      ['negative bytes', { ...day, wifiBytes: -1 }],
      ['negative Wh', { ...day, chargedWh: -1 }],
      ['null number', { ...day, chargedWh: null }],
      ['fractional sessions', { ...day, chargingSessions: 0.5 }],
      ['too many sessions', { ...day, chargingSessions: 5000 }],
      ['lower case currency', { ...day, currency: 'pln' }],
      ['string number', { ...day, mobileBytes: '5' }],
    ];
    for (const [name, d] of cases) {
      const res = await send({ installationId: 'install-val-1', days: [d] });
      expect(res.statusCode, name).toBe(400);
    }
    expect((await send({ installationId: 'install-val-1', days: [day, day] })).statusCode).toBe(400);
    expect((await send({ installationId: 'install-val-1', days: [] })).statusCode).toBe(400);
    for (const token of ['NaN', 'Infinity', '-Infinity']) {
      const raw = `{"installationId":"install-val-1","days":[{"date":"2026-10-12","mobileBytes":1,"wifiBytes":1,"chargedWh":${token},"wallWh":1,"chargingSessions":0,"estimatedCost":0,"currency":"PLN"}]}`;
      expect((await send(raw)).statusCode, token).toBe(400);
    }
    expect((await send({ installationId: 'install-val-1', days: [day] })).statusCode).toBe(200);
  });
});
