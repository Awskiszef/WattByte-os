import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/error_log.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import '../sync/account_key.dart';
import '../sync/daily_aggregate.dart';
import '../sync/sync_models.dart';

/// Local SQLite store. Everything WattByte knows lives here, on the device.
///
/// Times are stored as UTC epoch milliseconds; days as local `yyyy-MM-dd`
/// keys (the user's calendar day is what every screen groups by).
/// Writes are idempotent: days are keyed by date, sessions by start time,
/// sync items by day, so re-running a collection pass never duplicates rows.
class WattByteDb {
  WattByteDb._(this._db);

  final Database _db;

  static const schemaVersion = 5;

  /// Schema changes keyed by the version that introduces them. New installs
  /// run v1 `_create` followed by every migration, so both paths converge.
  static const migrations = <int, List<String>>{
    2: [
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_start ON charging_sessions(start_ms)',
      'CREATE INDEX IF NOT EXISTS idx_sessions_end ON charging_sessions(end_ms)',
      'CREATE INDEX IF NOT EXISTS idx_samples_time ON battery_samples(time_ms)',
      '''
      CREATE TABLE IF NOT EXISTS sync_queue(
        day TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        updated_ms INTEGER NOT NULL)''',
    ],
    3: [
      // Exponential backoff: an item is retried only after this instant (epoch ms).
      'ALTER TABLE sync_queue ADD COLUMN next_retry_ms INTEGER NOT NULL DEFAULT 0',
    ],
    4: [
      // The UI isolate and the background isolate can both record the same reading.
      // Drop existing duplicates first, then make a second insert a no-op.
      'DELETE FROM battery_samples WHERE id NOT IN '
          '(SELECT MIN(id) FROM battery_samples GROUP BY time_ms, source)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_samples_unique ON battery_samples(time_ms, source)',
    ],
    5: [
      // "Synced" stops being a property of the day: a cloud copy belongs to an
      // account only after an upload to THAT account. One row per (day, account);
      // `account_key` is a one-way key (see sync/account_key.dart), never a user id.
      '''
      CREATE TABLE IF NOT EXISTS sync_receipts(
        day TEXT NOT NULL,
        account_key TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        synced_at_ms INTEGER NOT NULL,
        PRIMARY KEY(day, account_key))''',
      // A payload the server (or the contract check) refused, per account.
      '''
      CREATE TABLE IF NOT EXISTS sync_rejections(
        day TEXT NOT NULL,
        account_key TEXT NOT NULL,
        fingerprint TEXT NOT NULL,
        error TEXT NOT NULL,
        rejected_ms INTEGER NOT NULL,
        PRIMARY KEY(day, account_key))''',
      'CREATE INDEX IF NOT EXISTS idx_receipts_account ON sync_receipts(account_key)',
      'CREATE INDEX IF NOT EXISTS idx_rejections_account ON sync_rejections(account_key)',
    ],
  };

  /// Meta keys of the pre-v5 sync bookkeeping. Read only by the v5 migration
  /// (and removed by it); nothing else may rely on them.
  static const legacyMetaQueueUser = 'queue_user_id';
  static const legacyMetaLastSync = 'last_sync_ms';
  static const legacyMetaDevicePrefix = 'server_device_id:';

  /// Set by the v5 migration to the account key of the legacy queue owner until the
  /// old global `wb.cloudSync` preference has been moved to that account.
  static const metaLegacyOwner = 'sync_legacy_owner';
  static const metaInstallationId = 'installation_id';
  static const metaAccountPrefix = 'sync_account:';
  static const metaDevicePrefix = 'server_device_id:';

  static Future<WattByteDb> open({String? path}) async {
    final file = path ?? p.join(await getDatabasesPath(), 'wattbyte.db');
    return _open(file, singleInstance: true);
  }

  /// A private, empty, in-memory database. Unlike `open(path: inMemoryDatabasePath)`
  /// every call returns a NEW database (`singleInstance: false`), so tests can hold
  /// several isolated stores at once. Requires a `databaseFactory` that supports
  /// in-memory databases (`sqflite_common_ffi` in tests).
  static Future<WattByteDb> openInMemory() =>
      _open(inMemoryDatabasePath, singleInstance: false);

