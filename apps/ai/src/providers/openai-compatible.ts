// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import OpenAI, { APIConnectionError, APIConnectionTimeoutError, APIError } from 'openai';

import { AI_OUTPUT_JSON_SCHEMA } from '../schemas.js';
import type { AIGenerationRequest, AIGenerationResult, AIProvider, AIProviderId, ModelConfig, ProviderHealthResult } from '../types.js';
import {
  getOk,
  networkMessage,
  ProviderError,
  retryAfterMsFrom,
  runWithDeadline,
  safeCode,
  safeRequestId,
  type FetchLike,
} from './http.js';
import { assertModels, REASONING_HEADROOM_TOKENS, reportedModel, resolveModel, tokenCount } from './models.js';

/**
 * The only request headers that ever leave the process. The official SDK also reads headers from the
 * environment (`OPENAI_CUSTOM_HEADERS`); a variable set for another tool on the developer's machine
 * must not be attached to WattByte's traffic, and must not travel to xAI. Nothing the SDK adds on its
 * own (platform telemetry, idempotency keys) is needed by either API.
 */
const ALLOWED_REQUEST_HEADERS: ReadonlySet<string> = new Set(['authorization', 'content-type', 'accept', 'user-agent']);

/** Wraps the transport so only `ALLOWED_REQUEST_HEADERS` reach the wire. The global fetch is looked up per call. */
function isolatedFetch(fetchImpl: FetchLike | undefined): FetchLike {
  return ((input: Parameters<FetchLike>[0], init?: Parameters<FetchLike>[1]) => {
    const headers = new Headers(init?.headers);
    for (const name of [...headers.keys()]) if (!ALLOWED_REQUEST_HEADERS.has(name.toLowerCase())) headers.delete(name);
    return (fetchImpl ?? globalThis.fetch)(input, { ...init, headers });
  }) as FetchLike;
}

const SILENT_LOGGER = { error: () => undefined, warn: () => undefined, info: () => undefined, debug: () => undefined };

/** xAI states the exact charge as integer "ticks" of a ten-billionth of a dollar (`usage.cost_in_usd_ticks`). */
const USD_TICKS_PER_DOLLAR = 10_000_000_000;

interface OutputPart {
  type?: string;
  text?: unknown;
  refusal?: unknown;
}
interface OutputItem {
  type?: string;
  content?: OutputPart[];
}
interface UsageShape {
  input_tokens?: unknown;
  output_tokens?: unknown;
  /** xAI has been seen to answer the Responses API with the Chat Completions names; accept both. */
  prompt_tokens?: unknown;
  completion_tokens?: unknown;
  cost_in_usd_ticks?: unknown;
}
/** What is read from a Responses API answer (OpenAI and xAI share this wire format). */
interface ResponsesAnswer {
  id?: unknown;
  model?: unknown;
  status?: unknown;
  error?: { code?: unknown } | null;
  incomplete_details?: { reason?: unknown } | null;
  output?: OutputItem[];
  usage?: UsageShape | null;
  _request_id?: unknown;
}

/** A 400 that named `temperature`: this model does not take a sampling temperature. */
class TemperatureRejected extends ProviderError {}

/** Reasoning models only accept the default temperature; any other value is a 400 that names the parameter. */
function rejectsTemperature(e: unknown): boolean {
  return e instanceof APIError && e.status === 400 && (e.param === 'temperature' || /\btemperature\b/i.test(e.message));
}

/** SDK exceptions become the same content-free, classified `ProviderError` every other adapter throws. */
function mapSdkError(id: AIProviderId, model: string, sentTemperature: boolean, e: unknown): ProviderError | undefined {
  if (e instanceof APIConnectionTimeoutError) {
    return new ProviderError(id, 'timeout (client)', undefined, true, { kind: 'timeout', model });
  }
  if (e instanceof APIConnectionError) {
    return new ProviderError(id, networkMessage(e.cause ?? e), undefined, true, { kind: 'network', model });
  }
  if (e instanceof APIError && typeof e.status === 'number') {
    // Only a short machine code: `message` and `error` quote the request on some providers.
    const code = safeCode(e.code) ?? safeCode(e.type);
    const detail = {
      model,
      code,
      retryAfterMs: e.headers ? retryAfterMsFrom(e.headers) : undefined,
      requestId: safeRequestId(e.requestID),
    };
    const message = `HTTP ${e.status}${code ? ` (${code})` : ''}`;
    if (sentTemperature && rejectsTemperature(e)) return new TemperatureRejected(id, message, e.status, undefined, detail);
    return new ProviderError(id, message, e.status, undefined, detail);
  }
  // `content-type: application/json` with a body that is not JSON.
  if (e instanceof SyntaxError) return new ProviderError(id, 'response body is not valid JSON', undefined, false, { kind: 'invalid_response', model });
  return undefined;
}

