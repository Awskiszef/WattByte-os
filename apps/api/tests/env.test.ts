import { describe, expect, it } from 'vitest';

import { envWarnings, loadEnv } from '../src/config/env.js';

const good = { NODE_ENV: 'production', DATABASE_URL: 'postgres://u:p@db:5432/x', DATABASE_SSL: '1', TRUST_PROXY_HOPS: '1', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd' };

describe('production environment guards', () => {
  it('accepts a real secret', () => {
    expect(loadEnv(good).NODE_ENV).toBe('production');
  });
  it('rejects the placeholder secret from .env.example', () => {
    expect(() => loadEnv({ ...good, JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars' })).toThrow(/placeholder/);
  });
  it('rejects the mock AI provider and a missing database', () => {
    expect(() => loadEnv({ ...good, AI_MOCK: '1' })).toThrow(/AI_MOCK/);
    expect(() => loadEnv({ NODE_ENV: 'production', JWT_SECRET: good.JWT_SECRET })).toThrow(/DATABASE_URL/);
    expect(() => loadEnv({ NODE_ENV: 'production', JWT_SECRET: good.JWT_SECRET })).toThrow(/must be set explicitly/);
  });
  it('does not restrict development', () => {
    expect(loadEnv({ NODE_ENV: 'development', JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars', AI_MOCK: '1' }).AI_MOCK).toBe('1');
  });
});

describe('AI configuration', () => {
  const dev = { NODE_ENV: 'development', JWT_SECRET: 'change-me-to-a-long-random-secret-of-at-least-32-chars' };
  const openai = { OPENAI_API_KEY: 'sk-test-key-not-real', OPENAI_FAST_MODEL: 'some-model' };

  it('has the documented defaults: 60 s per request, 20 s per call, 2 retries, fallback on, no default provider, no limits', () => {
    const env = loadEnv(dev);
    expect(env).toMatchObject({
      AI_REQUEST_TIMEOUT_MS: 60_000,
      AI_ATTEMPT_TIMEOUT_MS: 20_000,
      AI_MAX_RETRIES: 2,
      AI_FALLBACK_ENABLED: '1',
      AI_FALLBACK_ON_RATE_LIMIT: '1',
    });
    expect(env.AI_DEFAULT_PROVIDER).toBeUndefined();
    expect(env.AI_MODEL_PRICES).toBeUndefined();
    expect(env.AI_BUDGET_DAILY_USD).toBeUndefined();
    expect(env.AI_BUDGET_MONTHLY_USD).toBeUndefined();
    expect(env.AI_BUDGET_PROVIDER_DAILY_USD).toBeUndefined();
  });

  it('reads and parses every AI variable', () => {
    const env = loadEnv({
      ...dev,
      ...openai,
      XAI_API_KEY: 'xai-test-key-not-real',
      XAI_QUALITY_MODEL: 'grok-model',
      AI_DEFAULT_PROVIDER: 'xai',
      AI_REQUEST_TIMEOUT_MS: '45000',
      AI_ATTEMPT_TIMEOUT_MS: '15000',
      AI_MAX_RETRIES: '0',
      AI_FALLBACK_ENABLED: '0',
      AI_FALLBACK_ON_RATE_LIMIT: '0',
      AI_MODEL_PRICES: '{"some-model":{"input":0.4,"output":1.6}}',
      AI_BUDGET_DAILY_USD: '5',
      AI_BUDGET_MONTHLY_USD: '100.5',
      AI_BUDGET_PROVIDER_DAILY_USD: '{"openai":2,"xai":0}',
    });
    expect(env).toMatchObject({
      AI_DEFAULT_PROVIDER: 'xai',
      AI_REQUEST_TIMEOUT_MS: 45_000,
      AI_ATTEMPT_TIMEOUT_MS: 15_000,
      AI_MAX_RETRIES: 0,
      AI_FALLBACK_ENABLED: '0',
      AI_FALLBACK_ON_RATE_LIMIT: '0',
      AI_MODEL_PRICES: { 'some-model': { input: 0.4, output: 1.6 } },
      AI_BUDGET_DAILY_USD: 5,
      AI_BUDGET_MONTHLY_USD: 100.5,
      AI_BUDGET_PROVIDER_DAILY_USD: { openai: 2, xai: 0 },
    });
  });

  it('blank values (KEY= in an .env file) count as unset', () => {
    const env = loadEnv({ ...dev, AI_DEFAULT_PROVIDER: '', AI_MODEL_PRICES: '', AI_BUDGET_DAILY_USD: '', AI_REQUEST_TIMEOUT_MS: '' });
    expect(env.AI_DEFAULT_PROVIDER).toBeUndefined();
    expect(env.AI_REQUEST_TIMEOUT_MS).toBe(60_000);
  });

  describe('a provider that is required but cannot work is a readable boot error', () => {
    it('AI_DEFAULT_PROVIDER names an unknown provider', () => {
      expect(() => loadEnv({ ...dev, AI_DEFAULT_PROVIDER: 'gpt' })).toThrow(/AI_DEFAULT_PROVIDER/);
    });

    it('AI_DEFAULT_PROVIDER has no key', () => {
      expect(() => loadEnv({ ...dev, AI_DEFAULT_PROVIDER: 'openai' })).toThrow('AI_DEFAULT_PROVIDER=openai but OPENAI_API_KEY is not set');
      expect(() => loadEnv({ ...dev, ...openai, AI_DEFAULT_PROVIDER: 'xai' })).toThrow('AI_DEFAULT_PROVIDER=xai but XAI_API_KEY is not set');
      expect(loadEnv({ ...dev, ...openai, AI_DEFAULT_PROVIDER: 'openai' }).AI_DEFAULT_PROVIDER).toBe('openai');
    });

    it('a key without any model name', () => {
      expect(() => loadEnv({ ...dev, OPENAI_API_KEY: 'sk-test-key-not-real' })).toThrow(/OPENAI_API_KEY is set but neither OPENAI_FAST_MODEL nor OPENAI_QUALITY_MODEL is/);
      expect(() => loadEnv({ ...dev, XAI_API_KEY: 'xai-test-key-not-real' })).toThrow(/XAI_API_KEY is set but neither XAI_FAST_MODEL nor XAI_QUALITY_MODEL is/);
    });

    it('lists every problem at once, and never prints a key', () => {
      let message = '';
      try {
        loadEnv({ ...dev, OPENAI_API_KEY: 'sk-SECRET-VALUE-1', XAI_API_KEY: 'xai-SECRET-VALUE-2', AI_DEFAULT_PROVIDER: 'google', AI_ATTEMPT_TIMEOUT_MS: '30000', AI_REQUEST_TIMEOUT_MS: '20000' });
      } catch (e) {
        message = (e as Error).message;
      }
      expect(message).toContain('OPENAI_API_KEY is set but');
      expect(message).toContain('XAI_API_KEY is set but');
      expect(message).toContain('AI_DEFAULT_PROVIDER=google but GOOGLE_AI_API_KEY is not set');
      expect(message).toContain('AI_ATTEMPT_TIMEOUT_MS must not be larger than AI_REQUEST_TIMEOUT_MS');
      expect(message).not.toContain('SECRET-VALUE');
    });

    it('is not checked when AI is switched off or mocked (then no real provider is built)', () => {
      expect(loadEnv({ ...dev, AI_DEFAULT_PROVIDER: 'openai', FEATURE_AI: '0' }).AI_DEFAULT_PROVIDER).toBe('openai');
      expect(loadEnv({ ...dev, AI_DEFAULT_PROVIDER: 'openai', OPENAI_API_KEY: 'sk-test-key-not-real', AI_MOCK: '1' }).AI_MOCK).toBe('1');
    });
  });

  describe('numbers and switches are validated', () => {
    it.each([
      ['AI_REQUEST_TIMEOUT_MS', '500'],
      ['AI_REQUEST_TIMEOUT_MS', '400000'],
      ['AI_REQUEST_TIMEOUT_MS', 'soon'],
      ['AI_ATTEMPT_TIMEOUT_MS', '0'],
      ['AI_ATTEMPT_TIMEOUT_MS', '999999'],
      ['AI_MAX_RETRIES', '-1'],
      ['AI_MAX_RETRIES', '6'],
      ['AI_MAX_RETRIES', '1.5'],
      ['AI_FALLBACK_ENABLED', 'true'],
      ['AI_FALLBACK_ON_RATE_LIMIT', 'yes'],
      ['AI_BUDGET_DAILY_USD', '-1'],
      ['AI_BUDGET_DAILY_USD', 'lots'],
      ['AI_BUDGET_MONTHLY_USD', 'Infinity'],
    ])('%s=%s is refused, naming the variable', (name, value) => {
      expect(() => loadEnv({ ...dev, [name]: value })).toThrow(new RegExp(name));
    });

    it('a switch is 0 or 1, as everywhere else in this file (a typo cannot silently turn the fallback on or off)', () => {
      expect(() => loadEnv({ ...dev, AI_FALLBACK_ENABLED: 'true' })).toThrow(/AI_FALLBACK_ENABLED/);
    });
  });

  describe('JSON variables', () => {
    it.each([
      ['AI_MODEL_PRICES', 'not json'],
      ['AI_MODEL_PRICES', '[]'],
      ['AI_MODEL_PRICES', '{"m":{"input":-1,"output":1}}'],
      ['AI_MODEL_PRICES', '{"m":{"input":1}}'],
      ['AI_MODEL_PRICES', '{"m":{"input":1,"output":1,"extra":2}}'],
      ['AI_BUDGET_PROVIDER_DAILY_USD', '{"mistral":5}'],
      ['AI_BUDGET_PROVIDER_DAILY_USD', '{"openai":"five"}'],
      ['AI_BUDGET_PROVIDER_DAILY_USD', '{"openai":-1}'],
      ['AI_BUDGET_PROVIDER_DAILY_USD', '5'],
    ])('%s=%s is refused', (name, value) => {
      expect(() => loadEnv({ ...dev, [name]: value })).toThrow(new RegExp(name));
    });

    it('never echoes the value it could not parse', () => {
      expect(() => loadEnv({ ...dev, AI_MODEL_PRICES: '{"SENTINEL-VALUE":' })).toThrow(/AI_MODEL_PRICES must be valid JSON/);
      try {
        loadEnv({ ...dev, AI_MODEL_PRICES: '{"SENTINEL-VALUE":' });
      } catch (e) {
        expect((e as Error).message).not.toContain('SENTINEL-VALUE');
      }
    });
  });

  it('staging and production keep their guards and add nothing for a valid AI setup', () => {
    expect(loadEnv({ ...good, ...openai, AI_DEFAULT_PROVIDER: 'openai', AI_BUDGET_UNLIMITED: '1' }).AI_DEFAULT_PROVIDER).toBe('openai');
    expect(() => loadEnv({ ...good, AI_DEFAULT_PROVIDER: 'openai' })).toThrow(/OPENAI_API_KEY is not set/);
  });

  it('warns when a request may outlast the app\'s own 90 s patience', () => {
    expect(envWarnings(loadEnv({ ...dev, AI_REQUEST_TIMEOUT_MS: '120000' })).join('\n')).toMatch(/AI_REQUEST_TIMEOUT_MS is above 85 s/);
    expect(envWarnings(loadEnv({ ...dev, AI_REQUEST_TIMEOUT_MS: '60000' }))).toEqual([]);
  });
});
