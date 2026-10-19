import { afterEach, describe, expect, it } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { EurostatElectricityPriceProvider, latestValue, type JsonStat } from '../src/modules/electricity/eurostat.js';
import type { ElectricityPriceProvider } from '../src/modules/electricity/provider.js';
import { ElectricityPriceService } from '../src/modules/electricity/service.js';
import { makeApp, registerUser, type TestContext } from './helpers.js';

/** Trimmed real answer of nrg_pc_204 for PL (2026-10-12): three half-years, the newest flagged provisional. */
const PL_FIXTURE: JsonStat = {
  value: { '0': 1.0827, '1': 1.1505, '2': 1.2724 },
  id: ['freq', 'siec', 'nrg_cons', 'unit', 'tax', 'currency', 'geo', 'time'],
  size: [1, 1, 1, 1, 1, 1, 1, 3],
  dimension: {
    freq: { category: { index: { S: 0 } } },
    siec: { category: { index: { E7000: 0 } } },
    nrg_cons: { category: { index: { 'KWH2500-4999': 0 } } },
    unit: { category: { index: { KWH: 0 } } },
    tax: { category: { index: { I_TAX: 0 } } },
    currency: { category: { index: { NAC: 0 } } },
    geo: { category: { index: { PL: 0 } } },
    time: { category: { index: { '2025-S1': 0, '2025-S2': 1, '2026-S1': 2 } } },
  },
};

/** The same query for a country Eurostat does not report (US): empty geo and no values. */
const EMPTY_FIXTURE: JsonStat = { ...PL_FIXTURE, value: {}, size: [1, 1, 1, 1, 1, 1, 0, 3], dimension: { ...PL_FIXTURE.dimension, geo: { category: { index: {} } } } };

const fetchJson = (body: unknown, status = 200) => async () => ({ ok: status < 400, status, json: async () => body });

describe('EurostatElectricityPriceProvider', () => {
  it('builds the household query: electricity, band DC, all taxes, national currency, per kWh', () => {
    const url = new URL(new EurostatElectricityPriceProvider().queryUrl('PL'));
    expect(url.pathname.endsWith('/nrg_pc_204')).toBe(true);
    expect(Object.fromEntries(url.searchParams)).toEqual({
      geo: 'PL', siec: 'E7000', nrg_cons: 'KWH2500-4999', unit: 'KWH', tax: 'I_TAX', currency: 'NAC', lastTimePeriod: '3', format: 'JSON',
    });
    expect(new URL(new EurostatElectricityPriceProvider().queryUrl('GR')).searchParams.get('geo')).toBe('EL');
  });

  it('PL -> latest period with a value, in PLN, taxes and network costs included', async () => {
    const calls: string[] = [];
    const provider = new EurostatElectricityPriceProvider({ fetch: async (url) => { calls.push(url); return fetchJson(PL_FIXTURE)(); } });
    const r = await provider.getHouseholdPrice('PL');
    expect(r).toEqual({ countryCode: 'PL', currency: 'PLN', pricePerKwh: 1.2724, period: '2026-S1', source: 'eurostat', includesTaxes: true, includesNetworkCosts: true });
    expect(calls).toHaveLength(1);
  });

  it('falls back to the previous half-year when the newest one is still empty', () => {
    const partial: JsonStat = { ...PL_FIXTURE, value: { '0': 1.0827, '1': 1.1505 } };
    expect(latestValue(partial)).toEqual({ period: '2025-S2', value: 1.1505 });
    expect(latestValue({ ...PL_FIXTURE, value: {} })).toBeNull();
    // A response with several categories per dimension cannot be read as one series.
    expect(latestValue({ ...PL_FIXTURE, size: [1, 1, 2, 1, 1, 1, 1, 3] })).toBeNull();
  });

  it('a country outside the dataset is "no price" (null), not an error; a non-EU code is not even queried', async () => {
    let calls = 0;
    const provider = new EurostatElectricityPriceProvider({ fetch: async () => { calls++; return fetchJson(EMPTY_FIXTURE)(); } });
    expect(await provider.getHouseholdPrice('US')).toBeNull();
    expect(calls).toBe(0);
    expect(await provider.getHouseholdPrice('PL')).toBeNull();
    expect(calls).toBe(1);
  });

  it('transport failures throw so the service can fall back to the cache', async () => {
    const provider = new EurostatElectricityPriceProvider({ fetch: fetchJson({ error: [{ status: 400 }] }, 400) });
    await expect(provider.getHouseholdPrice('PL')).rejects.toThrow(/eurostat responded 400/);
    const broken = new EurostatElectricityPriceProvider({ fetch: async () => { throw new Error('ECONNRESET'); } });
    await expect(broken.getHouseholdPrice('PL')).rejects.toThrow('ECONNRESET');
  });
});