/** HTTP status a `failed` Responses answer stands for (the API reports upstream errors inside a 200). */
function failedStatus(code: string | undefined): number {
  if (code === 'rate_limit_exceeded') return 429;
  if (code === 'invalid_prompt' || code?.startsWith('invalid_') || code === 'data_residency_mismatch') return 400;
  return 502;
}

const POLICY_CODE = /policy|content_filter|safety/i;

export interface OpenAICompatibleOptions {
  readonly id: AIProviderId;
  readonly apiKey: string;
  readonly baseUrl: string;
  readonly models: ModelConfig;
  readonly fetchImpl?: FetchLike;
  /**
   * Ask for the JSON Schema of the output (`text.format`). Off for providers whose structured-output
   * support for the Responses API is not confirmed: the prompt demands JSON and `parseAIOutput` validates it.
   */
  readonly structuredOutput?: boolean;
}

/**
 * The Responses API (`POST {baseUrl}/responses`) through the official `openai` SDK. It serves OpenAI and
 * xAI, each with its own client and base URL; the two never share an instance.
 *
 * What it guarantees beyond the SDK's defaults:
 * - no ambient configuration: key, base URL and headers are the constructor's, never `OPENAI_*` variables;
 * - `store: false`: the aggregates are not kept at the provider for 30 days (the API stores by default);
 * - the SDK does not retry: retries, backoff and fallback belong to the gateway, which knows the time budget;
 * - one hard deadline per call plus cancellation by `AbortSignal`, and content-free errors (no body text);
 * - `temperature` is sent only where the model accepts it (see `generate`).
 */
export class OpenAICompatibleProvider implements AIProvider {
  readonly id: AIProviderId;
  /** ES private fields: invisible to JSON.stringify, util.inspect and structured loggers. */
  readonly #apiKey: string;
  readonly #client: OpenAI;
  private readonly baseUrl: string;
  private readonly models: ModelConfig;
  private readonly fetchImpl?: FetchLike;
  private readonly structuredOutput: boolean;
  /** Models that answered 400 to a temperature: not sent again by this instance. */
  private readonly noTemperature = new Set<string>();

