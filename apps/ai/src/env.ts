import { AnthropicProvider } from './providers/anthropic.js';
import { GoogleProvider } from './providers/google.js';
import type { FetchLike } from './providers/http.js';
import { OpenAIProvider, XAIProvider } from './providers/openai-compatible.js';
import type { AIProvider, AIProviderId } from './types.js';
import { AI_PROVIDER_IDS } from './types.js';

export interface ProviderEnv {
  readonly OPENAI_API_KEY?: string;
  readonly OPENAI_FAST_MODEL?: string;
  readonly OPENAI_QUALITY_MODEL?: string;
  readonly ANTHROPIC_API_KEY?: string;
  readonly ANTHROPIC_FAST_MODEL?: string;
  readonly ANTHROPIC_QUALITY_MODEL?: string;
  readonly GOOGLE_AI_API_KEY?: string;
  readonly GEMINI_FAST_MODEL?: string;
  readonly GEMINI_QUALITY_MODEL?: string;
  readonly XAI_API_KEY?: string;
  readonly XAI_FAST_MODEL?: string;
  readonly XAI_QUALITY_MODEL?: string;
}

/**
 * The only environment variables the gateway reads, per provider. Everything
 * else is ignored on purpose: in particular ANTHROPIC_BASE_URL,
 * OPENAI_BASE_URL, OPENAI_API_BASE, HTTP(S)_PROXY and friends, which belong to
 * other tools on the same machine and must never redirect WattByte traffic or
 * carry its keys to another host.
 */
export const PROVIDER_ENV_VARS: Readonly<Record<AIProviderId, { apiKey: keyof ProviderEnv; fastModel: keyof ProviderEnv; qualityModel: keyof ProviderEnv }>> = {
  openai: { apiKey: 'OPENAI_API_KEY', fastModel: 'OPENAI_FAST_MODEL', qualityModel: 'OPENAI_QUALITY_MODEL' },
  anthropic: { apiKey: 'ANTHROPIC_API_KEY', fastModel: 'ANTHROPIC_FAST_MODEL', qualityModel: 'ANTHROPIC_QUALITY_MODEL' },
  google: { apiKey: 'GOOGLE_AI_API_KEY', fastModel: 'GEMINI_FAST_MODEL', qualityModel: 'GEMINI_QUALITY_MODEL' },
  xai: { apiKey: 'XAI_API_KEY', fastModel: 'XAI_FAST_MODEL', qualityModel: 'XAI_QUALITY_MODEL' },
};

/** A set value, trimmed; blank (`KEY=` in an .env file) counts as unset. */
export function envValue(env: ProviderEnv, name: keyof ProviderEnv): string | undefined {
  const v = env[name]?.trim();
  return v ? v : undefined;
}

export interface ProvidersFromEnvOptions {
  /** Test seam: every adapter uses this instead of the global fetch. */
  readonly fetchImpl?: FetchLike;
}

/** Builds one provider, or undefined when its key is missing/blank. Throws when a key has no model. */
export function providerFromEnv(id: AIProviderId, env: ProviderEnv, opts: ProvidersFromEnvOptions = {}): AIProvider | undefined {
  const vars = PROVIDER_ENV_VARS[id];
  const apiKey = envValue(env, vars.apiKey);
  if (!apiKey) return undefined;
  const models = { fast: envValue(env, vars.fastModel), quality: envValue(env, vars.qualityModel) };
  const common = { apiKey, models, fetchImpl: opts.fetchImpl };
  switch (id) {
    case 'openai':
      return new OpenAIProvider(common);
    case 'anthropic':
      return new AnthropicProvider(common);
    case 'google':
      return new GoogleProvider(common);
    case 'xai':
      return new XAIProvider(common);
  }
}

/**
 * Instantiates every provider that has an API key; keys live only on the server.
 * Model names come only from configuration: a key without a model is a startup error.
 * Only the variables listed in PROVIDER_ENV_VARS are read, and only from the object passed in.
 */
export function providersFromEnv(env: ProviderEnv, opts: ProvidersFromEnvOptions = {}): AIProvider[] {
  const out: AIProvider[] = [];
  for (const id of Object.keys(PROVIDER_ENV_VARS) as AIProviderId[]) {
    const provider = providerFromEnv(id, env, opts);
    if (provider) out.push(provider);
  }
  return out;
}

/**
 * What is wrong with the provider configuration, as sentences for an operator (variable names, never
 * values). The API calls this at boot so a misconfiguration is one readable list instead of a stack trace:
 * a key without a model, or a default provider that has no key.
 */
export function providerEnvProblems(env: ProviderEnv, opts: { defaultProvider?: AIProviderId } = {}): string[] {
  const problems: string[] = [];
  for (const id of AI_PROVIDER_IDS) {
    const vars = PROVIDER_ENV_VARS[id];
    const hasKey = envValue(env, vars.apiKey) !== undefined;
    const hasModel = envValue(env, vars.fastModel) !== undefined || envValue(env, vars.qualityModel) !== undefined;
    if (hasKey && !hasModel) problems.push(`${vars.apiKey} is set but neither ${vars.fastModel} nor ${vars.qualityModel} is (no model name is hardcoded)`);
  }
  const preferred = opts.defaultProvider;
  if (preferred && envValue(env, PROVIDER_ENV_VARS[preferred].apiKey) === undefined) {
    problems.push(`AI_DEFAULT_PROVIDER=${preferred} but ${PROVIDER_ENV_VARS[preferred].apiKey} is not set`);
  }
  return problems;
}
