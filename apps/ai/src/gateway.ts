import type { BudgetGuard, BudgetStatus } from './budget.js';
import { allowsFallback, categorize, isRetryable, type AIErrorCategory, type FallbackPolicy } from './errors.js';
import { buildPrompt } from './prompts/index.js';
import { ProviderError } from './providers/http.js';
import { isModelName } from './providers/models.js';
import { backoffDelayMs, DEFAULT_RETRY_POLICY, sleep, type RetryPolicy } from './retry.js';
import type { ProviderRouter } from './router.js';
import { AIInputSchema, OutputRejectedError, parseAIOutput } from './schemas.js';
import type {
  AIGenerationRequest,
  AIGenerationResult,
  AIMode,
  AIProvider,
  AIProviderId,
  AITask,
  AttemptFailure,
  GenerateContext,
  GenerateOptions,
  GenerateOutcome,
  Plan,
  UsageRecord,
  UsageSink,
} from './types.js';
import { AI_PROVIDER_IDS, TASK_TIER } from './types.js';
import { estimateCost, type ModelPrices } from './usage.js';

/**
 * What the caller sees when generation fails. `message` is generic on purpose
 * (no provider text, status or prompt echo can reach a client that forwards
 * it); the per-provider reasons are the typed, content-free `attempts`.
 * `causes` holds the sanitized ProviderErrors for operator logs.
 *
 * - `invalid_input`          the aggregates (or the routing options) are not valid; nothing was called
 * - `no_provider`            nothing is configured, or the requested provider is not
 * - `budget_exceeded`        a spend limit is used up; nothing was called
 * - `all_providers_failed`   the provider(s) the policy allowed failed (see `attempts`)
 * - `aborted`                the caller cancelled
 */
export class AIGatewayError extends Error {
  constructor(
    readonly code: 'invalid_input' | 'no_provider' | 'budget_exceeded' | 'all_providers_failed' | 'aborted',
    message: string,
    readonly causes: readonly Error[] = [],
    readonly attempts: readonly AttemptFailure[] = [],
  ) {
    super(message);
    this.name = 'AIGatewayError';
  }
}

/** Structural subset of pino/Fastify loggers: `logger.info({ ... }, 'message')`. */
export interface GatewayLogger {
  info(entry: Record<string, unknown>, message?: string): void;
  warn(entry: Record<string, unknown>, message?: string): void;
}

export interface GatewayOptions {
  readonly router: ProviderRouter;
  readonly usage?: UsageSink;
  /** One call to one provider. Must be a finite number > 0. Default 20 000. */
  readonly timeoutMs?: number;
  /**
   * The whole `generate()`: every attempt, every retry pause and the fallback together. Nothing runs past it,
   * so keep it below the client's own timeout. Must be a finite number > 0. Default 60 000.
   */
  readonly requestTimeoutMs?: number;
  /** Extra calls to the same provider after a transient failure (429, 5xx, no connection). Default 2. */
  readonly maxRetries?: number;
  /** Backoff shape (`baseDelayMs`, `maxDelayMs`, `jitter`, `maxRetryAfterMs`). */
  readonly retry?: Partial<Omit<RetryPolicy, 'maxRetries'>>;
  /** Fallback to the next provider after a failure that allows it (see `allowsFallback`): at most ONE per request. */
  readonly fallback?: { readonly enabled?: boolean; readonly onRateLimit?: boolean };
  /** Tried first for every task when it is configured (`AI_DEFAULT_PROVIDER`); otherwise the task's own routing order. */
  readonly defaultProvider?: AIProviderId;
  /** Spend limits; checked before any provider is called. */
  readonly budget?: BudgetGuard;
  readonly now?: () => Date;
  /** Receives one `ai.attempt` entry per provider call; see `AttemptLogEntry` for the complete field list. */
  readonly logger?: GatewayLogger;
  /** Per-model prices by model name; models without one are estimated at the provider's flat price. */
  readonly modelPrices?: ModelPrices;
  /** Test seams: the pause between retries, the jitter and the monotonic clock (milliseconds) the time budget is measured on. */
  readonly sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
  readonly random?: () => number;
  readonly clock?: () => number;
}

