import type { AIProviderId } from '../types.js';

/**
 * Why an attempt failed, in terms the gateway can act on and log without ever
 * touching prompt or response text:
 *
 * - `timeout`          the provider did not answer within `timeoutMs`; the request was aborted
 * - `network`          DNS / connection / TLS failure before any HTTP status
 * - `http`             a non-2xx status (see `status`, `retryable`, `retryAfterMs`)
 * - `invalid_response` a 2xx body that is not JSON
 * - `refusal`          the model or the provider's safety layer declined to answer
 * - `empty_output`     a 2xx answer without any text
 * - `invalid_output`   text that is not JSON or does not match the output schema
 * - `unexpected`       a bug or an exception type the adapter did not anticipate
 * - `aborted`          the caller cancelled the request (AbortSignal); not a fault of the provider
 */
export type ProviderErrorKind =
  | 'timeout'
  | 'network'
  | 'http'
  | 'invalid_response'
  | 'refusal'
  | 'empty_output'
  | 'invalid_output'
  | 'unexpected'
  | 'aborted';

export interface ProviderErrorDetail {
  readonly kind?: ProviderErrorKind;
  /** The model that was asked, so a failure can still be logged with it. */
  readonly model?: string;
  /** From a `Retry-After` header; the router stretches the cooldown to at least this. */
  readonly retryAfterMs?: number;
  /** Short machine code from the error body (`invalid_api_key`, `insufficient_quota`); never free text. */
  readonly code?: string;
  /** Provider-side id of the request (response header or body id), for support tickets and invoices. */
  readonly requestId?: string;
  /** Token usage of a call that was billed but rejected (refusal, invalid output). */
  readonly inputTokens?: number;
  readonly outputTokens?: number;
}

/**
 * A failed provider attempt. `message` is built from the provider id, the
 * failure class and a short machine-readable code only: never from the
 * response body, which can echo the prompt, and never from request headers.
 */
export class ProviderError extends Error {
  readonly kind: ProviderErrorKind;
  readonly model?: string;
  readonly retryAfterMs?: number;
  readonly code?: string;
  readonly requestId?: string;
  readonly inputTokens?: number;
  readonly outputTokens?: number;

  constructor(
    readonly providerId: AIProviderId,
    message: string,
    readonly status?: number,
    /** Transient: the same request may well succeed later. Informational; every failure falls through to the next provider. */
    readonly retryable = status === undefined || status === 408 || status === 429 || status >= 500,
    detail: ProviderErrorDetail = {},
  ) {
    super(`${providerId}: ${message}`);
    this.name = 'ProviderError';
    this.kind = detail.kind ?? (status === undefined ? 'network' : 'http');
    this.model = detail.model;
    this.retryAfterMs = detail.retryAfterMs;
    this.code = detail.code;
    this.requestId = detail.requestId;
    this.inputTokens = detail.inputTokens;
    this.outputTokens = detail.outputTokens;
  }
}

export type FetchLike = typeof fetch;

export interface HttpOptions {
  readonly fetchImpl?: FetchLike;
}

class DeadlineExceeded extends Error {}
class CallerAborted extends Error {}

/**
 * Runs `run` with an abort signal and a hard deadline. The deadline is raced
 * against the work, so a fetch that ignores its signal (a test double, a
 * misbehaving proxy) still cannot hold the caller past `timeoutMs`; the timer
 * is always cleared. `external` is the caller's own cancellation: it aborts the
 * work at once and is reported as `CallerAborted`, never as a timeout.
 */
async function withDeadline<T>(timeoutMs: number, run: (signal: AbortSignal) => Promise<T>, external?: AbortSignal): Promise<T> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let callerAborted = false;
  let detach: (() => void) | undefined;
  const stop = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new DeadlineExceeded());
    }, timeoutMs);
    if (external) {
      const onAbort = (): void => {
        callerAborted = true;
        controller.abort();
        reject(new CallerAborted());
      };
      if (external.aborted) onAbort();
      else {
        external.addEventListener('abort', onAbort, { once: true });
        detach = () => external.removeEventListener('abort', onAbort);
      }
    }
  });
  try {
    return await Promise.race([run(controller.signal), stop]);
  } catch (e) {
    if (callerAborted || e instanceof CallerAborted) throw new CallerAborted();
    if (e instanceof DeadlineExceeded || controller.signal.aborted) throw new DeadlineExceeded();
    throw e;
  } finally {
    clearTimeout(timer);
    detach?.();
  }
}

