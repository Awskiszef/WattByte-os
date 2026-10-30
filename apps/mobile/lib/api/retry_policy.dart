// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'api_failure.dart';

/// How a failed API call is retried. One table, used by everything that retries
/// automatically (today the sync); `test/retry_policy_test.dart` pins it row by row.
///
/// | failure                                  | class       | decision |
/// |------------------------------------------|-------------|----------|
/// | no connection, DNS, TLS, timeout, 408    | transient   | retry with exponential backoff + jitter, capped, unlimited |
/// | HTTP 429 (not the AI quota)              | transient   | retry; waits at least the server's `Retry-After`, at least the own backoff |
/// | HTTP 401 after the one refresh + retry   | transient   | retry with backoff (a refresh that is rejected ends the session instead) |
/// | HTTP 5xx, other unexpected status        | limited     | retry with backoff and `Retry-After` (503), then FAIL after [maxLimitedAttempts] |
/// | HTTP 404 / 409                           | limited     | as above (a route or state the server may still sort out) |
/// | HTTP 400                                 | permanent   | FAIL at once, never retried automatically |
/// | AI quota 429 (`ai_quota_exceeded`)       | quota       | FAIL: a business limit, not a transport problem |
///
/// "FAIL" means: stop, keep the data, wait for a person (manual retry).
enum FailureClass { transient, limited, permanent, quota }

enum RetryAction { retry, fail }

class RetryDecision {
  const RetryDecision.retry(this.failureClass, Duration this.delay)
      : action = RetryAction.retry;

  const RetryDecision.fail(this.failureClass)
      : action = RetryAction.fail,
        delay = null;

  final RetryAction action;
  final FailureClass failureClass;

  /// Wait at least this long before the next automatic attempt (retry only).
  final Duration? delay;

  bool get shouldRetry => action == RetryAction.retry;

  @override
  String toString() => 'RetryDecision($action, $failureClass, delay: $delay)';
}

class RetryPolicy {
  const RetryPolicy({
    this.baseBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(hours: 1),
    this.maxLimitedAttempts = 8,
    this.maxPermanentFailures = 3,
    this.jitter = 0.2,
  });

  /// The wait after the first failure; doubles with every further one.
  final Duration baseBackoff;

  /// The own schedule never waits longer than this (before jitter). A server's
  /// `Retry-After` may exceed it: it is honoured, up to 24 hours.
  final Duration maxBackoff;

  /// Consecutive "limited" failures (5xx and friends) after which retrying stops.
  final int maxLimitedAttempts;

  /// Consecutive refusals (HTTP 400) after which automatic uploads stop. Each refusal
  /// is final for its payload and is not retried, but a day that keeps changing is a
  /// new payload: this bounds how often a server that refuses everything is asked.
  final int maxPermanentFailures;

  /// Relative jitter: 0.2 means +-20 %.
  final double jitter;

  /// The own exponential schedule: `base * 2^(attempt-1)`, capped, with +-[jitter].
  Duration backoff(int attempt, Random random) {
    final n = attempt < 1 ? 1 : attempt;
    final exp = baseBackoff.inMilliseconds * pow(2, min(n - 1, 40));
    final capped = min(exp.toDouble(), maxBackoff.inMilliseconds.toDouble());
    final factor = 1 + (random.nextDouble() * 2 - 1) * jitter;
    return Duration(milliseconds: (capped * factor).round());
  }

  FailureClass classify(ApiFailure f) {
    if (f.isQuotaExceeded) return FailureClass.quota;
    return switch (f.kind) {
      ApiFailureKind.network ||
      ApiFailureKind.timeout ||
      ApiFailureKind.rateLimited ||
      ApiFailureKind.unauthorized =>
        FailureClass.transient,
      ApiFailureKind.badRequest => FailureClass.permanent,
      ApiFailureKind.server ||
      ApiFailureKind.other ||
      ApiFailureKind.notFound ||
      ApiFailureKind.conflict =>
        FailureClass.limited,
    };
  }

  /// What to do after [failure].
  ///
  /// [attempts] counts consecutive failures including this one (it drives the
  /// backoff); [limitedFailures] counts consecutive failures of the limited class
  /// including this one (it drives giving up).
  RetryDecision decide(
    ApiFailure failure, {
    required int attempts,
    required int limitedFailures,
    required Random random,
  }) {
    final cls = classify(failure);
    switch (cls) {
      case FailureClass.permanent:
      case FailureClass.quota:
        return RetryDecision.fail(cls);
      case FailureClass.limited:
        if (limitedFailures >= maxLimitedAttempts) {
          return RetryDecision.fail(cls);
        }
      case FailureClass.transient:
        break;
    }
    return RetryDecision.retry(cls, delayFor(failure, attempts, random));
  }

  /// The wait before the next automatic attempt: the own backoff, or the
  /// server's `Retry-After` plus up to 10 % of it, whichever is longer.
  Duration delayFor(ApiFailure failure, int attempts, Random random) {
    final own = backoff(attempts, random);
    final asked = failure.retryAfter;
    if (asked == null) return own;
    final ms = asked.inMilliseconds;
    final honoured =
        Duration(milliseconds: ms + (ms * 0.1 * random.nextDouble()).round());
    return honoured > own ? honoured : own;
  }
}
