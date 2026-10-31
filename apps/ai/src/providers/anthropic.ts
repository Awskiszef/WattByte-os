// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { AIGenerationRequest, AIGenerationResult, AIProvider, ModelConfig, ProviderHealthResult } from '../types.js';
import { getOk, postJson, ProviderError, type FetchLike } from './http.js';
import { assertModels, reportedModel, resolveModel, tokenCount } from './models.js';

/**
 * Output headroom above the plan's token cap. The cap is sized for the answer, but a long (Polish) answer plus the JSON
 * around it can exceed it, and an answer cut inside the JSON is a billed failure (D-03). Not the 1024 the reasoning
 * models of the other adapters need: this one does not think before it answers.
 */
export const ANTHROPIC_OUTPUT_HEADROOM_TOKENS = 256;

interface MessagesResponse {
  content?: { type: string; text?: string }[];
  stop_reason?: string | null;
  usage?: { input_tokens?: number; output_tokens?: number };
  model?: string;
}

/**
 * Anthropic Messages API. The base URL is a constructor option only: this
 * adapter never reads ANTHROPIC_BASE_URL (or any other ambient variable), so a
 * proxy configured for some other tool on the same machine cannot capture
 * WattByte traffic.
 */
export class AnthropicProvider implements AIProvider {
  readonly id = 'anthropic' as const;
  private readonly baseUrl: string;
  private readonly models: ModelConfig;
  private readonly fetchImpl?: FetchLike;
  /** ES private field: invisible to JSON.stringify, util.inspect and structured loggers. */
  readonly #apiKey: string;

  constructor(opts: { apiKey: string; models: ModelConfig; baseUrl?: string; fetchImpl?: FetchLike }) {
    assertModels('anthropic', opts.models);
    this.#apiKey = opts.apiKey;
    this.models = opts.models;
    this.fetchImpl = opts.fetchImpl;
    this.baseUrl = (opts.baseUrl ?? 'https://api.anthropic.com').replace(/\/$/, '');
  }

  private headers(): Record<string, string> {
    return { 'x-api-key': this.#apiKey, 'anthropic-version': '2023-06-01' };
  }

  async generate(request: AIGenerationRequest): Promise<AIGenerationResult> {
    const started = Date.now();
    const model = resolveModel(this.id, this.models, request);
    const res = await postJson<MessagesResponse>({
      providerId: this.id,
      model,
      url: `${this.baseUrl}/v1/messages`,
      body: {
        model,
        max_tokens: request.maxOutputTokens + ANTHROPIC_OUTPUT_HEADROOM_TOKENS,
        temperature: request.mode === 'normal' ? 0.3 : 0.8,
        system: request.system,
        messages: [{ role: 'user', content: request.user }],
      },
      headers: this.headers(),
      timeoutMs: request.timeoutMs,
      signal: request.signal,
      fetchImpl: this.fetchImpl,
    });
    const inputTokens = tokenCount(res.usage?.input_tokens);
    const outputTokens = tokenCount(res.usage?.output_tokens);
    if (res.stop_reason === 'refusal') {
      throw new ProviderError(this.id, 'the model declined to answer', undefined, false, {
        kind: 'refusal',
        model,
        inputTokens: inputTokens ?? 0,
        outputTokens: outputTokens ?? 0,
      });
    }
    return {
      providerId: this.id,
      model: reportedModel(res.model, model),
      text: res.content?.find((c) => c.type === 'text')?.text ?? '',
      inputTokens: inputTokens ?? 0,
      outputTokens: outputTokens ?? 0,
      usageReported: inputTokens !== undefined && outputTokens !== undefined,
      // The answer hit the token limit: if it is unusable, that is the reason (and a bigger cap, not a different prompt, is the fix).
      truncated: res.stop_reason === 'max_tokens',
      latencyMs: Date.now() - started,
    };
  }

  async healthCheck(): Promise<ProviderHealthResult> {
    const r = await getOk(this.id, `${this.baseUrl}/v1/models?limit=1`, this.headers(), 5000, this.fetchImpl);
    return { providerId: this.id, ...r };
  }
}
