import { envValue, PROVIDER_ENV_VARS, providerFromEnv, type ProviderEnv } from '../src/env.js';
import type { FetchLike } from '../src/providers/http.js';
import { buildPrompt } from '../src/prompts/index.js';
import { OutputRejectedError, parseAIOutput, type AIInput } from '../src/schemas.js';
import { AI_PROVIDER_IDS, TASK_TIER, type AIGenerationRequest, type AIProviderId } from '../src/types.js';
import { estimateCost } from '../src/usage.js';

/**
 * Real-provider smoke test: ONE minimal request per provider that is fully
 * configured (API key and a model name). A provider without a key or model is
 * reported as NOT VERIFIED and is not an error; only a configured provider
 * that fails makes the run fail. The prompt is fixed and synthetic: no user
 * data of any kind is sent.
 */

export const NOT_VERIFIED_KEY = 'NOT VERIFIED — API KEY MISSING';
export const NOT_VERIFIED_MODEL = 'NOT VERIFIED — MODEL MISSING';

/** Synthetic aggregates; nothing here describes a real person or device. */
export const SMOKE_INPUT: AIInput = {
  period: '2026-10',
  periodType: 'month',
  mobileDataGb: 18.5,
  wifiDataGb: 120.25,
  totalDataGb: 138.75,
  chargingSessions: 30,
  batteryEnergyKwh: 0.4,
  wallEnergyKwh: 0.47,
  electricityCost: 0.54,
  currency: 'PLN',
};

export type SmokeStatus = 'verified' | 'not_verified_key' | 'not_verified_model' | 'failed';

export interface SmokeResult {
  readonly provider: AIProviderId;
  readonly status: SmokeStatus;
  readonly line: string;
}

export interface SmokeOptions {
  readonly env: ProviderEnv;
  readonly print: (line: string) => void;
  /** Test seam; the real run uses the global fetch against the real provider hosts. */
  readonly fetchImpl?: FetchLike;
  readonly timeoutMs?: number;
}

export interface SmokeRun {
  readonly results: readonly SmokeResult[];
  /** 0 unless a configured provider failed. */
  readonly exitCode: 0 | 1;
}

/** Strips every configured secret from text that is about to be printed. */
function redact(text: string, secrets: readonly string[]): string {
  return secrets.filter((s) => s.length >= 4).reduce((t, s) => t.split(s).join('***'), text);
}

async function smokeOne(id: AIProviderId, opts: SmokeOptions): Promise<SmokeResult> {
  const vars = PROVIDER_ENV_VARS[id];
  const apiKey = envValue(opts.env, vars.apiKey);
  if (!apiKey) return { provider: id, status: 'not_verified_key', line: `${id}: ${NOT_VERIFIED_KEY}` };
  if (!envValue(opts.env, vars.fastModel) && !envValue(opts.env, vars.qualityModel)) {
    return { provider: id, status: 'not_verified_model', line: `${id}: ${NOT_VERIFIED_MODEL}` };
  }

  const prompt = buildPrompt('insight', 'normal', 'en', SMOKE_INPUT);
  const request: AIGenerationRequest = {
    task: 'insight',
    tier: TASK_TIER.insight,
    mode: 'normal',
    locale: 'en',
    system: prompt.system,
    user: prompt.user,
    maxOutputTokens: 220,
    timeoutMs: opts.timeoutMs ?? 30_000,
  };
  const failed = (reason: string): SmokeResult => ({
    provider: id,
    status: 'failed',
    line: `${id}: FAILED — ${redact(reason, [apiKey])}`,
  });

  try {
    const provider = providerFromEnv(id, opts.env, { fetchImpl: opts.fetchImpl });
    if (!provider) return failed('provider could not be created'); // unreachable: key and model were checked above
    const started = performance.now();
    const result = await provider.generate(request);
    const latencyMs = Math.round(performance.now() - started);
    parseAIOutput(result.text, 'normal');
    if (result.usageReported === false) return failed('structured output is valid but the response carried no token usage (adapter or provider mismatch)');
    const cost = estimateCost({
      providerId: id,
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      usageReported: result.usageReported,
      reportedCostUsd: result.costUsd,
    });
    const usd = cost.basis === 'unknown' ? 'unknown' : `${cost.usd.toFixed(6)} (${cost.basis})`;
    return {
      provider: id,
      status: 'verified',
      line: `${id}: OK model=${result.model} latency_ms=${latencyMs} input_tokens=${result.inputTokens} output_tokens=${result.outputTokens} est_cost_usd=${usd}`,
    };
  } catch (e) {
    if (e instanceof OutputRejectedError) return failed(`${e.kind} (${e.reason})`);
    // ProviderError messages are already content-free; anything else is reduced to its class name.
    const message = e instanceof Error && e.name === 'ProviderError' ? e.message : `unexpected ${e instanceof Error ? e.name : 'error'}`;
    return failed(message);
  }
}

export async function runSmoke(opts: SmokeOptions): Promise<SmokeRun> {
  opts.print('smoke:ai: one minimal request per configured provider (fixed synthetic prompt, no user data)');
  const results: SmokeResult[] = [];
  for (const id of AI_PROVIDER_IDS) {
    const result = await smokeOne(id, opts);
    opts.print(result.line);
    results.push(result);
  }
  const count = (s: SmokeStatus): number => results.filter((r) => r.status === s).length;
  const notVerified = count('not_verified_key') + count('not_verified_model');
  const exitCode = count('failed') > 0 ? 1 : 0;
  opts.print(`summary: ${count('verified')} verified, ${count('failed')} failed, ${notVerified} not verified (exit ${exitCode})`);
  return { results, exitCode };
}
