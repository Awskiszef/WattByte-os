// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

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
  status: 'all_providers_failed' | 'budget_exceeded' | 'budget_unavailable' | 'no_provider' | 'overloaded' | 'aborted';
  /** Provider calls that were billed although nothing was delivered (their cost is on the spend ledger, the user's slot stays used). */
  billedAttempts?: number;
  /** One entry per provider that was asked: who, what failed (`kind`, `category`) and the HTTP status they answered with (if any). */
  attempts: { provider?: string; httpStatus?: number; kind: string; category?: string }[];
}

/** A bookkeeping step that failed after the provider call; the request itself is not affected. */
export interface AiBookkeepingFailure {
  step: 'usage_log' | 'quota_release';
  task: AITask;
}

export interface AiLog {
  generated(event: AiGeneratedEvent): void;
  failed(event: AiFailedEvent): void;
  bookkeepingFailed?(event: AiBookkeepingFailure): void;
}

/** Adapts a pino-style logger (typically `request.log`, so the lines carry the request id) to `AiLog`. */
export function aiLogFrom(logger: { info(fields: object, msg: string): void; error(fields: object, msg: string): void }): AiLog {
  return {
    generated: (e) => logger.info({ ai: e }, 'ai generation'),
    failed: (e) => logger.error({ ai: e }, 'ai generation failed'),
    bookkeepingFailed: (e) => logger.error({ ai: e }, 'ai bookkeeping failed'),
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

  async generate(task: AITask, userId: string, plan: Plan, body: AIGenerateRequest, log: AiLog | undefined = this.log, signal?: AbortSignal): Promise<AIGenerateResponse> {
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
      // `signal` is the client's connection: when it goes away no retry, no fallback and no further paid call is started.
      outcome = await this.gateway.generate(task, mode, body.input, { userRef: userId, plan, locale: body.locale ?? 'en' }, { signal });
    } catch (e) {
      const billed = e instanceof AIGatewayError ? e.billed.length : 0;
      // The slot goes back only when the user got nothing AND nothing was billed: a refused or cut-off answer is paid
      // for, and handing the slot back would let a client repeat a failing request for free (D-01). A release that
      // fails must not replace the real answer with a 500 (D-04).
      if (billed === 0) {
        await this.repos.ai.release(userId, day).catch(() => log?.bookkeepingFailed?.({ step: 'quota_release', task }));
      }
      if (e instanceof AIGatewayError) {
        if (e.code === 'invalid_input') throw HttpError.badRequest('invalid_ai_input', e.message);
        // Provider detail stays in the log (content-free: ids, kinds, categories, statuses); the client learns nothing of it.
        log?.failed({
          task,
          status: e.code,
          attempts: e.attempts.map((a) => ({ provider: a.providerId, httpStatus: a.status, kind: a.kind, category: a.category })),
          ...(billed > 0 ? { billedAttempts: billed } : {}),
        });
        // Overloaded: tell the client when to come back instead of letting it hammer an instance that is full.
        if (e.code === 'overloaded') throw new HttpError(503, 'ai_unavailable', 'AI providers are unavailable right now', 5);
        throw HttpError.unavailable('ai_unavailable', 'AI providers are unavailable right now');
      }
      throw e;
    }
    // The provider is paid and its cost is already on the spend ledger (held before the call, settled after). The log
    // row is bookkeeping: if it cannot be written the user still gets the answer they paid a quota slot for (D-04).
    try {
      await this.repos.ai.insert(
        {
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
        },
        { spend: false },
      );
    } catch {
      log?.bookkeepingFailed?.({ step: 'usage_log', task });
    }
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
