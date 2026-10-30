// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { AIGenerationRequest, AIProviderId, ModelConfig } from '../types.js';

function nonBlank(value: string | undefined): string | undefined {
  const v = value?.trim();
  return v ? v : undefined;
}

/** A model identifier as providers publish them (`name`, `name-2026-01-01`, `org/name`, `name:tag`). */
const MODEL_NAME = /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$/;

/** Visible-answer limit plus this much room: reasoning models count their hidden thinking against the same cap. */
export const REASONING_HEADROOM_TOKENS = 1024;

/**
 * Picks the model for a call: the backend's per-request override when there is one (validated, it is
 * sent to a paid API), otherwise the configured model for the request tier, falling back to the other
 * tier. A blank value (`OPENAI_FAST_MODEL=` in an .env file) counts as unset, otherwise `''` would win
 * over the tier that is actually configured.
 */
export function resolveModel(providerId: AIProviderId, models: ModelConfig, request: AIGenerationRequest): string {
  if (request.model !== undefined) {
    if (!MODEL_NAME.test(request.model)) throw new Error(`${providerId}: invalid model override`);
    return request.model;
  }
  const model = nonBlank(models[request.tier]) ?? nonBlank(models.fast) ?? nonBlank(models.quality);
  if (!model) throw new Error(`${providerId}: no model configured (set its FAST or QUALITY model variable)`);
  return model;
}

export function assertModels(providerId: AIProviderId, models: ModelConfig): void {
  if (!nonBlank(models.fast) && !nonBlank(models.quality)) throw new Error(`${providerId}: no model configured`);
}

/** The model name a provider reports back, if it is a plausible identifier; otherwise the one we asked for. */
export function reportedModel(reported: unknown, requested: string): string {
  return typeof reported === 'string' && MODEL_NAME.test(reported) ? reported : requested;
}

/** True for a string that may be used as `GenerateOptions.model`. */
export function isModelName(value: unknown): value is string {
  return typeof value === 'string' && MODEL_NAME.test(value);
}

/** A usable token count, or undefined when the provider sent nothing or something that is not a count. */
export function tokenCount(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : undefined;
}
