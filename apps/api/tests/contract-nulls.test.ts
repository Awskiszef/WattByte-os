/**
 * Regression for an earlier bug: generated Dart clients send an absent optional field as an explicit
 * `null`, and the API answered 400. Every request body of every route is posted here with `null` for
 * each optional or nullable property (found by walking the published OpenAPI schemas, so a field added
 * later is covered without touching this file), and also with that property left out.
 */
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';

import { sampleInput } from './helpers.js';
import { type Auth, type CloudFixture, type FixtureFactory, memoryFixture, postgresAvailable, postgresFixtureIn, registerAccount } from './cloud-support.js';

type Path = (string | number)[];

// Hundreds of requests and several scrypt hashes; a loaded machine needs more than the 5 s default.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// ------------------------------------------------------------------ schema walking

interface Schema {
  $ref?: string;
  type?: string | string[];
  nullable?: boolean;
  anyOf?: Schema[];
  properties?: Record<string, Schema>;
  required?: string[];
  items?: Schema;
}

interface Target {
  path: Path;
  /** May be left out of the body. */
  optional: boolean;
}

function walker(components: Record<string, Schema>) {
  const deref = (s: Schema): Schema => {
    if (!s.$ref) return s;
    const name = s.$ref.replace('#/components/schemas/', '');
    const target = components[name];
    if (!target) throw new Error(`unresolved ${s.$ref}`);
    return target;
  };
  const isNullable = (s: Schema): boolean =>
    s.nullable === true || (Array.isArray(s.type) && s.type.includes('null')) || (s.anyOf ?? []).some((a) => a.type === 'null');

  /** Every property that may be absent or null, with its path (array items are addressed as index 0). */
  const targets = (schema: Schema, path: Path = [], out: Target[] = []): Target[] => {
    const s = deref(schema);
    if (s.properties) {
      const required = new Set(s.required ?? []);
      for (const [name, prop] of Object.entries(s.properties)) {
        const optional = !required.has(name);
        if (optional || isNullable(deref(prop))) out.push({ path: [...path, name], optional });
        targets(prop, [...path, name], out);
      }
    } else if (s.items) {
      targets(s.items, [...path, 0], out);
    }
    return out;
  };
  return { targets };
}

function setAt(root: unknown, path: Path, value: unknown): void {
  let node = root as Record<string | number, unknown>;
  for (const key of path.slice(0, -1)) {
    const next = node[key];
    if (typeof next !== 'object' || next === null) throw new Error(`fixture has no ${path.join('.')} to put a null into`);
    node = next as Record<string | number, unknown>;
  }
  node[path[path.length - 1]!] = value;
}

function deleteAt(root: unknown, path: Path): void {
  let node = root as Record<string | number, unknown>;
  for (const key of path.slice(0, -1)) node = node[key] as Record<string | number, unknown>;
  delete node[path[path.length - 1]!];
}

const clone = <T>(v: T): T => structuredClone(v);

// ------------------------------------------------------------------ one valid request per body-bearing route

interface Ctx {
  fx: CloudFixture;
  user: Auth;
  installationId: string;
  /** A fresh refresh token (refresh rotates, logout consumes). */
  freshRefreshToken(): Promise<string>;
  uniqueEmail(): string;
}

interface Body {
  auth: boolean;
  /** Statuses that count as success for this route (default: any 2xx). */
  expect?: number[];
  /** A valid body with EVERY optional field present and non-null. */
  body: (ctx: Ctx) => Promise<unknown> | unknown;
  /**
   * Top-level fields that only make sense together (a capacity and its source). Nulling or dropping ONE of
   * them is a cross-field rule violation, a 400 `validation` that names the rule, not a null-handling bug: the
   * single-field probes skip them and a dedicated test pins the rule. Nulling or dropping ALL of them is probed.
   */
  coupled?: string[];
}

