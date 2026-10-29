import type { AIErrorCategory } from './errors.js';
import type { ProviderErrorKind } from './providers/http.js';
import type { AIInput, AIOutput } from './schemas.js';

export const AI_PROVIDER_IDS = ['openai', 'anthropic', 'google', 'xai'] as const;
export type AIProviderId = (typeof AI_PROVIDER_IDS)[number];

export const AI_TASKS = ['insight', 'weekly_summary', 'monthly_summary', 'roast'] as const;
export type AITask = (typeof AI_TASKS)[number];

export const AI_MODES = ['normal', 'friendly', 'funny', 'roast'] as const;
export type AIMode = (typeof AI_MODES)[number];

export const AI_LOCALES = ['en', 'pl'] as const;
export type AILocale = (typeof AI_LOCALES)[number];

export type Plan = 'free' | 'premium';

/** Which configured model of a provider to use: cheap and quick, or better. */
export const AI_TIERS = ['fast', 'quality'] as const;
export type AITier = (typeof AI_TIERS)[number];

/** Short observations are cheap; summaries get the better model. */
export const TASK_TIER: Record<AITask, AITier> = {
  insight: 'fast',
  roast: 'fast',
  weekly_summary: 'quality',
  monthly_summary: 'quality',
};

/** Model names live in configuration only; adapters never hardcode them. */
export interface ModelConfig {
  readonly fast?: string;
  readonly quality?: string;
}

/** What a provider receives: an already built prompt, never raw user data. */
export interface AIGenerationRequest {
  readonly task: AITask;
  readonly tier: AITier;
  readonly mode: AIMode;
  readonly locale: AILocale;
  readonly system: string;
  readonly user: string;
  readonly maxOutputTokens: number;
  /** Hard limit for this one call; the gateway shrinks it when little of the request budget is left. */
  readonly timeoutMs: number;
  /**
   * Backend-only model override for this call (validated by `resolveModel`); never set from client input.
   * Models are normally configuration: the tier's model of the provider.
   */
  readonly model?: string;
  /** Cancels the call at once (not a timeout, not a provider fault). */
  readonly signal?: AbortSignal;
}

export interface AIGenerationResult {
  readonly providerId: AIProviderId;
  readonly model: string;
  /** Raw model text; the gateway parses and validates it. */
  readonly text: string;
  readonly inputTokens: number;
  readonly outputTokens: number;
  /**
   * False when the response carried no usable token counts (the two numbers
   * above are then 0 and the cost is unknown, not zero). Absent means reported.
   */
  readonly usageReported?: boolean;
  /** What the provider itself says it charged for this call, in USD (xAI sends it); absent for the others. */
  readonly costUsd?: number;
  /** The provider's own id for the request, for support tickets and invoice reconciliation. */
  readonly requestId?: string;
  readonly latencyMs: number;
}

export interface ProviderHealthResult {
  readonly providerId: AIProviderId;
  readonly ok: boolean;
  readonly latencyMs?: number;
  readonly error?: string;
}

export interface AIProvider {
  readonly id: AIProviderId;
  generate(request: AIGenerationRequest): Promise<AIGenerationResult>;
  healthCheck(): Promise<ProviderHealthResult>;
}

/**
 * How an estimated cost was derived:
 * - `provider_reported` the provider's own figure for this very call (the charge itself, not an estimate)
 * - `model_price`       from a per-model price the operator supplied (`modelPrices`)
 * - `provider_estimate` from the flat approximate list price of the provider (no model price configured)
 * - `conservative_estimate` the provider sent no usable token counts, so the call is booked at its worst case (prompt size and the output cap)
 * - `unknown`           no cost could be derived at all; only the pure `estimateCost` returns it, a booked call never carries it
 */
export type CostBasis = 'provider_reported' | 'model_price' | 'provider_estimate' | 'conservative_estimate' | 'unknown';

/** A provider call that was (or must be assumed to have been) billed but delivered no answer: refusal, cut-off or invalid output. */
export interface BilledAttempt {
  readonly providerId: AIProviderId;
  readonly model: string;
  readonly kind: ProviderErrorKind;
  readonly inputTokens: number;
  readonly outputTokens: number;
  /** What the spend ledger was charged for it. */
  readonly costUsd: number;
  readonly costBasis: CostBasis;
  /** False when the token counts are not the provider's: `costUsd` is then the conservative worst case. */
  readonly usageReported: boolean;
}

/** Everything the gateway knows about one call; persisted by the API. */
export interface UsageRecord {
  /** Opaque reference chosen by the caller (e.g. user id). Never sent to a provider. */
  readonly userRef: string;
  readonly task: AITask;
  readonly mode: AIMode;
  readonly providerId: AIProviderId;
  readonly model: string;
  readonly inputTokens: number;
  readonly outputTokens: number;
  /** 0 when `costBasis` is `unknown`. */
  readonly estimatedCostUsd: number;
  readonly costBasis: CostBasis;
  /** False when the provider sent no token counts; `inputTokens`/`outputTokens` are then 0. */
  readonly usageReported: boolean;
  readonly latencyMs: number;
  /** The provider's id for the request that produced the answer; never persisted with prompts (there are none). */
  readonly providerRequestId?: string;
  readonly createdAt: Date;
}

export interface UsageSink {
  record(record: UsageRecord): Promise<void>;
}

export interface GenerateContext {
  readonly userRef: string;
  readonly plan: Plan;
  readonly locale: AILocale;
}

/**
 * Backend-only routing hints for one call. None of this is ever read from a client request:
 * the public routes do not accept a provider or a model.
 */
export interface GenerateOptions {
  /** Try this provider first instead of the configured default / the task's routing order. */
  readonly provider?: AIProviderId;
  /** Model name for `provider` only (the fallback keeps using its configured models). Needs `provider`. */
  readonly model?: string;
  /** Cancels the whole call: no retry, no fallback, the router is not told the provider failed. */
  readonly signal?: AbortSignal;
}

/** Why one provider attempt failed: the only per-provider detail that leaves the gateway. */
export interface AttemptFailure {
  readonly providerId: AIProviderId;
  readonly kind: ProviderErrorKind;
  readonly category: AIErrorCategory;
  /** HTTP status when the provider answered with one. */
  readonly status?: number;
}

export interface GenerateOutcome {
  readonly output: AIOutput;
  readonly providerId: AIProviderId;
  readonly model: string;
  readonly usage: UsageRecord;
  /** Providers tried before the one that answered. */
  readonly fallbacks: AIProviderId[];
}

export type { AIInput, AIOutput };
