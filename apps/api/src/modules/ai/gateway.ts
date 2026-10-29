import {
  AIGateway,
  createBudgetGuard,
  ProviderRouter,
  type AIProvider,
  type AIProviderId,
  type GatewayLogger,
  type GatewayOptions,
  type SpendLedger,
} from '@wattbyte/ai';

import type { Env } from '../../config/env.js';
import type { Repositories } from '../../database/repositories.js';

/** Everything in the gateway that the environment decides, as plain options (no provider, no I/O). */
export type EnvGatewayOptions = Pick<
  GatewayOptions,
  'timeoutMs' | 'requestTimeoutMs' | 'maxRetries' | 'fallback' | 'defaultProvider' | 'modelPrices'
>;

export function gatewayOptionsFromEnv(env: Env): EnvGatewayOptions {
  return {
    timeoutMs: env.AI_ATTEMPT_TIMEOUT_MS,
    requestTimeoutMs: env.AI_REQUEST_TIMEOUT_MS,
    maxRetries: env.AI_MAX_RETRIES,
    fallback: { enabled: env.AI_FALLBACK_ENABLED === '1', onRateLimit: env.AI_FALLBACK_ON_RATE_LIMIT === '1' },
    defaultProvider: env.AI_DEFAULT_PROVIDER,
    modelPrices: env.AI_MODEL_PRICES,
  };
}

/**
 * What the free plan may spend per UTC day: AI_BUDGET_FREE_DAILY_USD, else half of AI_BUDGET_DAILY_USD, else no
 * separate limit. Free accounts cost nothing to create (no verification yet), so they share part of the budget; the rest
 * is kept for paying users and the free plan can never exhaust the whole day.
 */
export function freePlanDailyUsd(env: Pick<Env, 'AI_BUDGET_FREE_DAILY_USD' | 'AI_BUDGET_DAILY_USD'>): number | undefined {
  if (env.AI_BUDGET_FREE_DAILY_USD !== undefined) return env.AI_BUDGET_FREE_DAILY_USD;
  return env.AI_BUDGET_DAILY_USD === undefined ? undefined : env.AI_BUDGET_DAILY_USD / 2;
}

/** The spend ledger of the gateway on top of the repositories (atomic hold against the AI_BUDGET_* limits, then settle). */
export function spendLedger(env: Env, repos: Repositories): SpendLedger {
  return {
    async reserve({ provider, estimateUsd, now, plan }) {
      const day = now.toISOString().slice(0, 10);
      const held = await repos.ai.reserveSpend({
        day,
        provider,
        plan,
        usd: estimateUsd,
        limits: {
          dailyUsd: env.AI_BUDGET_DAILY_USD,
          monthlyUsd: env.AI_BUDGET_MONTHLY_USD,
          providerDailyUsd: env.AI_BUDGET_PROVIDER_DAILY_USD?.[provider],
          planDailyUsd: plan === 'free' ? freePlanDailyUsd(env) : undefined,
        },
      });
      if (!held.ok) return held;
      return {
        ok: true,
        reservation: {
          // The hold was the worst case; the difference to the real cost goes back (or stays, when nothing is known).
          settle: (actualUsd, billed) =>
            repos.ai.adjustSpend({ day, provider, plan, deltaUsd: (billed ? actualUsd : 0) - estimateUsd, deltaRequests: billed ? 0 : -1 }),
        },
      };
    },
  };
}

/**
 * The production gateway: the providers that have keys, the policy from the environment, spend limits
 * checked against the daily spend table. `main.ts` builds it before the Fastify app exists, so the
 * logger is passed in as a late-binding wrapper.
 */
export function buildGateway(env: Env, repos: Repositories, providers: readonly AIProvider[], logger: GatewayLogger): AIGateway {
  return new AIGateway({
    router: new ProviderRouter(providers),
    logger,
    ...gatewayOptionsFromEnv(env),
    budget: createBudgetGuard(
      { dailyUsd: env.AI_BUDGET_DAILY_USD, monthlyUsd: env.AI_BUDGET_MONTHLY_USD, providerDailyUsd: env.AI_BUDGET_PROVIDER_DAILY_USD },
      { spentUsd: (sinceDay, provider?: AIProviderId) => repos.ai.spentUsd(sinceDay, provider) },
    ),
    // Always present, limits or not: every provider call is held on the ledger before it is made and settled after,
    // so spend is recorded (and limits hold under concurrency) whatever happens to the request afterwards.
    ledger: spendLedger(env, repos),
  });
}