const SAFE_CODE = /^[A-Za-z0-9_.:-]{1,64}$/;
const MAX_ERROR_BODY_CHARS = 65_536;
const MAX_RETRY_AFTER_MS = 24 * 3_600_000;

/**
 * Pulls a short machine code (`invalid_api_key`, `rate_limit_error`,
 * `RESOURCE_EXHAUSTED`, ...) out of a provider error body. Free text such as
 * `error.message` is never used: it may quote the request.
 */
export function errorCodeFromBody(text: string): string | undefined {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text.slice(0, MAX_ERROR_BODY_CHARS));
  } catch {
    return undefined;
  }
  if (typeof parsed !== 'object' || parsed === null) return undefined;
  const root = parsed as Record<string, unknown>;
  const nested = typeof root.error === 'object' && root.error !== null ? (root.error as Record<string, unknown>) : {};
  for (const candidate of [nested.type, nested.code, nested.status, root.type, root.code]) {
    if (typeof candidate === 'string' && SAFE_CODE.test(candidate)) return candidate;
  }
  return undefined;
}

/** `Retry-After` (seconds or HTTP date) and OpenAI's `retry-after-ms`, in milliseconds. */
export function retryAfterMsFrom(headers: Headers, nowMs: number = Date.now()): number | undefined {
  const clamp = (ms: number): number | undefined => (Number.isFinite(ms) && ms > 0 ? Math.min(Math.round(ms), MAX_RETRY_AFTER_MS) : undefined);
  const explicit = headers.get('retry-after-ms');
  if (explicit !== null && /^\d+(\.\d+)?$/.test(explicit.trim())) return clamp(Number(explicit));
  const value = headers.get('retry-after')?.trim();
  if (!value) return undefined;
  if (/^\d+(\.\d+)?$/.test(value)) return clamp(Number(value) * 1000);
  return clamp(Date.parse(value) - nowMs);
}

/** `network error (TypeError ECONNREFUSED)`: the error class and code only, never its message (it can quote URLs and keys). */
export function networkMessage(e: unknown): string {
  const err = e as { name?: unknown; code?: unknown; cause?: { code?: unknown } } | null;
  const code = [err?.cause?.code, err?.code].find((c): c is string => typeof c === 'string' && /^[A-Z0-9_]{3,40}$/.test(c));
  const name = typeof err?.name === 'string' && /^[A-Za-z]{1,40}$/.test(err.name) ? err.name : 'Error';
  return `network error (${name}${code ? ` ${code}` : ''})`;
}

export interface RunOptions<T> {
  readonly providerId: AIProviderId;
  readonly model: string;
  readonly timeoutMs: number;
  /** The caller's cancellation (`AIGenerationRequest.signal`). */
  readonly signal?: AbortSignal;
  readonly run: (signal: AbortSignal) => Promise<T>;
  /**
   * Turns an error thrown by `run` (an SDK exception, say) into a classified `ProviderError`.
   * Return undefined for anything it does not recognise: that is reported as a network failure.
   */
  readonly mapError?: (e: unknown) => ProviderError | undefined;
}

/**
 * The one place where a provider call gets its hard deadline and where every failure becomes a
 * classified, content-free `ProviderError`: timeout, caller cancellation, whatever `mapError`
 * recognises, and otherwise a network error carrying only the error class and code.
 */
export async function runWithDeadline<T>(o: RunOptions<T>): Promise<T> {
  const { providerId, model } = o;
  try {
    return await withDeadline(o.timeoutMs, o.run, o.signal);
  } catch (e) {
    if (e instanceof ProviderError) throw e;
    if (e instanceof CallerAborted) {
      throw new ProviderError(providerId, 'aborted by the caller', undefined, false, { kind: 'aborted', model });
    }
    if (e instanceof DeadlineExceeded) {
      throw new ProviderError(providerId, `timeout after ${o.timeoutMs} ms`, undefined, true, { kind: 'timeout', model });
    }
    const mapped = o.mapError?.(e);
    if (mapped) throw mapped;
    throw new ProviderError(providerId, networkMessage(e), undefined, true, { kind: 'network', model });
  }
}