/**
 * The ONLY fields the gateway ever logs: provider, model, task, outcome,
 * HTTP status, latency, token counts and the provider's request id. Prompts,
 * model output, response bodies, user references and keys are never part of an entry.
 */
export interface AttemptLogEntry {
  readonly event: 'ai.attempt';
  readonly provider: AIProviderId;
  readonly model?: string;
  readonly task: AITask;
  /** `ok` or the failure kind (`timeout`, `http`, `refusal`, ...). */
  readonly outcome: string;
  /** Failure category (`rate_limit`, `provider_unavailable`, ...); absent on success. */
  readonly category?: AIErrorCategory;
  readonly httpStatus?: number;
  /** 1 = the first call to this provider in this request, 2 = its first retry, ... */
  readonly attempt: number;
  /** True when the provider is the fallback, not the one the request started with. */
  readonly fallback: boolean;
  readonly latencyMs: number;
  readonly inputTokens?: number;
  readonly outputTokens?: number;
  /** The provider's id for the request (to quote in a support ticket). */
  readonly requestId?: string;
}

const MAX_OUTPUT_TOKENS: Record<Plan, number> = { free: 220, premium: 400 };

/** Not worth starting a call (or a retry) with less time than this left in the request budget. */
const MIN_ATTEMPT_MS = 1_000;

/** At most one other provider is asked after the first one: a failing request must not fan out into paid calls. */
const MAX_FALLBACKS = 1;

function asProviderError(providerId: AIProviderId, e: unknown): ProviderError {
  if (e instanceof ProviderError) return e;
  if (e instanceof OutputRejectedError) {
    return new ProviderError(providerId, e.kind === 'empty_output' ? 'empty output' : e.message, undefined, false, { kind: e.kind });
  }
  // A bug or an unforeseen exception type: keep the class, drop the message (it could quote anything).
  const name = e instanceof Error && /^[A-Za-z]{1,40}$/.test(e.name) ? e.name : 'Error';
  return new ProviderError(providerId, `unexpected ${name}`, undefined, false, { kind: 'unexpected' });
}

function positive(name: string, value: number): number {
  if (!Number.isFinite(value) || value <= 0) throw new RangeError(`${name} must be a finite number > 0`);
  return value;
}

/** What `status()` reports about one provider: configuration and health, never a key. */
export interface ProviderStatus {
  readonly id: AIProviderId;
  readonly configured: boolean;
  readonly inCooldown: boolean;
  readonly retryInMs: number;
  readonly consecutiveFailures: number;
}

export interface GatewayStatus {
  readonly providers: readonly ProviderStatus[];
  readonly defaultProvider: AIProviderId | null;
  readonly fallbackEnabled: boolean;
  readonly fallbackOnRateLimit: boolean;
  readonly maxRetries: number;
  readonly attemptTimeoutMs: number;
  readonly requestTimeoutMs: number;
  readonly budgetEnforced: boolean;
}

/**
 * The single entry point the API uses. Validates the aggregates, builds the
 * prompt, asks the first provider of the routing order (retrying transient
 * failures with backoff), falls back to at most one other provider when the
 * failure allows it, validates the model's JSON and records usage. It never
 * does arithmetic on the input.
 *
 * Time: one call never runs past `timeoutMs`, and the whole request never past
 * `requestTimeoutMs`; a cancelled `signal` ends it at once.
 */