  constructor(opts: OpenAICompatibleOptions) {
    this.id = opts.id;
    this.#apiKey = opts.apiKey;
    this.baseUrl = opts.baseUrl.replace(/\/$/, '');
    assertModels(opts.id, opts.models);
    this.models = opts.models;
    this.fetchImpl = opts.fetchImpl;
    this.structuredOutput = opts.structuredOutput ?? false;
    this.#client = new OpenAI({
      apiKey: opts.apiKey,
      baseURL: this.baseUrl,
      // Every other credential or endpoint the SDK would pick up from the environment is switched off.
      organization: null,
      project: null,
      adminAPIKey: null,
      webhookSecret: null,
      logLevel: 'off',
      logger: SILENT_LOGGER,
      maxRetries: 0,
      fetch: isolatedFetch(opts.fetchImpl),
    });
  }

  async generate(request: AIGenerationRequest): Promise<AIGenerationResult> {
    const started = Date.now();
    const model = resolveModel(this.id, this.models, request);
    const withTemperature = !this.noTemperature.has(model);
    try {
      return await this.send(request, model, withTemperature, started);
    } catch (e) {
      if (!(e instanceof TemperatureRejected)) throw e;
      // Reasoning models refuse a custom temperature. Model names are configuration, so a list of such models
      // would rot: learn it from the 400 instead (it is not billed), remember it, and ask again without.
      this.noTemperature.add(model);
      return this.send(request, model, false, started);
    }
  }

  private async send(request: AIGenerationRequest, model: string, withTemperature: boolean, started: number): Promise<AIGenerationResult> {
    const answer = await runWithDeadline<ResponsesAnswer>({
      providerId: this.id,
      model,
      timeoutMs: request.timeoutMs,
      signal: request.signal,
      mapError: (e) => mapSdkError(this.id, model, withTemperature, e),
      run: async (signal) =>
        (await this.#client.responses.create(
          {
            model,
            instructions: request.system,
            input: request.user,
            // The cap counts hidden reasoning tokens too; without headroom a reasoning model can spend it all thinking.
            max_output_tokens: request.maxOutputTokens + REASONING_HEADROOM_TOKENS,
            store: false,
            ...(withTemperature ? { temperature: request.mode === 'normal' ? 0.3 : 0.8 } : {}),
            ...(this.structuredOutput
              ? { text: { format: { type: 'json_schema' as const, name: 'wattbyte_ai_output', strict: true, schema: { ...AI_OUTPUT_JSON_SCHEMA } } } }
              : {}),
          },
          { signal, timeout: request.timeoutMs, maxRetries: 0 },
        )) as unknown as ResponsesAnswer,
    });
    return this.toResult(answer, model, started);
  }

  private toResult(answer: ResponsesAnswer, model: string, started: number): AIGenerationResult {
    if (typeof answer !== 'object' || answer === null || !Array.isArray(answer.output)) {
      // A 2xx that is not a Responses object (an HTML error page behind a proxy, a different API).
      throw new ProviderError(this.id, 'response is not a Responses API object', undefined, false, { kind: 'invalid_response', model });
    }
    const usage = answer.usage ?? undefined;
    const inputTokens = tokenCount(usage?.input_tokens) ?? tokenCount(usage?.prompt_tokens);
    const outputTokens = tokenCount(usage?.output_tokens) ?? tokenCount(usage?.completion_tokens);
    const requestId = safeRequestId(answer._request_id) ?? safeRequestId(answer.id);
    const billed = { model, requestId, inputTokens: inputTokens ?? 0, outputTokens: outputTokens ?? 0 };
    const status = typeof answer.status === 'string' ? answer.status : 'completed';

    if (status === 'failed') {
      const code = safeCode(answer.error?.code);
      if (code && POLICY_CODE.test(code)) throw new ProviderError(this.id, 'the model declined to answer', undefined, false, { kind: 'refusal', ...billed });
      const httpStatus = failedStatus(code);
      throw new ProviderError(this.id, `response failed${code ? ` (${code})` : ''}`, httpStatus, undefined, { code, ...billed });
    }
    if (status === 'incomplete') {
      const reason = safeCode(answer.incomplete_details?.reason);
      if (reason === 'content_filter') throw new ProviderError(this.id, 'the model declined to answer', undefined, false, { kind: 'refusal', ...billed });
      throw new ProviderError(this.id, `answer cut off${reason ? ` (${reason})` : ''}`, undefined, false, { kind: 'invalid_output', ...billed });
    }
    if (status !== 'completed') {
      throw new ProviderError(this.id, `unexpected response status (${safeCode(status) ?? 'unknown'})`, undefined, false, { kind: 'invalid_response', ...billed });
    }

    const parts = answer.output.flatMap((item) => (item?.type === 'message' && Array.isArray(item.content) ? item.content : []));
    if (parts.some((p) => p?.type === 'refusal')) {
      throw new ProviderError(this.id, 'the model declined to answer', undefined, false, { kind: 'refusal', ...billed });
    }
    const text = parts.map((p) => (p?.type === 'output_text' && typeof p.text === 'string' ? p.text : '')).join('');

    const ticks = usage?.cost_in_usd_ticks;
    const costUsd = typeof ticks === 'number' && Number.isFinite(ticks) && ticks >= 0 ? ticks / USD_TICKS_PER_DOLLAR : undefined;

    return {
      providerId: this.id,
      model: reportedModel(answer.model, model),
      text,
      inputTokens: inputTokens ?? 0,
      outputTokens: outputTokens ?? 0,
      usageReported: inputTokens !== undefined && outputTokens !== undefined,
      ...(costUsd === undefined ? {} : { costUsd }),
      ...(requestId === undefined ? {} : { requestId }),
      latencyMs: Date.now() - started,
    };
  }

  /** Lists models: no tokens, no cost. Proves the key and the connection, nothing more. */
  async healthCheck(): Promise<ProviderHealthResult> {
    const r = await getOk(this.id, `${this.baseUrl}/models`, { authorization: `Bearer ${this.#apiKey}` }, 5000, this.fetchImpl);
    return { providerId: this.id, ...r };
  }
}

export class OpenAIProvider extends OpenAICompatibleProvider {
  constructor(opts: { apiKey: string; models: ModelConfig; baseUrl?: string; fetchImpl?: FetchLike }) {
    super({
      id: 'openai',
      apiKey: opts.apiKey,
      baseUrl: opts.baseUrl ?? 'https://api.openai.com/v1',
      models: opts.models,
      fetchImpl: opts.fetchImpl,
      structuredOutput: true,
    });
  }
}

export class XAIProvider extends OpenAICompatibleProvider {
  constructor(opts: { apiKey: string; models: ModelConfig; baseUrl?: string; fetchImpl?: FetchLike }) {
    super({
      id: 'xai',
      apiKey: opts.apiKey,
      baseUrl: opts.baseUrl ?? 'https://api.x.ai/v1',
      models: opts.models,
      fetchImpl: opts.fetchImpl,
    });
  }
}
