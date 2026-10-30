// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import { NOT_VERIFIED_KEY, NOT_VERIFIED_MODEL, SMOKE_INPUT, runSmoke } from '../scripts/smoke-core.js';
import { AIInputSchema, type ProviderEnv } from '../src/index.js';
import type { AIProviderId } from '../src/types.js';
import { OUTPUT, specs, type Captured, type Reply } from './helpers/doubles.js';

const ROOT = join(import.meta.dirname, '..');

const HOSTS: Record<AIProviderId, string> = { openai: 'api.openai.com', anthropic: 'api.anthropic.com', google: 'generativelanguage.googleapis.com', xai: 'api.x.ai' };
const specOf = (id: AIProviderId) => specs.find((s) => s.name === id)!;

/** One fetch for all providers: answers by host and records every call. */
function multiFetch(replies: Partial<Record<AIProviderId, Reply | ((c: Captured) => Reply)>>) {
  const calls: (Captured & { provider: AIProviderId })[] = [];
  const fetchImpl = ((url: string, init: RequestInit) => {
    const provider = (Object.keys(HOSTS) as AIProviderId[]).find((id) => String(url).includes(HOSTS[id]))!;
    const captured = { provider, url: String(url), headers: (init.headers ?? {}) as Record<string, string>, body: JSON.parse(String(init.body)) as Record<string, unknown> };
    calls.push(captured);
    const r = replies[provider];
    const reply = (typeof r === 'function' ? r(captured) : r) ?? { status: 500 };
    if (reply.networkError !== undefined) return Promise.reject(reply.networkError);
    return Promise.resolve(new Response(reply.raw ?? JSON.stringify(reply.body ?? {}), { status: reply.status ?? 200, headers: { 'content-type': 'application/json' } }));
  }) as unknown as typeof fetch;
  return { fetchImpl, calls };
}

async function run(env: ProviderEnv & Record<string, string>, replies: Parameters<typeof multiFetch>[0] = {}, timeoutMs?: number) {
  const lines: string[] = [];
  const { fetchImpl, calls } = multiFetch(replies);
  const result = await runSmoke({ env, print: (l) => void lines.push(l), fetchImpl, timeoutMs });
  return { ...result, lines, calls };
}

const okBody = (id: AIProviderId, text = JSON.stringify(OUTPUT)) => ({ body: specOf(id).success(text) });

describe('smoke:ai without keys (this environment)', () => {
  it('prints NOT VERIFIED — API KEY MISSING for each of the 4 providers, makes no request, exits 0', async () => {
    const r = await run({});
    expect(r.lines.slice(1, 5)).toEqual([
      'openai: NOT VERIFIED — API KEY MISSING',
      'anthropic: NOT VERIFIED — API KEY MISSING',
      'google: NOT VERIFIED — API KEY MISSING',
      'xai: NOT VERIFIED — API KEY MISSING',
    ]);
    expect(r.lines.at(-1)).toBe('summary: 0 verified, 0 failed, 4 not verified (exit 0)');
    expect(r.exitCode).toBe(0);
    expect(r.calls).toHaveLength(0);
    expect(NOT_VERIFIED_KEY).toBe('NOT VERIFIED — API KEY MISSING');
  });

  it('blank keys (KEY= in an .env file) count as missing', async () => {
    const r = await run({ OPENAI_API_KEY: '', XAI_API_KEY: '   ', OPENAI_FAST_MODEL: 'm' });
    expect(r.results.map((x) => x.status)).toEqual(['not_verified_key', 'not_verified_key', 'not_verified_key', 'not_verified_key']);
    expect(r.exitCode).toBe(0);
  });

  it('a key without a model is NOT VERIFIED — MODEL MISSING (exit 0, no request)', async () => {
    const r = await run({ OPENAI_API_KEY: 'k1', ANTHROPIC_API_KEY: 'k2', GOOGLE_AI_API_KEY: 'k3', XAI_API_KEY: 'k4', GEMINI_FAST_MODEL: '', XAI_QUALITY_MODEL: ' ' });
    expect(r.lines.slice(1, 5)).toEqual(['openai', 'anthropic', 'google', 'xai'].map((id) => `${id}: NOT VERIFIED — MODEL MISSING`));
    expect(r.exitCode).toBe(0);
    expect(r.calls).toHaveLength(0);
    expect(NOT_VERIFIED_MODEL).toBe('NOT VERIFIED — MODEL MISSING');
  });

  it('a model without a key is a missing key (models alone verify nothing)', async () => {
    const r = await run({ OPENAI_FAST_MODEL: 'm', GEMINI_FAST_MODEL: 'm' });
    expect(r.results.every((x) => x.status === 'not_verified_key')).toBe(true);
  });
});