class ScriptedProvider implements ElectricityPriceProvider {
  readonly id = 'eurostat' as const;
  calls = 0;
  price: number | null = 1.2724;
  fail = false;
  async getHouseholdPrice(countryCode: string) {
    this.calls++;
    if (this.fail) throw new Error('source down');
    if (this.price == null) return null;
    return { countryCode, currency: 'PLN', pricePerKwh: this.price, period: '2026-S1', source: this.id, includesTaxes: true, includesNetworkCosts: true };
  }
}

describe('ElectricityPriceService', () => {
  const DAY = 86_400_000;

  function make() {
    let now = new Date('2026-10-13T10:00:00Z');
    const provider = new ScriptedProvider();
    const repos = new MemoryRepositories();
    const service = new ElectricityPriceService([provider], repos.prices, { cacheMs: 7 * DAY, now: () => now });
    return { provider, repos, service, advance: (ms: number) => (now = new Date(now.getTime() + ms)) };
  }

  it('asks the source once, then serves the cache until it expires', async () => {
    const { provider, service, advance } = make();
    expect((await service.get('PL'))?.pricePerKwh).toBe(1.2724);
    expect(await service.get('PL')).toMatchObject({ stale: false, updatedAt: '2026-10-13T10:00:00.000Z' });
    advance(6 * DAY);
    await service.get('PL');
    expect(provider.calls).toBe(1);
    provider.price = 1.3;
    advance(2 * DAY);
    expect((await service.get('PL'))?.pricePerKwh).toBe(1.3);
    expect(provider.calls).toBe(2);
  });

  it('source unavailable -> last known value marked stale; nothing cached -> null', async () => {
    const { provider, service, advance } = make();
    expect(await service.get('PL')).not.toBeNull();
    provider.fail = true;
    advance(8 * DAY);
    expect(await service.get('PL')).toMatchObject({ pricePerKwh: 1.2724, stale: true });
    expect(await service.get('DE')).toBeNull();
  });

  it('survives a restart through the repository (last known value, not memory)', async () => {
    const { provider, repos, service } = make();
    await service.get('PL');
    const second = new ElectricityPriceService([provider], repos.prices, { cacheMs: 7 * DAY });
    provider.fail = true;
    expect(await second.get('PL')).toMatchObject({ pricePerKwh: 1.2724, stale: false });
  });

  it('concurrent requests share one source call', async () => {
    const { provider, service } = make();
    await Promise.all([service.get('PL'), service.get('PL'), service.get('PL')]);
    expect(provider.calls).toBe(1);
  });
});

describe('GET /api/v1/electricity-price', () => {
  let ctx: TestContext;
  afterEach(() => ctx.app.close());

  it('validates the country code, uses the account country by default, 404 when no source covers it', async () => {
    const provider = new ScriptedProvider();
    ctx = await makeApp({}, { priceProviders: [provider] });
    const reg = await registerUser(ctx.app);

    expect((await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price?country=PL' })).statusCode).toBe(401);

    const bad = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price?country=pl1', headers: reg.headers });
    expect(bad.statusCode).toBe(400);

    const none = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price', headers: reg.headers });
    expect(none.statusCode).toBe(400);
    expect(none.json().error.code).toBe('country_required');

    const ok = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price?country=PL', headers: reg.headers });
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toMatchObject({ countryCode: 'PL', currency: 'PLN', pricePerKwh: 1.2724, period: '2026-S1', source: 'eurostat', includesTaxes: true, stale: false });

    await ctx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers: reg.headers, payload: { countryCode: 'PL', currencyCode: 'PLN' } });
    const byAccount = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price', headers: reg.headers });
    expect(byAccount.statusCode).toBe(200);
    expect(provider.calls).toBe(1);

    provider.price = null;
    const missing = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price?country=US', headers: reg.headers });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().error.code).toBe('electricity_price_unavailable');
  });
});
