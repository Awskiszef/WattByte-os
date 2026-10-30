// Provider call hardening from the audit appendix: a provider's redirect is not followed with the API key attached, a
// provider's answer is read only up to a cap, a `models/<id>` name from ListModels does not break the Google URL, and a
// budget limit that is NaN (which would silently switch the cap off) is refused.
import { describe, expect, it } from 'vitest';

import { createBudgetGuard, GoogleProvider, ProviderError } from '../src/index.js';
import { MAX_ERROR_BODY_BYTES, MAX_SUCCESS_BODY_BYTES, postJson } from '../src/providers/http.js';
import { fakeFetch, json, request, specs } from './helpers/doubles.js';

const post = (fetchImpl: typeof fetch) =>
  postJson<{ ok: boolean }>({ providerId: 'google', model: 'm', url: 'https://example.test/x', body: {}, headers: { 'x-api-key': 'k' }, timeoutMs: 1000, fetchImpl });

describe('postJson', () => {
  it('asks fetch not to follow redirects (the key header would travel with them)', async () => {
    let init: RequestInit | undefined;
    const fetchImpl = ((_url: string, i: RequestInit) => {
      init = i;
      return Promise.resolve(new Response('{"ok":true}', { status: 200 }));
    }) as unknown as typeof fetch;
    await post(fetchImpl);
    expect(init?.redirect).toBe('error');
  });

  it('a redirect answered by a runtime that refuses it is a network failure, not an answer', async () => {
    const fetchImpl = (() => Promise.reject(new TypeError('fetch failed', { cause: { code: 'UND_ERR_REDIRECT' } }))) as unknown as typeof fetch;
    const err = await post(fetchImpl).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ProviderError);
    expect((err as ProviderError).kind).toBe('network');
  });

  it('reads a success body up to the cap and refuses a larger one without buffering it', async () => {
    const ok = JSON.stringify({ ok: true, pad: 'x'.repeat(1000) });
    expect(await post((() => Promise.resolve(new Response(ok))) as unknown as typeof fetch)).toMatchObject({ ok: true });
    const huge = `{"ok":true,"pad":"${'x'.repeat(MAX_SUCCESS_BODY_BYTES)}"}`;
    const err = await post((() => Promise.resolve(new Response(huge))) as unknown as typeof fetch).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ProviderError);
    expect((err as ProviderError).kind).toBe('invalid_response');
  });

  it('refuses a body whose declared length is over the cap before reading it', async () => {
    let touched = false;
    const res = {
      ok: true,
      status: 200,
      headers: new Headers({ 'content-length': String(MAX_SUCCESS_BODY_BYTES + 1) }),
      get body() {
        touched = true;
        return null;
      },
      text: () => {
        touched = true;
        return Promise.resolve('{}');
      },
      json: () => {
        touched = true;
        return Promise.resolve({});
      },
    };
    const err = await post((() => Promise.resolve(res)) as unknown as typeof fetch).catch((e: unknown) => e);
    expect((err as ProviderError).kind).toBe('invalid_response');
    expect(touched).toBe(false);
  });

  it('an error body is read only for its machine code and only up to its small cap', async () => {
    const small = new Response(JSON.stringify({ error: { code: 'rate_limit_exceeded' } }), { status: 429 });
    const e1 = (await post((() => Promise.resolve(small)) as unknown as typeof fetch).catch((e: unknown) => e)) as ProviderError;
    expect(e1.status).toBe(429);
    expect(e1.message).toContain('rate_limit_exceeded');
    const big = new Response('x'.repeat(MAX_ERROR_BODY_BYTES * 4), { status: 500 });
    const e2 = (await post((() => Promise.resolve(big)) as unknown as typeof fetch).catch((e: unknown) => e)) as ProviderError;
    expect(e2.status).toBe(500);
    expect(e2.message).toBe('google: HTTP 500');
  });
});

describe('Google model names', () => {
  const google = specs.find((s) => s.name === 'google')!;
  it('a `models/<id>` name (as ListModels spells it) does not double the prefix in the URL', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: google.success(json) });
    await new GoogleProvider({ apiKey: 'k', baseUrl: 'https://g.test/v1', fetchImpl, models: { fast: 'models/gemini-x', quality: 'models/gemini-x' } }).generate(request);
    expect(calls[0]!.url).toBe('https://g.test/v1/models/gemini-x:generateContent');
  });
});

describe('budget limits', () => {
  const reader = { spentUsd: () => Promise.resolve(0) };
  it('refuses NaN, negative and infinite limits, accepts zero and ordinary values', () => {
    for (const bad of [Number.NaN, -1, Number.POSITIVE_INFINITY]) {
      expect(() => createBudgetGuard({ dailyUsd: bad }, reader), String(bad)).toThrow(RangeError);
      expect(() => createBudgetGuard({ monthlyUsd: bad }, reader)).toThrow(RangeError);
      expect(() => createBudgetGuard({ providerDailyUsd: { openai: bad } }, reader)).toThrow(RangeError);
    }
    expect(createBudgetGuard({ dailyUsd: 0 }, reader)).toBeDefined();
    expect(createBudgetGuard({ dailyUsd: 5, monthlyUsd: 50, providerDailyUsd: { xai: 1 } }, reader)).toBeDefined();
    expect(createBudgetGuard({}, reader)).toBeUndefined();
  });
});