describe('smoke:ai with configured providers (HTTP doubles standing in for the real APIs)', () => {
  const allConfigured: ProviderEnv & Record<string, string> = {
    OPENAI_API_KEY: 'sk-openai-LEAKCHECK-1', OPENAI_FAST_MODEL: 'openai-fast',
    ANTHROPIC_API_KEY: 'sk-anthropic-LEAKCHECK-2', ANTHROPIC_FAST_MODEL: 'anthropic-fast',
    GOOGLE_AI_API_KEY: 'sk-google-LEAKCHECK-3', GEMINI_FAST_MODEL: 'gemini-fast',
    XAI_API_KEY: 'sk-xai-LEAKCHECK-4', XAI_FAST_MODEL: 'xai-fast',
  };
  const allOk = { openai: okBody('openai'), anthropic: okBody('anthropic'), google: okBody('google'), xai: okBody('xai') };

  it('performs exactly ONE request per configured provider and prints provider, model, latency, tokens and cost', async () => {
    const r = await run(allConfigured, allOk);
    expect(r.calls.map((c) => c.provider)).toEqual(['openai', 'anthropic', 'google', 'xai']);
    expect(r.exitCode).toBe(0);
    expect(r.results.map((x) => x.status)).toEqual(['verified', 'verified', 'verified', 'verified']);
    const line = r.lines.find((l) => l.startsWith('openai:'))!;
    expect(line).toMatch(/^openai: OK model=\S+ latency_ms=\d+ input_tokens=11 output_tokens=7 est_cost_usd=0\.000016 \(provider_estimate\)$/);
    expect(r.lines.find((l) => l.startsWith('google:'))).toMatch(/^google: OK model=fast-model-x-001 latency_ms=\d+ input_tokens=11 output_tokens=7 est_cost_usd=/);
    expect(r.lines.at(-1)).toBe('summary: 4 verified, 0 failed, 0 not verified (exit 0)');
  });

  it('uses the fast model (the insight tier) and its provider-specific variable', async () => {
    const r = await run(allConfigured, allOk);
    expect(r.calls.find((c) => c.provider === 'openai')!.body.model).toBe('openai-fast');
    expect(r.calls.find((c) => c.provider === 'anthropic')!.body.model).toBe('anthropic-fast');
    expect(r.calls.find((c) => c.provider === 'google')!.url).toContain('/models/gemini-fast:generateContent');
    expect(r.calls.find((c) => c.provider === 'xai')!.body.model).toBe('xai-fast');
  });

  it('falls back to the quality model when no fast model is configured', async () => {
    const r = await run({ XAI_API_KEY: 'k-xai', XAI_QUALITY_MODEL: 'xai-quality' }, { xai: okBody('xai') });
    expect(r.calls[0]!.body.model).toBe('xai-quality');
    expect(r.results.find((x) => x.provider === 'xai')!.status).toBe('verified');
  });

  it('sends only the fixed synthetic prompt: no environment value, no key, no personal data', async () => {
    const r = await run(allConfigured, allOk);
    expect(() => AIInputSchema.parse(SMOKE_INPUT)).not.toThrow();
    for (const call of r.calls) {
      const wire = JSON.stringify(call.body);
      expect(wire).toContain('You are WattByte');
      expect(wire).toContain('138.75 GB'); // the fixed synthetic aggregate
      for (const [name, value] of Object.entries(allConfigured)) if (name.endsWith('_API_KEY')) expect(wire).not.toContain(value);
      expect(wire).not.toMatch(/@|\/Users\/|api[_-]?key/i);
    }
  });

  it('is not affected by ambient base-URL variables of other tools', async () => {
    const r = await run({ ...allConfigured, ANTHROPIC_BASE_URL: 'http://127.0.0.1:9/evil', OPENAI_BASE_URL: 'http://127.0.0.1:9/evil', HTTPS_PROXY: 'http://127.0.0.1:9' }, allOk);
    expect(r.calls.map((c) => new URL(c.url).hostname)).toEqual(Object.values(HOSTS));
  });

  it('a configured provider that fails makes the run fail (exit 1) while the others are still tried', async () => {
    const r = await run(allConfigured, { ...allOk, anthropic: { status: 401, body: { error: { type: 'authentication_error', message: 'invalid x-api-key sk-anthropic-LEAKCHECK-2' } } } });
    expect(r.exitCode).toBe(1);
    expect(r.lines.find((l) => l.startsWith('anthropic:'))).toBe('anthropic: FAILED — anthropic: HTTP 401 (authentication_error)');
    expect(r.results.map((x) => x.status)).toEqual(['verified', 'failed', 'verified', 'verified']);
    expect(r.lines.at(-1)).toBe('summary: 3 verified, 1 failed, 0 not verified (exit 1)');
  });

  it('mixed run: unconfigured providers do not fail the run, configured ones are verified', async () => {
    const r = await run({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: 'm', GOOGLE_AI_API_KEY: 'k' }, { openai: okBody('openai') });
    expect(r.results.map((x) => x.status)).toEqual(['verified', 'not_verified_key', 'not_verified_model', 'not_verified_key']);
    expect(r.exitCode).toBe(0);
    expect(r.lines.at(-1)).toBe('summary: 1 verified, 0 failed, 3 not verified (exit 0)');
  });

  it.each([
    ['prose instead of JSON', 'Sure! Here is an insight.', /invalid_output \(no JSON object in output\)/],
    ['a schema violation', JSON.stringify({ ...OUTPUT, severity: 'catastrophe' }), /invalid_output \(schema \(severity: invalid_enum_value\)\)/],
    ['a missing field', JSON.stringify({ title: 'x', message: 'y', severity: 'info' }), /invalid_output \(schema \(emoji: invalid_type\)\)/],
    ['empty output', '', /empty_output \(empty output\)/],
  ])('structured output validation: %s fails the provider without printing the model text', async (_n, text, expected) => {
    const r = await run({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: 'm' }, { openai: okBody('openai', text) });
    expect(r.exitCode).toBe(1);
    const line = r.lines.find((l) => l.startsWith('openai:'))!;
    expect(line).toMatch(/^openai: FAILED — /);
    expect(line).toMatch(expected);
    expect(line).not.toContain('Sure!');
  });

  it('valid output but no token usage in the response is a failure (the adapter mapping would be wrong)', async () => {
    const r = await run({ ANTHROPIC_API_KEY: 'k', ANTHROPIC_FAST_MODEL: 'm' }, { anthropic: { body: specOf('anthropic').success(JSON.stringify(OUTPUT), null) } });
    expect(r.exitCode).toBe(1);
    expect(r.lines.find((l) => l.startsWith('anthropic:'))).toMatch(/FAILED — .*no token usage/);
  });

  it('a refusal, a timeout and a network error are failures with a classified, content-free reason', async () => {
    const refusal = await run({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: 'm' }, { openai: { body: specOf('openai').refusals[0] } });
    expect(refusal.lines.find((l) => l.startsWith('openai:'))).toBe('openai: FAILED — openai: the model declined to answer');
    const network = await run({ XAI_API_KEY: 'k', XAI_FAST_MODEL: 'm' }, { xai: { networkError: new TypeError('fetch failed') } });
    expect(network.lines.find((l) => l.startsWith('xai:'))).toBe('xai: FAILED — xai: network error (TypeError)');
    expect(network.exitCode).toBe(1);
  });

  it('a provider that never answers fails after the smoke timeout instead of hanging the run', async () => {
    const started = Date.now();
    const lines: string[] = [];
    const hang = (() => new Promise(() => undefined)) as unknown as typeof fetch;
    const r = await runSmoke({ env: { GOOGLE_AI_API_KEY: 'k', GEMINI_FAST_MODEL: 'm' }, print: (l) => void lines.push(l), fetchImpl: hang, timeoutMs: 100 });
    expect(Date.now() - started).toBeLessThan(4000);
    expect(r.exitCode).toBe(1);
    expect(lines.find((l) => l.startsWith('google:'))).toBe('google: FAILED — google: timeout after 100 ms');
  });

  it('never prints a key, even when the failure text would contain it', async () => {
    const leaky = { networkError: Object.assign(new Error('connect failed to https://api.x.ai/?key=sk-xai-LEAKCHECK-4'), { code: 'ECONNREFUSED' }) };
    const r = await run(allConfigured, { ...allOk, xai: leaky, openai: { status: 401, raw: 'bad key sk-openai-LEAKCHECK-1' } });
    const output = r.lines.join('\n');
    expect(output).not.toMatch(/LEAKCHECK/);
    expect(output).not.toMatch(/Bearer|x-api-key|x-goog-api-key|authorization/i);
  });
});

