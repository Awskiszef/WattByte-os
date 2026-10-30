// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { AI_PROVIDER_IDS, type AITask } from '@wattbyte/ai';
import { AIGenerateRequest, AIGenerateResponse, ErrorResponse } from '@wattbyte/contracts';
import type { FastifyRequest } from 'fastify';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { type FeatureFlags, requireFeature } from '../../features/flags.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import type { TokenService } from '../auth/tokens.js';
import { aiLogFrom, type AiService } from './service.js';

export interface AiRoutesOptions {
  service: AiService;
  tokens: TokenService;
  features: FeatureFlags;
  /** Per-IP requests per minute on the AI routes. */
  rateLimitMax?: number;
}

/**
 * What `GET /ai/status` answers. Configuration and health only: no key, no part of a key, no model name,
 * nothing that was sent to or received from a provider. Operator tooling, not part of the app's contract,
 * so it is kept out of the OpenAPI document (and with it out of the generated Dart client).
 */
const AiStatusResponse = z.object({
  enabled: z.boolean(),
  providers: z.record(
    z.enum(AI_PROVIDER_IDS),
    z.object({ configured: z.boolean(), inCooldown: z.boolean(), retryInSec: z.number().int().nonnegative(), consecutiveFailures: z.number().int().nonnegative() }),
  ),
  defaultProvider: z.enum(AI_PROVIDER_IDS).nullable(),
  fallback: z.object({ enabled: z.boolean(), onRateLimit: z.boolean() }),
  maxRetries: z.number().int().nonnegative(),
  timeouts: z.object({ attemptMs: z.number().int().positive(), requestMs: z.number().int().positive() }),
  budgetEnforced: z.boolean(),
});

const ROUTES: readonly { path: string; task: AITask; summary: string }[] = [
  { path: '/ai/insight', task: 'insight', summary: 'One observation about a period' },
  { path: '/ai/weekly-summary', task: 'weekly_summary', summary: 'Summary of a week' },
  { path: '/ai/monthly-summary', task: 'monthly_summary', summary: 'Summary of a month' },
  { path: '/ai/roast', task: 'roast', summary: 'Playful roast (tone is always roast)' },
];

export const aiRoutes: FastifyPluginAsyncZod<AiRoutesOptions> = async (app, { service, tokens, features, rateLimitMax }) => {
  const auth = requireAuth(tokens);
  /** `FEATURE_AI=0` switches every AI route off: 503 `feature_disabled`. */
  const aiEnabled = requireFeature(features, 'ai');
  app.get(
    '/ai/status',
    {
      preHandler: auth,
      config: { rateLimit: { max: rateLimitMax ?? 20, timeWindow: '1 minute' } },
      schema: { hide: true, response: { 200: AiStatusResponse, 401: ErrorResponse, 429: ErrorResponse } },
    },
    async () => {
      const s = service.status();
      return {
        enabled: features.ai,
        providers: Object.fromEntries(
          s.providers.map((p) => [p.id, { configured: p.configured, inCooldown: p.inCooldown, retryInSec: Math.ceil(p.retryInMs / 1000), consecutiveFailures: p.consecutiveFailures }]),
        ) as z.infer<typeof AiStatusResponse>['providers'],
        defaultProvider: s.defaultProvider,
        fallback: { enabled: s.fallbackEnabled, onRateLimit: s.fallbackOnRateLimit },
        maxRetries: s.maxRetries,
        timeouts: { attemptMs: s.attemptTimeoutMs, requestMs: s.requestTimeoutMs },
        budgetEnforced: s.budgetEnforced,
      };
    },
  );

  for (const { path, task, summary } of ROUTES) {
    app.post(
      path,
      {
        preHandler: auth,
        preParsing: aiEnabled,
        // One budget per SIGNED-IN USER for all AI routes together (D-11). It runs after authentication (preHandler), so the
        // key is the account, not the address: users behind one NAT or proxy do not share it, and rotating addresses does
        // not multiply it. The global per-client limit still applies on top.
        config: {
          rateLimit: {
            max: rateLimitMax ?? 20,
            timeWindow: '1 minute',
            groupId: 'ai',
            hook: 'preHandler',
            keyGenerator: (request: FastifyRequest) => `user:${request.user?.userId ?? request.ip}`,
          },
        },
        schema: {
          tags: ['ai'],
          summary,
          description: 'Input must be pre-computed aggregates only; the model never calculates.',
          security: [{ bearerAuth: [] }],
          body: AIGenerateRequest,
          response: { 200: AIGenerateResponse, 400: ErrorResponse, 401: ErrorResponse, 429: ErrorResponse, 503: ErrorResponse },
        },
      },
      async (request, reply) => {
        const { userId, plan } = currentUser(request);
        // The client hung up: stop paying for an answer nobody reads (no retry, no fallback, no new call).
        const gone = new AbortController();
        reply.raw.once('close', () => {
          if (!reply.raw.writableFinished) gone.abort();
        });
        return service.generate(task, userId, plan, request.body, aiLogFrom(request.log), gone.signal);
      },
    );
  }
};
