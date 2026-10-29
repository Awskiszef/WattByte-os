import { expect } from 'vitest';

import { AI_OUTPUT_JSON_SCHEMA, AnthropicProvider, GoogleProvider, OpenAIProvider, REASONING_HEADROOM_TOKENS, XAIProvider } from '../../src/index.js';
import type { AIGenerationRequest, AIProvider, AIProviderId } from '../../src/types.js';

export const OUTPUT = { title: 'Heavy month', message: '34% more data than last month.', tone: 'normal', severity: 'info', emoji: '⚡' };
export const json = JSON.stringify(OUTPUT);

export const request: AIGenerationRequest = {
  task: 'insight',
  tier: 'fast',
  mode: 'normal',
  locale: 'en',
  system: 'SYSTEM PROMPT',
  user: 'USER PROMPT',
  maxOutputTokens: 220,
  timeoutMs: 200,
};

export const gatewayInput = {
  period: '2026-10',
  periodType: 'month' as const,
  mobileDataGb: 187.4,
  wifiDataGb: 1433.8,
  totalDataGb: 1621.2,
  chargingSessions: 94,
  batteryEnergyKwh: 1.56,
  wallEnergyKwh: 1.84,
  electricityCost: 2.31,
  currency: 'PLN',
  previousPeriodChangePercent: 34,
};

export const ctx = { userRef: 'user-ref-7f3a', plan: 'free' as const, locale: 'en' as const };

export interface Captured {
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
}

export type Reply = {
  status?: number;
  body?: unknown;
  raw?: string;
  headers?: Record<string, string>;
  /** Never answers; rejects when the request is aborted (what a real fetch does). */
  hang?: boolean;
  /** Never answers and never reacts to the abort signal (a misbehaving fetch). */
  hangIgnoringSignal?: boolean;
  /** Rejects like a network failure. */
  networkError?: unknown;
};

