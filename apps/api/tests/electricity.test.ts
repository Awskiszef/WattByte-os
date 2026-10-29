import { afterEach, describe, expect, it, vi } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { EurostatElectricityPriceProvider, latestValue, nationalCurrencyFor, type JsonStat } from '../src/modules/electricity/eurostat.js';
import type { ElectricityPriceProvider } from '../src/modules/electricity/provider.js';
import { ElectricityPriceService, PriceUnavailableError } from '../src/modules/electricity/service.js';
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

  describe('a country that changed its currency (C-09: Bulgaria joined the euro on 2026-01-01)', () => {
    const bg = (value: Record<string, number | null>): JsonStat => ({
      ...PL_FIXTURE,
      value,
      dimension: { ...PL_FIXTURE.dimension, geo: { category: { index: { BG: 0 } } } },
    });
    const ask = (stat: JsonStat) => new EurostatElectricityPriceProvider({ fetch: fetchJson(stat) }).getHouseholdPrice('BG');

    it('the period decides: 2025 is leva, 2026 on is euro', async () => {
      expect(nationalCurrencyFor('BG', '2025-S2')).toBe('BGN');
      expect(nationalCurrencyFor('BG', '2026-S1')).toBe('EUR');
      expect(nationalCurrencyFor('BG', '2027-S2')).toBe('EUR');
      expect(nationalCurrencyFor('PL', '2030-S1')).toBe('PLN');
      expect(nationalCurrencyFor('HR', '2022-S2')).toBe('EUR');
      expect(nationalCurrencyFor('US', '2026-S1')).toBeUndefined();
    });

    it('a price of the newest period is labelled EUR, not BGN', async () => {
      const r = await ask(bg({ '0': 0.2, '1': 0.22, '2': 0.12 }));
      expect(r).toMatchObject({ countryCode: 'BG', currency: 'EUR', period: '2026-S1', pricePerKwh: 0.12 });
    });

    it('when only the old period has a value it is still the old currency', async () => {
      const r = await ask(bg({ '0': 0.2, '1': 0.22, '2': null }));
      expect(r).toMatchObject({ currency: 'BGN', period: '2025-S2', pricePerKwh: 0.22 });
    });
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

  afterEach(() => vi.useRealTimers());

  function make() {
    let now = new Date('2026-10-13T10:00:00Z');
    const provider = new ScriptedProvider();
    const repos = new MemoryRepositories();
    const service = new ElectricityPriceService([provider], repos.prices, { cacheMs: 7 * DAY, now: () => now });
    return { provider, repos, service, now: () => now, advance: (ms: number) => (now = new Date(now.getTime() + ms)) };
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

  it('source unavailable -> last known value marked stale; nothing cached -> "upstream_failed", not "not covered" (B-14)', async () => {
    const { provider, service, advance } = make();
    expect(await service.get('PL')).not.toBeNull();
    provider.fail = true;
    advance(8 * DAY);
    expect(await service.get('PL')).toMatchObject({ pricePerKwh: 1.2724, stale: true });
    await expect(service.get('DE')).rejects.toMatchObject({ name: 'PriceUnavailableError', reason: 'upstream_failed' });
  });

  it('a failed lookup is not repeated for every request: one source call per cooldown, then another try (B-14, C-12)', async () => {
    const { provider, service, advance } = make();
    provider.fail = true;
    for (let i = 0; i < 5; i++) await expect(service.get('DE')).rejects.toBeInstanceOf(PriceUnavailableError);
    expect(provider.calls).toBe(1);
    advance(61_000);
    provider.fail = false;
    expect(await service.get('DE')).toMatchObject({ pricePerKwh: 1.2724, stale: false });
    expect(provider.calls).toBe(2);
  });

  it('a stale value is served during the cooldown without asking the failing source again', async () => {
    const { provider, service, advance } = make();
    await service.get('PL');
    provider.fail = true;
    advance(8 * DAY);
    for (let i = 0; i < 4; i++) expect(await service.get('PL')).toMatchObject({ stale: true });
    expect(provider.calls).toBe(2);
  });

  it('"no source covers this country" is remembered, and is a different error from an outage (C-12)', async () => {
    const { provider, service, advance } = make();
    provider.price = null;
    for (let i = 0; i < 4; i++) await expect(service.get('US')).rejects.toMatchObject({ reason: 'not_covered' });
    expect(provider.calls).toBe(1);
    advance(7 * 3_600_000);
    await expect(service.get('US')).rejects.toMatchObject({ reason: 'not_covered' });
    expect(provider.calls).toBe(2);
  });

  it('an older period never overwrites a newer one that is already known (C-12)', async () => {
    const { provider, service, advance, repos } = make();
    await service.get('PL'); // 2026-S1
    provider.getHouseholdPrice = async (countryCode: string) => ({ countryCode, currency: 'PLN', pricePerKwh: 0.9, period: '2025-S2', source: 'eurostat' as const, includesTaxes: true, includesNetworkCosts: true });
    advance(8 * DAY);
    const dto = await service.get('PL');
    expect(dto).toMatchObject({ pricePerKwh: 1.2724, period: '2026-S1', stale: false });
    expect((await repos.prices.get('PL'))?.period).toBe('2026-S1');
  });

  it.each([
    '2026-10-19T10:00:00Z',
    '2026-10-20T10:00:00Z',
    '2026-10-21T10:00:00Z',
    '2035-01-01T00:00:00Z',
  ])('survives a restart independently of wall time (%s)', async (wallTime) => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date(wallTime));
    const { provider, repos, service, now, advance } = make();
    await service.get('PL');
    const second = new ElectricityPriceService([provider], repos.prices, { cacheMs: 7 * DAY, now });
    provider.fail = true;
    expect(await second.get('PL')).toMatchObject({ pricePerKwh: 1.2724, stale: false });
    expect(provider.calls).toBe(1);
    advance(7 * DAY);
    expect(await second.get('PL')).toMatchObject({ pricePerKwh: 1.2724, stale: true });
    expect(provider.calls).toBe(2);
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

  it('an outage with nothing cached is a 503 with Retry-After, not a 404 "not covered" (B-14)', async () => {
    const provider = new ScriptedProvider();
    provider.fail = true;
    ctx = await makeApp({}, { priceProviders: [provider] });
    const reg = await registerUser(ctx.app);
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/electricity-price?country=DE', headers: reg.headers });
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe('electricity_price_unavailable');
    expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
  });
});
