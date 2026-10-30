// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it, vi } from 'vitest';

import { OpenAIProvider, ProviderError, REASONING_HEADROOM_TOKENS, XAIProvider, resolveModel, type ProviderEnv, providersFromEnv } from '../src/index.js';
import { fakeFetch, json, models, request, specs } from './helpers/doubles.js';
import { startServer, type LoopbackServer } from './helpers/server.js';

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllEnvs();
});

const openai = specs.find((s) => s.name === 'openai')!;
const xai = specs.find((s) => s.name === 'xai')!;

async function failure(make: () => Promise<unknown>): Promise<ProviderError> {
  const err = await make().catch((e: unknown) => e);
  expect(err, 'expected a ProviderError').toBeInstanceOf(ProviderError);
  return err as ProviderError;
}

describe.each([openai, xai])('$name through the official SDK: isolation from the environment', (spec) => {
  /** Variables the SDK itself would read, set as a developer machine (or a CI runner) might have them. */
  const AMBIENT_SDK_ENV = {
    OPENAI_BASE_URL: 'http://127.0.0.1:9/ambient',
    OPENAI_ORG_ID: 'org-ambient',
    OPENAI_PROJECT_ID: 'proj-ambient',
    OPENAI_ADMIN_KEY: 'sk-admin-ambient',
    OPENAI_WEBHOOK_SECRET: 'whsec-ambient',
    OPENAI_LOG: 'debug',
    OPENAI_CUSTOM_HEADERS: 'x-ambient-header: leaked\nx-another: leaked',
  };

  it('sends only the headers it needs and never an organisation, project or header from the environment', async () => {
    for (const [k, v] of Object.entries(AMBIENT_SDK_ENV)) vi.stubEnv(k, v);
    const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
    await spec.make(fetchImpl).generate(request);
    expect(calls).toHaveLength(1);
    expect(Object.keys(calls[0]!.headers).sort()).toEqual(['accept', 'authorization', 'content-type', 'user-agent']);
    expect(calls[0]!.url).toBe(spec.url('fast-model-x'));
    expect(JSON.stringify(calls[0])).not.toMatch(/ambient|leaked|127\.0\.0\.1:9/);
  });

  it('the SDK does not log (a debug level in the environment cannot print requests)', async () => {
    vi.stubEnv('OPENAI_LOG', 'debug');
    const spies = (['log', 'debug', 'info', 'warn', 'error'] as const).map((m) => vi.spyOn(console, m).mockImplementation(() => undefined));
    try {
      await spec.make(fakeFetch({ body: spec.success(json) }).fetchImpl).generate(request);
      await spec.make(fakeFetch({ status: 500, body: {} }).fetchImpl).generate(request).catch(() => undefined);
      for (const spy of spies) expect(spy).not.toHaveBeenCalled();
    } finally {
      for (const spy of spies) spy.mockRestore();
    }
  });
});

describe('two providers, two clients', () => {
  it('OpenAI and xAI never share a base URL or a key, even when built from one fetch', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: openai.success(json) });
    await new OpenAIProvider({ apiKey: 'k-openai', models, fetchImpl }).generate(request);
    await new XAIProvider({ apiKey: 'k-xai', models, fetchImpl }).generate(request);
    expect(calls.map((c) => c.url)).toEqual(['https://api.openai.com/v1/responses', 'https://api.x.ai/v1/responses']);
    expect(calls.map((c) => c.headers.authorization)).toEqual(['Bearer k-openai', 'Bearer k-xai']);
  });

  it('providersFromEnv builds both from their own variables', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: openai.success(json) });
    const env: ProviderEnv = { OPENAI_API_KEY: 'k-openai', OPENAI_FAST_MODEL: 'gpt-x', XAI_API_KEY: 'k-xai', XAI_FAST_MODEL: 'grok-x' };
    for (const p of providersFromEnv(env, { fetchImpl })) await p.generate(request);
    expect(calls.map((c) => [c.url, c.body.model])).toEqual([
      ['https://api.openai.com/v1/responses', 'gpt-x'],
      ['https://api.x.ai/v1/responses', 'grok-x'],
    ]);
  });
});

describe.each([openai, xai])('$name: no hidden retries', (spec) => {
  it.each([429, 500, 502, 503])('HTTP %i is ONE call: the SDK does not retry, the gateway decides', async (status) => {
    const { fetchImpl, calls } = fakeFetch({ status, body: {}, headers: { 'retry-after': '1' } });
    await failure(() => spec.make(fetchImpl).generate(request));
    expect(calls).toHaveLength(1);
  });

  it('a connection error is ONE call as well', async () => {
    const { fetchImpl, calls } = fakeFetch({ networkError: new TypeError('fetch failed') });
    await failure(() => spec.make(fetchImpl).generate(request));
    expect(calls).toHaveLength(1);
  });
});

