import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/core/error_log.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/account_key.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_ownership.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'sync_support.dart';

/// Schema v5 and the move from "synced is a property of the day" to receipts per
/// account: an install that already has `sync_queue.state = 'synced'` rows, the
/// queue owner in `meta.queue_user_id` and the one global `wb.cloudSync` flag.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const installation = 'abcdef0123456789abcdef0123456789';
  final ownerKey = accountKeyFor(installation, 'user-a');
  final otherKey = accountKeyFor(installation, 'user-b');

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wb_migration_');
    path = '${dir.path}/wattbyte.db';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String payload(String date, {int mobile = 100}) =>
      jsonEncode(agg(date, mobile: mobile).toJson());

  /// A database exactly as app version <= 4 left it, with real rows.
  Future<void> buildV4({
    bool withOwner = true,
    bool withQueue = true,
  }) async {
    final old = await openDatabase(path, version: 4, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE daily_data(day TEXT PRIMARY KEY, mobile_rx INTEGER NOT NULL DEFAULT 0, mobile_tx INTEGER NOT NULL DEFAULT 0, wifi_rx INTEGER NOT NULL DEFAULT 0, wifi_tx INTEGER NOT NULL DEFAULT 0, estimated INTEGER NOT NULL DEFAULT 0)');
      await db.execute(
          'CREATE TABLE battery_samples(id INTEGER PRIMARY KEY AUTOINCREMENT, time_ms INTEGER NOT NULL, level INTEGER NOT NULL, plugged INTEGER NOT NULL, charge_uah INTEGER, energy_nwh INTEGER, voltage_mv INTEGER, source TEXT NOT NULL)');
      await db.execute(
          'CREATE TABLE charging_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, start_level INTEGER NOT NULL, end_level INTEGER NOT NULL, charge_delta_uah INTEGER, energy_delta_nwh INTEGER, avg_voltage_mv INTEGER, sparse INTEGER NOT NULL DEFAULT 0)');
      await db.execute(
          'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute(
          "CREATE TABLE sync_queue(day TEXT PRIMARY KEY, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, updated_ms INTEGER NOT NULL, next_retry_ms INTEGER NOT NULL DEFAULT 0)");
      await db.insert('daily_data', {'day': '2026-10-12', 'mobile_rx': 7});
      await db.insert('daily_data', {'day': '2026-10-13', 'mobile_rx': 9});
      await db.insert('charging_sessions', {
        'start_ms': 1000,
        'end_ms': 5000,
        'start_level': 20,
        'end_level': 80
      });
      await db.insert('meta', {'key': 'iface_counters', 'value': 'keep-me'});
      if (withOwner) {
        await db
            .insert('meta', {'key': 'installation_id', 'value': installation});
        await db.insert('meta', {'key': 'queue_user_id', 'value': 'user-a'});
        await db
            .insert('meta', {'key': 'last_sync_ms', 'value': '1791800000000'});
        await db.insert(
            'meta', {'key': 'server_device_id:user-a', 'value': 'srv-dev-9'});
        await db.insert(
            'meta', {'key': 'server_device_id:user-b', 'value': 'srv-dev-7'});
        await db
            .insert('meta', {'key': 'server_device_id:user-c', 'value': ''});
      }
      if (withQueue) {
        Future<void> row(String day, String state,
            {int attempts = 0,
            String? error,
            int next = 0,
            String? raw,
            int mobile = 100}) {
          return db.insert('sync_queue', {
            'day': day,
            'payload': raw ?? payload(day, mobile: mobile),
            'state': state,
            'attempts': attempts,
            'last_error': error,
            'updated_ms': 1791700000000 + attempts,
            'next_retry_ms': next,
          });
        }

        await row('2026-10-08', 'syncing');
        await row('2026-10-09', 'pending',
            attempts: 3, error: 'network', next: 1791999999999);
        await row('2026-10-10', 'synced');
        await row('2026-10-11', 'synced');
        await row('2026-10-12', 'pending',
            mobile: 555); // changed after it was synced
        await row('2026-10-13', 'failed', attempts: 1, error: 'validation');
        await row('2026-10-07', 'synced', raw: '{nope');
      }
    });
    await old.close();
  }

  Future<WattByteDb> openMigrated() => WattByteDb.open(path: path);

  test('schema version 5 with the ledger tables', () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    expect(WattByteDb.schemaVersion, 5);
    expect(await db.rawDatabase.getVersion(), 5);
    for (final t in ['sync_receipts', 'sync_rejections']) {
      expect(
          await db.rawDatabase.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
              [t]),
          hasLength(1),
          reason: t);
    }
  });

  test(
      'the owner\'s synced rows become receipts with the stored payload\'s fingerprint',
      () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    final receipts = await db.receipts(ownerKey);
    expect(receipts.keys.toSet(), {'2026-10-10', '2026-10-11'});
    expect(receipts['2026-10-10']!.fingerprint, agg('2026-10-10').fingerprint);
    expect(receipts['2026-10-11']!.fingerprint, agg('2026-10-11').fingerprint);
    expect(receipts['2026-10-10']!.syncedAt,
        DateTime.fromMillisecondsSinceEpoch(1791700000000));
    // Nobody else owns anything.
    expect(await db.receiptCount(otherKey), 0);
    // The failed row is a rejection, not a retry.
    final rejections = await db.rejections(ownerKey);
    expect(rejections.keys, ['2026-10-13']);
    expect(rejections['2026-10-13']!.error, 'validation');
    expect(
        rejections['2026-10-13']!.fingerprint, agg('2026-10-13').fingerprint);
  });

  test(
      'the queue payloads stay (device-local), their state columns are normalised',
      () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    final items = await db.syncItems();
    expect(
        items.map((i) => i.payload.date),
        [
          '2026-10-08',
          '2026-10-09',
          '2026-10-10',
          '2026-10-11',
          '2026-10-12',
          '2026-10-13',
        ],
        reason: 'the unreadable payload was dropped, nothing else');
    expect(items.every((i) => i.state == SyncState.pending), isTrue);
    expect(items.every((i) => i.attempts == 0 && i.lastError == null), isTrue);
    expect(items.every((i) => i.nextRetryAt == null), isTrue);
    expect(
        items
            .firstWhere((i) => i.payload.date == '2026-10-12')
            .payload
            .mobileBytes,
        555);
    expect(recentErrors.any((e) => e.contains('sync queue migration')), isTrue,
        reason: 'dropping the unreadable row is recorded, not silent');
  });

  test('local statistics and unrelated meta survive untouched', () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    expect((await db.allDaily()).map((d) => d.mobileRx), [7, 9]);
    expect(await db.allSessions(), hasLength(1));
    expect(await db.meta('iface_counters'), 'keep-me');
    expect(await db.meta('installation_id'), installation);
  });

  test('legacy meta is re-keyed and removed: no raw user id remains', () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    expect(await db.meta('queue_user_id'), isNull);
    expect(await db.meta('last_sync_ms'), isNull);
    expect(await db.meta('server_device_id:user-a'), isNull);
    expect(await db.meta('server_device_id:user-b'), isNull);
    expect(await db.meta('server_device_id:user-c'), isNull);
    expect(await db.meta('server_device_id:$ownerKey'), 'srv-dev-9');
    expect(await db.meta('server_device_id:$otherKey'), 'srv-dev-7');
    expect(
        await db
            .meta('server_device_id:${accountKeyFor(installation, 'user-c')}'),
        isNull,
        reason: 'an empty cached id means "none"');
    final dump = jsonEncode({
      for (final t in ['meta', 'sync_receipts', 'sync_rejections'])
        t: await db.rawDatabase.query(t)
    });
    expect(dump, isNot(contains('user-a')));
    expect(dump, isNot(contains('user-b')));
  });

  test(
      'the owner keeps its last success time (throttle survives the upgrade) but is not yet enabled',
      () async {
    await buildV4();
    final db = await openMigrated();
    addTearDown(db.close);
    final st = await SyncOwnership(db).state(ownerKey);
    expect(st.lastSuccessMs, 1791800000000);
    expect(st.enabled, isFalse,
        reason: 'the consent is in SharedPreferences and is moved separately');
    expect(await db.meta('sync_legacy_owner'), ownerKey);
  });

  group('the global wb.cloudSync flag moves to the queue owner', () {
    test('flag ON: the owner is enabled with scope history, nobody else',
        () async {
      await buildV4();
      SharedPreferences.setMockInitialValues({'wb.cloudSync': true});
      final store = SettingsStore(await SharedPreferences.getInstance());
      expect(store.legacyCloudSync, isTrue);
      final db = await openMigrated();
      addTearDown(db.close);
      final ownership = SyncOwnership(db);
      await ownership.adoptLegacyPreference(
          legacyEnabled: store.legacyCloudSync ?? false,
          now: DateTime(2026, 10, 13, 12));
      final st = await ownership.state(ownerKey);
      expect(st.enabled, isTrue);
      expect(st.scope, SyncScope.history);
      expect(st.lastSuccessMs, 1791800000000, reason: 'bookkeeping is kept');
      expect((await ownership.state(otherKey)).enabled, isFalse);
      expect(await db.meta('sync_legacy_owner'), isNull,
          reason: 'consumed: it happens once');
      // Idempotent: a second call changes nothing, and does not re-enable.
      await ownership.disable(ownerKey);
      await ownership.adoptLegacyPreference(
          legacyEnabled: true, now: DateTime(2026, 10, 14));
      expect((await ownership.state(ownerKey)).enabled, isFalse);
    });

    test('flag OFF: nobody is enabled', () async {
      await buildV4();
      final db = await openMigrated();
      addTearDown(db.close);
      final ownership = SyncOwnership(db);
      await ownership.adoptLegacyPreference(
          legacyEnabled: false, now: DateTime(2026, 10, 13));
      expect((await ownership.state(ownerKey)).enabled, isFalse);
      expect(await db.meta('sync_legacy_owner'), isNull);
    });

    test('flag ON but no queue owner to attribute it to: nobody is enabled',
        () async {
      await buildV4(withOwner: false, withQueue: false);
      final db = await openMigrated();
      addTearDown(db.close);
      expect(await db.meta('sync_legacy_owner'), isNull);
      final ownership = SyncOwnership(db);
      await ownership.adoptLegacyPreference(
          legacyEnabled: true, now: DateTime(2026, 10, 13));
      expect(await db.metaKeys('sync_account:'), isEmpty);
    });

    test(
        'end to end after the upgrade: only the delta goes up, only for the owner',
        () async {
      await buildV4();
      final db = await openMigrated();
      final rig = await SyncRig.create(signedInAs: 'user-a', db: db);
      addTearDown(rig.close);
      await SyncOwnership(db).adoptLegacyPreference(
          legacyEnabled: true, now: DateTime(2026, 10, 13, 12));
      final o = await rig.sync.syncNow();
      expect(o.status, SyncStatus.synced);
      final sent = rig.backend
          .where('POST', '/api/v1/usage/sync')
          .expand((r) => (r.body!['days'] as List).map((d) => d['date']))
          .toList();
      expect(sent, ['2026-10-08', '2026-10-09', '2026-10-12'],
          reason: 'synced days (10, 11) are not uploaded again, the rejected '
              'day (13) is not retried, the changed day (12) and the '
              'unfinished ones (8, 9) are');
      // The registration was NOT repeated: the legacy device id was carried over.
      expect(rig.backend.where('POST', '/api/v1/devices'), isEmpty);
      expect(rig.backend.where('POST', '/api/v1/usage/sync').single.bearer,
          'access-user-a');

      // Another user of the phone: sync stays off, nothing leaves.
      await rig.signOut();
      await rig.signIn('user-b');
      rig.backend.requests.clear();
      expect((await rig.sync.syncNow()).skip, SyncSkip.notEnabled);
      expect(rig.backend.requests, isEmpty);
    });
  });

  test('migrating twice (open again) changes nothing', () async {
    await buildV4();
    var db = await openMigrated();
    final before = jsonEncode({
      for (final t in [
        'meta',
        'sync_receipts',
        'sync_rejections',
        'sync_queue'
      ])
        t: await db.rawDatabase.query(t, orderBy: t == 'meta' ? 'key' : 'day')
    });
    await db.close();
    db = await openMigrated();
    addTearDown(db.close);
    final after = jsonEncode({
      for (final t in [
        'meta',
        'sync_receipts',
        'sync_rejections',
        'sync_queue'
      ])
        t: await db.rawDatabase.query(t, orderBy: t == 'meta' ? 'key' : 'day')
    });
    expect(after, before);
  });

  test(
      'a fresh install and an empty v4 database both end up at v5 without ledger rows',
      () async {
    final fresh = await WattByteDb.openInMemory();
    addTearDown(fresh.close);
    expect(await fresh.rawDatabase.getVersion(), 5);
    expect(await fresh.metaKeys(''), isEmpty,
        reason: 'no installation id is invented when nothing was ever synced');

    await buildV4(withOwner: false, withQueue: false);
    final db = await openMigrated();
    addTearDown(db.close);
    expect(await db.receiptCount(ownerKey), 0);
    expect(await db.metaKeys('sync_'), isEmpty);
    expect(await db.metaKeys('server_device_id:'), isEmpty);
    expect(await db.meta('installation_id'), isNull);
  });

  test('two in-memory databases are isolated from each other', () async {
    final a = await WattByteDb.openInMemory();
    final b = await WattByteDb.openInMemory();
    addTearDown(a.close);
    addTearDown(b.close);
    await a.setMeta('k', 'a');
    expect(await b.meta('k'), isNull);
  });
}
