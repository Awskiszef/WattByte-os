// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../core/periods.dart';
import 'daily_aggregate.dart';

/// Lifecycle of a queued aggregate in the schema up to version 4, when "synced"
/// was a property of the day. From version 5 on it is a property of (day,
/// account): see [SyncReceipt]. The enum and the columns that store it remain
/// because SQLite cannot drop columns portably; new code only ever writes
/// `pending` and ignores the value when reading.
enum SyncState { pending, syncing, synced, failed }

/// Which local days an account's sync may upload.
enum SyncScope {
  /// Every local day, including those that predate the moment sync was enabled.
  history,

  /// Only days from the day sync was enabled onwards.
  fromNow,
}

/// One day's aggregate as the device computed it.
///
/// This is DEVICE-LOCAL data: it has no account owner and survives sign-out and
/// account switches. Keyed by day, so re-aggregating the same day replaces the row
/// instead of adding a second one. Whether the day has been uploaded, and for
/// whom, is recorded separately in [SyncReceipt]s; [state], [attempts],
/// [lastError] and [nextRetryAt] are legacy (version <= 4) and no longer drive
/// anything.
class SyncQueueItem {
  const SyncQueueItem({
    required this.day,
    required this.payload,
    this.state = SyncState.pending,
    this.attempts = 0,
    this.lastError,
    required this.updatedAt,
    this.nextRetryAt,
  });

  final DateTime day;
  final DailyAggregate payload;
  final SyncState state;
  final int attempts;
  final String? lastError;
  final DateTime updatedAt;

  /// Backoff: not retried before this instant.
  final DateTime? nextRetryAt;

  SyncQueueItem copyWith({
    SyncState? state,
    int? attempts,
    String? lastError,
    bool clearError = false,
    DateTime? updatedAt,
    DateTime? nextRetryAt,
  }) =>
      SyncQueueItem(
        day: day,
        payload: payload,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
        updatedAt: updatedAt ?? this.updatedAt,
        nextRetryAt: nextRetryAt,
      );

  Map<String, Object?> toRow() => {
        'day': dayKey(day),
        'payload': jsonEncode(payload.toJson()),
        'state': state.name,
        'attempts': attempts,
        'last_error': lastError,
        'updated_ms': updatedAt.millisecondsSinceEpoch,
        'next_retry_ms': nextRetryAt?.millisecondsSinceEpoch ?? 0,
      };

  static SyncQueueItem fromRow(Map<String, Object?> m) => SyncQueueItem(
        day: parseDayKey(m['day'] as String),
        payload: DailyAggregate.fromJson(
            jsonDecode(m['payload'] as String) as Map<String, dynamic>),
        state: SyncState.values.byName(m['state'] as String),
        attempts: m['attempts'] as int,
        lastError: m['last_error'] as String?,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_ms'] as int),
        nextRetryAt: (m['next_retry_ms'] as int? ?? 0) == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['next_retry_ms'] as int),
      );
}

/// Proof that the aggregate with [fingerprint] for [day] was uploaded to the
/// account identified by [accountKey].
///
/// [accountKey] is a one-way key (`SyncOwnership.accountKey`), never the user id
/// or the e-mail. A day needs uploading for an account iff it has no receipt or
/// the receipt's fingerprint differs from the current aggregate's.
class SyncReceipt {
  const SyncReceipt({
    required this.day,
    required this.accountKey,
    required this.fingerprint,
    required this.syncedAt,
  });

  /// Local `yyyy-MM-dd`.
  final String day;
  final String accountKey;
  final String fingerprint;
  final DateTime syncedAt;

  Map<String, Object?> toRow() => {
        'day': day,
        'account_key': accountKey,
        'fingerprint': fingerprint,
        'synced_at_ms': syncedAt.millisecondsSinceEpoch,
      };

  static SyncReceipt fromRow(Map<String, Object?> m) => SyncReceipt(
        day: m['day'] as String,
        accountKey: m['account_key'] as String,
        fingerprint: m['fingerprint'] as String,
        syncedAt: DateTime.fromMillisecondsSinceEpoch(m['synced_at_ms'] as int),
      );
}

/// The server (or the contract check) refused this exact aggregate for this
/// account. It is not retried automatically; a changed aggregate has a new
/// fingerprint and gets its own chance, and "retry failed" clears the rows.
class SyncRejection {
  const SyncRejection({
    required this.day,
    required this.accountKey,
    required this.fingerprint,
    required this.error,
    required this.rejectedAt,
  });

  final String day;
  final String accountKey;
  final String fingerprint;

  /// Machine code (`validation`, `invalid_local`, ...); never a message from the user's data.
  final String error;
  final DateTime rejectedAt;

  Map<String, Object?> toRow() => {
        'day': day,
        'account_key': accountKey,
        'fingerprint': fingerprint,
        'error': error,
        'rejected_ms': rejectedAt.millisecondsSinceEpoch,
      };

  static SyncRejection fromRow(Map<String, Object?> m) => SyncRejection(
        day: m['day'] as String,
        accountKey: m['account_key'] as String,
        fingerprint: m['fingerprint'] as String,
        error: m['error'] as String,
        rejectedAt:
            DateTime.fromMillisecondsSinceEpoch(m['rejected_ms'] as int),
      );
}