/** A fetch double that records the request and answers with `reply` (a function = per-call reply). */
export function fakeFetch(reply: Reply | ((call: number, captured: Captured) => Reply)): { fetchImpl: typeof fetch; calls: Captured[] } {
  const calls: Captured[] = [];
  const fetchImpl = ((url: string, init: RequestInit) => {
    const captured: Captured = {
      url: String(url),
      // The SDK hands over a Headers object, the hand-written adapters a plain record: normalise both.
      headers: Object.fromEntries(new Headers(init.headers as ConstructorParameters<typeof Headers>[0]).entries()),
      body: init.body ? (JSON.parse(String(init.body)) as Record<string, unknown>) : {},
    };
    calls.push(captured);
    const r = typeof reply === 'function' ? reply(calls.length, captured) : reply;
    if (r.networkError !== undefined) return Promise.reject(r.networkError);
    if (r.hangIgnoringSignal) return new Promise(() => undefined);
    if (r.hang) {
      return new Promise((_, reject) => {
        init.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
      });
    }
    const text = r.raw ?? JSON.stringify(r.body ?? {});
    return Promise.resolve(new Response(text, { status: r.status ?? 200, headers: { 'content-type': 'application/json', ...r.headers } }));
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

export const models = { fast: 'fast-model-x', quality: 'quality-model-x' };

/** Token usage as a provider might (mis)report it; `null` = no usage object at all. */
export type UsageShape = { input?: unknown; output?: unknown; thoughts?: unknown } | null;

export interface Spec {
  name: AIProviderId;
  make: (fetchImpl: typeof fetch, overrides?: { baseUrl?: string; models?: { fast?: string; quality?: string } }) => AIProvider;
  url: (model: string) => string;
  authHeader: [string, string];
  /** A successful 2xx body carrying `text` and `usage` (default: valid counts below). */
  success: (text: string, usage?: UsageShape) => unknown;
  /** A 2xx body in which the model/safety layer refused to answer. */
  refusals: unknown[];
  checkPayload: (body: Record<string, unknown>, model: string) => void;
  /** What `success(json)` must be parsed to. */
  tokens: { input: number; output: number };
  /** Wire names of the usage fields, for the failure messages of the tests. */
  usageFields: string;
}

const okUsage = { input: 11, output: 7 };

/** A Responses API answer (OpenAI and xAI share the wire format). */
function responsesBody(text: string, usage: UsageShape, model: string | undefined): Record<string, unknown> {
  return {
    id: 'resp_0123456789abcdef',
    object: 'response',
    status: 'completed',
    ...(model ? { model } : {}),
    output: [
      { type: 'reasoning', id: 'rs_1', summary: [] },
      { type: 'message', id: 'msg_1', role: 'assistant', content: [{ type: 'output_text', text, annotations: [] }] },
    ],
    usage:
      usage === null
        ? undefined
        : {
            input_tokens: usage.input,
            output_tokens: usage.output,
            total_tokens: typeof usage.input === 'number' && typeof usage.output === 'number' ? usage.input + usage.output : undefined,
            output_tokens_details: { reasoning_tokens: 0 },
          },
  };
}

const responsesRefusals: unknown[] = [
  {
    id: 'resp_r1',
    status: 'completed',
    output: [{ type: 'message', role: 'assistant', content: [{ type: 'refusal', refusal: "I can't help with that." }] }],
    usage: { input_tokens: 20, output_tokens: 9 },
  },
  { id: 'resp_r2', status: 'incomplete', incomplete_details: { reason: 'content_filter' }, output: [], usage: { input_tokens: 20, output_tokens: 0 } },
];

export const specs: Spec[] = [
  {
    name: 'openai',
    make: (fetchImpl, o = {}) => new OpenAIProvider({ apiKey: 'k-openai', models: o.models ?? models, fetchImpl, baseUrl: o.baseUrl }),
    url: () => 'https://api.openai.com/v1/responses',
    authHeader: ['authorization', 'Bearer k-openai'],
    success: (text, usage = okUsage) => responsesBody(text, usage, 'fast-model-x-2026'),
    refusals: responsesRefusals,
    checkPayload: (b, model) => {
      expect(b.model).toBe(model);
      expect(b.instructions).toBe('SYSTEM PROMPT');
      expect(b.input).toBe('USER PROMPT');
      // Reasoning models spend their hidden thinking from the same cap: 220 visible tokens + headroom.
      expect(b.max_output_tokens).toBe(220 + REASONING_HEADROOM_TOKENS);
      // The aggregates are not kept at OpenAI for 30 days (the API stores by default).
      expect(b.store).toBe(false);
      expect(b.temperature).toBe(0.3);
      expect(b.text).toEqual({ format: { type: 'json_schema', name: 'wattbyte_ai_output', strict: true, schema: AI_OUTPUT_JSON_SCHEMA } });
      expect(b).not.toHaveProperty('messages');
      expect(b).not.toHaveProperty('response_format');
    },
    tokens: { input: 11, output: 7 },
    usageFields: 'usage.input_tokens / usage.output_tokens',
  },
  {
    name: 'xai',
    make: (fetchImpl, o = {}) => new XAIProvider({ apiKey: 'k-xai', models: o.models ?? models, fetchImpl, baseUrl: o.baseUrl }),
    url: () => 'https://api.x.ai/v1/responses',
    authHeader: ['authorization', 'Bearer k-xai'],
    success: (text, usage = okUsage) => responsesBody(text, usage, undefined),
    refusals: responsesRefusals,
    checkPayload: (b, model) => {
      expect(b.model).toBe(model);
      expect(b.instructions).toBe('SYSTEM PROMPT');
      expect(b.input).toBe('USER PROMPT');
      expect(b.max_output_tokens).toBe(220 + REASONING_HEADROOM_TOKENS);
      expect(b.store).toBe(false);
      // Structured-output support of xAI's Responses API is not confirmed: the prompt asks for JSON, the parser checks it.
      expect(b).not.toHaveProperty('text');
      expect(b).not.toHaveProperty('messages');
    },
    tokens: { input: 11, output: 7 },
    usageFields: 'usage.input_tokens / usage.output_tokens',
  },
  {
    name: 'anthropic',
    make: (fetchImpl, o = {}) => new AnthropicProvider({ apiKey: 'k-anthropic', models: o.models ?? models, fetchImpl, baseUrl: o.baseUrl }),
    url: () => 'https://api.anthropic.com/v1/messages',
    authHeader: ['x-api-key', 'k-anthropic'],
    success: (text, usage = okUsage) => ({
      model: 'fast-model-x',
      content: [{ type: 'text', text }],
      stop_reason: 'end_turn',
      usage: usage === null ? undefined : { input_tokens: usage.input, output_tokens: usage.output },
    }),
    refusals: [{ content: [], stop_reason: 'refusal', usage: { input_tokens: 20, output_tokens: 0 } }],
    checkPayload: (b, model) => {
      expect(b.model).toBe(model);
      expect(b.system).toBe('SYSTEM PROMPT');
      expect(b.messages).toEqual([{ role: 'user', content: 'USER PROMPT' }]);
      // the plan's cap plus the 256 tokens of headroom: an answer cut inside the JSON is a billed failure (D-03)
      expect(b.max_tokens).toBe(220 + 256);
    },
    tokens: { input: 11, output: 7 },
    usageFields: 'usage.input_tokens / usage.output_tokens',
  },
  {
    name: 'google',
    make: (fetchImpl, o = {}) => new GoogleProvider({ apiKey: 'k-google', models: o.models ?? models, fetchImpl, baseUrl: o.baseUrl }),
    url: (model) => `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    authHeader: ['x-goog-api-key', 'k-google'],
    success: (text, usage = okUsage) => ({
      modelVersion: 'fast-model-x-001',
      candidates: [{ content: { parts: [{ text }] }, finishReason: 'STOP' }],
      usageMetadata:
        usage === null
          ? undefined
          : { promptTokenCount: usage.input, candidatesTokenCount: usage.output, thoughtsTokenCount: usage.thoughts },
    }),
    refusals: [
      { promptFeedback: { blockReason: 'SAFETY' }, usageMetadata: { promptTokenCount: 20 } },
      { candidates: [{ finishReason: 'SAFETY' }], usageMetadata: { promptTokenCount: 20, candidatesTokenCount: 0 } },
    ],
    checkPayload: (b) => {
      expect(b.systemInstruction).toEqual({ parts: [{ text: 'SYSTEM PROMPT' }] });
      expect(b.contents).toEqual([{ role: 'user', parts: [{ text: 'USER PROMPT' }] }]);
      const cfg = b.generationConfig as Record<string, unknown>;
      expect(cfg.responseMimeType).toBe('application/json');
      expect(cfg.maxOutputTokens as number).toBeGreaterThan(220); // headroom for reasoning tokens
    },
    tokens: { input: 11, output: 7 },
    usageFields: 'usageMetadata.promptTokenCount / candidatesTokenCount (+ thoughtsTokenCount)',
  },
];
