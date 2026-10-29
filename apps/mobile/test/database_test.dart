import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';
import 'package:wattbyte/sync/sync_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  BatterySample sample(int ms, {String source = 'app', int level = 50}) =>
      BatterySample(
          time: DateTime.fromMillisecondsSinceEpoch(ms),
          level: level,
          plugged: true,
          source: source);

  test('the same reading recorded by two isolates is stored once', () async {
    final db = await WattByteDb.open(path: inMemoryDatabasePath);
    addTearDown(db.close);
    await db.insertSamples([sample(1000), sample(2000)]);
    await db.insertSamples(
        [sample(1000), sample(3000), sample(1000, source: 'worker')]);
    final all = await db.samples();
    expect(all.map((s) => s.time.millisecondsSinceEpoch),
        [1000, 1000, 2000, 3000]);
    expect(all.where((s) => s.source == 'worker'), hasLength(1));
  });

  test(
      'upgrading a v3 database removes duplicate samples and keeps everything else',
      () async {
    const path = '${inMemoryDatabasePath}_upgrade';
    await deleteDatabase(
        path); // a file of an earlier run would be at a newer version
    // Build a v3-shaped database by hand, with duplicates and a queued day.
    final old = await openDatabase(path, version: 3, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE battery_samples(id INTEGER PRIMARY KEY AUTOINCREMENT, time_ms INTEGER NOT NULL, level INTEGER NOT NULL, plugged INTEGER NOT NULL, charge_uah INTEGER, energy_nwh INTEGER, voltage_mv INTEGER, source TEXT NOT NULL)');
      await db.execute(
          'CREATE TABLE daily_data(day TEXT PRIMARY KEY, mobile_rx INTEGER NOT NULL DEFAULT 0, mobile_tx INTEGER NOT NULL DEFAULT 0, wifi_rx INTEGER NOT NULL DEFAULT 0, wifi_tx INTEGER NOT NULL DEFAULT 0, estimated INTEGER NOT NULL DEFAULT 0)');
      await db.execute(
          'CREATE TABLE charging_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, start_level INTEGER NOT NULL, end_level INTEGER NOT NULL, charge_delta_uah INTEGER, energy_delta_nwh INTEGER, avg_voltage_mv INTEGER, sparse INTEGER NOT NULL DEFAULT 0)');
      await db.execute(
          'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.execute(
          "CREATE TABLE sync_queue(day TEXT PRIMARY KEY, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, updated_ms INTEGER NOT NULL, next_retry_ms INTEGER NOT NULL DEFAULT 0)");
      for (final t in [1000, 1000, 2000]) {
        await db.insert('battery_samples',
            {'time_ms': t, 'level': 50, 'plugged': 1, 'source': 'app'});
      }
      await db.insert('daily_data', {'day': '2026-10-12', 'mobile_rx': 7});
      await db.insert('meta', {'key': 'k', 'value': 'v'});
    });
    await old.close();

    final db = await WattByteDb.open(path: path);
    addTearDown(db.close);
    expect((await db.samples()).map((s) => s.time.millisecondsSinceEpoch),
        [1000, 2000]);
    expect((await db.allDaily()).single.mobileRx, 7,
        reason: 'no user data is lost by the upgrade');
    expect(await db.meta('k'), 'v');
    await db.insertSamples([sample(1000)]);
    expect(await db.samples(), hasLength(2));
  });

  group('schema v5: the sync ledger', () {
    SyncReceipt receipt(String day, String key, {String fp = 'f'}) =>
        SyncReceipt(
            day: day,
            accountKey: key,
            fingerprint: fp,
            syncedAt: DateTime.fromMillisecondsSinceEpoch(1000));

    test('receipts are per (day, account); saving again replaces', () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      await db.saveReceipts([
        receipt('2026-10-12', 'a'),
        receipt('2026-10-12', 'b', fp: 'other'),
        receipt('2026-10-13', 'a'),
      ]);
      expect(
          (await db.receipts('a')).keys.toSet(), {'2026-10-12', '2026-10-13'});
      expect((await db.receipts('b')).values.single.fingerprint, 'other');
      await db.saveReceipts([receipt('2026-10-12', 'a', fp: 'new')]);
      expect((await db.receipts('a'))['2026-10-12']!.fingerprint, 'new');
      expect(await db.receiptCount('a'), 2);
      expect(await db.receiptCount('nobody'), 0);
    });

    test('rejections are per (day, account) and can be cleared per account',
        () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      SyncRejection rej(String day, String key) => SyncRejection(
          day: day,
          accountKey: key,
          fingerprint: 'f',
          error: 'validation',
          rejectedAt: DateTime.fromMillisecondsSinceEpoch(5));
      await db.saveRejections([rej('2026-10-12', 'a'), rej('2026-10-12', 'b')]);
      await db.clearRejections('a');
      expect(await db.rejections('a'), isEmpty);
      expect(await db.rejections('b'), hasLength(1));
    });

    test(
        'mutateMeta is an atomic read-modify-write: 50 concurrent increments add up',
        () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      await Future.wait([
        for (var i = 0; i < 50; i++)
          db.mutateMeta('n', (v) => '${(int.tryParse(v ?? '') ?? 0) + 1}'),
      ]);
      expect(await db.meta('n'), '50');
      expect(await db.mutateMeta('n', (v) => null), isNull);
      expect(await db.meta('n'), isNull);
    });

    test('metaKeys matches a prefix literally (no LIKE wildcards)', () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      for (final k in ['a_1', 'ab1', 'a%1', 'a_', 'b_1']) {
        await db.setMeta(k, 'v');
      }
      expect(await db.metaKeys('a_'), unorderedEquals(['a_1', 'a_']));
      expect(await db.metaKeys('a%'), ['a%1']);
      expect(await db.metaKeys(''), hasLength(5));
    });

    test('deleteAccountSyncData removes one account only, in one transaction',
        () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      await db.saveReceipts(
          [receipt('2026-10-12', 'a'), receipt('2026-10-12', 'b')]);
      await db.setMeta('sync_account:a', '{}');
      await db.setMeta('sync_account:b', '{}');
      await db.setMeta('server_device_id:a', 'd');
      await db.setMeta('server_device_id:b', 'd');
      await db.setMeta('server_device_id:raw-user', 'd');
      await db.deleteAccountSyncData('a',
          extraMetaKeys: ['server_device_id:raw-user']);
      expect(await db.receiptCount('a'), 0);
      expect(await db.receiptCount('b'), 1);
      expect(await db.metaKeys(''),
          unorderedEquals(['sync_account:b', 'server_device_id:b']));
    });

    test('syncItems(sinceDay) returns that day and later, oldest first',
        () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      for (final d in ['2026-10-10', '2026-10-12', '2026-10-11']) {
        await db.upsertSyncItem(SyncQueueItem(
            day: parseDayKey(d),
            payload: DailyAggregate(
                date: d,
                mobileBytes: 1,
                wifiBytes: 1,
                chargedWh: 0,
                wallWh: 0,
                chargingSessions: 0,
                estimatedCost: 0,
                currency: 'PLN'),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1)));
      }
      expect(
          (await db.syncItems(sinceDay: '2026-10-11'))
              .map((i) => i.payload.date),
          ['2026-10-11', '2026-10-12']);
      expect(await db.syncItems(), hasLength(3));
    });

    test(
        'resetAll erases statistics, queue and receipts but keeps identity and consent',
        () async {
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      await db
          .replaceDaily([DailyData(day: DateTime(2026, 10, 12), mobileRx: 5)]);
      await db.saveReceipts([receipt('2026-10-12', 'a')]);
      for (final k in [
        'installation_id',
        'sync_account:a',
        'server_device_id:a',
        'sync_legacy_owner',
        'iface_counters',
        'calibrated_capacity_mah',
      ]) {
        await db.setMeta(k, 'v');
      }
      await db.resetAll();
      expect(await db.allDaily(), isEmpty);
      expect(await db.receiptCount('a'), 0);
      expect(
          await db.metaKeys(''),
          unorderedEquals([
            'installation_id',
            'sync_account:a',
            'server_device_id:a',
            'sync_legacy_owner',
          ]));
    });

    test('upgrading a v4 database creates the tables and keeps every row',
        () async {
      // (the migration of the ownership rows is covered in sync_ownership_migration_test.dart)
      const path = '${inMemoryDatabasePath}_v4_to_v5';
      await deleteDatabase(path);
      final old = await openDatabase(path, version: 4, onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE battery_samples(id INTEGER PRIMARY KEY AUTOINCREMENT, time_ms INTEGER NOT NULL, level INTEGER NOT NULL, plugged INTEGER NOT NULL, charge_uah INTEGER, energy_nwh INTEGER, voltage_mv INTEGER, source TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE daily_data(day TEXT PRIMARY KEY, mobile_rx INTEGER NOT NULL DEFAULT 0, mobile_tx INTEGER NOT NULL DEFAULT 0, wifi_rx INTEGER NOT NULL DEFAULT 0, wifi_tx INTEGER NOT NULL DEFAULT 0, estimated INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE charging_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, start_level INTEGER NOT NULL, end_level INTEGER NOT NULL, charge_delta_uah INTEGER, energy_delta_nwh INTEGER, avg_voltage_mv INTEGER, sparse INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute(
            "CREATE TABLE sync_queue(day TEXT PRIMARY KEY, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, updated_ms INTEGER NOT NULL, next_retry_ms INTEGER NOT NULL DEFAULT 0)");
        await db.insert('daily_data', {'day': '2026-10-12', 'mobile_rx': 7});
        await db.insert('meta', {'key': 'k', 'value': 'v'});
      });
      await old.close();
      final db = await WattByteDb.open(path: path);
      addTearDown(db.close);
      expect((await db.allDaily()).single.mobileRx, 7);
      expect(await db.meta('k'), 'v');
      await db.saveReceipts([receipt('2026-10-12', 'a')]);
      expect(await db.receiptCount('a'), 1);
    });
  });

  group(
      'the database opens even with duplicate sessions from an old build (F-17)',
      () {
    test(
        'upgrading v1 keeps the first of two sessions with the same start and builds the unique index',
        () async {
      const path = '${inMemoryDatabasePath}_dup_sessions';
      await deleteDatabase(path);
      final old = await openDatabase(path, version: 1, onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE battery_samples(id INTEGER PRIMARY KEY AUTOINCREMENT, time_ms INTEGER NOT NULL, level INTEGER NOT NULL, plugged INTEGER NOT NULL, charge_uah INTEGER, energy_nwh INTEGER, voltage_mv INTEGER, source TEXT NOT NULL)');
        await db.execute(
            'CREATE TABLE daily_data(day TEXT PRIMARY KEY, mobile_rx INTEGER NOT NULL DEFAULT 0, mobile_tx INTEGER NOT NULL DEFAULT 0, wifi_rx INTEGER NOT NULL DEFAULT 0, wifi_tx INTEGER NOT NULL DEFAULT 0, estimated INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE charging_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, start_level INTEGER NOT NULL, end_level INTEGER NOT NULL, charge_delta_uah INTEGER, energy_delta_nwh INTEGER, avg_voltage_mv INTEGER, sparse INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        for (final end in [5000, 9000, 7000]) {
          await db.insert('charging_sessions', {
            'start_ms': 1000,
            'end_ms': end,
            'start_level': 20,
            'end_level': 80,
          });
        }
        await db.insert('charging_sessions', {
          'start_ms': 20000,
          'end_ms': 30000,
          'start_level': 10,
          'end_level': 50
        });
      });
      await old.close();

      final db = await WattByteDb.open(path: path);
      addTearDown(db.close);
      final sessions = await db.allSessions();
      expect(
          sessions.map((s) => s.start.millisecondsSinceEpoch), [1000, 20000]);
      expect(sessions.first.end.millisecondsSinceEpoch, 5000,
          reason: 'the first one is kept');
      await db.insertSessions([
        ChargingSession(
            start: DateTime.fromMillisecondsSinceEpoch(1000),
            end: DateTime.fromMillisecondsSinceEpoch(2000),
            startLevel: 1,
            endLevel: 2)
      ]);
      expect(await db.allSessions(), hasLength(2),
          reason: 'a second insert of the same start is a no-op');
    });
  });
}