export class AIGateway {
  private readonly router: ProviderRouter;
  private readonly usage?: UsageSink;
  private readonly timeoutMs: number;
  private readonly requestTimeoutMs: number;
  private readonly retry: RetryPolicy;
  private readonly fallbackEnabled: boolean;
  private readonly fallbackPolicy: FallbackPolicy;
  private readonly defaultProvider?: AIProviderId;
  private readonly budget?: BudgetGuard;
  private readonly now: () => Date;
  private readonly logger?: GatewayLogger;
  private readonly modelPrices?: ModelPrices;
  private readonly sleep: (ms: number, signal?: AbortSignal) => Promise<void>;
  private readonly random: () => number;
  private readonly clock: () => number;

  constructor(opts: GatewayOptions) {
    this.router = opts.router;
    this.usage = opts.usage;
    this.timeoutMs = positive('timeoutMs', opts.timeoutMs ?? 20_000);
    this.requestTimeoutMs = positive('requestTimeoutMs', opts.requestTimeoutMs ?? 60_000);
    const maxRetries = opts.maxRetries ?? DEFAULT_RETRY_POLICY.maxRetries;
    if (!Number.isInteger(maxRetries) || maxRetries < 0 || maxRetries > 10) throw new RangeError('maxRetries must be an integer from 0 to 10');
    this.retry = { ...DEFAULT_RETRY_POLICY, ...opts.retry, maxRetries };
    if (!Number.isFinite(this.retry.baseDelayMs) || this.retry.baseDelayMs < 0) throw new RangeError('retry.baseDelayMs must be a finite number >= 0');
    if (!Number.isFinite(this.retry.jitter) || this.retry.jitter < 0 || this.retry.jitter > 1) throw new RangeError('retry.jitter must be between 0 and 1');
    this.fallbackEnabled = opts.fallback?.enabled ?? true;
    this.fallbackPolicy = { onRateLimit: opts.fallback?.onRateLimit ?? true };
    this.defaultProvider = opts.defaultProvider;
    this.budget = opts.budget;
    this.now = opts.now ?? (() => new Date());
    this.logger = opts.logger;
    this.modelPrices = opts.modelPrices;
    this.sleep = opts.sleep ?? sleep;
    this.random = opts.random ?? Math.random;
    this.clock = opts.clock ?? (() => performance.now());
  }

  /** Configuration and health of every provider, without calling any of them. */
  status(): GatewayStatus {
    const health = new Map(this.router.health().map((h) => [h.id, h]));
    return {
      providers: AI_PROVIDER_IDS.map((id) => {
        const h = health.get(id);
        return { id, configured: h !== undefined, inCooldown: h?.inCooldown ?? false, retryInMs: h?.retryInMs ?? 0, consecutiveFailures: h?.consecutiveFailures ?? 0 };
      }),
      defaultProvider: this.defaultProvider ?? null,
      fallbackEnabled: this.fallbackEnabled,
      fallbackOnRateLimit: this.fallbackPolicy.onRateLimit,
      maxRetries: this.retry.maxRetries,
      attemptTimeoutMs: this.timeoutMs,
      requestTimeoutMs: this.requestTimeoutMs,
      budgetEnforced: this.budget !== undefined,
    };
  }