const BODIES: Record<string, Body> = {
  'POST /api/v1/auth/register': { auth: false, body: (c) => ({ email: c.uniqueEmail(), password: 'correct horse battery', displayName: 'Null Tester' }) },
  'POST /api/v1/auth/login': { auth: false, body: (c) => ({ email: c.user.email, password: 'correct horse battery' }) },
  'POST /api/v1/auth/refresh': { auth: false, body: async (c) => ({ refreshToken: await c.freshRefreshToken() }) },
  'POST /api/v1/auth/logout': { auth: false, expect: [204], body: async (c) => ({ refreshToken: await c.freshRefreshToken() }) },
  // Not configured yet: the documented answer is 501, and it must come from the handler, not from validation.
  'POST /api/v1/auth/apple': { auth: false, expect: [501], body: () => ({ idToken: 'x'.repeat(20) }) },
  'POST /api/v1/auth/google': { auth: false, expect: [501], body: () => ({ idToken: 'x'.repeat(20) }) },
  'PATCH /api/v1/me': { auth: true, body: () => ({ displayName: 'New Name' }) },
  'PUT /api/v1/me/settings': {
    auth: true,
    body: () => ({
      countryCode: 'PL',
      countryCodeSource: 'detected',
      currencyCode: 'PLN',
      currencyCodeSource: 'manual',
      electricityPriceMode: 'automatic',
      manualElectricityPrice: 1.2,
      electricityPriceSource: 'migratedManual',
    }),
  },
  'POST /api/v1/devices': {
    auth: true,
    body: (c) => ({
      installationId: c.installationId,
      platform: 'android',
      model: 'Pixel 8',
      modelIdentifier: 'Pixel 8',
      designCapacityMah: 4575,
      designCapacityWh: 17.6,
      designCapacitySource: 'localDeviceDatabase',
      estimatedFullChargeCapacityMah: 4400,
      estimatedFullChargeCapacityWh: 16.9,
      fullChargeCapacitySource: 'androidChargeCounter',
      fullChargeCapacityConfidence: 'medium',
    }),
    // Design capacity and the estimate are two groups stored atomically (docs/BATTERY_CAPACITY.md).
    coupled: [
      'designCapacityMah', 'designCapacityWh', 'designCapacitySource',
      'estimatedFullChargeCapacityMah', 'estimatedFullChargeCapacityWh', 'fullChargeCapacitySource', 'fullChargeCapacityConfidence',
    ],
  },
  'POST /api/v1/usage/sync': {
    auth: true,
    body: (c) => ({
      installationId: c.installationId,
      days: [
        { date: '2026-10-12', mobileBytes: 1, wifiBytes: 2, chargedWh: 3, wallWh: 4, chargingSessions: 1, estimatedCost: 0.1, currency: 'PLN', dataEstimated: false, energyEstimated: true },
      ],
    }),
  },
  ...Object.fromEntries(
    ['insight', 'weekly-summary', 'monthly-summary', 'roast'].map((task) => [
      `POST /api/v1/ai/${task}`,
      {
        auth: true,
        body: () => ({
          mode: 'friendly',
          locale: 'pl',
          input: { ...sampleInput, previousPeriodChangePercent: 12.5, wifiSharePercent: 88.5, averageSessionMah: 2400 },
        }),
      } satisfies Body,
    ]),
  ),
};

