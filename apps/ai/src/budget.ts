import type { AIProviderId } from './types.js';

/**
 * Spend limits in USD. Every field is optional; a limit that is not set is not enforced. They are checked
 * against the cost the gateway records for each answer, which is an ESTIMATE unless the provider
 * reports the charge itself (`CostBasis`): set per-model prices (`modelPrices`) for limits worth trusting.
 *
 * Per user there is no cost limit here: the API already caps each user at a number of answers per day
 * (quota) and each answer at a number of output tokens, which bounds what one user can spend.
 */
export interface BudgetLimits {
  /** All providers together, per UTC day. */
  readonly dailyUsd?: number;
  /** All providers together, per UTC calendar month. */
  readonly monthlyUsd?: number;
  /** Per provider and UTC day: a provider at its limit is skipped, the others keep answering. */
  readonly providerDailyUsd?: Readonly<Partial<Record<AIProviderId, number>>>;
}

/** Where the spend comes from; the API backs it with a table of daily totals. */
export interface SpendReader {
  /** USD spent from the start of UTC day `sinceDay` (`YYYY-MM-DD`) until now, for one provider or all. */
  spentUsd(sinceDay: string, provider?: AIProviderId): Promise<number>;
}

export interface BudgetStatus {
  /** Set when a limit that covers every provider is used up: nothing is called. */
  readonly exceeded?: 'daily' | 'monthly';
  /** Providers that reached their own daily limit: left out of routing for now. */
  readonly exhaustedProviders: ReadonlySet<AIProviderId>;
}

export interface BudgetGuard {
  check(now: Date): Promise<BudgetStatus>;
}

const NONE: BudgetStatus = { exhaustedProviders: new Set() };

/** Undefined when no limit is configured, so callers skip the check (and its queries) altogether. */
export function createBudgetGuard(limits: BudgetLimits, reader: SpendReader): BudgetGuard | undefined {
  const perProvider = Object.entries(limits.providerDailyUsd ?? {}).filter((e): e is [AIProviderId, number] => typeof e[1] === 'number');
  if (limits.dailyUsd === undefined && limits.monthlyUsd === undefined && perProvider.length === 0) return undefined;

  return {
    async check(now) {
      const day = now.toISOString().slice(0, 10);
      const month = `${day.slice(0, 8)}01`;
      const [daily, monthly, providers] = await Promise.all([
        limits.dailyUsd === undefined ? undefined : reader.spentUsd(day),
        limits.monthlyUsd === undefined ? undefined : reader.spentUsd(month),
        Promise.all(perProvider.map(async ([id, limit]) => ((await reader.spentUsd(day, id)) >= limit ? id : undefined))),
      ]);
      const exhaustedProviders = new Set(providers.filter((id): id is AIProviderId => id !== undefined));
      if (daily !== undefined && limits.dailyUsd !== undefined && daily >= limits.dailyUsd) return { exceeded: 'daily', exhaustedProviders };
      if (monthly !== undefined && limits.monthlyUsd !== undefined && monthly >= limits.monthlyUsd) return { exceeded: 'monthly', exhaustedProviders };
      return exhaustedProviders.size === 0 ? NONE : { exhaustedProviders };
    },
  };
}