describe.each([openai, xai])('$name: temperature is sent only where the model accepts it', (spec) => {
  const rejection = { status: 400, body: { error: { type: 'invalid_request_error', code: 'unsupported_value', param: 'temperature', message: 'SENTINEL-ECHO only the default (1) value is supported' } } };

  it('sends a temperature by default (0.3 for normal, 0.8 for the playful modes)', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
    const provider = spec.make(fetchImpl);
    await provider.generate(request);
    await provider.generate({ ...request, mode: 'roast' });
    expect(calls.map((c) => c.body.temperature)).toEqual([0.3, 0.8]);
  });

  it('a 400 that names the temperature is answered once without it, and remembered for that model', async () => {
    const { fetchImpl, calls } = fakeFetch((n) => (n === 1 ? rejection : { body: spec.success(json) }));
    const provider = spec.make(fetchImpl);
    const first = await provider.generate(request);
    expect(first.text).toBe(json);
    expect(calls).toHaveLength(2);
    expect(calls[0]!.body).toHaveProperty('temperature');
    expect(calls[1]!.body).not.toHaveProperty('temperature');
    // The second request of the same model does not even try it.
    await provider.generate(request);
    expect(calls).toHaveLength(3);
    expect(calls[2]!.body).not.toHaveProperty('temperature');
    // Another model is still asked with a temperature.
    await provider.generate({ ...request, tier: 'quality' });
    expect(calls[3]!.body).toHaveProperty('temperature');
  });

  it('works when the provider names the parameter only in free text (xAI answers with a sentence)', async () => {
    const { fetchImpl, calls } = fakeFetch((n) => (n === 1 ? { status: 400, body: { code: 'Client specified an invalid argument', error: 'Argument not supported: temperature' } } : { body: spec.success(json) }));
    expect((await spec.make(fetchImpl).generate(request)).text).toBe(json);
    expect(calls).toHaveLength(2);
  });

  it('any other 400 is a plain invalid-request error: nothing is dropped, nothing is asked twice', async () => {
    const { fetchImpl, calls } = fakeFetch({ status: 400, body: { error: { type: 'invalid_request_error', param: 'model', message: 'SENTINEL-ECHO bad model' } } });
    const err = await failure(() => spec.make(fetchImpl).generate(request));
    expect(calls).toHaveLength(1);
    expect(err).toMatchObject({ kind: 'http', status: 400, retryable: false });
    expect(err.message).toBe(`${spec.name}: HTTP 400 (invalid_request_error)`);
  });

  it('a second 400 about the temperature (even without it) is surfaced, not looped on', async () => {
    const { fetchImpl, calls } = fakeFetch(rejection);
    const err = await failure(() => spec.make(fetchImpl).generate(request));
    expect(calls).toHaveLength(2);
    expect(err).toMatchObject({ kind: 'http', status: 400 });
    expect(err.message).not.toContain('SENTINEL-ECHO');
  });
});

