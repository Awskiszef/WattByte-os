import { type AIGateway, AIGatewayError, type AIMode, type AITask, type GatewayStatus } from '@wattbyte/ai';
import type { AIGenerateRequest, AIGenerateResponse } from '@wattbyte/contracts';

import type { Plan, Repositories } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';

export interface AiLimits {
  free: number;
  premium: number;
}

/**
 * What the API may say about an AI call in its logs: provider id, model, latency, token counts, status.
 * Never the prompt, the aggregates, the answer, the user id or a provider's error text (which can echo the prompt).
 */
export interface AiGeneratedEvent {
  task: AITask;
  provider: string;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  status: 'ok';
}

export interface AiFailedEvent {
  task: AITask;
  /** Why the gateway gave up: the provider(s) the policy allowed failed, a spend limit is used up, or nothing is configured. */
  status: 'all_providers_failed' | 'budget_exceeded' | 'no_provider' | 'aborted';
  /** One entry per provider that was asked: who, what failed (`kind`, `category`) and the HTTP status they answered with (if any). */
  attempts: { provider?: string; httpStatus?: number; kind: string; category?: string }[];
}

export interface AiLog {
  generated(event: AiGeneratedEvent): void;
  failed(event: AiFailedEvent): void;
}

/** Adapts a pino-style logger (typically `request.log`, so the lines carry the request id) to `AiLog`. */
export function aiLogFrom(logger: { info(fields: object, msg: string): void; error(fields: object, msg: string): void }): AiLog {
  return {
    generated: (e) => logger.info({ ai: e }, 'ai generation'),
    failed: (e) => logger.error({ ai: e }, 'ai generation failed'),
  };
}

/**
 * API-side gatekeeper for the gateway: quota per plan and UTC day, cost log.
 * Only aggregates reach the gateway; the user id is kept as an opaque
 * reference for the usage log and never enters a prompt.
 */
export class AiService {
  constructor(
    private readonly repos: Repositories,
    private readonly gateway: AIGateway,
    private readonly limits: AiLimits,
    private readonly now: () => Date = () => new Date(),
    private readonly log?: AiLog,
  ) {}

  /** Which providers are configured and healthy, and the policy in force. Calls no provider, shows no key. */
  status(): GatewayStatus {
    return this.gateway.status();
  }

  async generate(task: AITask, userId: string, plan: Plan, body: AIGenerateRequest, log: AiLog | undefined = this.log): Promise<AIGenerateResponse> {
    const limit = this.limits[plan];
    const day = utcDayKey(this.now());
    // Reserve first, atomically: concurrent requests cannot exceed the limit, and a
    // deleted account fails here (foreign key) before any provider is paid.
    const used = await this.repos.ai.reserve(userId, day, limit);
    if (used === null) {
      // The quota is per UTC day, so the caller may retry at the next UTC midnight.
      throw HttpError.tooMany('ai_quota_exceeded', `Daily AI limit reached (${limit} per day on the ${plan} plan)`, secondsUntilNextUtcDay(this.now()));
    }

    const mode: AIMode = task === 'roast' ? 'roast' : (body.mode ?? 'normal');
    let outcome;
    try {
      outcome = await this.gateway.generate(task, mode, body.input, { userRef: userId, plan, locale: body.locale ?? 'en' });
    } catch (e) {
      // The user got nothing, so the slot goes back.
      await this.repos.ai.release(userId, day);
      if (e instanceof AIGatewayError) {
        if (e.code === 'invalid_input') throw HttpError.badRequest('invalid_ai_input', e.message);
        // Provider detail stays in the log (content-free: ids, kinds, categories, statuses); the client learns nothing of it.
        log?.failed({
          task,
          status: e.code,
          attempts: e.attempts.map((a) => ({ provider: a.providerId, httpStatus: a.status, kind: a.kind, category: a.category })),
        });
        throw HttpError.unavailable('ai_unavailable', 'AI providers are unavailable right now');
      }
      throw e;
    }
    await this.repos.ai.insert({
      userId,
      task,
      mode,
      provider: outcome.providerId,
      model: outcome.model,
      inputTokens: outcome.usage.inputTokens,
      outputTokens: outcome.usage.outputTokens,
      estimatedCostUsd: outcome.usage.estimatedCostUsd,
      costBasis: outcome.usage.costBasis,
      usageReported: outcome.usage.usageReported,
      latencyMs: outcome.usage.latencyMs,
      createdAt: outcome.usage.createdAt,
    });
    log?.generated({
      task,
      provider: outcome.providerId,
      model: outcome.model,
      latencyMs: outcome.usage.latencyMs,
      inputTokens: outcome.usage.inputTokens,
      outputTokens: outcome.usage.outputTokens,
      status: 'ok',
    });
    return {
      output: outcome.output,
      provider: outcome.providerId,
      model: outcome.model,
      remainingToday: Math.max(0, limit - used),
    };
  }
}

export function utcDayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

export function secondsUntilNextUtcDay(d: Date): number {
  const next = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - d.getTime()) / 1000));
}
