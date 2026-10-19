import {
  AIGateway,
  createBudgetGuard,
  ProviderRouter,
  type AIProvider,
  type AIProviderId,
  type GatewayLogger,
  type GatewayOptions,
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
  });
}