  async generate(task: AITask, mode: AIMode, rawInput: unknown, ctx: GenerateContext, options: GenerateOptions = {}): Promise<GenerateOutcome> {
    const parsed = AIInputSchema.safeParse(rawInput);
    if (!parsed.success) {
      throw new AIGatewayError('invalid_input', parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; '));
    }
    if (options.model !== undefined && (options.provider === undefined || !isModelName(options.model))) {
      throw new AIGatewayError('invalid_input', 'model: needs a provider and a plausible model name');
    }
    if (options.provider !== undefined && !this.router.provider(options.provider)) {
      throw new AIGatewayError('no_provider', 'the requested AI provider is not configured');
    }
    if (options.signal?.aborted) throw new AIGatewayError('aborted', 'request cancelled');

    const prompt = buildPrompt(task, mode, ctx.locale, parsed.data);
    const request: Omit<AIGenerationRequest, 'timeoutMs' | 'model'> = {
      task,
      tier: TASK_TIER[task],
      mode,
      locale: ctx.locale,
      system: prompt.system,
      user: prompt.user,
      maxOutputTokens: MAX_OUTPUT_TOKENS[ctx.plan],
      signal: options.signal,
    };

    const budget = await this.checkBudget();
    if (budget.exceeded) throw new AIGatewayError('budget_exceeded', `AI ${budget.exceeded} budget is used up`);
    const candidates = this.router.order(task, { prefer: options.provider ?? this.defaultProvider, exclude: budget.exhaustedProviders });
    if (candidates.length === 0) {
      if (budget.exhaustedProviders.size > 0) throw new AIGatewayError('budget_exceeded', 'AI budget is used up for every configured provider');
      throw new AIGatewayError('no_provider', 'no AI provider is configured');
    }

    const deadline = this.clock() + this.requestTimeoutMs;
    const chain = candidates.slice(0, 1 + (this.fallbackEnabled ? MAX_FALLBACKS : 0));
    const errors: ProviderError[] = [];
    const failed: AIProviderId[] = [];

    for (const [position, provider] of chain.entries()) {
      // A fallback only gets a call when enough of the request budget is left to make one worthwhile.
      if (position > 0 && deadline - this.clock() < MIN_ATTEMPT_MS) break;
      try {
        // The model override belongs to the provider it was asked for: the fallback keeps its configured models.
        const model = position === 0 && provider.id === options.provider ? options.model : undefined;
        return await this.attempt(provider, { ...request, model }, { mode, task, ctx, deadline, fallback: position > 0, failed });
      } catch (e) {
        const err = asProviderError(provider.id, e);
        errors.push(err);
        if (err.kind === 'aborted') {
          // The caller gave up: not the provider's fault, so the router is not told and nothing else is tried.
          throw new AIGatewayError('aborted', 'request cancelled', errors, this.attemptsOf(errors));
        }
        // Any failed provider is demoted: a bad key, a wrong model name or a model that keeps answering in
        // prose would otherwise cost a (billed) call on every single request.
        this.router.markFailure(provider.id, { retryAfterMs: err.retryAfterMs });
        failed.push(provider.id);
        if (!allowsFallback(err, this.fallbackPolicy)) break;
      }
    }
    throw new AIGatewayError('all_providers_failed', 'all AI providers failed', errors, this.attemptsOf(errors));
  }

  private attemptsOf(errors: readonly ProviderError[]): AttemptFailure[] {
    return errors.map((e) => ({ providerId: e.providerId, kind: e.kind, category: categorize(e), status: e.status }));
  }

  /** One provider, with its retries. Resolves with the outcome or throws the final `ProviderError`. */
  private async attempt(
    provider: AIProvider,
    request: Omit<AIGenerationRequest, 'timeoutMs'>,
    run: { mode: AIMode; task: AITask; ctx: GenerateContext; deadline: number; fallback: boolean; failed: readonly AIProviderId[] },
  ): Promise<GenerateOutcome> {
    const { mode, task, ctx, deadline, fallback } = run;
    for (let n = 0; ; n += 1) {
      if (request.signal?.aborted) throw new ProviderError(provider.id, 'aborted by the caller', undefined, false, { kind: 'aborted' });
      const started = this.clock();
      // Never less than 1 ms: a pause that overshot must not hand an adapter a zero or negative deadline.
      const timeoutMs = Math.max(1, Math.min(this.timeoutMs, Math.floor(deadline - started)));
      let result: AIGenerationResult | undefined;
      try {
        result = await provider.generate({ ...request, timeoutMs });
        const output = parseAIOutput(result.text, mode);
        this.router.markSuccess(provider.id);
        const cost = estimateCost({
          providerId: provider.id,
          model: result.model,
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
          usageReported: result.usageReported,
          reportedCostUsd: result.costUsd,
          modelPrices: this.modelPrices,
        });
        const usage: UsageRecord = {
          userRef: ctx.userRef,
          task,
          mode,
          providerId: provider.id,
          model: result.model,
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
          estimatedCostUsd: cost.usd,
          costBasis: cost.basis,
          usageReported: result.usageReported !== false,
          latencyMs: result.latencyMs,
          ...(result.requestId === undefined ? {} : { providerRequestId: result.requestId }),
          createdAt: this.now(),
        };
        this.log('info', {
          provider: provider.id,
          model: result.model,
          task,
          outcome: 'ok',
          attempt: n + 1,
          fallback,
          latencyMs: result.latencyMs,
          requestId: result.requestId,
          ...(usage.usageReported ? { inputTokens: result.inputTokens, outputTokens: result.outputTokens } : {}),
        });
        await this.record(usage);
        return { output, providerId: provider.id, model: result.model, usage, fallbacks: [...run.failed] };
      } catch (e) {
        const err = asProviderError(provider.id, e);
        // A rejected answer was still billed; its token counts come from the result or the error.
        const billed = result?.usageReported === false ? undefined : result ?? err;
        this.log('warn', {
          provider: provider.id,
          model: result?.model ?? err.model,
          task,
          outcome: err.kind,
          category: categorize(err),
          httpStatus: err.status,
          attempt: n + 1,
          fallback,
          latencyMs: Math.round(this.clock() - started),
          requestId: result?.requestId ?? err.requestId,
          ...(billed && (billed.inputTokens || billed.outputTokens) ? { inputTokens: billed.inputTokens, outputTokens: billed.outputTokens } : {}),
        });
        if (n >= this.retry.maxRetries || !isRetryable(err) || request.signal?.aborted) throw err;
        const wait = backoffDelayMs(n, this.retry, this.random, err.retryAfterMs);
        // No wait the user would sit through for nothing: a long Retry-After, or a budget that cannot take the pause plus a call.
        if (wait === undefined || this.clock() + wait + MIN_ATTEMPT_MS > deadline) throw err;
        await this.sleep(wait, request.signal);
      }
    }
  }

  private async checkBudget(): Promise<BudgetStatus> {
    if (!this.budget) return { exhaustedProviders: new Set() };
    try {
      return await this.budget.check(this.now());
    } catch (e) {
      // Fail open: a spend table that cannot be read must not switch every AI feature off. It is reported, loudly.
      this.warn({ event: 'ai.budget_check_failed', error: e instanceof Error ? e.name : 'Error' }, 'ai budget check failed');
      return { exhaustedProviders: new Set() };
    }
  }

  private async record(usage: UsageRecord): Promise<void> {
    if (!this.usage) return;
    try {
      await this.usage.record(usage);
    } catch (e) {
      // The user already has their answer (and the provider was paid): a broken usage sink must
      // neither trigger another provider call nor fail the request. It is reported, not hidden.
      const entry = { event: 'ai.usage_record_failed', provider: usage.providerId, error: e instanceof Error ? e.name : 'Error' };
      try {
        if (!this.logger) throw new Error('no logger');
        this.logger.warn(entry, 'ai usage record failed');
      } catch {
        console.error('ai gateway: usage record failed', entry.error);
      }
    }
  }

  private warn(entry: Record<string, unknown>, message: string): void {
    try {
      if (!this.logger) throw new Error('no logger');
      this.logger.warn(entry, message);
    } catch {
      console.error(`ai gateway: ${message}`, entry.error);
    }
  }

  private log(level: 'info' | 'warn', entry: Omit<AttemptLogEntry, 'event'>): void {
    if (!this.logger) return;
    const clean = Object.fromEntries(Object.entries({ event: 'ai.attempt', ...entry }).filter(([, v]) => v !== undefined));
    try {
      this.logger[level](clean, 'ai attempt');
    } catch (e) {
      // Telemetry must not turn a paid, valid answer (or the next fallback) into an error.
      console.error('ai gateway: logger failed', e instanceof Error ? e.name : 'Error');
    }
  }
}
