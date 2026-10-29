// The cloud-sync queue and schedule keep working through gaps, outages and a bad day (audit F-05, F-06, F-12, F-17, F-18).
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/core/periods.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_queue.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';
import 'sync_support.dart';

void main() {
  ensureSqliteFfi();

  final calc = EnergyCalc(
    batteryCapacityMah: 4500,
    nominalVoltage: 3.85,
    efficiency: 0.85,
    pricePerKwh: 1.15,
  );
  DateTime d(int day) => DateTime(2026, 10, day);

  group('the queue follows the data (F-05)', () {
    late WattByteDb db;
    late SyncQueue queue;
    setUp(() async {
      db = await WattByteDb.openInMemory();
      queue = SyncQueue(db);
    });
    tearDown(() => db.close());

    Future<void> pass(List<DailyData> days, DateTime now, {String? owner}) =>
        queue.enqueueRecent(
            days: days,
            sessions: const [],
            calc: calc,
            currency: 'PLN',
            now: now,
            settingsOwner: owner);

    Future<List<String>> queued() async =>
        [for (final i in await db.syncItems()) dayKey(i.day)];

    test('days back-filled behind the three-day window after a gap are queued',
        () async {
      // The app ran on the 1st, then not for nine days; the Android collector back-fills days 2..9 when it runs again.
      await pass([DailyData(day: d(1), mobileRx: 5)], d(1));
      expect(await queued(), ['2026-10-01']);

      final days = [
        DailyData(day: d(1), mobileRx: 5),
        for (var x = 2; x <= 10; x++) DailyData(day: d(x), mobileRx: x * 1000),
      ];
      await pass(days, d(10));
      expect(
          await queued(),
          [
            for (var x = 1; x <= 10; x++)
              '2026-10-${x.toString().padLeft(2, '0')}'
          ],
          reason: 'only days 8-10 would be queued by a three-day window');
    });

    test(
        'the very first pass queues the whole history once (repairs gaps of older builds)',
        () async {
      final days = [
        for (var x = 1; x <= 10; x++) DailyData(day: d(x), mobileRx: x)
      ];
      await pass(days, d(10));
      expect((await queued()).length, 10);
    });

    test('an unchanged queue is not rewritten (no churn of the schedule)',
        () async {
      final days = [
        for (var x = 1; x <= 5; x++) DailyData(day: d(x), mobileRx: x)
      ];
      await pass(days, d(5));
      final before = {
        for (final i in await db.syncItems()) dayKey(i.day): i.updatedAt
      };
      await pass(days, d(5).add(const Duration(hours: 3)));
      final after = {
        for (final i in await db.syncItems()) dayKey(i.day): i.updatedAt
      };
      expect(after, before);
    });

    test('a day in the future is dropped from the queue', () async {
      await db.upsertSyncItem(SyncQueueItem(
          day: d(20), payload: agg('2026-10-20'), updatedAt: d(10)));
      await pass([DailyData(day: d(10), mobileRx: 5)], d(10));
      expect(await queued(), ['2026-10-10']);
    });
  });

  group(
      'figures computed under another account are not uploaded by this one (F-18)',
      () {
    late WattByteDb db;
    setUp(() async => db = await WattByteDb.openInMemory());
    tearDown(() => db.close());

    test(
        'switching the settings owner rebuilds every queued day with the new account\'s price',
        () async {
      final queue = SyncQueue(db);
      final session = ChargingSession(
        start: d(2).add(const Duration(hours: 22)),
        end: d(3).add(const Duration(hours: 6)),
        startLevel: 20,
        endLevel: 100,
        chargeDeltaUah: 3000000,
        avgVoltageMv: 3900,
      );
      final days = [
        DailyData(day: d(3), mobileRx: 5),
        DailyData(day: d(8), mobileRx: 5)
      ];
      EnergyCalc priced(double price) => EnergyCalc(
          batteryCapacityMah: 4500,
          nominalVoltage: 3.85,
          efficiency: 0.85,
          pricePerKwh: price);

      await queue.enqueueRecent(
          days: days,
          sessions: [session],
          calc: priced(1.0),
          currency: 'PLN',
          now: d(8),
          settingsOwner: 'account-a');
      final a = (await db.syncItems())
          .firstWhere((i) => dayKey(i.day) == '2026-10-02')
          .payload;
      expect(a.currency, 'PLN');
      expect(a.estimatedCost, greaterThan(0));

      // Account B (free electricity, another currency) signs in on the same phone. Day 2 is older than the three-day window.
      await queue.enqueueRecent(
          days: days,
          sessions: [session],
          calc: priced(0),
          currency: 'EUR',
          now: d(8),
          settingsOwner: 'account-b');
      final b = (await db.syncItems())
          .firstWhere((i) => dayKey(i.day) == '2026-10-02')
          .payload;
      expect(b.currency, 'EUR',
          reason: 'a stale row would carry account A\'s currency');
      expect(b.estimatedCost, 0);
      expect(await db.meta(SyncQueue.metaSettingsOwner), 'account-b');
    });

    test('the same owner keeps its rows', () async {
      final queue = SyncQueue(db);
      final days = [DailyData(day: d(3), mobileRx: 5)];
      await queue.enqueueRecent(
          days: days,
          sessions: const [],
          calc: calc,
          currency: 'PLN',
          now: d(8),
          settingsOwner: 'account-a');
      final first = (await db.syncItems()).single.updatedAt;
      await queue.enqueueRecent(
          days: days,
          sessions: const [],
          calc: calc,
          currency: 'PLN',
          now: d(8).add(const Duration(hours: 1)),
          settingsOwner: 'account-a');
      expect((await db.syncItems()).single.updatedAt, first);
    });
  });

  group('server trouble is probed, not final (F-06)', () {
    late SyncRig rig;
    setUp(() async {
      rig = await SyncRig.create();
      await rig.queue(agg('2026-10-13'));
      await rig.sync.enable(SyncScope.history);
    });
    tearDown(() => rig.close());

    Future<void> haltWith(Object Function(dynamic) route) async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => route(r) as dynamic;
      for (var n = 0; n < 8; n++) {
        await rig.sync.syncNow();
      }
      expect((await rig.sync.accountState())!.halted, isTrue);
    }

    test(
        'a halt waits for the probe interval, then one automatic attempt finds the server back and clears it',
        () async {
      final unavailable = rig.backend.routes['POST /api/v1/usage/sync'];
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(503, 'unavailable');
      for (var n = 0; n < 8; n++) {
        await rig.sync.syncNow();
      }
      expect((await rig.sync.accountState())!.halted, isTrue);
      expect((await rig.sync.syncIfDue()).skip, SyncSkip.halted);

      rig.advance(const Duration(hours: 5));
      expect((await rig.sync.syncIfDue()).skip, SyncSkip.halted,
          reason: 'too early for the probe');

      rig.backend.routes['POST /api/v1/usage/sync'] =
          unavailable!; // the server is back
      rig.advance(const Duration(
          hours: 3)); // 8 h after the halt: beyond 6 h + 25 % jitter
      final probe = await rig.sync.syncIfDue();
      expect(probe.status, SyncStatus.synced);
      expect((await rig.sync.accountState())!.halted, isFalse);
      expect(await rig.receiptsOf('user-a'), isNotEmpty);
    });

    test('a failing probe halts again and waits for the next one', () async {
      await haltWith((_) => FakeBackend.error(503, 'unavailable'));
      rig.advance(const Duration(hours: 8));
      final probe = await rig.sync.syncIfDue();
      expect(probe.status, SyncStatus.rejected);
      expect((await rig.sync.accountState())!.halted, isTrue);
      expect((await rig.sync.syncIfDue()).skip, SyncSkip.halted);
    });

    test(
        'refused payloads (HTTP 400, again and again) stay halted: a probe would repeat the same refusal',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(400, 'validation');
      for (var n = 0; n < 6; n++) {
        await rig.queue(agg('2026-10-${(1 + n).toString().padLeft(2, '0')}',
            mobile: 10 + n));
        await rig.sync.syncNow();
      }
      final st = (await rig.sync.accountState())!;
      if (st.halted) {
        rig.advance(const Duration(days: 2));
        expect((await rig.sync.syncIfDue()).skip, SyncSkip.halted);
      }
    });

    test(
        'the kill switch (503 feature_disabled) is not a failure: no halt, no count, a later attempt',
        () async {
      rig.backend.routes['POST /api/v1/usage/sync'] =
          (r) => FakeBackend.error(503, 'feature_disabled');
      final before = (await rig.sync.accountState())!;
      for (var n = 0; n < 12; n++) {
        final o = await rig.sync.syncNow();
        expect(o.status, SyncStatus.retryLater, reason: 'attempt $n');
      }
      final st = (await rig.sync.accountState())!;
      expect(st.halted, isFalse);
      expect(st.attempts, before.attempts);
      expect(st.limitedFailures, before.limitedFailures);
      expect(st.lastError, 'feature_disabled');
      // A scheduled run waits instead of hammering.
      expect((await rig.sync.syncIfDue()).skip, SyncSkip.backingOff);
    });
  });

  group('one bad day does not reject its whole chunk (F-12)', () {
    test('the day the server refuses is isolated; the others are uploaded',
        () async {
      final rig = await SyncRig.create();
      addTearDown(rig.close);
      const days = [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-08',
        '2026-10-09',
        '2026-10-10',
      ];
      const bad = '2026-10-04';
      await rig.queueDays(days);
      await rig.sync.enable(SyncScope.history);
      final ok = rig.backend.routes['POST /api/v1/usage/sync']!;
      rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
        final sent = [
          for (final x in (r.body!['days'] as List)) (x as Map)['date']
        ];
        return sent.contains(bad)
            ? FakeBackend.error(400, 'validation')
            : ok(r);
      };
      for (var run = 0; run < 3; run++) {
        await rig.sync.syncNow();
      }
      final uploaded =
          (await rig.receiptsOf('user-a')).map((r) => r.day).toSet();
      expect(uploaded, days.toSet()..remove(bad));
      expect(rig.cloud.datesOf('user-a'), isNot(contains(bad)));
      expect(
          rig.backend.where('POST', '/api/v1/usage/sync').length, lessThan(25));
      final snap = (await rig.sync.snapshot())!;
      expect(snap.failed, 1, reason: 'only the refused day is failed');
    });
  });
}
