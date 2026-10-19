import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { inspect } from 'node:util';

import { describe, expect, it, vi } from 'vitest';

import { PROVIDER_ENV_VARS, providerEnvProblems, providerFromEnv, providersFromEnv, type ProviderEnv } from '../src/index.js';
import { OUTPUT, fakeFetch, json, request, specs } from './helpers/doubles.js';

describe('providersFromEnv', () => {
  it('a key without any model name is a startup error (no model is hardcoded)', () => {
    expect(() => providersFromEnv({ OPENAI_API_KEY: 'k' })).toThrow(/no model configured/);
    expect(() => providersFromEnv({ ANTHROPIC_API_KEY: 'k' })).toThrow(/no model configured/);
    expect(() => providersFromEnv({ GOOGLE_AI_API_KEY: 'k' })).toThrow(/no model configured/);
    expect(() => providersFromEnv({ XAI_API_KEY: 'k' })).toThrow(/no model configured/);
  });

  it('a key with only blank model names is the same startup error', () => {
    expect(() => providersFromEnv({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: '', OPENAI_QUALITY_MODEL: '  ' })).toThrow(/no model configured/);
  });

  it('builds exactly the providers that have a key, in a stable order', () => {
    const list = providersFromEnv({ XAI_API_KEY: 'b', XAI_QUALITY_MODEL: 'q', OPENAI_API_KEY: 'a', OPENAI_FAST_MODEL: 'm' });
    expect(list.map((p) => p.id)).toEqual(['openai', 'xai']);
    expect(providersFromEnv({}).map((p) => p.id)).toEqual([]);
  });

  it('builds all four when everything is configured', () => {
    const env: ProviderEnv = {
      OPENAI_API_KEY: 'a', OPENAI_FAST_MODEL: 'm1',
      ANTHROPIC_API_KEY: 'b', ANTHROPIC_QUALITY_MODEL: 'm2',
      GOOGLE_AI_API_KEY: 'c', GEMINI_FAST_MODEL: 'm3',
      XAI_API_KEY: 'd', XAI_FAST_MODEL: 'm4',
    };
    expect(providersFromEnv(env).map((p) => p.id)).toEqual(['openai', 'anthropic', 'google', 'xai']);
  });

  it('a blank or whitespace key (KEY= in an .env file) means "not configured", not a broken provider', () => {
    expect(providersFromEnv({ OPENAI_API_KEY: '', OPENAI_FAST_MODEL: 'm', XAI_API_KEY: '   ', XAI_FAST_MODEL: 'm' })).toEqual([]);
  });

  it('trims keys and models before use', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: specs[0]!.success(json) });
    const [p] = providersFromEnv({ OPENAI_API_KEY: '  secret-key  ', OPENAI_FAST_MODEL: ' model-a ' }, { fetchImpl });
    await p!.generate(request);
    expect(calls[0]!.headers.authorization).toBe('Bearer secret-key');
    expect(calls[0]!.body.model).toBe('model-a');
  });

  it('OPENAI_FAST_MODEL= (blank) with only a quality model still serves insight requests', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: specs[0]!.success(json) });
    const [p] = providersFromEnv({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: '', OPENAI_QUALITY_MODEL: 'quality-only' }, { fetchImpl });
    await p!.generate({ ...request, tier: 'fast' });
    expect(calls[0]!.body.model).toBe('quality-only');
  });

  it('maps each provider to its own variables (Gemini models are GEMINI_*, its key GOOGLE_AI_API_KEY)', () => {
    expect(PROVIDER_ENV_VARS.google).toEqual({ apiKey: 'GOOGLE_AI_API_KEY', fastModel: 'GEMINI_FAST_MODEL', qualityModel: 'GEMINI_QUALITY_MODEL' });
    expect(providerFromEnv('google', { GOOGLE_AI_API_KEY: 'k', GEMINI_QUALITY_MODEL: 'm' })?.id).toBe('google');
    expect(() => providerFromEnv('google', { GOOGLE_AI_API_KEY: 'k' })).toThrow(/no model configured/);
    expect(providerFromEnv('google', { GEMINI_FAST_MODEL: 'm' })).toBeUndefined(); // models alone do not enable a provider
  });

  it('every configured provider answers through the gateway request path (smoke of the wiring itself)', async () => {
    for (const spec of specs) {
      const { fetchImpl } = fakeFetch({ body: spec.success(json) });
      const env: ProviderEnv = {
        OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: 'm',
        ANTHROPIC_API_KEY: 'k', ANTHROPIC_FAST_MODEL: 'm',
        GOOGLE_AI_API_KEY: 'k', GEMINI_FAST_MODEL: 'm',
        XAI_API_KEY: 'k', XAI_FAST_MODEL: 'm',
      };
      const provider = providersFromEnv(env, { fetchImpl }).find((p) => p.id === spec.name)!;
      expect((await provider.generate(request)).text).toBe(json);
    }
    expect(OUTPUT.title).toBe('Heavy month');
  });
});