describe('smoke:ai is not part of the unit test run', () => {
  const pkg = JSON.parse(readFileSync(join(ROOT, 'package.json'), 'utf8')) as { scripts: Record<string, string> };

  it('`test` is plain vitest and `smoke:ai` is a separate script that does not go through vitest', () => {
    expect(pkg.scripts.test).toBe('vitest run');
    expect(pkg.scripts['smoke:ai']).toMatch(/node( --env-file-if-exists=\S+)? dist-smoke\/scripts\/smoke\.js/);
    expect(pkg.scripts['smoke:ai']).not.toContain('vitest');
    expect(pkg.scripts.test).not.toContain('smoke');
  });

  it('vitest only collects tests/**/*.test.ts; no real-API *.smoke.ts file lives under tests/', () => {
    const config = readFileSync(join(ROOT, 'vitest.config.ts'), 'utf8');
    expect(config).toContain("include: ['tests/**/*.test.ts']");
    const files = readdirSync(join(ROOT, 'tests'), { recursive: true }) as string[];
    expect(files.filter((f) => /\.smoke\.[cm]?[jt]s$/.test(f))).toEqual([]);
  });

  it('the CLI entry sits in scripts/, never in tests/', () => {
    expect(readdirSync(join(ROOT, 'scripts')).sort()).toEqual(['smoke-core.ts', 'smoke.ts']);
  });
});
