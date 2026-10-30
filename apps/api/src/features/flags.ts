// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { FastifyReply, FastifyRequest } from 'fastify';

import type { Env } from '../config/env.js';
import { HttpError } from '../errors/http-error.js';

/** Server-side switches (env `FEATURE_*`); no external flag service, a restart applies a change. */
export interface FeatureFlags {
  ai: boolean;
  subscriptions: boolean;
  cloudSync: boolean;
}

export type FeatureName = keyof FeatureFlags;

export function featureFlagsFromEnv(env: Pick<Env, 'FEATURE_AI' | 'FEATURE_SUBSCRIPTIONS' | 'FEATURE_CLOUD_SYNC'>): FeatureFlags {
  return {
    ai: env.FEATURE_AI === '1',
    subscriptions: env.FEATURE_SUBSCRIPTIONS === '1',
    cloudSync: env.FEATURE_CLOUD_SYNC === '1',
  };
}

/**
 * Route-level `preParsing` hook for the routes of one feature: answers 503 `feature_disabled` while the
 * flag is off. It runs after the app-level authentication hook (also `preParsing`), so an anonymous caller
 * gets 401 and learns nothing about the flags (they are public at `GET /api/v1/config` anyway), and before
 * the body is parsed or validated, so a disabled feature never reads a request body.
 */
export function requireFeature(features: FeatureFlags, name: FeatureName) {
  return async (_request: FastifyRequest, _reply: FastifyReply): Promise<void> => {
    if (!features[name]) throw HttpError.unavailable('feature_disabled', 'This feature is not enabled on this server');
  };
}