describe('providerEnvProblems (the readable startup check)', () => {
  it('is empty for a valid or an empty configuration', () => {
    expect(providerEnvProblems({})).toEqual([]);
    expect(providerEnvProblems({ OPENAI_API_KEY: 'k', OPENAI_FAST_MODEL: 'm', XAI_API_KEY: 'k', XAI_QUALITY_MODEL: 'm' }, { defaultProvider: 'xai' })).toEqual([]);
  });

  it('names a key that has no model, per provider, without printing any value', () => {
    const problems = providerEnvProblems({ OPENAI_API_KEY: 'sk-SECRET-VALUE', XAI_API_KEY: 'xai-SECRET-VALUE', XAI_FAST_MODEL: '  ', GOOGLE_AI_API_KEY: 'g', GEMINI_QUALITY_MODEL: 'm' });
    expect(problems).toEqual([
      'OPENAI_API_KEY is set but neither OPENAI_FAST_MODEL nor OPENAI_QUALITY_MODEL is (no model name is hardcoded)',
      'XAI_API_KEY is set but neither XAI_FAST_MODEL nor XAI_QUALITY_MODEL is (no model name is hardcoded)',
    ]);
    expect(JSON.stringify(problems)).not.toContain('SECRET-VALUE');
  });

  it('a default provider needs its key (blank counts as missing)', () => {
    expect(providerEnvProblems({}, { defaultProvider: 'openai' })).toEqual(['AI_DEFAULT_PROVIDER=openai but OPENAI_API_KEY is not set']);
    expect(providerEnvProblems({ XAI_API_KEY: '   ', XAI_FAST_MODEL: 'm' }, { defaultProvider: 'xai' })).toEqual(['AI_DEFAULT_PROVIDER=xai but XAI_API_KEY is not set']);
  });

  it('agrees with providersFromEnv about what is a key without a model', () => {
    for (const id of ['openai', 'anthropic', 'google', 'xai'] as const) {
      const env = { [PROVIDER_ENV_VARS[id].apiKey]: 'k' } as ProviderEnv;
      expect(providerEnvProblems(env)).toHaveLength(1);
      expect(() => providersFromEnv(env)).toThrow(/no model configured/);
    }
  });
});

describe('ambient environment never reaches an adapter', () => {
  // Names other tools on a developer machine use; none of them is a WattByte setting.
  const AMBIENT = {
    ANTHROPIC_BASE_URL: 'http://127.0.0.1:9/anthropic',
    ANTHROPIC_API_URL: 'http://127.0.0.1:9/anthropic',
    ANTHROPIC_AUTH_TOKEN: 'ambient-token',
    OPENAI_BASE_URL: 'http://127.0.0.1:9/openai',
    OPENAI_API_BASE: 'http://127.0.0.1:9/openai',
    OPENAI_ORG_ID: 'org-ambient',
    OPENAI_PROJECT_ID: 'proj-ambient',
    OPENAI_ADMIN_KEY: 'sk-admin-ambient',
    OPENAI_CUSTOM_HEADERS: 'x-ambient-header: leaked',
    GOOGLE_API_BASE_URL: 'http://127.0.0.1:9/google',
    GEMINI_BASE_URL: 'http://127.0.0.1:9/google',
    XAI_BASE_URL: 'http://127.0.0.1:9/xai',
    HTTPS_PROXY: 'http://127.0.0.1:9',
    HTTP_PROXY: 'http://127.0.0.1:9',
  };

  const wattbyteEnv: ProviderEnv = {
    OPENAI_API_KEY: 'k-openai', OPENAI_FAST_MODEL: 'm',
    ANTHROPIC_API_KEY: 'k-anthropic', ANTHROPIC_FAST_MODEL: 'm',
    GOOGLE_AI_API_KEY: 'k-google', GEMINI_FAST_MODEL: 'm',
    XAI_API_KEY: 'k-xai', XAI_FAST_MODEL: 'm',
  };
  const defaultHost = { openai: 'https://api.openai.com/', anthropic: 'https://api.anthropic.com/', google: 'https://generativelanguage.googleapis.com/', xai: 'https://api.x.ai/' };

  it('providersFromEnv given an env object full of ambient variables still calls the default hosts, with the WattByte keys', async () => {
    for (const spec of specs) {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      const provider = providersFromEnv({ ...wattbyteEnv, ...AMBIENT } as ProviderEnv, { fetchImpl }).find((p) => p.id === spec.name)!;
      await provider.generate(request);
      expect(calls[0]!.url.startsWith(defaultHost[spec.name]), `${spec.name}: ${calls[0]!.url}`).toBe(true);
      expect(calls[0]!.headers[spec.authHeader[0]]).toBe(spec.authHeader[1]);
      expect(JSON.stringify(calls[0])).not.toMatch(/ambient|127\.0\.0\.1:9/);
    }
  });

  it('adapters built directly ignore process.env as well (ANTHROPIC_BASE_URL & co. set for the duration of the call)', async () => {
    for (const [k, v] of Object.entries(AMBIENT)) vi.stubEnv(k, v);
    try {
      for (const spec of specs) {
        const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
        await spec.make(fetchImpl).generate(request);
        expect(calls[0]!.url, spec.name).toBe(spec.url('fast-model-x'));
      }
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it('no source file reads process.env or mentions a base-URL variable: configuration comes in only as arguments', () => {
    const root = join(import.meta.dirname, '..', 'src');
    const files = (readdirSync(root, { recursive: true }) as string[]).filter((f) => f.endsWith('.ts'));
    expect(files.length).toBeGreaterThan(8);
    for (const f of files) {
      // Comments may name the variables that are deliberately ignored; code may not touch them.
      const code = readFileSync(join(root, f), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/.*$/gm, '$1');
      expect(code, f).not.toMatch(/process\.env|import\.meta\.env|Deno\.env|Bun\.env/);
      expect(code, f).not.toMatch(/_BASE_URL|_API_BASE|_API_URL|HTTPS?_PROXY|ALL_PROXY/);
    }
  });
});

describe('keys stay out of anything that gets serialised', () => {
  it.each(specs)('$name provider: JSON.stringify and util.inspect never show the API key', (spec) => {
    const provider = spec.make(fakeFetch({}).fetchImpl);
    const key = spec.authHeader[1].replace('Bearer ', '');
    expect(JSON.stringify(provider)).not.toContain(key);
    expect(inspect(provider, { depth: 8, showHidden: true })).not.toContain(key);
    expect(String(provider)).not.toContain(key);
  });
});
