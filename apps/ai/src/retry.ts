// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Retry timing for one provider inside one request. Which failures are worth retrying is decided in
 * `errors.ts` (`isRetryable`); this file only answers "how long to wait".
 */
export interface RetryPolicy {
  /** Extra calls to the same provider after the first one fails transiently. 0 = never retry. */
  readonly maxRetries: number;
  /** Wait before the first retry; every further retry doubles it. */
  readonly baseDelayMs: number;
  /** Upper bound of the doubled wait, before jitter. */
  readonly maxDelayMs: number;
  /** Random spread as a fraction of the wait (0.25 = between 75 % and 125 %), so parallel requests do not retry in lockstep. */
  readonly jitter: number;
  /**
   * A provider that asks for a longer pause than this (HTTP `Retry-After`) is not waited for: the user is
   * waiting too, so the request moves on and the router keeps that provider out for as long as it asked.
   */
  readonly maxRetryAfterMs: number;
}

export const DEFAULT_RETRY_POLICY: RetryPolicy = {
  maxRetries: 2,
  baseDelayMs: 500,
  maxDelayMs: 8_000,
  jitter: 0.25,
  maxRetryAfterMs: 5_000,
};

/**
 * Milliseconds to wait before retry number `retryIndex` (0 = the first retry): 500, 1000, 2000 ... with
 * jitter, and never less than the provider asked for. Undefined when the provider asked for longer
 * than `maxRetryAfterMs`: do not retry.
 */
export function backoffDelayMs(retryIndex: number, policy: RetryPolicy, random: () => number, retryAfterMs?: number): number | undefined {
  if (retryAfterMs !== undefined && retryAfterMs > policy.maxRetryAfterMs) return undefined;
  const exponential = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** Math.min(retryIndex, 30));
  const r = random();
  const spread = 1 - policy.jitter + 2 * policy.jitter * (Number.isFinite(r) ? Math.min(Math.max(r, 0), 1) : 0.5);
  return Math.round(Math.max(exponential * spread, retryAfterMs ?? 0));
}

/** Resolves after `ms`, or at once when `signal` aborts (the caller then looks at the signal). */
export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal?.aborted) {
      resolve();
      return;
    }
    const done = (): void => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', done);
      resolve();
    };
    const timer = setTimeout(done, ms);
    signal?.addEventListener('abort', done, { once: true });
  });
}
