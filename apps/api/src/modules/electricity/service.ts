import type { ElectricityPriceDto } from '@wattbyte/contracts';

import type { ElectricityPriceRepository, ElectricityPriceRow } from '../../database/repositories.js';
import type { ElectricityPriceProvider } from './provider.js';

export interface ElectricityPriceServiceOptions {
  /** How long a fetched value is served without asking the source again. */
  cacheMs: number;
  /** After a failed lookup the source is left alone for this long (default 60 s): an outage is not retried per request. */
  failureMs?: number;
  /** How long "no source covers this country" is remembered (default 6 h). */
  notCoveredMs?: number;
  now?: () => Date;
  onError?: (countryCode: string, error: Error) => void;
}

/** Why there is no price: no source covers the country, or the sources could not be reached and nothing is cached. */
export class PriceUnavailableError extends Error {
  constructor(
    readonly reason: 'not_covered' | 'upstream_failed',
    readonly retryAfterSec?: number,
  ) {
    super(reason === 'not_covered' ? 'no source covers this country' : 'the price sources are unavailable');
    this.name = 'PriceUnavailableError';
  }
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
  private readonly inFlight = new Map<string, Promise<FetchOutcome>>();
  /** country -> instant before which the source is not asked again after a failure / a "not covered" answer. */
  private readonly failedUntil = new Map<string, number>();
  private readonly notCoveredUntil = new Map<string, number>();
  private readonly now: () => Date;

  constructor(
    private readonly providers: ElectricityPriceProvider[],
    private readonly repo: ElectricityPriceRepository,
    private readonly options: ElectricityPriceServiceOptions,
  ) {
    this.now = options.now ?? (() => new Date());
  }

  /**
   * The price, possibly stale. Throws [PriceUnavailableError]: `not_covered` (answered by every source, remembered for a
   * while, a 404 for the client) or `upstream_failed` (nothing cached and a source failed: a 503 with a retry hint, not a
   * claim that the country is not covered).
   */
  async get(countryCode: string): Promise<ElectricityPriceDto> {
    const cached = this.memory.get(countryCode) ?? (await this.repo.get(countryCode));
    if (cached) this.memory.set(countryCode, cached);
    if (cached && this.isFresh(cached)) return toDto(cached, false);

    const nowMs = this.now().getTime();
    if (!cached && (this.notCoveredUntil.get(countryCode) ?? 0) > nowMs) throw new PriceUnavailableError('not_covered');
    const coolingDown = (this.failedUntil.get(countryCode) ?? 0) > nowMs;
    if (coolingDown) {
      // A source that just failed is not asked again for every request: the last known value (stale) or a 503.
      if (cached) return toDto(cached, true);
      throw new PriceUnavailableError('upstream_failed', Math.ceil(((this.failedUntil.get(countryCode) ?? nowMs) - nowMs) / 1000));
    }

    const outcome = await this.refresh(countryCode);
    if (outcome.row) {
      // Never let an older period overwrite a newer one that is already known (a slow or lagging source).
      const winner = cached && cached.period > outcome.row.period ? { ...cached, fetchedAt: outcome.row.fetchedAt } : outcome.row;
      if (winner !== outcome.row) {
        this.memory.set(countryCode, winner);
        await this.repo.set(winner);
      }
      return toDto(winner, false);
    }
    if (cached) return toDto(cached, true);
    if (outcome.failed) throw new PriceUnavailableError('upstream_failed', Math.ceil((this.options.failureMs ?? FAILURE_MS) / 1000));
    throw new PriceUnavailableError('not_covered');
  }

  private isFresh(row: ElectricityPriceRow): boolean {
    return this.now().getTime() - row.fetchedAt.getTime() < this.options.cacheMs;
  }

  private refresh(countryCode: string): Promise<FetchOutcome> {
    const running = this.inFlight.get(countryCode);
    if (running) return running;
    const task = this.fetchFromProviders(countryCode).finally(() => this.inFlight.delete(countryCode));
    this.inFlight.set(countryCode, task);
    return task;
  }

  private async fetchFromProviders(countryCode: string): Promise<FetchOutcome> {
    let failed = false;
    for (const provider of this.providers) {
      try {
        const result = await provider.getHouseholdPrice(countryCode);
        if (!result) continue;
        const row: ElectricityPriceRow = { ...result, fetchedAt: this.now() };
        this.memory.set(countryCode, row);
        await this.repo.set(row);
        this.failedUntil.delete(countryCode);
        return { row, failed: false };
      } catch (e) {
        failed = true;
        this.options.onError?.(countryCode, e instanceof Error ? e : new Error(String(e)));
      }
    }
    const nowMs = this.now().getTime();
    if (failed) this.failedUntil.set(countryCode, nowMs + (this.options.failureMs ?? FAILURE_MS));
    else this.notCoveredUntil.set(countryCode, nowMs + (this.options.notCoveredMs ?? NOT_COVERED_MS));
    return { row: null, failed };
  }
}

const FAILURE_MS = 60_000;
const NOT_COVERED_MS = 6 * 3_600_000;

interface FetchOutcome {
  row: ElectricityPriceRow | null;
  /** At least one source threw (as opposed to every source answering "not covered"). */
  failed: boolean;
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
