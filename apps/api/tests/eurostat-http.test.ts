import type { Server } from 'node:http';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// @ts-expect-error plain ES module without types (a repo script shared with the CI e2e job)
import { startFakeEurostat } from '../../../scripts/fake-eurostat.mjs';
import { EurostatElectricityPriceProvider } from '../src/modules/electricity/eurostat.js';

/** The real provider over a REAL HTTP round trip (global fetch) against the fixture server used by the CI e2e job. */
describe('EurostatElectricityPriceProvider over HTTP (fixture server)', () => {
  let server: Server;
  let provider: EurostatElectricityPriceProvider;
  beforeAll(async () => {
    const started = await startFakeEurostat(0);
    server = started.server as Server;
    provider = new EurostatElectricityPriceProvider({ baseUrl: started.baseUrl as string, timeoutMs: 5000 });
  });
  afterAll(() => new Promise<void>((resolve) => server.close(() => resolve())));

  it('PL: newest half-year, PLN, taxes and network costs included', async () => {
    expect(await provider.getHouseholdPrice('PL')).toMatchObject({ countryCode: 'PL', currency: 'PLN', pricePerKwh: 1.2724, period: '2026-S1', source: 'eurostat' });
  });

  it('DE and CZ resolve to their national currency; Greece is queried as EL', async () => {
    expect(await provider.getHouseholdPrice('DE')).toMatchObject({ currency: 'EUR', pricePerKwh: 0.3618 });
    expect(await provider.getHouseholdPrice('CZ')).toMatchObject({ currency: 'CZK', pricePerKwh: 7.0108 });
    expect(await provider.getHouseholdPrice('GR')).toBeNull(); // EL is not in the fixture: an empty dataset is "no price", not an error
  });

  it('a country outside the dataset is null (no invented price)', async () => {
    expect(await provider.getHouseholdPrice('FR')).toBeNull();
    expect(await provider.getHouseholdPrice('US')).toBeNull();
  });

  it('a wrong base path is a transport error, so the service can fall back to its cache', async () => {
    const broken = new EurostatElectricityPriceProvider({ baseUrl: 'http://127.0.0.1:1/none', timeoutMs: 1000 });
    await expect(broken.getHouseholdPrice('PL')).rejects.toThrow();
  });
});