describe.each([openai, xai])('$name: reading a Responses answer', (spec) => {
  const answer = (over: Record<string, unknown>) => ({ body: { id: 'resp_1', object: 'response', status: 'completed', output: [], usage: { input_tokens: 5, output_tokens: 3 }, ...over } });

  it('joins the text parts of the message and ignores reasoning items', async () => {
    const { fetchImpl } = fakeFetch(
      answer({
        output: [
          { type: 'reasoning', summary: [{ type: 'summary_text', text: 'SENTINEL-THINKING' }] },
          { type: 'message', content: [{ type: 'output_text', text: '{"title":' }, { type: 'output_text', text: '"x"}' }] },
        ],
      }),
    );
    expect((await spec.make(fetchImpl).generate(request)).text).toBe('{"title":"x"}');
  });

  it('an answer without any message is empty text, not an error here (the gateway rejects it)', async () => {
    const r = await spec.make(fakeFetch(answer({ output: [{ type: 'reasoning', summary: [] }] })).fetchImpl).generate(request);
    expect(r).toMatchObject({ text: '', inputTokens: 5, outputTokens: 3, usageReported: true });
  });

  it('status incomplete because of max_output_tokens is a cut-off answer: invalid_output, billed tokens kept, not retryable', async () => {
    const err = await failure(() => spec.make(fakeFetch(answer({ status: 'incomplete', incomplete_details: { reason: 'max_output_tokens' }, usage: { input_tokens: 40, output_tokens: 1244 } })).fetchImpl).generate(request));
    expect(err).toMatchObject({ kind: 'invalid_output', retryable: false, inputTokens: 40, outputTokens: 1244 });
    expect(err.message).toBe(`${spec.name}: answer cut off (max_output_tokens)`);
  });

  it.each([
    ['rate_limit_exceeded', 429, true],
    ['server_error', 502, true],
    ['invalid_prompt', 400, false],
  ])('status failed with %s stands for HTTP %i (retryable: %s)', async (code, status, retryable) => {
    const err = await failure(() => spec.make(fakeFetch(answer({ status: 'failed', error: { code, message: 'SENTINEL-ECHO' } })).fetchImpl).generate(request));
    expect(err).toMatchObject({ kind: 'http', status, retryable, code });
    expect(err.message).not.toContain('SENTINEL-ECHO');
  });

  it('status failed because of a policy violation is a refusal', async () => {
    const err = await failure(() => spec.make(fakeFetch(answer({ status: 'failed', error: { code: 'bio_policy' } })).fetchImpl).generate(request));
    expect(err.kind).toBe('refusal');
  });

  it.each(['queued', 'in_progress', 'cancelled', 'something_new'])('status %s is an invalid response (we never ask for background runs)', async (status) => {
    const err = await failure(() => spec.make(fakeFetch(answer({ status })).fetchImpl).generate(request));
    expect(err).toMatchObject({ kind: 'invalid_response', retryable: false });
  });

  it.each([
    ['an HTML page with a JSON content type', { raw: '<html>maintenance</html>' }],
    ['a JSON value that is not a Responses object', { body: ['not', 'an', 'object'] }],
    ['an object without output', { body: { id: 'x', status: 'completed' } }],
  ])('%s is an invalid response', async (_label, reply) => {
    const err = await failure(() => spec.make(fakeFetch(reply).fetchImpl).generate(request));
    expect(err).toMatchObject({ kind: 'invalid_response', retryable: false });
  });

  it('reports the request id from the response header, falling back to the response id', async () => {
    const withHeader = await spec.make(fakeFetch({ ...answer({}), headers: { 'x-request-id': 'req_abc123' } }).fetchImpl).generate(request);
    expect(withHeader.requestId).toBe('req_abc123');
    const withoutHeader = await spec.make(fakeFetch(answer({ id: 'resp_zz9' })).fetchImpl).generate(request);
    expect(withoutHeader.requestId).toBe('resp_zz9');
    const hostile = await spec.make(fakeFetch({ ...answer({ id: 'bad id with spaces' }), headers: { 'x-request-id': 'has space' } }).fetchImpl).generate(request);
    expect(hostile.requestId).toBeUndefined();
  });

  it('the request id of a failed call travels with the error', async () => {
    const err = await failure(() => spec.make(fakeFetch({ status: 503, body: {}, headers: { 'x-request-id': 'req_fail_77' } }).fetchImpl).generate(request));
    expect(err.requestId).toBe('req_fail_77');
  });

  it('keeps the machine code of an HTTP error for the retry policy (insufficient_quota is not a "wait and retry")', async () => {
    const err = await failure(() => spec.make(fakeFetch({ status: 429, body: { error: { type: 'insufficient_quota', code: 'insufficient_quota', message: 'SENTINEL-ECHO' } } }).fetchImpl).generate(request));
    expect(err).toMatchObject({ status: 429, code: 'insufficient_quota' });
  });
});

describe('xAI usage and cost', () => {
  const body = (usage: Record<string, unknown>) => ({ body: { id: 'resp_x', status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: json }] }], usage } });

  it('takes the exact charge xAI reports (ticks of a ten-billionth of a dollar)', async () => {
    const r = await xai.make(fakeFetch(body({ input_tokens: 11, output_tokens: 7, cost_in_usd_ticks: 37_756_000 })).fetchImpl).generate(request);
    expect(r.costUsd).toBeCloseTo(0.0037756, 10);
  });

  it.each([['absent', undefined], ['negative', -1], ['a string', '37756000'], ['not finite', Number.POSITIVE_INFINITY]])('a cost that is %s is ignored', async (_label, ticks) => {
    const r = await xai.make(fakeFetch(body({ input_tokens: 11, output_tokens: 7, cost_in_usd_ticks: ticks })).fetchImpl).generate(request);
    expect(r).not.toHaveProperty('costUsd');
  });

  it('understands the Chat-Completions names xAI has been seen to use inside Responses', async () => {
    const r = await xai.make(fakeFetch(body({ prompt_tokens: 30, completion_tokens: 12 })).fetchImpl).generate(request);
    expect(r).toMatchObject({ inputTokens: 30, outputTokens: 12, usageReported: true });
  });

  it('OpenAI sends no cost, so none is invented', async () => {
    const r = await openai.make(fakeFetch({ body: openai.success(json) }).fetchImpl).generate(request);
    expect(r).not.toHaveProperty('costUsd');
  });
});

