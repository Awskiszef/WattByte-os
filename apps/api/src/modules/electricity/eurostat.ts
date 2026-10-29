import type { ElectricityPriceProvider, ElectricityPriceResult } from './provider.js';

/**
 * Eurostat `nrg_pc_204`: electricity prices for household consumers, bi-annual.
 *
 * Query: electricity (siec=E7000), consumption band DC (2 500-4 999 kWh/year,
 * the band Eurostat and national regulators use as the "typical household"),
 * all taxes and levies included (tax=I_TAX), national currency (currency=NAC),
 * per kWh. The last three half-years are requested and the latest one that
 * carries a value is used (the newest period is sometimes still empty for a
 * country). Prices in this dataset are national averages of what households
 * pay end to end: energy, network charges, taxes.
 */
export const EUROSTAT_DEFAULT_BASE_URL = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data';
export const EUROSTAT_DATASET = 'nrg_pc_204';

/** ISO 3166-1 alpha-2 codes whose Eurostat `geo` code differs. */
const GEO_ALIASES: Record<string, string> = { GR: 'EL', GB: 'UK' };

/** National currency of each country Eurostat reports in `nrg_pc_204` (NAC = this). */
export const EUROSTAT_NATIONAL_CURRENCY: Record<string, string> = {
  AT: 'EUR', BE: 'EUR', BG: 'BGN', HR: 'EUR', CY: 'EUR', CZ: 'CZK', DK: 'DKK', EE: 'EUR', FI: 'EUR', FR: 'EUR',
  DE: 'EUR', GR: 'EUR', HU: 'HUF', IE: 'EUR', IT: 'EUR', LV: 'EUR', LT: 'EUR', LU: 'EUR', MT: 'EUR', NL: 'EUR',
  PL: 'PLN', PT: 'EUR', RO: 'RON', SK: 'EUR', SI: 'EUR', ES: 'EUR', SE: 'SEK', IS: 'ISK', LI: 'CHF', NO: 'NOK',
  ME: 'EUR', MK: 'MKD', AL: 'ALL', RS: 'RSD', TR: 'TRY', BA: 'BAM', XK: 'EUR', MD: 'MDL', UA: 'UAH', GE: 'GEL',
};

/**
 * A country that changed its national currency: the price of a period before `from` is quoted in the old currency (the
 * map above), from `from` on in `to`. Bulgaria adopted the euro on 2026-01-01 (period `2026-S1`); Eurostat's NAC series
 * follows the currency of the period, so labelling every Bulgarian price BGN made a 2026 price look 1.96 times too low
 * in leva (audit C-09). Periods are Eurostat half-years (`YYYY-S1`, `YYYY-S2`), which sort as strings.
 */
export const CURRENCY_CHANGES: Record<string, { from: string; to: string }> = {
  BG: { from: '2026-S1', to: 'EUR' },
};

/** The currency a price of `countryCode` for `period` is quoted in; undefined when Eurostat does not cover the country. */
export function nationalCurrencyFor(countryCode: string, period: string): string | undefined {
  const base = EUROSTAT_NATIONAL_CURRENCY[countryCode];
  if (!base) return undefined;
  const change = CURRENCY_CHANGES[countryCode];
  return change && period >= change.from ? change.to : base;
}

/** Minimal JSON-stat 2.0 shape used by the Eurostat dissemination API. */
export interface JsonStat {
  value: Record<string, number | null>;
  id: string[];
  size: number[];
  dimension: Record<string, { category: { index: Record<string, number>; label?: Record<string, string> } }>;
  error?: unknown;
}

export type FetchLike = (url: string, init?: { signal?: AbortSignal; headers?: Record<string, string> }) => Promise<{
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
}>;

export interface EurostatOptions {
  baseUrl?: string;
  fetch?: FetchLike;
  timeoutMs?: number;
}

export class EurostatElectricityPriceProvider implements ElectricityPriceProvider {
  readonly id = 'eurostat' as const;
  private readonly baseUrl: string;
  private readonly fetchImpl: FetchLike;
  private readonly timeoutMs: number;

  constructor(options: EurostatOptions = {}) {
    this.baseUrl = (options.baseUrl ?? EUROSTAT_DEFAULT_BASE_URL).replace(/\/$/, '');
    this.fetchImpl = options.fetch ?? ((url, init) => fetch(url, init));
    this.timeoutMs = options.timeoutMs ?? 15_000;
  }

  queryUrl(countryCode: string): string {
    const geo = GEO_ALIASES[countryCode] ?? countryCode;
    const q = new URLSearchParams({
      geo,
      siec: 'E7000',
      nrg_cons: 'KWH2500-4999',
      unit: 'KWH',
      tax: 'I_TAX',
      currency: 'NAC',
      lastTimePeriod: '3',
      format: 'JSON',
    });
    return `${this.baseUrl}/${EUROSTAT_DATASET}?${q.toString()}`;
  }

  async getHouseholdPrice(countryCode: string): Promise<ElectricityPriceResult | null> {
    // A country Eurostat does not cover: not an error, just no household price from this source.
    if (!EUROSTAT_NATIONAL_CURRENCY[countryCode]) return null;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await this.fetchImpl(this.queryUrl(countryCode), { signal: controller.signal, headers: { accept: 'application/json' } });
      if (!res.ok) throw new Error(`eurostat responded ${res.status}`);
      const body = (await res.json()) as JsonStat;
      if (body.error) throw new Error(`eurostat error: ${JSON.stringify(body.error).slice(0, 200)}`);
      const latest = latestValue(body);
      if (!latest) return null;
      return {
        countryCode,
        currency: nationalCurrencyFor(countryCode, latest.period)!,
        pricePerKwh: latest.value,
        period: latest.period,
        source: 'eurostat',
        // I_TAX = all taxes and levies included; the dataset is an end-user price, network charges included.
        includesTaxes: true,
        includesNetworkCosts: true,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}

/**
 * The newest period with a value. With every other dimension filtered to one
 * category the value index equals the time index, which this checks (the
 * response echoes its dimension sizes) rather than assumes.
 */
export function latestValue(stat: JsonStat): { period: string; value: number } | null {
  if (!Array.isArray(stat.id) || !Array.isArray(stat.size) || !stat.dimension?.time) return null;
  const timePos = stat.id.indexOf('time');
  if (timePos < 0) return null;
  // Every non-time dimension must be a single category, otherwise indices would interleave.
  if (stat.size.some((n, i) => i !== timePos && n !== 1)) return null;
  const periods = Object.entries(stat.dimension.time.category.index).sort((a, b) => b[1] - a[1]);
  for (const [period, index] of periods) {
    const v = stat.value?.[String(index)];
    if (typeof v === 'number' && Number.isFinite(v) && v > 0) return { period, value: v };
  }
  return null;
}