function describeNulls(label: string, make: FixtureFactory, enabled = true): void {
  describe.skipIf(!enabled)(`explicit null for optional fields (${label})`, () => {
    let fx: CloudFixture;
    let ctx: Ctx;
    let components: Record<string, Schema>;
    let operations: { key: string; method: string; path: string; schema: Schema }[];

    beforeAll(async () => {
      // Generous limits: this suite sends hundreds of requests from one address.
      fx = await make({ AI_FREE_DAILY_LIMIT: '100000', AI_RATE_LIMIT_PER_MIN: '100000', RATE_LIMIT_PER_MIN: '100000' });
      const user = await registerAccount(fx, 'nulls');
      const installationId = `install-nulls-${Date.now().toString(36)}`;
      ctx = {
        fx,
        user,
        installationId,
        uniqueEmail: () => fx.email('nulls-reg'),
        freshRefreshToken: async () => {
          const res = await fx.app.inject({ method: 'POST', url: '/api/v1/auth/login', payload: { email: user.email, password: user.password } });
          return (res.json() as { tokens: { refreshToken: string } }).tokens.refreshToken;
        },
      };
      // The device the usage sync needs.
      const dev = await fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: user.headers, payload: { installationId, platform: 'android' } });
      expect(dev.statusCode).toBe(201);

      const spec = fx.app.swagger() as unknown as {
        paths: Record<string, Record<string, { requestBody?: { content?: Record<string, { schema?: Schema }> } }>>;
        components: { schemas: Record<string, Schema> };
      };
      components = spec.components.schemas;
      operations = [];
      for (const [path, item] of Object.entries(spec.paths)) {
        for (const [method, op] of Object.entries(item)) {
          const schema = op.requestBody?.content?.['application/json']?.schema;
          if (schema) operations.push({ key: `${method.toUpperCase()} ${path}`, method: method.toUpperCase(), path, schema });
        }
      }
    });
    afterAll(() => fx.close());

    const send = async (op: { method: string; path: string }, auth: boolean, payload: unknown) =>
      fx.app.inject({
        method: op.method as 'POST',
        url: op.path,
        ...(auth ? { headers: ctx.user.headers } : {}),
        payload: payload as object,
      });

    it('every route with a request body has a fixture here (a new one must be added to BODIES)', () => {
      expect(operations.length).toBeGreaterThanOrEqual(12);
      expect(operations.map((o) => o.key).filter((k) => !(k in BODIES)), 'routes with a body but no fixture in contract-nulls.test.ts').toEqual([]);
      expect(Object.keys(BODIES).filter((k) => !operations.some((o) => o.key === k)), 'fixtures for routes that no longer take a body').toEqual([]);
    });

    it('finds the optional and nullable fields of the schemas (so the walk is not vacuous)', () => {
      const { targets } = walker(components);
      const names = (key: string) => targets(operations.find((o) => o.key === key)!.schema).map((t) => t.path.join('.'));
      expect(names('POST /api/v1/auth/register')).toEqual(['displayName']);
      expect(names('PATCH /api/v1/me')).toEqual(['displayName']);
      expect(names('PUT /api/v1/me/settings').sort()).toEqual([
        'countryCode',
        'countryCodeSource',
        'currencyCode',
        'currencyCodeSource',
        'electricityPriceMode',
        'electricityPriceSource',
        'manualElectricityPrice',
      ]);
      expect(names('POST /api/v1/devices').sort()).toEqual([
        'designCapacityMah',
        'designCapacitySource',
        'designCapacityWh',
        'estimatedFullChargeCapacityMah',
        'estimatedFullChargeCapacityWh',
        'fullChargeCapacityConfidence',
        'fullChargeCapacitySource',
        'model',
        'modelIdentifier',
      ]);
      expect(names('POST /api/v1/usage/sync').sort()).toEqual(['days.0.dataEstimated', 'days.0.energyEstimated']);
      expect(names('POST /api/v1/ai/insight').sort()).toEqual(['input.averageSessionMah', 'input.previousPeriodChangePercent', 'input.wifiSharePercent', 'locale', 'mode']);
      expect(names('POST /api/v1/auth/login')).toEqual([]);
    });

    it('the base bodies are valid (a null variant failing is then the null\'s fault)', async () => {
      for (const op of operations) {
        const fixture = BODIES[op.key];
        if (!fixture) continue;
        const res = await send(op, fixture.auth, await fixture.body(ctx));
        const ok = fixture.expect ? fixture.expect.includes(res.statusCode) : res.statusCode >= 200 && res.statusCode < 300;
        expect(ok, `${op.key} base body -> ${res.statusCode} ${res.body.slice(0, 160)}`).toBe(true);
      }
    });

    it('every optional or nullable property accepts an explicit null, alone and all at once, and may be left out', async () => {
      const { targets } = walker(components);
      const failures: string[] = [];
      let sent = 0;
      for (const op of operations) {
        const fixture = BODIES[op.key];
        if (!fixture) continue;
        const found = targets(op.schema);
        const check = async (label: string, payload: unknown) => {
          const res = await send(op, fixture.auth, payload);
          sent += 1;
          const ok = fixture.expect ? fixture.expect.includes(res.statusCode) : res.statusCode >= 200 && res.statusCode < 300;
          if (!ok) failures.push(`${op.key} ${label} -> ${res.statusCode} ${res.body.slice(0, 140)}`);
        };
        for (const t of found) {
          // A member of a coupled group is probed with its whole group (below), see Body.coupled.
          if (fixture.coupled?.includes(String(t.path[0])) && t.path.length === 1) continue;
          const withNull = clone(await fixture.body(ctx));
          setAt(withNull, t.path, null);
          await check(`${t.path.join('.')}: null`, withNull);
          if (t.optional) {
            const without = clone(await fixture.body(ctx));
            deleteAt(without, t.path);
            await check(`${t.path.join('.')}: absent`, without);
          }
        }
        if (found.length > 0) {
          const allNull = clone(await fixture.body(ctx));
          for (const t of found) setAt(allNull, t.path, null);
          await check('every optional field null at once', allNull);
          const allAbsent = clone(await fixture.body(ctx));
          for (const t of found.filter((x) => x.optional)) deleteAt(allAbsent, t.path);
          await check('every optional field absent at once', allAbsent);
        }
      }
      expect(sent).toBeGreaterThan(60);
      expect(failures, 'null for an optional field must never be a 400').toEqual([]);
    });

    it('null for a REQUIRED, non-nullable field is still rejected (the walk distinguishes the two)', async () => {
      const cases: [string, Path][] = [
        ['POST /api/v1/auth/register', ['email']],
        ['POST /api/v1/auth/register', ['password']],
        ['POST /api/v1/auth/login', ['email']],
        ['POST /api/v1/auth/refresh', ['refreshToken']],
        ['POST /api/v1/devices', ['installationId']],
        ['POST /api/v1/devices', ['platform']],
        ['POST /api/v1/usage/sync', ['days']],
        ['POST /api/v1/usage/sync', ['days', 0, 'mobileBytes']],
        ['POST /api/v1/usage/sync', ['days', 0, 'currency']],
        ['POST /api/v1/ai/insight', ['input']],
        ['POST /api/v1/ai/insight', ['input', 'period']],
      ];
      for (const [key, path] of cases) {
        const op = operations.find((o) => o.key === key)!;
        const fixture = BODIES[key]!;
        const payload = clone(await fixture.body(ctx));
        setAt(payload, path, null);
        const res = await send(op, fixture.auth, payload);
        expect(res.statusCode, `${key} ${path.join('.')}: null`).toBe(400);
      }
    });

    it('semantic requirements keep their documented 4xx: manual price mode needs a price, whatever mix of null and absent is sent', async () => {
      const own = await registerAccount(fx, 'nulls-manual');
      const put = (payload: unknown) => fx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: own.headers, payload: payload as object });
      const get = async () => (await fx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers: own.headers })).json();
      const none = await put({ electricityPriceMode: 'manual', manualElectricityPrice: null });
      expect(none.statusCode).toBe(400);
      expect(none.json().error.code).toBe('manual_price_required');
      expect((await put({ electricityPriceMode: 'manual' })).statusCode).toBe(400);
      expect((await put({ electricityPriceMode: 'manual', manualElectricityPrice: 0.9 })).statusCode).toBe(200);
      // A null mode means "not given": it stays manual, and a null country clears the country.
      expect((await put({ electricityPriceMode: null, manualElectricityPrice: 0.9, countryCode: null })).statusCode).toBe(200);
      expect(await get()).toMatchObject({ electricityPriceMode: 'manual', manualElectricityPrice: 0.9, countryCode: null });

      // Manual mode may never be left without a price, however the request spells it: nothing changes on a 400.
      for (const payload of [{ electricityPriceMode: 'manual', manualElectricityPrice: null }, { manualElectricityPrice: null }, { electricityPriceMode: null, manualElectricityPrice: null }]) {
        const res = await put(payload);
        expect(res.statusCode, JSON.stringify(payload)).toBe(400);
        expect(res.json().error.code).toBe('manual_price_required');
        expect(await get()).toMatchObject({ electricityPriceMode: 'manual', manualElectricityPrice: 0.9 });
      }
      // Leaving the price out keeps it; switching to automatic may clear it.
      expect((await put({ countryCode: 'PL' })).statusCode).toBe(200);
      expect(await get()).toMatchObject({ electricityPriceMode: 'manual', manualElectricityPrice: 0.9, countryCode: 'PL' });
      expect((await put({ electricityPriceMode: 'automatic', manualElectricityPrice: null })).statusCode).toBe(200);
      expect(await get()).toMatchObject({ electricityPriceMode: 'automatic', manualElectricityPrice: null });
      // An all-null request (what a generated client sends for an empty update) is valid in automatic mode.
      expect((await put({ countryCode: null, currencyCode: null, electricityPriceMode: null, manualElectricityPrice: null })).statusCode).toBe(200);
      expect(await get()).toMatchObject({ countryCode: null, currencyCode: null, electricityPriceMode: 'automatic', manualElectricityPrice: null });
    });

    it('a populated battery group is a unit: all members null is fine, one member null is a validation 400 naming the rule', async () => {
      const own = await registerAccount(fx, 'nulls-groups');
      const post = (extra: Record<string, unknown>) =>
        fx.app.inject({ method: 'POST', url: '/api/v1/devices', headers: own.headers, payload: { installationId: 'install-nulls-groups', platform: 'ios', ...extra } });
      const design = { designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase' };
      const estimate = { estimatedFullChargeCapacityMah: 3190.5, estimatedFullChargeCapacityWh: 12.2, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' };
      const nullDesign = { designCapacityMah: null, designCapacityWh: null, designCapacitySource: null };
      const nullEstimate = { estimatedFullChargeCapacityMah: null, estimatedFullChargeCapacityWh: null, fullChargeCapacitySource: null, fullChargeCapacityConfidence: null };

      // What a generated client sends for a registration that only knows the design capacity.
      expect((await post({ ...design, ...nullEstimate })).statusCode).toBe(201);
      expect((await post({ ...nullDesign, ...estimate })).statusCode).toBe(201);
      expect((await post({ ...nullDesign, ...nullEstimate })).statusCode).toBe(201);

      // One member of a populated group nulled (or dropped): the group is incoherent, and the answer says why.
      const broken: [string, Record<string, unknown>, RegExp][] = [
        ['design mAh null', { ...design, designCapacityMah: null }, /designCapacityWh needs designCapacityMah/],
        ['design source null', { ...design, designCapacitySource: null }, /need a designCapacitySource/],
        ['estimate mAh null', { ...estimate, estimatedFullChargeCapacityMah: null }, /estimatedFullChargeCapacityWh needs estimatedFullChargeCapacityMah/],
        ['estimate source null', { ...estimate, fullChargeCapacitySource: null }, /need a fullChargeCapacitySource/],
        ['estimate confidence null', { ...estimate, fullChargeCapacityConfidence: null }, /needs a fullChargeCapacityConfidence/],
      ];
      for (const [name, body, message] of broken) {
        const res = await post(body);
        expect(res.statusCode, name).toBe(400);
        expect(res.json().error.code, name).toBe('validation');
        expect(res.json().error.message, name).toMatch(message);
      }
      // Wh is optional inside both groups: null (or left out) is fine.
      expect((await post({ ...design, designCapacityWh: null })).statusCode).toBe(201);
      expect((await post({ ...estimate, estimatedFullChargeCapacityWh: null })).statusCode).toBe(201);
    });

    it('a null mode or locale means the defaults (normal, en), and a null optional field changes nothing stored', async () => {
      const ai = await fx.app.inject({
        method: 'POST',
        url: '/api/v1/ai/insight',
        headers: ctx.user.headers,
        payload: { mode: null, locale: null, input: { ...sampleInput, previousPeriodChangePercent: null, wifiSharePercent: null, averageSessionMah: null } },
      });
      expect(ai.statusCode).toBe(200);
      expect(ai.json().output.tone).toBe('normal');

      // A device registered with nulls keeps what an earlier registration stored.
      const own = await registerAccount(fx, 'nulls-device');
      const first = await fx.app.inject({
        method: 'POST',
        url: '/api/v1/devices',
        headers: own.headers,
        payload: {
          installationId: 'install-nulls-keep', platform: 'ios', model: 'iPhone 15 Pro', modelIdentifier: 'iPhone16,1',
          designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase',
          estimatedFullChargeCapacityMah: 3190.5, estimatedFullChargeCapacityWh: 12.2, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high',
        },
      });
      expect(first.statusCode).toBe(201);
      const again = await fx.app.inject({
        method: 'POST',
        url: '/api/v1/devices',
        headers: own.headers,
        payload: {
          installationId: 'install-nulls-keep', platform: 'ios', model: null, modelIdentifier: null,
          designCapacityMah: null, designCapacityWh: null, designCapacitySource: null,
          estimatedFullChargeCapacityMah: null, estimatedFullChargeCapacityWh: null, fullChargeCapacitySource: null, fullChargeCapacityConfidence: null,
        },
      });
      expect(again.statusCode).toBe(201);
      expect(again.json()).toMatchObject({
        model: 'iPhone 15 Pro', modelIdentifier: 'iPhone16,1',
        designCapacityMah: 3274, designCapacityWh: 12.7, designCapacitySource: 'localDeviceDatabase',
        estimatedFullChargeCapacityMah: 3190.5, estimatedFullChargeCapacityWh: 12.2, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high',
      });
    });

    it('usage sync with null flags applies the defaults (dataEstimated false, energyEstimated true)', async () => {
      const res = await fx.app.inject({
        method: 'POST',
        url: '/api/v1/usage/sync',
        headers: ctx.user.headers,
        payload: {
          installationId: ctx.installationId,
          days: [{ date: '2026-10-09', mobileBytes: 1, wifiBytes: 2, chargedWh: 3, wallWh: 4, chargingSessions: 1, estimatedCost: 0.1, currency: 'PLN', dataEstimated: null, energyEstimated: null }],
        },
      });
      expect(res.statusCode).toBe(200);
      const day = (await fx.app.inject({ method: 'GET', url: '/api/v1/usage/daily?from=2026-10-09&to=2026-10-09', headers: ctx.user.headers })).json();
      expect(day.days[0]).toMatchObject({ date: '2026-10-09', dataEstimated: false, energyEstimated: true });
    });
  });
}

describeNulls('memory repositories', memoryFixture);
// Own schema: parallel files that count whole tables in `public` must not see these writes.
describeNulls('PostgreSQL', postgresFixtureIn('wb_cloud_nulls'), postgresAvailable);
