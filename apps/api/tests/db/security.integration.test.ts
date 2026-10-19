import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { expectErrorBody, sampleDay, seedUser } from '../support.js';
import { closePgApp, DATABASE_URL, makePgApp, type PgContext, uniqueEmail } from './helpers.js';

/** The security rules that only a real database can break: SQL handling, column types, row scoping in SQL. */
describe.skipIf(!DATABASE_URL)('security regression (PostgreSQL)', () => {
  let ctx: PgContext;
  beforeAll(async () => {
    ctx = await makePgApp();
  });
  afterAll(() => closePgApp(ctx));

  const post = (url: string, payload: unknown, headers: Record<string, string> = {}) =>
    ctx.app.inject({ method: 'POST', url, payload: payload as object, headers });
  const auth = (token: string) => ({ authorization: `Bearer ${token}` });

  it('SQL-looking but valid e-mail addresses are data, not code', async () => {
    const tag = `${process.pid}-${Date.now()}`;
    const tricky = [`o'brien--${tag}@test.wattbyte`, `x'or'1'or'1-${tag}@test.wattbyte`, `a+b.c_d-${tag}@test.wattbyte`];
    for (const email of tricky) {
      const res = await post('/api/v1/auth/register', { email, password: 'password123' });
      expect(res.statusCode, email).toBe(201);
      expect(res.json().user.email).toBe(email);
      const login = await post('/api/v1/auth/login', { email: email.toUpperCase(), password: 'password123' });
      expect(login.statusCode, email).toBe(200);
    }
    // The classic payloads are rejected as e-mail addresses, and the table is still there.
    for (const email of ["'; DROP TABLE users; --", "x@test.wattbyte' OR '1'='1"]) {
      expect((await post('/api/v1/auth/login', { email, password: 'password123' })).statusCode).toBe(400);
    }
    const count = await ctx.pool.query('SELECT count(*)::int AS n FROM users');
    expect(count.rows[0].n).toBeGreaterThanOrEqual(tricky.length);
  });

  it('a NUL character in any text field is a 400, not a database error', async () => {
    const reg = await seedUser(ctx.repos, uniqueEmail('nul'));
    const headers = auth(reg.accessToken);
    const cases: [string, string, unknown][] = [
      ['register displayName', '/api/v1/auth/register', { email: uniqueEmail('nul2'), password: 'password123', displayName: 'a\u0000b' }],
      ['device installationId', '/api/v1/devices', { installationId: 'install\u0000-1234', platform: 'ios' }],
      ['device model', '/api/v1/devices', { installationId: 'install-nul-5678', platform: 'ios', model: 'iPhone\u0000' }],
      ['device modelIdentifier', '/api/v1/devices', { installationId: 'install-nul-9012', platform: 'ios', modelIdentifier: 'iPhone16,1\u0000' }],
    ];
    for (const [name, url, payload] of cases) {
      const res = await post(url, payload, url.includes('register') ? {} : headers);
      expect(res.statusCode, name).toBe(400);
      expectErrorBody(res.json(), 'validation');
    }
    const patch = await ctx.app.inject({ method: 'PATCH', url: '/api/v1/me', headers, payload: { displayName: 'x\u0000y' } });
    expect(patch.statusCode).toBe(400);
    // NUL spelled as a JSON escape inside a nested value is found too.
    const nested = await post('/api/v1/usage/sync', { installationId: 'install-nul-3456', days: [{ ...sampleDay('2026-10-10'), currency: 'P\u0000N' }] }, headers);
    expect(nested.statusCode).toBe(400);
  });

  it('capacities below the column resolution are a 400, not a check-constraint failure (500)', async () => {
    const reg = await seedUser(ctx.repos, uniqueEmail('tiny'));
    const headers = auth(reg.accessToken);
    for (const [name, extra] of [
      ['design mAh rounds to 0.0', { designCapacityMah: 0.01, designCapacitySource: 'manual' }],
      ['design mAh below the resolution', { designCapacityMah: 0.09, designCapacitySource: 'manual' }],
      ['design Wh rounds to 0.000', { designCapacityMah: 3000, designCapacityWh: 0.0001, designCapacitySource: 'manual' }],
      ['design Wh below the resolution', { designCapacityMah: 3000, designCapacityWh: 0.0009, designCapacitySource: 'manual' }],
      ['estimated mAh rounds to 0.0', { estimatedFullChargeCapacityMah: 0.01, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }],
      ['estimated mAh below the resolution', { estimatedFullChargeCapacityMah: 0.09, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }],
      ['estimated Wh rounds to 0.000', { estimatedFullChargeCapacityMah: 3000, estimatedFullChargeCapacityWh: 0.0001, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }],
      ['estimated Wh below the resolution', { estimatedFullChargeCapacityMah: 3000, estimatedFullChargeCapacityWh: 0.0009, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }],
    ] as const) {
      const res = await post('/api/v1/devices', { installationId: `install-tiny-${name.length}-${process.pid}`, platform: 'ios', ...extra }, headers);
      expect(res.statusCode, name).toBe(400);
      expectErrorBody(res.json(), 'validation');
    }
    // The smallest storable values are accepted.
    const ok = await post(
      '/api/v1/devices',
      {
        installationId: `install-tiny-ok-${process.pid}`, platform: 'ios',
        designCapacityMah: 0.1, designCapacityWh: 0.001, designCapacitySource: 'manual',
        estimatedFullChargeCapacityMah: 0.1, estimatedFullChargeCapacityWh: 0.001, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'low',
      },
      headers,
    );
    expect(ok.statusCode).toBe(201);
    expect(ok.json()).toMatchObject({ designCapacityMah: 0.1, designCapacityWh: 0.001, estimatedFullChargeCapacityMah: 0.1, estimatedFullChargeCapacityWh: 0.001 });
  });

  it('non-ASCII text round-trips untouched (emoji, combining marks, right-to-left)', async () => {
    const reg = await seedUser(ctx.repos, uniqueEmail('unicode'));
    const names = ['Zażółć gęślą jaźń', '😀🔋⚡', 'é', 'שלום עולם'];
    for (const displayName of names) {
      const res = await ctx.app.inject({ method: 'PATCH', url: '/api/v1/me', headers: auth(reg.accessToken), payload: { displayName } });
      expect(res.statusCode, displayName).toBe(200);
      expect(res.json().displayName).toBe(displayName);
    }
  });

  it('row scoping holds in SQL: devices and usage of another user are neither listed, deleted nor writable', async () => {
    const a = await seedUser(ctx.repos, uniqueEmail('idor-a'));
    const b = await seedUser(ctx.repos, uniqueEmail('idor-b'));
    const bDevice = (await post('/api/v1/devices', { installationId: 'b-pg-install-1', platform: 'ios' }, auth(b.accessToken))).json() as { id: string };
    expect((await post('/api/v1/usage/sync', { installationId: 'b-pg-install-1', days: [sampleDay('2026-10-10')] }, auth(b.accessToken))).statusCode).toBe(200);

    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/devices', headers: auth(a.accessToken) })).json().devices).toEqual([]);
    const del = await ctx.app.inject({ method: 'DELETE', url: `/api/v1/devices/${bDevice.id}`, headers: auth(a.accessToken) });
    expect(del.statusCode).toBe(404);
    const aSync = await post('/api/v1/usage/sync', { installationId: 'b-pg-install-1', days: [{ ...sampleDay('2026-10-10'), mobileBytes: 7 }] }, auth(a.accessToken));
    expect(aSync.statusCode).toBe(404);
    const aDaily = await ctx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-01&to=2026-10-31', headers: auth(a.accessToken) });
    expect(aDaily.json().days).toEqual([]);

    const rows = await ctx.pool.query('SELECT user_id, mobile_bytes::int AS mobile FROM daily_usage WHERE device_id = $1', [bDevice.id]);
    expect(rows.rows).toEqual([{ user_id: b.userId, mobile: 1_000 }]);
  });

  it('mass assignment against the real schema: the stored plan stays free', async () => {
    const email = uniqueEmail('mass');
    const res = await post('/api/v1/auth/register', { email, password: 'password123', plan: 'premium', isPremium: true });
    expect(res.statusCode).toBe(201);
    const stored = await ctx.pool.query('SELECT plan FROM users WHERE id = $1', [res.json().user.id]);
    expect(stored.rows[0].plan).toBe('free');
    const token = res.json().tokens.accessToken as string;
    await ctx.app.inject({ method: 'PATCH', url: '/api/v1/me', headers: auth(token), payload: { displayName: 'x', plan: 'premium' } });
    await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: auth(token), payload: { countryCode: 'PL', plan: 'premium' } });
    expect((await ctx.pool.query('SELECT plan FROM users WHERE id = $1', [res.json().user.id])).rows[0].plan).toBe('free');
  });
});