describe.each([openai, xai])('$name: model override and cancellation', (spec) => {
  it('a backend-chosen model replaces the configured one for that call', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
    await spec.make(fetchImpl).generate({ ...request, model: 'override-model-1' });
    expect(calls[0]!.body.model).toBe('override-model-1');
  });

  it.each(['', ' ', 'has space', '../x', 'a'.repeat(200), 'model\nname'])('refuses the model override %j before any request is made', async (model) => {
    const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
    await expect(spec.make(fetchImpl).generate({ ...request, model })).rejects.toThrow(/invalid model override/);
    expect(calls).toHaveLength(0);
  });

  it('resolveModel validates the override the same way for every adapter', () => {
    expect(resolveModel('openai', models, { ...request, model: 'ok-model_1.5:latest' })).toBe('ok-model_1.5:latest');
    expect(() => resolveModel('openai', models, { ...request, model: 'no good' })).toThrow();
  });

  it('a signal that is aborted mid-call ends it at once as "aborted", not as a timeout, leaving no timer', async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const { fetchImpl } = fakeFetch({ hang: true });
    const pending = spec.make(fetchImpl).generate({ ...request, timeoutMs: 60_000, signal: controller.signal }).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(100);
    controller.abort();
    const err = (await pending) as ProviderError;
    expect(err).toBeInstanceOf(ProviderError);
    expect(err).toMatchObject({ kind: 'aborted', retryable: false });
    expect(vi.getTimerCount()).toBe(0);
  });

  it('even a transport that ignores the signal cannot keep the caller waiting after an abort', async () => {
    vi.useFakeTimers();
    const controller = new AbortController();
    const { fetchImpl } = fakeFetch({ hangIgnoringSignal: true });
    const pending = spec.make(fetchImpl).generate({ ...request, timeoutMs: 60_000, signal: controller.signal }).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(100);
    controller.abort();
    expect(await pending).toMatchObject({ kind: 'aborted' });
  });

  it('a signal that is already aborted makes no request', async () => {
    const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
    const err = await failure(() => spec.make(fetchImpl).generate({ ...request, signal: AbortSignal.abort() }));
    expect(err.kind).toBe('aborted');
    expect(calls).toHaveLength(0);
  });
});

describe('the output cap', () => {
  it('leaves room for hidden reasoning on top of the visible limit, for both providers', async () => {
    for (const spec of [openai, xai]) {
      const { fetchImpl, calls } = fakeFetch({ body: spec.success(json) });
      await spec.make(fetchImpl).generate({ ...request, maxOutputTokens: 400 });
      expect(calls[0]!.body.max_output_tokens).toBe(400 + REASONING_HEADROOM_TOKENS);
    }
  });
});

describe('the OpenAI request over a real HTTP server (real SDK transport, real sockets)', () => {
  let server: LoopbackServer | undefined;
  afterEach(async () => {
    await server?.close();
    server = undefined;
  });

  it.each([openai, xai])('$name: the SDK posts JSON to {base}/responses with only the allowed headers', async (spec) => {
    vi.stubEnv('OPENAI_CUSTOM_HEADERS', 'x-ambient-header: leaked');
    server = await startServer((_req, res) => void res.writeHead(200, { 'content-type': 'application/json', 'x-request-id': 'req_loop_1' }).end(JSON.stringify(spec.success(json))));
    const r = await spec.make(undefined as unknown as typeof fetch, { baseUrl: `${server.origin}/v1` }).generate(request);
    expect(r).toMatchObject({ text: json, requestId: 'req_loop_1', usageReported: true });
    const sent = server.requests[0]!;
    expect(sent.url).toBe('/v1/responses');
    expect(sent.method).toBe('POST');
    expect(sent.headers['x-ambient-header']).toBeUndefined();
    expect(sent.headers['openai-organization']).toBeUndefined();
    expect(sent.headers['openai-project']).toBeUndefined();
    expect(Object.keys(sent.headers).filter((h) => h.startsWith('x-stainless'))).toEqual([]);
  });
});