  static Future<WattByteDb> _open(String file,
      {required bool singleInstance}) async {
    final db = await openDatabase(
      file,
      version: schemaVersion,
      singleInstance: singleInstance,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _create(db);
        await _upgrade(db, 1, version);
      },
      onUpgrade: _upgrade,
    );
    return WattByteDb._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE daily_data(
        day TEXT PRIMARY KEY,
        mobile_rx INTEGER NOT NULL DEFAULT 0 CHECK (mobile_rx >= 0),
        mobile_tx INTEGER NOT NULL DEFAULT 0 CHECK (mobile_tx >= 0),
        wifi_rx INTEGER NOT NULL DEFAULT 0 CHECK (wifi_rx >= 0),
        wifi_tx INTEGER NOT NULL DEFAULT 0 CHECK (wifi_tx >= 0),
        estimated INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''
      CREATE TABLE battery_samples(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time_ms INTEGER NOT NULL,
        level INTEGER NOT NULL CHECK (level BETWEEN 0 AND 100),
        plugged INTEGER NOT NULL,
        charge_uah INTEGER,
        energy_nwh INTEGER,
        voltage_mv INTEGER,
        source TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE charging_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL CHECK (end_ms >= start_ms),
        start_level INTEGER NOT NULL,
        end_level INTEGER NOT NULL,
        charge_delta_uah INTEGER,
        energy_delta_nwh INTEGER,
        avg_voltage_mv INTEGER,
        sparse INTEGER NOT NULL DEFAULT 0)''');
    await db.execute(
        'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      for (final sql in migrations[v] ?? const <String>[]) {
        await db.execute(sql);
      }
      if (v == 5) await _migrateOwnership(db);
    }
  }

  /// Version 5: "synced" moves from the day to (day, account).
  ///
  /// Before, `sync_queue.state = 'synced'` meant "the server of the queue owner
  /// (`meta.queue_user_id`) has this day". The owner's synced rows become receipts
  /// under the owner's account key (the stored payload's fingerprint), its failed
  /// rows become rejections, the cached server device ids are re-keyed from the raw
  /// user id to the account key, and the legacy fields are removed so that no raw
  /// user id stays behind. The old global `wb.cloudSync` preference lives in
  /// SharedPreferences and is moved by `SyncOwnership.adoptLegacyPreference` using
  /// the [metaLegacyOwner] marker written here. Runs inside the upgrade transaction:
  /// all or nothing.
  static Future<void> _migrateOwnership(Database db) async {
    final meta = {
      for (final r in await db.query('meta'))
        r['key'] as String: r['value'] as String
    };
    final owner = meta[legacyMetaQueueUser];
    final lastSyncMs = int.tryParse(meta[legacyMetaLastSync] ?? '');
    final hasLegacyDevice =
        meta.keys.any((k) => k.startsWith(legacyMetaDevicePrefix));
    var installation = meta[metaInstallationId];
    final needsKeys = (owner != null && owner.isNotEmpty) || hasLegacyDevice;
    if (needsKeys && (installation == null || installation.length < 8)) {
      // Account keys derive from the installation id; one that was never created
      // (nothing was ever uploaded) is created now, exactly as the first upload would.
      final r = Random.secure();
      installation = List.generate(16, (_) => r.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await db.insert(
          'meta', {'key': metaInstallationId, 'value': installation},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final ownerKey = owner != null && owner.isNotEmpty && installation != null
        ? accountKeyFor(installation, owner)
        : null;

    for (final row in await db.query('sync_queue')) {
      final day = row['day'] as String;
      final DailyAggregate payload;
      try {
        payload = DailyAggregate.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>);
      } catch (e, st) {
        // Derived data that cannot be read is dropped (it is rebuilt from
        // daily_data on the next pass) instead of making every start fail.
        reportError(e, st, 'sync queue migration');
        await db.delete('sync_queue', where: 'day = ?', whereArgs: [day]);
        continue;
      }
      if (ownerKey != null) {
        final updated = row['updated_ms'] as int;
        switch (row['state']) {
          case 'synced':
            await db.insert(
                'sync_receipts',
                SyncReceipt(
                  day: day,
                  accountKey: ownerKey,
                  fingerprint: payload.fingerprint,
                  syncedAt: DateTime.fromMillisecondsSinceEpoch(updated),
                ).toRow(),
                conflictAlgorithm: ConflictAlgorithm.replace);
          case 'failed':
            await db.insert(
                'sync_rejections',
                SyncRejection(
                  day: day,
                  accountKey: ownerKey,
                  fingerprint: payload.fingerprint,
                  error: (row['last_error'] as String?) ?? 'failed',
                  rejectedAt: DateTime.fromMillisecondsSinceEpoch(updated),
                ).toRow(),
                conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }
    // The state columns no longer mean anything: normalise them.
    await db.execute("UPDATE sync_queue SET state = 'pending', attempts = 0, "
        'last_error = NULL, next_retry_ms = 0');

    // Cached server device ids: raw user id -> account key.
    if (installation != null) {
      for (final e in meta.entries
          .where((e) => e.key.startsWith(legacyMetaDevicePrefix))) {
        final userId = e.key.substring(legacyMetaDevicePrefix.length);
        if (e.value.isNotEmpty && userId.isNotEmpty) {
          await db.insert(
              'meta',
              {
                'key':
                    '$metaDevicePrefix${accountKeyFor(installation, userId)}',
                'value': e.value
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await db.delete('meta', where: 'key = ?', whereArgs: [e.key]);
      }
    }

    if (ownerKey != null) {
      final state = AccountSyncState(key: ownerKey, lastSuccessMs: lastSyncMs);
      await db.insert(
          'meta',
          {
            'key': '$metaAccountPrefix$ownerKey',
            'value': jsonEncode(state.toJson())
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('meta', {'key': metaLegacyOwner, 'value': ownerKey},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await db.delete('meta',
        where: 'key IN (?, ?)',
        whereArgs: [legacyMetaQueueUser, legacyMetaLastSync]);
  }

  Future<void> close() => _db.close();

  /// The underlying connection, for tests that must look at raw rows (for example to
  /// prove that no user id or e-mail is stored). Production code goes through the
  /// methods of this class.
  @visibleForTesting
  Database get rawDatabase => _db;

  // ---------------------------------------------------------------- daily data

  /// Android: authoritative per-day totals from the system (replace).
  Future<void> replaceDaily(Iterable<DailyData> rows) async {
    final b = _db.batch();
    for (final r in rows) {
      b.insert('daily_data', _dailyToMap(r),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  /// iOS: increments measured between two counter snapshots (add).
  Future<void> addDaily(Iterable<DailyData> rows) async {
    final b = _db.batch();
    for (final r in rows) {
      b.rawInsert(
        'INSERT INTO daily_data(day, mobile_rx, mobile_tx, wifi_rx, wifi_tx, estimated) '
        'VALUES(?, ?, ?, ?, ?, ?) ON CONFLICT(day) DO UPDATE SET '
        'mobile_rx = mobile_rx + excluded.mobile_rx, '
        'mobile_tx = mobile_tx + excluded.mobile_tx, '
        'wifi_rx = wifi_rx + excluded.wifi_rx, '
        'wifi_tx = wifi_tx + excluded.wifi_tx, '
        'estimated = max(estimated, excluded.estimated)',
        [
          dayKey(r.day),
          r.mobileRx,
          r.mobileTx,
          r.wifiRx,
          r.wifiTx,
          r.estimated ? 1 : 0
        ],
      );
    }
    await b.commit(noResult: true);
  }

  Future<List<DailyData>> allDaily() async =>
      (await _db.query('daily_data', orderBy: 'day'))
          .map(_dailyFromMap)
          .toList();

  Future<DateTime?> latestDay() async {
    final rows = await _db.query('daily_data',
        columns: ['day'], orderBy: 'day DESC', limit: 1);
    return rows.isEmpty ? null : parseDayKey(rows.first['day'] as String);
  }

  // ------------------------------------------------------------------- samples

  Future<void> insertSamples(Iterable<BatterySample> samples) async {
    final b = _db.batch();
    for (final s in samples) {
      if (s.level < 0 || s.level > 100) continue;
      b.insert(
          'battery_samples',
          {
            'time_ms': s.time.millisecondsSinceEpoch,
            'level': s.level,
            'plugged': s.plugged ? 1 : 0,
            'charge_uah': s.chargeUah,
            'energy_nwh': s.energyNwh,
            'voltage_mv': s.voltageMv,
            'source': s.source,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await b.commit(noResult: true);
  }

  Future<List<BatterySample>> samples() async =>
      (await _db.query('battery_samples', orderBy: 'time_ms, id'))
          .map((m) => BatterySample(
                time: DateTime.fromMillisecondsSinceEpoch(m['time_ms'] as int),
                level: m['level'] as int,
                plugged: (m['plugged'] as int) == 1,
                chargeUah: m['charge_uah'] as int?,
                energyNwh: m['energy_nwh'] as int?,
                voltageMv: m['voltage_mv'] as int?,
                source: m['source'] as String,
              ))
          .toList();

  Future<void> deleteSamplesBefore(DateTime t) => _db.delete('battery_samples',
      where: 'time_ms < ?', whereArgs: [t.millisecondsSinceEpoch]);

  // ------------------------------------------------------------------ sessions

  /// Idempotent: a session that starts at an already stored instant is skipped.
  Future<void> insertSessions(Iterable<ChargingSession> sessions) async {
    final b = _db.batch();
    for (final s in sessions) {
      b.insert(
        'charging_sessions',
        {
          'start_ms': s.start.millisecondsSinceEpoch,
          'end_ms': s.end.millisecondsSinceEpoch,
          'start_level': s.startLevel,
          'end_level': s.endLevel,
          'charge_delta_uah': s.chargeDeltaUah,
          'energy_delta_nwh': s.energyDeltaNwh,
          'avg_voltage_mv': s.avgVoltageMv,
          'sparse': s.sparse ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await b.commit(noResult: true);
  }

  Future<List<ChargingSession>> allSessions() async =>
      (await _db.query('charging_sessions', orderBy: 'start_ms'))
          .map((m) => ChargingSession(
                id: m['id'] as int,
                start:
                    DateTime.fromMillisecondsSinceEpoch(m['start_ms'] as int),
                end: DateTime.fromMillisecondsSinceEpoch(m['end_ms'] as int),
                startLevel: m['start_level'] as int,
                endLevel: m['end_level'] as int,
                chargeDeltaUah: m['charge_delta_uah'] as int?,
                energyDeltaNwh: m['energy_delta_nwh'] as int?,
                avgVoltageMv: m['avg_voltage_mv'] as int?,
                sparse: (m['sparse'] as int) == 1,
              ))
          .toList();

  // ---------------------------------------------------------------------- meta

  Future<String?> meta(String key) async {
    final rows =
        await _db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) =>
      _db.insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteMeta(String key) =>
      _db.delete('meta', where: 'key = ?', whereArgs: [key]);

  /// Keys that start with [prefix].
  Future<List<String>> metaKeys(String prefix) async {
    final rows = await _db.query('meta',
        columns: ['key'],
        where: 'substr(key, 1, ?) = ?',
        whereArgs: [prefix.length, prefix]);
    return [for (final r in rows) r['key'] as String];
  }

  /// Atomic read-modify-write of one meta value: [change] receives the current
  /// value (null when absent) and returns the new one (null deletes the key).
  /// Used for the per-account sync state, which a running upload and a UI switch
  /// both update: a read and a write that straddled an `await` would silently
  /// undo the other's change.
  Future<String?> mutateMeta(
          String key, String? Function(String? current) change) =>
      _db.transaction((txn) async {
        final rows = await txn.query('meta',
            where: 'key = ?', whereArgs: [key], limit: 1);
        final next =
            change(rows.isEmpty ? null : rows.first['value'] as String);
        if (next == null) {
          await txn.delete('meta', where: 'key = ?', whereArgs: [key]);
        } else {
          await txn.insert('meta', {'key': key, 'value': next},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return next;
      });

  // ---------------------------------------------------------------- sync queue
  //
  // `sync_queue` holds the latest aggregate of each local day. It is DEVICE-LOCAL:
  // no account owns it, it survives sign-out and account switches. What was
  // uploaded, and for whom, lives in `sync_receipts`.

  /// Queued aggregates, oldest day first. [sinceDay] (`yyyy-MM-dd`) keeps only
  /// that day and later ones.
  Future<List<SyncQueueItem>> syncItems(
      {SyncState? state, String? sinceDay}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (state != null) {
      where.add('state = ?');
      args.add(state.name);
    }
    if (sinceDay != null) {
      where.add('day >= ?');
      args.add(sinceDay);
    }
    final rows = await _db.query(
      'sync_queue',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'day',
    );
    return rows.map(SyncQueueItem.fromRow).toList();
  }

  /// Inserts or replaces the item for its day (one row per day).
  Future<void> upsertSyncItem(SyncQueueItem item) =>
      _db.insert('sync_queue', item.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);

  /// Writes several items atomically.
  Future<void> saveSyncItems(Iterable<SyncQueueItem> items) async {
    final b = _db.batch();
    for (final i in items) {
      b.insert('sync_queue', i.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  // ------------------------------------------------------------ sync receipts

  /// Everything uploaded to [accountKey], by day (`yyyy-MM-dd`).
  Future<Map<String, SyncReceipt>> receipts(String accountKey) async {
    final rows = await _db.query('sync_receipts',
        where: 'account_key = ?', whereArgs: [accountKey]);
    return {
      for (final r in rows.map(SyncReceipt.fromRow)) r.day: r,
    };
  }

  Future<int> receiptCount(String accountKey) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM sync_receipts WHERE account_key = ?',
          [accountKey])) ??
      0;

  /// Atomic: all receipts of one accepted upload, or none.
  Future<void> saveReceipts(Iterable<SyncReceipt> receipts) async {
    final b = _db.batch();
    for (final r in receipts) {
      b.insert('sync_receipts', r.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<Map<String, SyncRejection>> rejections(String accountKey) async {
    final rows = await _db.query('sync_rejections',
        where: 'account_key = ?', whereArgs: [accountKey]);
    return {
      for (final r in rows.map(SyncRejection.fromRow)) r.day: r,
    };
  }

  Future<void> saveRejections(Iterable<SyncRejection> rejections) async {
    final b = _db.batch();
    for (final r in rejections) {
      b.insert('sync_rejections', r.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  Future<void> clearRejections(String accountKey) =>
      _db.delete('sync_rejections',
          where: 'account_key = ?', whereArgs: [accountKey]);

  /// Erases everything this phone remembers about one account: its receipts and
  /// rejections, its sync state and its cached server device id ([extraMetaKeys]
  /// for legacy spellings). Local statistics and the sync queue are untouched.
  /// One transaction.
  Future<void> deleteAccountSyncData(String accountKey,
          {Iterable<String> extraMetaKeys = const []}) =>
      _db.transaction((txn) async {
        await txn.delete('sync_receipts',
            where: 'account_key = ?', whereArgs: [accountKey]);
        await txn.delete('sync_rejections',
            where: 'account_key = ?', whereArgs: [accountKey]);
        for (final k in [
          '$metaAccountPrefix$accountKey',
          '$metaDevicePrefix$accountKey',
          ...extraMetaKeys,
        ]) {
          await txn.delete('meta', where: 'key = ?', whereArgs: [k]);
        }
      });

  // --------------------------------------------------------------------- reset

  /// "Reset statistics": erases every statistic and everything derived from it
  /// (daily data, samples, sessions, the sync queue, the upload receipts and
  /// rejections, the interface counters and calibration in `meta`).
  ///
  /// Kept on purpose: the installation id and the per-account sync state and
  /// device ids. They are consent and identity records, not statistics: wiping them
  /// would silently switch cloud sync off for everyone and register this phone as a
  /// new device in every account.
  Future<void> resetAll() => _db.transaction((txn) async {
        for (final t in [
          'daily_data',
          'battery_samples',
          'charging_sessions',
          'sync_queue',
          'sync_receipts',
          'sync_rejections',
        ]) {
          await txn.delete(t);
        }
        await txn.delete('meta',
            where: 'key != ? AND key != ? AND substr(key, 1, ?) != ? '
                'AND substr(key, 1, ?) != ?',
            whereArgs: [
              metaInstallationId,
              metaLegacyOwner,
              metaAccountPrefix.length,
              metaAccountPrefix,
              metaDevicePrefix.length,
              metaDevicePrefix,
            ]);
      });

  static Map<String, Object?> _dailyToMap(DailyData r) => {
        'day': dayKey(r.day),
        'mobile_rx': r.mobileRx,
        'mobile_tx': r.mobileTx,
        'wifi_rx': r.wifiRx,
        'wifi_tx': r.wifiTx,
        'estimated': r.estimated ? 1 : 0,
      };

  static DailyData _dailyFromMap(Map<String, Object?> m) => DailyData(
        day: parseDayKey(m['day'] as String),
        mobileRx: m['mobile_rx'] as int,
        mobileTx: m['mobile_tx'] as int,
        wifiRx: m['wifi_rx'] as int,
        wifiTx: m['wifi_tx'] as int,
        estimated: (m['estimated'] as int) == 1,
      );
}
