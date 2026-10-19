import type { ProviderError } from './providers/http.js';

/**
 * One vocabulary for everything a provider can do wrong, whichever vendor said it:
 *
 * - `authentication`       401 / 403: a missing, revoked or unauthorised key
 * - `rate_limit`           429: too many requests, or the account's quota is used up
 * - `timeout`              no answer within the time we allow (also HTTP 408)
 * - `provider_unavailable` 5xx or no connection: the provider is down or unreachable
 * - `invalid_request`      the other 4xx: our request or the configured model name is wrong
 * - `response`             a 2xx that is unusable: refusal, empty text, text that fails the schema
 * - `aborted`              the caller cancelled; says nothing about the provider
 *
 * The category is derived from facts the adapters already record (`kind`, `status`), so it can
 * never disagree with them. Policy (retry, fallback) is decided here and nowhere else.
 */
export const AI_ERROR_CATEGORIES = ['authentication', 'rate_limit', 'timeout', 'provider_unavailable', 'invalid_request', 'response', 'aborted'] as const;
export type AIErrorCategory = (typeof AI_ERROR_CATEGORIES)[number];

type ErrorFacts = Pick<ProviderError, 'kind' | 'status' | 'code'>;

export function categorize(e: ErrorFacts): AIErrorCategory {
  switch (e.kind) {
    case 'aborted':
      return 'aborted';
    case 'timeout':
      return 'timeout';
    case 'network':
      return 'provider_unavailable';
    case 'invalid_response':
    case 'refusal':
    case 'empty_output':
    case 'invalid_output':
    case 'unexpected':
      return 'response';
    case 'http': {
      const status = e.status ?? 0;
      if (status === 401 || status === 403) return 'authentication';
      if (status === 429) return 'rate_limit';
      if (status === 408) return 'timeout';
      if (status >= 500) return 'provider_unavailable';
      return 'invalid_request';
    }
  }
}

/** 429 answers that mean "the account has no money/quota left", not "slow down": waiting does not help. */
const QUOTA_EXHAUSTED_CODES = new Set(['insufficient_quota', 'billing_not_active']);

/**
 * Worth asking the SAME provider again after a short pause: the failure is transient and it did
 * not use up the time budget. A timeout is deliberately not retried (the attempt already spent its
 * whole slice; the next provider can use the rest), and neither is anything that would fail the same
 * way again: bad request, bad key, refusal, bad output.
 */
export function isRetryable(e: ErrorFacts): boolean {
  switch (categorize(e)) {
    case 'rate_limit':
      return !(e.code !== undefined && QUOTA_EXHAUSTED_CODES.has(e.code));
    case 'provider_unavailable':
      // 501 / 505 will not get better by waiting.
      return e.status === undefined || (e.status !== 501 && e.status !== 505);
    case 'timeout':
      // HTTP 408 (the server gave up on us) is transient; our own timeout is not retried.
      return e.kind === 'http';
    default:
      return false;
  }
}

export interface FallbackPolicy {
  /** Whether a 429 may send the request to the other provider (some operators would rather wait). */
  readonly onRateLimit: boolean;
}

/**
 * May the request go to a different provider after this failure?
 *
 * Yes: timeouts, no connection, 5xx, HTTP 408, a body that is not JSON, and a 429 when allowed.
 * No: invalid request, authentication failure, a missing key, a refusal or any answer that fails the
 * output schema. Those would be paid for again, or they hide a defect (a revoked key, a wrong
 * model name, a bad prompt) that must surface instead of being papered over by the other vendor.
 */
export function allowsFallback(e: ErrorFacts, policy: FallbackPolicy): boolean {
  switch (categorize(e)) {
    case 'timeout':
    case 'provider_unavailable':
      return true;
    case 'rate_limit':
      return policy.onRateLimit;
    case 'response':
      return e.kind === 'invalid_response';
    default:
      return false;
  }
}
