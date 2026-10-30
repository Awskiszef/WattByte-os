import type { AIGenerationRequest, AIGenerationResult, AIProvider, ModelConfig, ProviderHealthResult } from '../types.js';
import { getOk, postJson, ProviderError, type FetchLike } from './http.js';
import { assertModels, REASONING_HEADROOM_TOKENS, reportedModel, resolveModel, tokenCount } from './models.js';

interface GenerateContentResponse {
  candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number; thoughtsTokenCount?: number };
  modelVersion?: string;
}

/** `finishReason` values that mean the safety layer, not the model's own end of turn, stopped the answer. */
const BLOCKED_FINISH_REASONS = new Set(['SAFETY', 'RECITATION', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII', 'IMAGE_SAFETY']);

/** Google Gemini generateContent API. The base URL is a constructor option only; no ambient variable is read. */
export class GoogleProvider implements AIProvider {
  readonly id = 'google' as const;
  private readonly baseUrl: string;
  private readonly models: ModelConfig;
  private readonly fetchImpl?: FetchLike;
  /** ES private field: invisible to JSON.stringify, util.inspect and structured loggers. */
  readonly #apiKey: string;

  constructor(opts: { apiKey: string; models: ModelConfig; baseUrl?: string; fetchImpl?: FetchLike }) {
    assertModels('google', opts.models);
    this.#apiKey = opts.apiKey;
    this.models = opts.models;
    this.fetchImpl = opts.fetchImpl;
    this.baseUrl = (opts.baseUrl ?? 'https://generativelanguage.googleapis.com/v1beta').replace(/\/$/, '');
  }

  async generate(request: AIGenerationRequest): Promise<AIGenerationResult> {
    const started = Date.now();
    const model = resolveModel(this.id, this.models, request);
    // ListModels names models `models/<id>`; the endpoint below adds the prefix itself.
    const modelId = model.replace(/^models\//, '');
    const res = await postJson<GenerateContentResponse>({
      providerId: this.id,
      model,
      url: `${this.baseUrl}/models/${encodeURIComponent(modelId)}:generateContent`,
      body: {
        systemInstruction: { parts: [{ text: request.system }] },
        contents: [{ role: 'user', parts: [{ text: request.user }] }],
        generationConfig: {
          responseMimeType: 'application/json',
          // Gemini counts hidden reasoning tokens against this limit; leave room so the JSON is not cut off.
          maxOutputTokens: request.maxOutputTokens + REASONING_HEADROOM_TOKENS,
          temperature: request.mode === 'normal' ? 0.3 : 0.8,
        },
      },
      headers: { 'x-goog-api-key': this.#apiKey },
      timeoutMs: request.timeoutMs,
      signal: request.signal,
      fetchImpl: this.fetchImpl,
    });
    const meta = res.usageMetadata;
    const promptTokens = tokenCount(meta?.promptTokenCount);
    const candidateTokens = tokenCount(meta?.candidatesTokenCount);
    // Reasoning tokens are billed as output.
    const outputTokens = candidateTokens === undefined ? undefined : candidateTokens + (tokenCount(meta?.thoughtsTokenCount) ?? 0);
    const finishReason = res.candidates?.[0]?.finishReason;
    if (res.promptFeedback?.blockReason || (finishReason !== undefined && BLOCKED_FINISH_REASONS.has(finishReason))) {
      throw new ProviderError(this.id, 'the request or the answer was blocked by the safety layer', undefined, false, {
        kind: 'refusal',
        model,
        inputTokens: promptTokens ?? 0,
        outputTokens: outputTokens ?? 0,
      });
    }
    return {
      providerId: this.id,
      model: reportedModel(res.modelVersion, model),
      text: res.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '',
      inputTokens: promptTokens ?? 0,
      outputTokens: outputTokens ?? 0,
      usageReported: promptTokens !== undefined && outputTokens !== undefined,
      latencyMs: Date.now() - started,
    };
  }

  async healthCheck(): Promise<ProviderHealthResult> {
    const r = await getOk(
      this.id,
      `${this.baseUrl}/models?pageSize=1`,
      { 'x-goog-api-key': this.#apiKey },
      5000,
      this.fetchImpl,
    );
    return { providerId: this.id, ...r };
  }
}