/// What this phone remembers about ONE account's cloud sync, stored as JSON in
/// `meta` under `sync_account:<accountKey>`.
///
/// Cloud sync is an explicit per-account opt-in on this device: an account that
/// never enabled it here (including a second user of the same phone) has
/// [enabled] false and uploads nothing. Everything else is bookkeeping for the
/// schedule (last success, backoff) so that it survives a restart and never leaks
/// from one account to another.
class AccountSyncState {
  const AccountSyncState({
    required this.key,
    this.enabled = false,
    this.scope,
    this.enabledOn,
    this.lastSuccessMs,
    this.attempts = 0,
    this.limitedFailures = 0,
    this.permanentFailures = 0,
    this.nextRetryMs = 0,
    this.retryDelayMs = 0,
    this.lastError,
    this.halted = false,
  });

  /// The account key this state belongs to (not stored inside the JSON).
  final String key;
  final bool enabled;

  /// Which days may be uploaded; null until sync was enabled once.
  final SyncScope? scope;

  /// Local day (`yyyy-MM-dd`) sync was last enabled; the start of the `fromNow` window.
  final String? enabledOn;

  /// Epoch ms of the last SUCCESSFUL upload (drives the 5-minute throttle).
  final int? lastSuccessMs;

  /// Consecutive failed attempts since the last success (drives the backoff).
  final int attempts;

  /// Consecutive failures of the "limited retry" class (HTTP 5xx and friends).
  final int limitedFailures;

  /// Consecutive uploads the server refused for good (HTTP 400). A changed day gets
  /// its own chance, but a refusal after a refusal is not allowed to repeat forever.
  final int permanentFailures;

  /// Automatic paths do not retry before this instant (0 = none).
  final int nextRetryMs;

  /// The delay [nextRetryMs] was computed with: lets a clock that moved backwards
  /// be detected (the remaining wait can never exceed the delay it was set with).
  final int retryDelayMs;
  final String? lastError;

  /// Gave up after repeated server errors: only a manual retry continues.
  final bool halted;

  AccountSyncState copyWith({
    bool? enabled,
    SyncScope? scope,
    String? enabledOn,
    int? lastSuccessMs,
    bool clearLastSuccess = false,
    int? attempts,
    int? limitedFailures,
    int? permanentFailures,
    int? nextRetryMs,
    int? retryDelayMs,
    String? lastError,
    bool clearError = false,
    bool? halted,
  }) =>
      AccountSyncState(
        key: key,
        enabled: enabled ?? this.enabled,
        scope: scope ?? this.scope,
        enabledOn: enabledOn ?? this.enabledOn,
        lastSuccessMs:
            clearLastSuccess ? null : (lastSuccessMs ?? this.lastSuccessMs),
        attempts: attempts ?? this.attempts,
        limitedFailures: limitedFailures ?? this.limitedFailures,
        permanentFailures: permanentFailures ?? this.permanentFailures,
        nextRetryMs: nextRetryMs ?? this.nextRetryMs,
        retryDelayMs: retryDelayMs ?? this.retryDelayMs,
        lastError: clearError ? null : (lastError ?? this.lastError),
        halted: halted ?? this.halted,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        if (scope != null) 'scope': scope!.name,
        if (enabledOn != null) 'enabledOn': enabledOn,
        if (lastSuccessMs != null) 'lastSuccessMs': lastSuccessMs,
        'attempts': attempts,
        'limitedFailures': limitedFailures,
        'permanentFailures': permanentFailures,
        'nextRetryMs': nextRetryMs,
        'retryDelayMs': retryDelayMs,
        if (lastError != null) 'lastError': lastError,
        'halted': halted,
      };

  /// Tolerant on purpose: an unreadable or foreign value yields the default
  /// (sync off), never an exception and never "on".
  static AccountSyncState fromJson(String key, Object? decoded) {
    if (decoded is! Map) return AccountSyncState(key: key);
    int intOf(String k) => decoded[k] is int ? decoded[k] as int : 0;
    return AccountSyncState(
      key: key,
      enabled: decoded['enabled'] == true,
      scope: SyncScope.values.asNameMap()[decoded['scope']],
      enabledOn: decoded['enabledOn'] is String
          ? decoded['enabledOn'] as String
          : null,
      lastSuccessMs: decoded['lastSuccessMs'] is int
          ? decoded['lastSuccessMs'] as int
          : null,
      attempts: intOf('attempts'),
      limitedFailures: intOf('limitedFailures'),
      permanentFailures: intOf('permanentFailures'),
      nextRetryMs: intOf('nextRetryMs'),
      retryDelayMs: intOf('retryDelayMs'),
      lastError: decoded['lastError'] is String
          ? decoded['lastError'] as String
          : null,
      halted: decoded['halted'] == true,
    );
  }

  @override
  String toString() =>
      'AccountSyncState(enabled: $enabled, scope: ${scope?.name}, attempts: $attempts, halted: $halted)';
}
