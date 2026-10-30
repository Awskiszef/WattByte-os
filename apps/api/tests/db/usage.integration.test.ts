// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { closePgApp, DATABASE_URL, makePgApp, type PgContext, register, uniqueEmail } from './helpers.js';

const day = {
  date: '2026-10-12',
  mobileBytes: 5,
  wifiBytes: 10,
  chargedWh: 10,
  wallWh: 12,
  chargingSessions: 1,
  estimatedCost: 0.01,
  currency: 'PLN',
  dataEstimated: false,
  energyEstimated: true,
};

describe.skipIf(!DATABASE_URL)('usage sync (PostgreSQL)', () => {
  let ctx: PgContext;
  let headers: { authorization: string };
  let userId: string;
  beforeAll(async () => {
    ctx = await makePgApp();
    const reg = await register(ctx.app, uniqueEmail('usage'));
    userId = reg.user.id;
    headers = { authorization: `Bearer ${reg.tokens.accessToken}` };
    const dev = await ctx.app.inject({ method: 'POST', url: '/api/v1/devices', headers, payload: { installationId: 'install-usage-1', platform: 'android' } });
    expect(dev.statusCode).toBe(201);
  });
  afterAll(() => closePgApp(ctx));

  const sync = (days: unknown[]) =>
    ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers, payload: { installationId: 'install-usage-1', days } });

  it('is idempotent per (user, device, date): a repeat updates instead of duplicating', async () => {
    expect((await sync([day])).statusCode).toBe(200);
    expect((await sync([{ ...day, mobileBytes: 7 }])).statusCode).toBe(200);
    const rows = await ctx.pool.query('SELECT count(*)::int AS n, max(mobile_bytes)::int AS m FROM daily_usage WHERE user_id = $1', [userId]);
    expect(rows.rows[0]).toEqual({ n: 1, m: 7 });
  });

  it('concurrent identical syncs still leave one row', async () => {
    const date = '2026-09-01';
    const res = await Promise.all(Array.from({ length: 10 }, () => sync([{ ...day, date }])));
    expect(res.every((r) => r.statusCode === 200)).toBe(true);
    const n = await ctx.pool.query('SELECT count(*)::int AS n FROM daily_usage WHERE user_id = $1 AND date = $2', [userId, date]);
    expect(n.rows[0].n).toBe(1);
  });

  it('every malformed payload is a 400, never a 500 and never reaches the database', async () => {
    // Scoped to this user: other test files write to daily_usage in parallel, a table-wide count would race with them.
    const before = (await ctx.pool.query('SELECT count(*)::int AS n FROM daily_usage WHERE user_id = $1', [userId])).rows[0].n;
    const bad: unknown[][] = [
      [{ ...day, date: '2026-13-45' }],
      [{ ...day, date: '2026-02-30' }],
      [{ ...day, date: '2999-01-01' }],
      [{ ...day, date: '1999-01-01' }],
      [{ ...day, date: 'not-a-date' }],
      [{ ...day, chargedWh: 1e12 }],
      [{ ...day, wallWh: 1e12 }],
      [{ ...day, estimatedCost: 1e9 }],
      [{ ...day, mobileBytes: 9007199254740991 }],
      [{ ...day, wifiBytes: -1 }],
      [{ ...day, chargedWh: -0.5 }],
      [{ ...day, chargedWh: null }],
      [{ ...day, chargingSessions: 1.5 }],
      [{ ...day, chargingSessions: 100000 }],
      [{ ...day, currency: 'pln' }],
      [{ ...day, currency: 'PLNX' }],
      [{ ...day, mobileBytes: '5' }],
      [day, { ...day }],
      [],
      Array.from({ length: 93 }, (_, i) => ({ ...day, date: `2026-01-${String((i % 28) + 1).padStart(2, '0')}` })),
    ];
    for (const days of bad) {
      const res = await sync(days);
      expect(res.statusCode, JSON.stringify(days).slice(0, 120)).toBe(400);
    }
    // JSON cannot carry NaN or Infinity; sent as raw tokens the body does not parse.
    for (const token of ['NaN', 'Infinity', '-Infinity']) {
      const raw = `{"installationId":"install-usage-1","days":[{"date":"2026-10-12","mobileBytes":1,"wifiBytes":1,"chargedWh":${token},"wallWh":1,"chargingSessions":0,"estimatedCost":0,"currency":"PLN"}]}`;
      const res = await ctx.app.inject({ method: 'POST', url: '/api/v1/usage/sync', headers: { ...headers, 'content-type': 'application/json' }, payload: raw });
      expect(res.statusCode).toBe(400);
    }
    expect((await ctx.pool.query('SELECT count(*)::int AS n FROM daily_usage WHERE user_id = $1', [userId])).rows[0].n).toBe(before);
  });

  it('GET /usage/daily rejects invalid ranges with 400', async () => {
    for (const q of ['from=2026-13-45&to=2026-14-99', 'from=2026-10-10&to=2026-10-01', 'from=2020-01-01&to=2026-10-01', 'from=x&to=y']) {
      const res = await ctx.app.inject({ method: 'GET', url: `/api/v1/usage/daily?${q}`, headers });
      expect(res.statusCode, q).toBe(400);
    }
    const ok = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers });
    expect(ok.statusCode).toBe(200);
  });
});
