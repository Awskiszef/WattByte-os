import type { AIProviderId, CostBasis, UsageRecord, UsageSink } from './types.js';

export interface Price {
  /** USD per 1M input tokens. */
  readonly input: number;
  /** USD per 1M output tokens. */
  readonly output: number;
}

/** Optional per-model prices keyed by model name, supplied by the operator (model names live only in configuration). */
export type ModelPrices = Readonly<Record<string, Price>>;

/**
 * Approximate list prices in USD per 1M tokens, one flat figure per provider,
 * used only for the `estimated_cost` column. Model names come from
 * configuration and change often, so this table deliberately does not list
 * models: a model without an entry in `modelPrices` is estimated at the
 * provider figure and reported as `provider_estimate`. The real invoice comes
 * from the provider.
 */
export const PRICE_PER_MILLION_USD: Readonly<Record<AIProviderId, Price>> = {
  openai: { input: 0.4, output: 1.6 },
  anthropic: { input: 3, output: 15 },
  google: { input: 0.3, output: 2.5 },
  // The upper end of xAI's current text models (docs.x.ai/docs/models, 2026-10-13: $1.25-2.00 in, $2.50-6.00 out per 1M).
  // xAI also reports the exact charge per call, which takes precedence (`provider_reported`).
  xai: { input: 2, output: 6 },
};

export interface CostEstimate {
  /** USD, rounded to 6 decimals; 0 when `basis` is `unknown`. */
  readonly usd: number;
  readonly basis: CostBasis;
}

export interface CostInput {
  readonly providerId: AIProviderId;
  /** Model name as reported by the provider (a dated variant such as `name-2026-01-01` matches the price of `name`). */
  readonly model: string;
  readonly inputTokens: number;
  readonly outputTokens: number;
  /** False when the provider sent no token usage: the cost is then unknown, not 0. */
  readonly usageReported?: boolean;
  /** The charge the provider itself reported for this call, in USD; beats every estimate. */
  readonly reportedCostUsd?: number;
  readonly modelPrices?: ModelPrices;
}

const UNKNOWN: CostEstimate = { usd: 0, basis: 'unknown' };

function validPrice(p: Price | undefined): p is Price {
  return p !== undefined && Number.isFinite(p.input) && p.input >= 0 && Number.isFinite(p.output) && p.output >= 0;
}

/** Exact name first, then the longest configured name followed by a `-` suffix (dated snapshots). */
function modelPrice(prices: ModelPrices | undefined, model: string): Price | undefined {
  if (!prices) return undefined;
  if (Object.hasOwn(prices, model)) return prices[model];
  const key = Object.keys(prices)
    .filter((k) => model.startsWith(`${k}-`))
    .sort((a, b) => b.length - a.length)[0];
  return key === undefined ? undefined : prices[key];
}

const validTokens = (n: number): boolean => Number.isFinite(n) && n >= 0;
const round6 = (n: number): number => Math.round(n * 1e6) / 1e6;

/**
 * Cost of one call. Never throws and never yields NaN/Infinity/negative. The provider's own figure
 * wins when it sent one; otherwise it is an estimate from the token counts. Missing or invalid usage,
 * or an unusable price, gives `{ usd: 0, basis: 'unknown' }` so "no data" cannot be mistaken for "free".
 */
export function estimateCost(input: CostInput): CostEstimate {
  const reported = input.reportedCostUsd;
  if (reported !== undefined && Number.isFinite(reported) && reported >= 0) return { usd: round6(reported), basis: 'provider_reported' };
  if (input.usageReported === false || !validTokens(input.inputTokens) || !validTokens(input.outputTokens)) return UNKNOWN;
  const override = modelPrice(input.modelPrices, input.model);
  const price = override ?? PRICE_PER_MILLION_USD[input.providerId];
  if (!validPrice(price)) return UNKNOWN;
  const usd = round6((input.inputTokens * price.input + input.outputTokens * price.output) / 1_000_000);
  if (!Number.isFinite(usd)) return UNKNOWN;
  return { usd, basis: override === undefined ? 'provider_estimate' : 'model_price' };
}

/**
 * Provider-level estimate for known-good token counts. Invalid counts are a
 * programming error here, so they throw instead of being priced as 0; use
 * `estimateCost` when the counts come from a provider response.
 */
export function estimateCostUsd(providerId: AIProviderId, inputTokens: number, outputTokens: number): number {
  if (!validTokens(inputTokens) || !validTokens(outputTokens)) throw new RangeError('token counts must be finite and >= 0');
  const e = estimateCost({ providerId, model: '', inputTokens, outputTokens });
  if (e.basis === 'unknown') throw new RangeError(`no price for provider ${providerId}`);
  return e.usd;
}

/** Keeps records in memory (tests, local dev). */
export class MemoryUsageSink implements UsageSink {
  readonly records: UsageRecord[] = [];

  async record(record: UsageRecord): Promise<void> {
    this.records.push(record);
  }
}
