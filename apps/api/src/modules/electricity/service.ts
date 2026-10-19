import type { ElectricityPriceDto } from '@wattbyte/contracts';

import type { ElectricityPriceRepository, ElectricityPriceRow } from '../../database/repositories.js';
import type { ElectricityPriceProvider } from './provider.js';

export interface ElectricityPriceServiceOptions {
  /** How long a fetched value is served without asking the source again. */
  cacheMs: number;
  now?: () => Date;
  onError?: (countryCode: string, error: Error) => void;
}

/**
 * Household electricity price with caching and fallback:
 *
 *   fresh cache (memory, then database) -> provider -> last known value (stale) -> null
 *
 * The source is asked at most once per `cacheMs` per country and never more
 * than once at a time (concurrent requests share one in-flight fetch). A source
 * outage returns the last known value marked `stale`; only with nothing cached
 * does the caller see "unavailable". Prices are statistical averages, never a
 * user's tariff, which is why the API also reports `source` and `period`.
 */
export class ElectricityPriceService {
  private readonly memory = new Map<string, ElectricityPriceRow>();
  private readonly inFlight = new Map<string, Promise<ElectricityPriceRow | null>>();
  private readonly now: () => Date;

  constructor(
    private readonly providers: ElectricityPriceProvider[],
    private readonly repo: ElectricityPriceRepository,
    private readonly options: ElectricityPriceServiceOptions,
  ) {
    this.now = options.now ?? (() => new Date());
  }

  async get(countryCode: string): Promise<ElectricityPriceDto | null> {
    const cached = this.memory.get(countryCode) ?? (await this.repo.get(countryCode));
    if (cached) this.memory.set(countryCode, cached);
    if (cached && this.isFresh(cached)) return toDto(cached, false);

    const fetched = await this.refresh(countryCode);
    if (fetched) return toDto(fetched, false);
    return cached ? toDto(cached, true) : null;
  }

  private isFresh(row: ElectricityPriceRow): boolean {
    return this.now().getTime() - row.fetchedAt.getTime() < this.options.cacheMs;
  }

  private refresh(countryCode: string): Promise<ElectricityPriceRow | null> {
    const running = this.inFlight.get(countryCode);
    if (running) return running;
    const task = this.fetchFromProviders(countryCode).finally(() => this.inFlight.delete(countryCode));
    this.inFlight.set(countryCode, task);
    return task;
  }

  private async fetchFromProviders(countryCode: string): Promise<ElectricityPriceRow | null> {
    for (const provider of this.providers) {
      try {
        const result = await provider.getHouseholdPrice(countryCode);
        if (!result) continue;
        const row: ElectricityPriceRow = { ...result, fetchedAt: this.now() };
        this.memory.set(countryCode, row);
        await this.repo.set(row);
        return row;
      } catch (e) {
        this.options.onError?.(countryCode, e instanceof Error ? e : new Error(String(e)));
      }
    }
    return null;
  }
}

export function toDto(row: ElectricityPriceRow, stale: boolean): ElectricityPriceDto {
  return {
    countryCode: row.countryCode,
    currency: row.currency,
    pricePerKwh: row.pricePerKwh,
    period: row.period,
    source: row.source,
    includesTaxes: row.includesTaxes,
    includesNetworkCosts: row.includesNetworkCosts,
    updatedAt: row.fetchedAt.toISOString(),
    stale,
  };
}
