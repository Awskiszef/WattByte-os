import { AppConfigDto } from '@wattbyte/contracts';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

import type { AppEnv } from '../../config/env.js';
import type { FeatureFlags } from '../../features/flags.js';

export interface ConfigRoutesOptions {
  environment: AppEnv;
  features: FeatureFlags;
  /** Daily AI generations per plan, read from the environment: the app never hardcodes them. */
  aiDailyLimits: { free: number; premium: number };
}

export const configRoutes: FastifyPluginAsyncZod<ConfigRoutesOptions> = async (app, { environment, features, aiDailyLimits }) => {
  app.get(
    '/config',
    {
      // Public on purpose: the app reads it before (and without) a session to learn which features exist.
      config: { public: true },
      schema: {
        tags: ['config'],
        summary: 'Runtime configuration: environment, feature flags and AI limits',
        description: 'Contains no secret and nothing account-specific. A disabled feature answers 503 `feature_disabled`.',
        response: { 200: AppConfigDto },
      },
    },
    async () => ({ environment, features, ai: { dailyLimits: aiDailyLimits } }),
  );
};
