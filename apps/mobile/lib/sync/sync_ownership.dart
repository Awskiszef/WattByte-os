// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:math';

import '../core/periods.dart';
import '../storage/database.dart';
import 'account_key.dart';
import 'sync_models.dart';

/// What this phone knows about WHO has WHAT in the cloud.
///
/// * Local history (daily data, sessions, queue payloads) is device-local and owned
///   by nobody.
/// * Everything account-specific (upload receipts, rejected payloads, the sync
///   switch and its scope, the schedule, the cached server device id) is stored
///   under an [accountKey]: `sha256(installationId + ':' + userId)`, 32 hex digits.
///   The user id and the e-mail never appear in these records.
///
/// All state mutations are atomic read-modify-writes (`WattByteDb.mutateMeta`), so
/// an upload finishing while the user flips the switch can never undo the switch.
///
/// See `docs/SYNC_OWNERSHIP.md`.
class SyncOwnership {
  SyncOwnership(this._db);

  final WattByteDb _db;

  static const _accountPrefix = WattByteDb.metaAccountPrefix;
  static const _devicePrefix = WattByteDb.metaDevicePrefix;

  /// Random per-installation id (128 bits). No IMEI, MAC, advertising id or hardware
  /// fingerprint. Created once, atomically, even when two callers ask at once.
  Future<String> installationId() async {
    final id = await _db.mutateMeta(WattByteDb.metaInstallationId, (current) {
      if (current != null && current.length >= 8) return current;
      final r = Random.secure();
      return List.generate(16, (_) => r.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    });
    return id!;
  }

  Future<String> accountKey(String userId) async =>
      accountKeyFor(await installationId(), userId);

  // ------------------------------------------------------------- account state

  static AccountSyncState _parse(String key, String? json) {
    if (json == null) return AccountSyncState(key: key);
    try {
      return AccountSyncState.fromJson(key, jsonDecode(json));
    } on FormatException {
      // A damaged record must never read as "sync on".
      return AccountSyncState(key: key);
    }
  }

  /// The stored state of [key]; the default (sync OFF) for an account that never
  /// enabled sync on this phone.
  Future<AccountSyncState> state(String key) async =>
      _parse(key, await _db.meta('$_accountPrefix$key'));

  /// Applies [change] to the stored state atomically and returns the result.
  Future<AccountSyncState> update(String key,
      AccountSyncState Function(AccountSyncState current) change) async {
    late AccountSyncState result;
    await _db.mutateMeta('$_accountPrefix$key', (json) {
      result = change(_parse(key, json));
      return jsonEncode(result.toJson());
    });
    return result;
  }

  /// Switches sync on for [key]. [scope] is required on purpose: there is no default
  /// that silently uploads a phone's history to an account.
  ///
  /// `fromNow` starts the window today; `history` makes every local day eligible.
  /// Enabling again with the same scope changes nothing (the window does not slide);
  /// widening `fromNow` to `history` keeps the original enable day. The schedule
  /// (backoff, halt) is reset: the user just asked for sync.
  Future<AccountSyncState> enable(String key, SyncScope scope, DateTime now) {
    return update(key, (s) {
      final String enabledOn;
      if (s.enabled && s.scope == scope && s.enabledOn != null) {
        enabledOn = s.enabledOn!;
      } else if (scope == SyncScope.history &&
          s.enabled &&
          s.enabledOn != null) {
        enabledOn = s.enabledOn!;
      } else {
        enabledOn = dayKey(now);
      }
      return s.copyWith(
        enabled: true,
        scope: scope,
        enabledOn: enabledOn,
        attempts: 0,
        limitedFailures: 0,
        permanentFailures: 0,
        nextRetryMs: 0,
        retryDelayMs: 0,
        halted: false,
        clearError: true,
      );
    });
  }

  /// Switches sync off for [key]. Receipts stay: signing in again and enabling sync
  /// uploads only what changed since.
  Future<AccountSyncState> disable(String key) =>
      update(key, (s) => s.copyWith(enabled: false));

  // -------------------------------------------------------------- device ids

  Future<String?> deviceId(String key) async {
    final v = await _db.meta('$_devicePrefix$key');
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> saveDeviceId(String key, String id) =>
      _db.setMeta('$_devicePrefix$key', id);

  Future<void> clearDeviceId(String key) =>
      _db.deleteMeta('$_devicePrefix$key');

  // ------------------------------------------------------------ account delete

  /// The account of [userId] was deleted: remove its receipts, rejections, sync
  /// state and cached server device id, and any legacy record that still names the
  /// raw user id. Local statistics, sessions and the sync queue are untouched
  /// (device-local data survives).
  Future<void> forgetUser(String userId) async {
    final installation = await _db.meta(WattByteDb.metaInstallationId);
    final legacyKeys = <String>['${WattByteDb.legacyMetaDevicePrefix}$userId'];
    if (await _db.meta(WattByteDb.legacyMetaQueueUser) == userId) {
      legacyKeys
        ..add(WattByteDb.legacyMetaQueueUser)
        ..add(WattByteDb.legacyMetaLastSync);
    }
    if (installation == null || installation.length < 8) {
      for (final k in legacyKeys) {
        await _db.deleteMeta(k);
      }
      return;
    }
    final key = accountKeyFor(installation, userId);
    await _db.deleteAccountSyncData(key, extraMetaKeys: legacyKeys);
    if (await _db.meta(WattByteDb.metaLegacyOwner) == key) {
      await _db.deleteMeta(WattByteDb.metaLegacyOwner);
    }
  }

  // ---------------------------------------------------------- legacy migration

  /// Moves the old global `wb.cloudSync` preference to the account that owned the
  /// legacy queue (`WattByteDb` v5 migration leaves its key in `sync_legacy_owner`).
  ///
  /// * flag on + known owner: that account gets sync enabled with scope `history`
  ///   (what the switch always meant), nobody else does;
  /// * flag off, or no owner to attribute it to: nothing is enabled. A consent that
  ///   cannot be tied to an account is not carried over.
  ///
  /// The caller deletes the preference afterwards. Idempotent: the marker is
  /// removed, a second call finds nothing to do.
  Future<void> adoptLegacyPreference({
    required bool legacyEnabled,
    required DateTime now,
  }) async {
    final owner = await _db.meta(WattByteDb.metaLegacyOwner);
    if (owner != null && legacyEnabled) {
      await update(
          owner,
          (s) => s.copyWith(
                enabled: true,
                scope: SyncScope.history,
                enabledOn: dayKey(now),
              ));
    }
    if (owner != null) await _db.deleteMeta(WattByteDb.metaLegacyOwner);
  }
}
