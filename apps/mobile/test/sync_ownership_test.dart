import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/account_key.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';
import 'package:wattbyte/sync/sha256.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';
import 'sync_support.dart';

/// The ownership policy (docs/SYNC_OWNERSHIP.md), one test per rule:
///
///  1. local history is device-local and survives sign-out and switches
///  2. a receipt exists per (day, account), written only after an upload to that account
///  3. cloud sync is an explicit per-account opt-in, default OFF for everybody
///  4. switch / logout / restore never marks, requeues or uploads for another account;
///     results arriving after the account changed are dropped
///  5. deleting an account removes everything this phone knows about it
void main() {
  late SyncRig rig;

  setUp(() async => rig = await SyncRig.create());
  tearDown(() => rig.close());

  Future<void> asUser(String id) async {
    await rig.signOut();
    await rig.signIn(id);
  }

  group('3: sync is a per-account opt-in, default OFF', () {
    test(
        'a second user of the same phone never inherits the first user\'s sync',
        () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 7);

      await asUser('user-b');
      final st = (await rig.sync.accountState())!;
      expect(st.enabled, isFalse);
      expect(st.scope, isNull);
      expect(await rig.sync.isEnabled(), isFalse);
      rig.backend.requests.clear();
      for (final run in [rig.sync.syncNow, rig.sync.syncIfDue]) {
        final o = await run();
        expect(o.status, SyncStatus.idle);
        expect(o.skip, SyncSkip.notEnabled);
      }
      expect(rig.backend.requests, isEmpty,
          reason: 'B must not upload anything, not even a device registration');
      expect(rig.cloud.datesOf('user-b'), isEmpty);
      expect(await rig.receiptsOf('user-b'), isEmpty);
    });

    test('scope fromNow uploads only days from the enable day on', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.fromNow);
      final o = await rig.sync.syncNow();
      expect(o.uploaded, 1);
      expect(rig.cloud.datesOf('user-a'), ['2026-10-13']);

      // The window starts at the enable day and does not move on a repeated enable.
      rig.advance(const Duration(days: 2));
      await rig.sync.enable(SyncScope.fromNow);
      expect((await rig.sync.accountState())!.enabledOn, '2026-10-13');
    });

    test('scope history makes every local day eligible', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 7);
      expect(rig.cloud.datesOf('user-a'), sevenDays());
    });

    test('widening fromNow to history keeps the original enable day', () async {
      await rig.sync.enable(SyncScope.fromNow);
      rig.advance(const Duration(days: 3));
      await rig.sync.enable(SyncScope.history);
      final st = (await rig.sync.accountState())!;
      expect(st.scope, SyncScope.history);
      expect(st.enabledOn, '2026-10-13');
    });

    test('daysWithoutReceipt counts local days older than the enable day',
        () async {
      final local = [for (final d in sevenDays()) agg(d)];
      // Before enabling: relative to today.
      expect(await rig.sync.daysWithoutReceipt(local), 6,
          reason: 'six days are older than today, none has a receipt');
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.fromNow);
      await rig.sync.syncNow(); // uploads today only
      expect(await rig.sync.daysWithoutReceipt(local), 6);
      // Once the history is uploaded there is nothing left to offer.
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      expect(await rig.sync.daysWithoutReceipt(local), 0);
      // Another account has none of it.
      await asUser('user-b');
      expect(await rig.sync.daysWithoutReceipt(local), 6);
      // Signed out: nothing to ask.
      await rig.signOut();
      expect(await rig.sync.daysWithoutReceipt(local), 0);
    });

    test('empty and invalid days are not counted as missing history', () async {
      const empty = DailyAggregate(
          date: '2026-10-11',
          mobileBytes: 0,
          wifiBytes: 0,
          chargedWh: 0,
          wallWh: 0,
          chargingSessions: 0,
          estimatedCost: 0,
          currency: 'PLN');
      final local = [
        agg('2026-10-10'),
        empty,
        agg('2026-10-12', wh: 1e9),
      ];
      expect(await rig.sync.daysWithoutReceipt(local), 1);
    });

    test('the choice survives an app restart', () async {
      await rig.sync.enable(SyncScope.history);
      final restarted = rig.restart();
      final st = (await restarted.accountState())!;
      expect(st.enabled, isTrue);
      expect(st.scope, SyncScope.history);
    });

    test('disable stops uploads at once but keeps the receipts', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      await rig.sync.disable();
      await rig.queue(agg('2026-10-13', mobile: 4242));
      rig.backend.requests.clear();
      expect((await rig.sync.syncNow()).skip, SyncSkip.notEnabled);
      expect(rig.backend.requests, isEmpty);
      expect(await rig.db.receiptCount(await rig.keyOf('user-a')), 7);

      // Enabling again uploads only the delta, not the history again.
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 1);
      expect(
          rig.cloud.rowsByUser['user-a']!['2026-10-13']!['mobileBytes'], 4242);
    });

    test('a damaged state record reads as "sync off", never "on"', () async {
      await rig.sync.enable(SyncScope.history);
      final key = await rig.keyOf('user-a');
      await rig.db.setMeta('sync_account:$key', '{not json');
      expect((await rig.sync.accountState())!.enabled, isFalse);
      await rig.db.setMeta('sync_account:$key', '[1,2]');
      expect((await rig.sync.accountState())!.enabled, isFalse);
      await rig.db.setMeta('sync_account:$key', '{"enabled":"yes"}');
      expect((await rig.sync.accountState())!.enabled, isFalse);
    });
  });

  group('2: receipts per (day, account)', () {
    test('the same day is tracked separately for every account', () async {
      await rig.queueDays(['2026-10-12']);
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      await asUser('user-b');
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 1,
          reason: 'A\'s receipt says nothing about B');
      final a = await rig.receiptsOf('user-a');
      final b = await rig.receiptsOf('user-b');
      expect(a.single.accountKey, isNot(b.single.accountKey));
      expect(a.single.fingerprint, b.single.fingerprint);
    });

    test('a receipt is written only after the server accepted the upload',
        () async {
      await rig.queueDays(['2026-10-12']);
      await rig.sync.enable(SyncScope.history);
      rig.backend.offline = true;
      await rig.sync.syncNow();
      expect(await rig.receiptsOf('user-a'), isEmpty);
      rig.backend.offline = false;
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(500, 'boom');
      await rig.sync.syncNow();
      expect(await rig.receiptsOf('user-a'), isEmpty);
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(400, 'validation');
      await rig.sync.syncNow();
      expect(await rig.receiptsOf('user-a'), isEmpty);
    });

    test(
        'the walk-through: A history, logout, B on the same database, back to A',
        () async {
      await rig.queueDays(sevenDays());

      // A opts in with history: seven rows.
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 7);
      final aRows = {...?rig.cloud.rowsByUser['user-a']};
      expect(aRows, hasLength(7));

      // Logout: receipts stay.
      await rig.signOut();
      expect(await rig.db.receiptCount(await rig.keyOf('user-a')), 7);

      // B signs in on the SAME local database: nothing is uploaded, nothing is marked.
      await rig.signIn('user-b');
      rig.backend.requests.clear();
      expect((await rig.sync.syncNow()).skip, SyncSkip.notEnabled);
      expect(rig.backend.requests, isEmpty);
      expect(rig.cloud.datesOf('user-b'), isEmpty);
      expect(await rig.receiptsOf('user-b'), isEmpty);

      // B chooses "from now": only today.
      await rig.sync.enable(SyncScope.fromNow);
      expect((await rig.sync.syncNow()).uploaded, 1);
      expect(rig.cloud.datesOf('user-b'), ['2026-10-13']);

      // B then chooses the history: the other six days.
      await rig.sync.enable(SyncScope.history);
      expect((await rig.sync.syncNow()).uploaded, 6);
      expect(rig.cloud.datesOf('user-b'), sevenDays());

      // A's rows are exactly what they were.
      expect(rig.cloud.rowsByUser['user-a'], aRows);

      // A signs in again: fingerprints match, zero uploads.
      await asUser('user-a');
      rig.backend.requests.clear();
      final o = await rig.sync.syncNow();
      expect(o.uploaded, 0);
      expect(o.skip, SyncSkip.nothingDue);
      expect(rig.backend.requests, isEmpty);

      // One changed day: exactly one upload for each account that has sync enabled.
      await rig.queue(agg('2026-10-10', mobile: 7777));
      expect((await rig.sync.syncNow()).uploaded, 1);
      await asUser('user-b');
      expect((await rig.sync.syncNow()).uploaded, 1);
      await asUser('user-a');
      expect((await rig.sync.syncNow()).uploaded, 0);
      final changed = rig.cloud.uploads
          .where((u) => u.dates.length == 1 && u.dates.single == '2026-10-10')
          .map((u) => u.user);
      expect(changed.toList()..sort(), ['user-a', 'user-b']);
      expect(
          rig.cloud.rowsByUser['user-a']!['2026-10-10']!['mobileBytes'], 7777);
      expect(
          rig.cloud.rowsByUser['user-b']!['2026-10-10']!['mobileBytes'], 7777);
    });

    test(
        'an account switch does not requeue or touch the first account\'s receipts',
        () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final before = await rig.receiptsOf('user-a');
      await asUser('user-b');
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final after = await rig.receiptsOf('user-a');
      expect([for (final r in after) (r.day, r.fingerprint, r.syncedAt)],
          [for (final r in before) (r.day, r.fingerprint, r.syncedAt)]);
    });
  });

  group('4: in-flight results of a previous session are dropped', () {
    test('a response that arrives after the account changed writes no receipts',
        () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      final normal = rig.backend.routes['POST /api/v1/usage/sync']!;
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        // The user signs out and B signs in while this request is on the wire.
        rig.sessions.clear();
        rig.sessions.adopt(sessionOf('user-b'));
        final days = (r.body!['days'] as List).cast<Map<String, dynamic>>();
        rig.backend.routes['POST /api/v1/usage/sync'] = normal;
        return FakeBackend.json({
          'accepted': days.length,
          'dates': days.map((d) => d['date']).toList(),
        });
      };
      final o = await rig.sync.syncNow();
      expect(o.status, SyncStatus.idle);
      expect(o.skip, SyncSkip.accountChanged);
      expect(await rig.receiptsOf('user-a'), isEmpty);
      expect(await rig.receiptsOf('user-b'), isEmpty);
      final b = await rig.sync.accountState();
      expect(b!.enabled, isFalse, reason: 'B never opted in');
      expect((await rig.db.rejections(await rig.keyOf('user-a'))), isEmpty);
      expect((await rig.db.rejections(await rig.keyOf('user-b'))), isEmpty);
      // The idempotent upload is simply repeated when A comes back.
      await asUser('user-a');
      expect((await rig.sync.syncNow()).uploaded, 7);
    });

    test('a failure arriving after the account changed records nothing either',
        () async {
      await rig.queueDays(['2026-10-12']);
      await rig.sync.enable(SyncScope.history);
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        rig.sessions.clear();
        rig.sessions.adopt(sessionOf('user-b'));
        return FakeBackend.error(400, 'validation');
      };
      expect((await rig.sync.syncNow()).skip, SyncSkip.accountChanged);
      expect(await rig.db.rejections(await rig.keyOf('user-a')), isEmpty);
    });

    test('a request prepared for A never goes out with B\'s token', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      // The very first request (device registration) is where B takes over.
      rig.backend.routes['POST /api/v1/devices'] = (r) {
        rig.sessions.clear();
        rig.sessions.adopt(sessionOf('user-b'));
        return FakeBackend.json(FakeBackend.device('dev-user-a'), 201);
      };
      final o = await rig.sync.syncNow();
      expect(o.skip, SyncSkip.accountChanged);
      expect(rig.backend.where('POST', '/api/v1/usage/sync'), isEmpty,
          reason: 'the upload must not follow with the new user\'s token');
      expect(rig.backend.requests.where((r) => r.bearer == 'access-user-b'),
          isEmpty);
      expect(
          await rig.sync.ownership.deviceId(await rig.keyOf('user-a')), isNull,
          reason:
              'a device id of a request that crossed an account change is not kept');
    });

    test(
        'an account deleted while its upload is in flight leaves nothing behind',
        () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      Future<void>? forgetting;
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        forgetting = rig.sync.forgetAccount('user-a');
        final days = (r.body!['days'] as List).cast<Map<String, dynamic>>();
        return FakeBackend.json({
          'accepted': days.length,
          'dates': days.map((d) => d['date']).toList(),
        });
      };
      final o = await rig.sync.syncNow();
      await forgetting;
      expect(o.skip, SyncSkip.accountChanged);
      final key = await rig.keyOf('user-a');
      expect(await rig.db.receiptCount(key), 0);
      expect(await rig.db.meta('sync_account:$key'), isNull);
      expect(await rig.db.meta('server_device_id:$key'), isNull);
    });

    test('logout and login of the same user also drop the in-flight result',
        () async {
      await rig.queueDays(['2026-10-12']);
      await rig.sync.enable(SyncScope.history);
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        rig.sessions.clear();
        rig.sessions.adopt(sessionOf('user-a'));
        return FakeBackend.json({
          'accepted': 1,
          'dates': ['2026-10-12']
        });
      };
      expect((await rig.sync.syncNow()).skip, SyncSkip.accountChanged);
      expect(await rig.receiptsOf('user-a'), isEmpty);
    });

    test('a token refresh of the same session does NOT cancel the run',
        () async {
      await rig.queueDays(['2026-10-12']);
      await rig.sync.enable(SyncScope.history);
      var first = true;
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        if (first) {
          first = false;
          return FakeBackend.error(401, 'invalid_token');
        }
        return FakeBackend.json({
          'accepted': 1,
          'dates': ['2026-10-12']
        });
      };
      expect((await rig.sync.syncNow()).status, SyncStatus.synced);
      expect((await rig.receiptsOf('user-a')).single.day, '2026-10-12');
    });
  });

  group('5: deleting an account', () {
    test(
        'removes that account\'s receipts, rejections, state and device id; keeps the rest',
        () async {
      await rig.queueDays(sevenDays());
      await rig.db.replaceDaily(
          [DailyData(day: DateTime(2026, 10, 12), mobileRx: 5, mobileTx: 1)]);
      await rig.db.insertSessions([
        ChargingSession(
            start: DateTime(2026, 10, 12, 22),
            end: DateTime(2026, 10, 13, 6),
            startLevel: 20,
            endLevel: 90)
      ]);
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final keyA = await rig.keyOf('user-a');
      await rig.db.saveRejections([
        SyncRejection(
            day: '2026-10-01',
            accountKey: keyA,
            fingerprint: 'x',
            error: 'validation',
            rejectedAt: rig.now)
      ]);
      // legacy spelling of the cached device id (raw user id) from before v5
      await rig.db.setMeta('server_device_id:user-a', 'legacy-dev');
      await asUser('user-b');
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final bBefore = await rig.receiptsOf('user-b');
      final bState = await rig.sync.accountState();

      await rig.sync.forgetAccount('user-a');

      expect(await rig.db.receiptCount(keyA), 0);
      expect(await rig.db.rejections(keyA), isEmpty);
      expect(await rig.db.meta('sync_account:$keyA'), isNull);
      expect(await rig.db.meta('server_device_id:$keyA'), isNull);
      expect(await rig.db.meta('server_device_id:user-a'), isNull);
      // The next sign-in of that e-mail would be a brand new account: sync off.
      await asUser('user-a');
      expect((await rig.sync.accountState())!.enabled, isFalse);

      // Local data and the other account are untouched.
      expect(await rig.db.allDaily(), hasLength(1));
      expect(await rig.db.allSessions(), hasLength(1));
      expect(await rig.db.syncItems(), hasLength(7));
      await asUser('user-b');
      expect([for (final r in await rig.receiptsOf('user-b')) r.fingerprint],
          [for (final r in bBefore) r.fingerprint]);
      expect((await rig.sync.accountState())!.enabled, bState!.enabled);
    });

    test('forgetting an account that never synced is harmless', () async {
      await rig.sync.forgetAccount('user-z');
      await rig.sync.forgetAccount('user-a');
      expect(await rig.sync.isEnabled(), isFalse);
    });

    test('nothing of the account remains in any table or meta value', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      await rig.sync.registerDevice(_spec);
      await rig.sync.forgetAccount('user-a');
      final dump = await _dumpEverything(rig.db);
      expect(dump, isNot(contains('user-a')));
      expect(dump, isNot(contains('@example.test')));
      expect(dump, isNot(contains(await rig.keyOf('user-a'))));
    });
  });

  group('device registration is per account', () {
    test(
        'the battery facts of this phone go to the signed-in account\'s own '
        'device record, and A\'s record is not touched by B', () async {
      await rig.sync.registerDevice(_spec,
          fullCharge: FullChargeCapacityEstimator.estimate(
              chargeUah: 3600000, level: 100));
      final a = rig.cloud.deviceTable.rowsOf('user-a').single;
      expect(a['designCapacityMah'], 4575);
      expect(a['estimatedFullChargeCapacityMah'], 3600);

      await asUser('user-b');
      expect(rig.cloud.deviceTable.rowsOf('user-b'), isEmpty,
          reason: 'signing in registers nothing by itself');
      // B enables sync: the registration of the sync path carries no battery
      // facts (null keeps whatever a setup registered), and it is B's record.
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final b = rig.cloud.deviceTable.rowsOf('user-b').single;
      for (final key in FakeBackend.batteryKeys) {
        expect(b[key], isNull, reason: key);
      }
      expect(rig.cloud.deviceTable.rowsOf('user-a').single, a,
          reason: 'B never writes into A\'s device record');
    });
  });

  group('ledger privacy', () {
    test('no user id and no e-mail is stored by the sync code', () async {
      await rig.queueDays(sevenDays());
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      await rig.sync.registerDevice(_spec);
      await asUser('user-b');
      await rig.sync.enable(SyncScope.fromNow);
      await rig.sync.syncNow();
      final dump = await _dumpEverything(rig.db);
      for (final secret in [
        'user-a',
        'user-b',
        '@example.test',
        'access-',
        'refresh-'
      ]) {
        expect(dump, isNot(contains(secret)), reason: secret);
      }
    });

    test('account keys: 32 hex, per user, per installation, one-way formula',
        () async {
      final installation = await rig.sync.installationId();
      final a = await rig.keyOf('user-a');
      final b = await rig.keyOf('user-b');
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(b));
      expect(a, await rig.keyOf('user-a'), reason: 'stable');
      expect(a, accountKeyFor(installation, 'user-a'));
      expect(a, sha256Hex('$installation:user-a').substring(0, 32));
      final other = await SyncRig.create();
      addTearDown(other.close);
      expect(await other.keyOf('user-a'), isNot(a),
          reason: 'the same user has another key on another installation');
    });
  });

  group('1: local history is device-local', () {
    test(
        'sign-out and account switches never change local statistics or the queue',
        () async {
      await rig.queueDays(sevenDays());
      await rig.db.replaceDaily(
          [DailyData(day: DateTime(2026, 10, 12), mobileRx: 5, mobileTx: 1)]);
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final queueBefore = [
        for (final i in await rig.db.syncItems())
          (i.payload.date, i.payload.fingerprint)
      ];
      await rig.signOut();
      await rig.signIn('user-b');
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      await rig.signOut();
      expect([
        for (final i in await rig.db.syncItems())
          (i.payload.date, i.payload.fingerprint)
      ], queueBefore);
      expect(await rig.db.allDaily(), hasLength(1));
    });

    test(
        'reset statistics erases the data and receipts but keeps the consent records',
        () async {
      await rig.queueDays(sevenDays());
      await rig.db.replaceDaily(
          [DailyData(day: DateTime(2026, 10, 12), mobileRx: 5, mobileTx: 1)]);
      await rig.db.setMeta('iface_counters', 'x');
      await rig.sync.enable(SyncScope.history);
      await rig.sync.syncNow();
      final installation = await rig.sync.installationId();
      final key = await rig.keyOf('user-a');

      await rig.db.resetAll();

      expect(await rig.db.allDaily(), isEmpty);
      expect(await rig.db.syncItems(), isEmpty);
      expect(await rig.db.receiptCount(key), 0);
      expect(await rig.db.meta('iface_counters'), isNull);
      expect(await rig.sync.installationId(), installation,
          reason: 'else every account would see this phone as a new device');
      expect(await rig.keyOf('user-a'), key);
      expect((await rig.sync.accountState())!.enabled, isTrue,
          reason: 'resetting statistics must not silently switch sync off');
      expect(await rig.sync.ownership.deviceId(key), isNotNull);
    });
  });
}

final _spec = DeviceSpecification(
    manufacturer: 'Google',
    model: 'Pixel 8',
    modelIdentifier: 'Pixel 8',
    design: DesignCapacity(
        mah: 4575, source: DesignCapacitySource.localDeviceDatabase));

/// Every row of every sync-related table and of `meta`, as one string.
Future<String> _dumpEverything(WattByteDb db) async {
  final raw = db.rawDatabase;
  final out = <String, Object?>{};
  for (final t in ['meta', 'sync_receipts', 'sync_rejections']) {
    out[t] = await raw.query(t);
  }
  return jsonEncode(out);
}
