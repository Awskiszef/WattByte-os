import { afterEach, describe, expect, it, vi } from 'vitest';

import { ProviderError, type ProviderErrorKind } from '../src/index.js';
import { fakeFetch, json, request, specs, type Spec } from './helpers/doubles.js';
import { startServer, waitFor, type LoopbackServer } from './helpers/server.js';

afterEach(() => {
  vi.useRealTimers();
});

async function failure(spec: Spec, reply: Parameters<typeof fakeFetch>[0], req = request): Promise<ProviderError> {
  const { fetchImpl } = fakeFetch(reply);
  const err = await spec.make(fetchImpl).generate(req).catch((e: unknown) => e);
  expect(err, 'expected the adapter to throw').toBeInstanceOf(ProviderError);
  return err as ProviderError;
}

describe.each(specs)('$name adapter (HTTP double, no network)', (spec) => {
  describe('request mapping', () => {
    it('sends URL, auth header and payload for the configured fast model', async () => {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      await spec.make(fetchImpl).generate(request);
      expect(calls).toHaveLength(1);
      expect(calls[0]!.url).toBe(spec.url('fast-model-x'));
      expect(calls[0]!.headers[spec.authHeader[0]]).toBe(spec.authHeader[1]);
      expect(calls[0]!.headers['content-type']).toBe('application/json');
      spec.checkPayload(calls[0]!.body, 'fast-model-x');
    });

    it('uses the quality model for summary tasks', async () => {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      await spec.make(fetchImpl).generate({ ...request, task: 'monthly_summary', tier: 'quality' });
      expect(calls[0]!.url + JSON.stringify(calls[0]!.body)).toContain('quality-model-x');
    });
  });

  describe('tier selection (models come only from configuration)', () => {
    const modelSeen = async (cfg: { fast?: string; quality?: string }, tier: 'fast' | 'quality') => {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      await spec.make(fetchImpl, { models: cfg }).generate({ ...request, tier });
      return calls[0]!.url + JSON.stringify(calls[0]!.body);
    };

    it('fast tier -> fast model, quality tier -> quality model when both are set', async () => {
      expect(await modelSeen({ fast: 'only-fast', quality: 'only-quality' }, 'fast')).toContain('only-fast');
      expect(await modelSeen({ fast: 'only-fast', quality: 'only-quality' }, 'quality')).toContain('only-quality');
    });

    it('falls back to the other tier when one model variable is missing', async () => {
      expect(await modelSeen({ fast: 'only-fast' }, 'quality')).toContain('only-fast');
      expect(await modelSeen({ quality: 'only-quality' }, 'fast')).toContain('only-quality');
    });

    it('treats a blank model (KEY= in an .env file) as unset instead of sending an empty model', async () => {
      expect(await modelSeen({ fast: '', quality: 'only-quality' }, 'fast')).toContain('only-quality');
      expect(await modelSeen({ fast: '  ', quality: 'only-quality' }, 'fast')).toContain('only-quality');
    });

    it('refuses to be built without any model', () => {
      expect(() => spec.make(fakeFetch({}).fetchImpl, { models: {} })).toThrow(/no model configured/);
      expect(() => spec.make(fakeFetch({}).fetchImpl, { models: { fast: '', quality: ' ' } })).toThrow(/no model configured/);
    });
  });

  describe('token usage extraction', () => {
    it(`reads ${spec.usageFields}`, async () => {
      const { fetchImpl } = fakeFetch({ body: spec.success(json) });
      const r = await spec.make(fetchImpl).generate(request);
      expect(r.text).toBe(json);
      expect(r).toMatchObject({ providerId: spec.name, inputTokens: spec.tokens.input, outputTokens: spec.tokens.output, usageReported: true });
    });

    it('flags missing usage instead of pretending it was 0', async () => {
      const { fetchImpl } = fakeFetch({ body: spec.success(json, null) });
      const r = await spec.make(fetchImpl).generate(request);
      expect(r.text).toBe(json);
      expect(r).toMatchObject({ inputTokens: 0, outputTokens: 0, usageReported: false });
    });

    it('flags usage with only one of the two counts', async () => {
      const { fetchImpl } = fakeFetch({ body: spec.success(json, { input: 11 }) });
      const r = await spec.make(fetchImpl).generate(request);
      expect(r).toMatchObject({ inputTokens: 11, outputTokens: 0, usageReported: false });
    });

    it.each([
      ['negative', -5],
      ['a string', 'many'],
      ['null', null],
    ])('treats a count that is %s as not reported (never NaN or negative)', async (_label, bad) => {
      const { fetchImpl } = fakeFetch({ body: spec.success(json, { input: bad, output: 7 }) });
      const r = await spec.make(fetchImpl).generate(request);
      expect(r.usageReported).toBe(false);
      expect(r.inputTokens).toBe(0);
      expect(Number.isNaN(r.inputTokens)).toBe(false);
    });

    it('floors fractional counts so they fit integer columns', async () => {
      const { fetchImpl } = fakeFetch({ body: spec.success(json, { input: 11.9, output: 7.2 }) });
      const r = await spec.make(fetchImpl).generate(request);
      expect(r).toMatchObject({ inputTokens: 11, outputTokens: 7, usageReported: true });
    });

    it('returns empty text as empty text; the gateway decides what that means', async () => {
      const { fetchImpl } = fakeFetch({ body: spec.success('') });
      expect((await spec.make(fetchImpl).generate(request)).text).toBe('');
    });
  });

  describe('HTTP status handling', () => {
    it.each([
      [400, false],
      [401, false],
      [403, false],
      [404, false],
      [422, false],
      [408, true],
      [429, true],
      [500, true],
      [502, true],
      [503, true],
      [529, true],
    ])('HTTP %i -> ProviderError{kind:http, retryable:%s}', async (status, retryable) => {
      const err = await failure(spec, { status, body: { error: { message: 'nope' } } });
      expect(err).toMatchObject({ kind: 'http', status, retryable, providerId: spec.name });
      expect(err.message).toContain(`HTTP ${status}`);
    });

    it('keeps only a short machine code from the error body, never its text', async () => {
      const err = await failure(spec, {
        status: 400,
        body: { error: { type: 'invalid_request_error', message: 'SENTINEL-ECHO your prompt was: USER PROMPT 187.4 GB', param: 'messages' } },
      });
      expect(err.message).toBe(`${spec.name}: HTTP 400 (invalid_request_error)`);
      expect(err.message).not.toContain('SENTINEL-ECHO');
      expect(err.message).not.toContain('USER PROMPT');
    });

    it('ignores free text in a code field (xAI puts sentences there) and non-JSON bodies', async () => {
      const sentence = await failure(spec, { status: 400, body: { code: 'Client specified an invalid argument', error: 'SENTINEL-ECHO' } });
      expect(sentence.message).toBe(`${spec.name}: HTTP 400`);
      const html = await failure(spec, { status: 502, raw: '<html>SENTINEL-ECHO bad gateway</html>' });
      expect(html.message).toBe(`${spec.name}: HTTP 502`);
    });

    it.each([
      ['a number of seconds', { 'retry-after': '7' }, 7000],
      ['fractional seconds', { 'retry-after': '1.5' }, 1500],
      ['OpenAI retry-after-ms', { 'retry-after-ms': '250' }, 250],
      ['garbage', { 'retry-after': 'soon' }, undefined],
      ['zero', { 'retry-after': '0' }, undefined],
      ['a date in the past', { 'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT' }, undefined],
      ['an absurd value (capped at 24 h)', { 'retry-after': '999999999' }, 86_400_000],
    ])('429 with Retry-After as %s', async (_label, headers, expected) => {
      const err = await failure(spec, { status: 429, body: {}, headers });
      expect(err.retryAfterMs).toBe(expected);
      expect(err.retryable).toBe(true);
    });

    it('understands an HTTP-date Retry-After', async () => {
      const date = new Date(Date.now() + 30_000).toUTCString();
      const err = await failure(spec, { status: 503, body: {}, headers: { 'retry-after': date } });
      expect(err.retryAfterMs).toBeGreaterThan(25_000);
      expect(err.retryAfterMs).toBeLessThanOrEqual(30_000);
    });

    it('a 2xx body that is not JSON is invalid_response (not retryable)', async () => {
      const err = await failure(spec, { raw: '<html>bad gateway</html>' });
      expect(err).toMatchObject({ kind: 'invalid_response', retryable: false });
      expect(err.message).not.toContain('<html>');
    });
  });

  describe('timeout', () => {
    it.each([
      ['a fetch that honours the abort signal', { hang: true }],
      ['a fetch that ignores the abort signal', { hangIgnoringSignal: true }],
    ])('aborts within the configured timeout with %s, classified as timeout, leaving no timer behind', async (_label, reply) => {
      vi.useFakeTimers();
      const { fetchImpl } = fakeFetch(reply);
      let settled = false;
      const pending = spec.make(fetchImpl).generate({ ...request, timeoutMs: 5000 }).catch((e: unknown) => e).finally(() => (settled = true));

      await vi.advanceTimersByTimeAsync(4999);
      expect(settled, 'must not give up before the timeout').toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      const err = (await pending) as ProviderError;

      expect(err).toBeInstanceOf(ProviderError);
      expect(err).toMatchObject({ kind: 'timeout', retryable: true, providerId: spec.name, model: 'fast-model-x' });
      expect(err.status).toBeUndefined();
      expect(err.message).toContain('timeout after 5000 ms');
      expect(vi.getTimerCount()).toBe(0);
    });

    it('clears its timer after a success and after an HTTP error', async () => {
      vi.useFakeTimers();
      await spec.make(fakeFetch({ body: spec.success(json) }).fetchImpl).generate({ ...request, timeoutMs: 5000 });
      expect(vi.getTimerCount()).toBe(0);
      await failure(spec, { status: 500, body: {} }, { ...request, timeoutMs: 5000 });
      expect(vi.getTimerCount()).toBe(0);
    });

    it('healthCheck also times out instead of hanging', async () => {
      vi.useFakeTimers();
      const { fetchImpl } = fakeFetch({ hangIgnoringSignal: true });
      const pending = spec.make(fetchImpl).healthCheck();
      await vi.advanceTimersByTimeAsync(5000);
      expect(await pending).toMatchObject({ providerId: spec.name, ok: false, error: 'timeout after 5000 ms' });
      expect(vi.getTimerCount()).toBe(0);
    });
  });

  describe('network failures', () => {
    it('classifies a connection error as network and does not echo its message', async () => {
      const cause = Object.assign(new Error('connect ECONNREFUSED https://secret-host.example/?key=k-leak'), { code: 'ECONNREFUSED' });
      const err = await failure(spec, { networkError: Object.assign(new TypeError('fetch failed https://secret-host.example/?key=k-leak'), { cause }) });
      expect(err).toMatchObject({ kind: 'network', retryable: true, status: undefined });
      expect(err.message).toBe(`${spec.name}: network error (TypeError ECONNREFUSED)`);
    });

    it('does not trust the shape of a thrown value', async () => {
      const err = await failure(spec, { networkError: 'plain string with k-leak' });
      expect(err.kind).toBe('network');
      expect(err.message).not.toContain('k-leak');
    });
  });

  describe('refusals', () => {
    it.each(spec.refusals.map((body, i) => [i, body] as const))('refusal variant %i is a non-retryable refusal that keeps the billed tokens', async (_i, body) => {
      const err = await failure(spec, { body });
      expect(err).toMatchObject({ kind: 'refusal', retryable: false, providerId: spec.name });
      expect(err.inputTokens).toBe(20);
      expect(err.message).not.toMatch(/can't help|Declined/);
    });
  });

  describe('secrets', () => {
    it.each([400, 401, 429, 500])('the API key never appears in the error for HTTP %i', async (status) => {
      const err = await failure(spec, { status, raw: `bad key ${spec.authHeader[1]}` });
      expect(err.message).not.toContain(spec.authHeader[1].replace('Bearer ', ''));
      expect(JSON.stringify(err)).not.toContain(spec.authHeader[1].replace('Bearer ', ''));
    });
  });
});

describe.each(specs)('$name adapter over a real loopback HTTP server', (spec) => {
  let server: LoopbackServer | undefined;
  afterEach(async () => {
    await server?.close();
    server = undefined;
  });

  const baseUrl = () => (spec.name === 'openai' || spec.name === 'xai' ? `${server!.origin}/v1` : server!.origin);

  it('parses a real HTTP answer, headers and body included', async () => {
    server = await startServer((_req, res) => {
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(spec.success(json)));
    });
    const provider = spec.make(undefined as unknown as typeof fetch, { baseUrl: baseUrl() });
    const r = await provider.generate(request);
    expect(r).toMatchObject({ text: json, inputTokens: 11, outputTokens: 7, usageReported: true });
    const sent = server.requests[0]!;
    expect(sent.method).toBe('POST');
    expect(sent.headers[spec.authHeader[0]]).toBe(spec.authHeader[1]);
    spec.checkPayload(JSON.parse(sent.body) as Record<string, unknown>, 'fast-model-x');
  });

  it('carries Retry-After over a real 429', async () => {
    server = await startServer((_req, res) => {
      res.writeHead(429, { 'content-type': 'application/json', 'retry-after': '3' }).end(JSON.stringify({ error: { type: 'rate_limit_error', message: 'SENTINEL' } }));
    });
    const err = (await spec.make(undefined as unknown as typeof fetch, { baseUrl: baseUrl() }).generate(request).catch((e: unknown) => e)) as ProviderError;
    expect(err).toMatchObject({ kind: 'http', status: 429, retryAfterMs: 3000 });
    expect(err.message).toBe(`${spec.name}: HTTP 429 (rate_limit_error)`);
  });

  it('aborts a request the server never answers: classified as timeout, connection really closed', async () => {
    server = await startServer(() => undefined); // accepts, reads, never answers
    const provider = spec.make(undefined as unknown as typeof fetch, { baseUrl: baseUrl() });
    const started = Date.now();
    const err = (await provider.generate({ ...request, timeoutMs: 150 }).catch((e: unknown) => e)) as ProviderError;
    const elapsed = Date.now() - started;
    expect(err).toMatchObject({ kind: 'timeout' satisfies ProviderErrorKind, providerId: spec.name });
    expect(elapsed).toBeGreaterThanOrEqual(140);
    expect(elapsed).toBeLessThan(4000); // generous: CI machines stall; the point is that it does not hang
    expect(await waitFor(() => server!.aborted() === 1), 'the server should see the client hang up').toBe(true);
  });

  it('reports a refused connection as a network error', async () => {
    server = await startServer(() => undefined);
    const url = baseUrl();
    await server.close();
    server = undefined;
    const err = (await spec.make(undefined as unknown as typeof fetch, { baseUrl: url }).generate(request).catch((e: unknown) => e)) as ProviderError;
    expect(err).toMatchObject({ kind: 'network', retryable: true });
    expect(err.message).not.toContain('127.0.0.1');
  });
});