/** A machine code safe to log and to put in an error message; anything else (free text) is dropped. */
export function safeCode(value: unknown): string | undefined {
  return typeof value === 'string' && SAFE_CODE.test(value) ? value : undefined;
}

/** A provider-side request id that is safe to log; anything else is dropped. */
export function safeRequestId(value: unknown): string | undefined {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(value) ? value : undefined;
}

export interface PostJsonOptions {
  readonly providerId: AIProviderId;
  readonly model: string;
  readonly url: string;
  readonly body: unknown;
  readonly headers: Record<string, string>;
  readonly timeoutMs: number;
  readonly signal?: AbortSignal;
  readonly fetchImpl?: FetchLike;
}

/** A success answer of a provider is a few KiB of JSON; anything near this is not an answer. */
export const MAX_SUCCESS_BODY_BYTES = 1024 * 1024;
/** An error body is only read for its machine code. */
export const MAX_ERROR_BODY_BYTES = 16 * 1024;

class BodyTooLarge extends Error {}

/** Reads at most [limit] bytes of the body as text; throws [BodyTooLarge] instead of buffering more. */
async function readCapped(res: Response, limit: number): Promise<string> {
  const declared = Number(res.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > limit) throw new BodyTooLarge();
  if (!res.body) return res.text();
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let received = 0;
  let text = '';
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    received += value.byteLength;
    if (received > limit) {
      await reader.cancel().catch(() => undefined);
      throw new BodyTooLarge();
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

/** POST JSON with a hard timeout; every failure becomes a classified ProviderError. */
export async function postJson<T>(o: PostJsonOptions): Promise<T> {
  const { providerId, model } = o;
  const fetchImpl = o.fetchImpl ?? fetch;
  return runWithDeadline<T>({
    providerId,
    model,
    timeoutMs: o.timeoutMs,
    signal: o.signal,
    run: async (signal) => {
      const res = await fetchImpl(o.url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...o.headers },
        body: JSON.stringify(o.body),
        // The API key travels in a request header (some providers use a custom one that a runtime does not strip on a
        // cross-origin redirect): a redirect from a provider endpoint is a failure, never followed.
        redirect: 'error',
        signal,
      });
      if (!res.ok) {
        const code = errorCodeFromBody(await readCapped(res, MAX_ERROR_BODY_BYTES).catch(() => ''));
        throw new ProviderError(providerId, `HTTP ${res.status}${code ? ` (${code})` : ''}`, res.status, undefined, {
          model,
          code,
          retryAfterMs: retryAfterMsFrom(res.headers),
          requestId: safeRequestId(res.headers.get('x-request-id') ?? res.headers.get('request-id')),
        });
      }
      try {
        return JSON.parse(await readCapped(res, MAX_SUCCESS_BODY_BYTES)) as T;
      } catch {
        throw new ProviderError(providerId, 'response body is not valid JSON', res.status, false, { kind: 'invalid_response', model });
      }
    },
  });
}

export async function getOk(
  providerId: AIProviderId,
  url: string,
  headers: Record<string, string>,
  timeoutMs: number,
  fetchImpl: FetchLike = fetch,
): Promise<{ ok: boolean; latencyMs: number; error?: string }> {
  const started = Date.now();
  try {
    const res = await withDeadline(timeoutMs, (signal) => fetchImpl(url, { method: 'GET', headers, signal }));
    return { ok: res.ok, latencyMs: Date.now() - started, error: res.ok ? undefined : `HTTP ${res.status}` };
  } catch (e) {
    const error = e instanceof DeadlineExceeded ? `timeout after ${timeoutMs} ms` : networkMessage(e);
    return { ok: false, latencyMs: Date.now() - started, error };
  }
}
