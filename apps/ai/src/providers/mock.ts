// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { AIGenerationRequest, AIGenerationResult, AIProvider, AIProviderId, ProviderHealthResult } from '../types.js';
import { ProviderError } from './http.js';

export interface MockBehaviour {
  /** Text to return; defaults to a valid JSON output. */
  text?: string;
  /** Throw instead of answering. */
  fail?: boolean | ProviderError;
  healthy?: boolean;
  latencyMs?: number;
}

/** Deterministic provider for tests and local development without API keys. */
export class MockProvider implements AIProvider {
  readonly calls: AIGenerationRequest[] = [];

  constructor(
    readonly id: AIProviderId,
    private behaviour: MockBehaviour = {},
  ) {}

  set(behaviour: MockBehaviour): void {
    this.behaviour = { ...this.behaviour, ...behaviour };
  }

  async generate(request: AIGenerationRequest): Promise<AIGenerationResult> {
    this.calls.push(request);
    const { fail } = this.behaviour;
    if (fail) throw fail instanceof ProviderError ? fail : new ProviderError(this.id, 'mock failure', 503);
    const text =
      this.behaviour.text ??
      JSON.stringify({
        title: `Mock ${request.task}`,
        message: `Mock message from ${this.id} in ${request.mode} mode.`,
        tone: request.mode,
        severity: 'info',
        emoji: '⚡',
      });
    return {
      providerId: this.id,
      model: `${this.id}-mock`,
      text,
      inputTokens: Math.ceil((request.system.length + request.user.length) / 4),
      outputTokens: Math.ceil(text.length / 4),
      latencyMs: this.behaviour.latencyMs ?? 1,
    };
  }

  async healthCheck(): Promise<ProviderHealthResult> {
    return { providerId: this.id, ok: this.behaviour.healthy ?? true, latencyMs: 0 };
  }
}
