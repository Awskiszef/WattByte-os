/**
 * Household electricity price from Eurostat `nrg_pc_204`, the same query the
 * WattByte API uses (band DC: 2 500 to 4 999 kWh a year, all taxes and levies
 * included, national currency). Fetched on the server, cached for a day, and
 * every failure becomes `null` so the page renders a placeholder instead of a
 * made-up number.
 */
const EUROSTAT_BASE = 'https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data';
const DATASET = 'nrg_pc_204';

type JsonStat = {
  id?: string[];
  size?: number[];
  value?: Record<string, number | null>;
  dimension?: Record<string, { category: { index: Record<string, number>; label?: Record<string, string> } }>;
};

export type ElectricityPrice = {
  countryCode: string;
  currency: string;
  pricePerKwh: number;
  /** Eurostat period, for example "2025-S1" (first half of 2025). */
  period: string;
};

const NATIONAL_CURRENCY: Record<string, string> = {
  PL: 'PLN',
  DE: 'EUR',
  FR: 'EUR',
  ES: 'EUR',
  IT: 'EUR',
  NL: 'EUR',
  CZ: 'CZK',
  SE: 'SEK',
  DK: 'DKK',
  HU: 'HUF',
  RO: 'RON',
  BG: 'BGN',
  NO: 'NOK',
};

export function eurostatUrl(countryCode: string): string {
  const q = new URLSearchParams({
    geo: countryCode,
    siec: 'E7000',
    nrg_cons: 'KWH2500-4999',
    unit: 'KWH',
    tax: 'I_TAX',
    currency: 'NAC',
    lastTimePeriod: '3',
    format: 'JSON',
  });
  return `${EUROSTAT_BASE}/${DATASET}?${q.toString()}`;
}

/** The newest period that carries a value; the newest period is sometimes still empty. */
export function latestValue(stat: JsonStat): { period: string; value: number } | null {
  if (!Array.isArray(stat.id) || !Array.isArray(stat.size) || !stat.dimension?.time) return null;
  const timePos = stat.id.indexOf('time');
  if (timePos < 0) return null;
  if (stat.size.some((n, i) => i !== timePos && n !== 1)) return null;
  const periods = Object.entries(stat.dimension.time.category.index).sort((a, b) => b[1] - a[1]);
  for (const [period, index] of periods) {
    const v = stat.value?.[String(index)];
    if (typeof v === 'number' && Number.isFinite(v) && v > 0) return { period, value: v };
  }
  return null;
}

export function formatPeriod(period: string): string {
  const m = /^(\d{4})-S([12])$/.exec(period);
  if (!m) return period;
  return `${m[2] === '1' ? 'first' : 'second'} half of ${m[1]}`;
}

export async function getHouseholdPrice(countryCode: string, timeoutMs = 8000): Promise<ElectricityPrice | null> {
  const currency = NATIONAL_CURRENCY[countryCode];
  if (!currency) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(eurostatUrl(countryCode), {
      signal: controller.signal,
      headers: { accept: 'application/json' },
      next: { revalidate: 86_400 },
    });
    if (!res.ok) return null;
    const latest = latestValue((await res.json()) as JsonStat);
    if (!latest) return null;
    return { countryCode, currency, pricePerKwh: latest.value, period: latest.period };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
