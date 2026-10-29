// The collection pass must not lose data when something fails half way (audit G-11, H-05, G-12). Driven through the real
// Collector, a scripted native side and a real in-memory SQLite database.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/collection/counter_folder.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import 'support/fake_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final t0 = DateTime(2026, 10, 13, 8);
  late DateTime now;
  late FakeSystem fake;
  late WattByteDb db;
  late Collector collector;

  Future<void> start(HarnessPlatform platform) async {
    now = t0;
    fake = FakeSystem(platform: platform, batteryLevel: 50, clock: () => now);
    db = await WattByteDb.openInMemory();
    collector = Collector(system: fake.system, db: db);
  }

  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  Map<String, Object?> workerSample(int minute, int level) => {
        'timeMs': t0.add(Duration(minutes: minute)).millisecondsSinceEpoch,
        'level': level,
        'plugged': true,
        'chargeUah': null,
        'energyNwh': null,
        'voltageMv': null,
        'source': 'worker',
      };

  Future<int> workerRows() async =>
      (await db.samples()).where((s) => s.source == 'worker').length;

  group('Android worker samples (H-05, G-11)', () {
    setUp(() => start(HarnessPlatform.android));

    test('are acknowledged only after they are stored', () async {
      fake.pendingSamples = [workerSample(1, 20), workerSample(2, 22)];
      await collector.collect(now: now);
      expect(await workerRows(), 2);
      expect(fake.ackedTokens, isNotEmpty);
      expect(fake.pendingSamples, isEmpty);
    });

    test(
        'survive a failing database write: not acknowledged, delivered again and stored next time',
        () async {
      fake.pendingSamples = [workerSample(1, 20), workerSample(2, 22)];
      // The write fails (the table is not there for one pass).
      await db.rawDatabase.execute(
          'ALTER TABLE battery_samples RENAME TO battery_samples_away');
      await expectLater(collector.collect(now: now), throwsA(anything));
      expect(fake.ackedTokens, isEmpty);
      expect(fake.pendingSamples, hasLength(2),
          reason: 'the native side still has them');

      await db.rawDatabase.execute(
          'ALTER TABLE battery_samples_away RENAME TO battery_samples');
      await collector.collect(now: now.add(const Duration(minutes: 5)));
      expect(await workerRows(), 2);
      expect(fake.pendingSamples, isEmpty);
    });

    test(
        'a failing acknowledgement costs nothing: stored once, delivered again, still stored once',
        () async {
      fake.pendingSamples = [workerSample(1, 20)];
      fake.failing.add('ackSamples');
      await collector.collect(now: now);
      expect(await workerRows(), 1);
      expect(fake.pendingSamples, hasLength(1));

      fake.failing.clear();
      await collector.collect(now: now.add(const Duration(minutes: 5)));
      expect(await workerRows(), 1, reason: 'the same sample twice is one row');
      expect(fake.pendingSamples, isEmpty);
    });

    test(
        'a failing battery snapshot does not lose the worker samples that were already stored',
        () async {
      fake.pendingSamples = [workerSample(1, 20)];
      fake.failing.add('batterySnapshot');
      await expectLater(collector.collect(now: now), throwsA(anything));
      expect(await workerRows(), 1,
          reason: 'stored before the snapshot was requested');
      expect(fake.pendingSamples, isEmpty,
          reason: 'and acknowledged, so nothing is delivered twice');
    });

    test(
        'a native side without the two-step calls still works through the one-step drain',
        () async {
      fake.pendingSamples = [workerSample(1, 20)];
      fake.unsupported.addAll(['peekSamples', 'ackSamples']);
      await collector.collect(now: now);
      expect(await workerRows(), 1);
      expect(fake.pendingSamples, isEmpty);
    });

    test(
        'a native side that fails the two-step call outright is an error, not a silent skip',
        () async {
      fake.pendingSamples = [workerSample(1, 20)];
      fake.failing.add('peekSamples');
      await expectLater(collector.collect(now: now), throwsA(anything));
      expect(fake.pendingSamples, hasLength(1));
    });
  });

  group('the two steps of a pass are independent (G-12)', () {
    setUp(() => start(HarnessPlatform.android));

    test('a failing data step does not stop the battery step', () async {
      fake.failing.add('queryDataDaily');
      fake.pendingSamples = [workerSample(1, 20)];
      final result = await collector.collect(now: now);
      expect(await workerRows(), 1);
      expect(result.latest, isNotNull);
    });
  });

  group('iOS counter fold and its baseline (G-11)', () {
    setUp(() => start(HarnessPlatform.ios));

    RawInterfaceCounters reading(int wifi, {int minutes = 0}) =>
        RawInterfaceCounters(
          wifiRx: 0,
          wifiTx: 0,
          cellRx: 0,
          cellTx: 0,
          bootTimeMs: t0.millisecondsSinceEpoch - 20 * 24 * 3600 * 1000,
          timeMs: t0.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          bits: 64,
          ifaces: {'en0': (rx: wifi, tx: 0)},
        );

    test(
        'the increment and the baseline are written together: a failed baseline write rolls the increment back',
        () async {
      fake.counters = reading(1000);
      await collector.collect(now: now);
      // Break the meta table so the baseline write fails after the increment would have been added.
      await db.rawDatabase.execute('ALTER TABLE meta RENAME TO meta_away');
      now = t0.add(const Duration(hours: 1));
      fake.counters = reading(5000, minutes: 60);
      // The data step fails (and is reported) but the pass itself completes: the battery step is independent.
      await collector.collect(now: now);
      await db.rawDatabase.execute('ALTER TABLE meta_away RENAME TO meta');
      expect((await db.allDaily()).fold<int>(0, (a, d) => a + d.wifi), 0,
          reason: 'the 4000 bytes were not added without their baseline');

      // The next pass measures against the OLD baseline and books the 4000 bytes exactly once.
      now = t0.add(const Duration(hours: 2));
      fake.counters = reading(5000, minutes: 120);
      await collector.collect(now: now);
      expect((await db.allDaily()).fold<int>(0, (a, d) => a + d.wifi), 4000);
    });
  });

  group('CounterFolder.spread never produces a negative day (G-12)', () {
    test('rounding many shares up leaves a remainder of zero, not minus one',
        () {
      final from = DateTime(2026, 10, 13, 23);
      final to = DateTime(2026, 10, 18, 1); // six calendar days, uneven shares
      for (final total in [1, 2, 3, 5, 7, 11, 1000003]) {
        final out = CounterFolder.spread(
            DailyData(
                day: to,
                wifiRx: total,
                mobileRx: total,
                wifiTx: total,
                mobileTx: total),
            from,
            to);
        for (final d in out) {
          expect(d.wifiRx, greaterThanOrEqualTo(0), reason: 'total $total');
          expect(d.mobileRx, greaterThanOrEqualTo(0));
          expect(d.wifiTx, greaterThanOrEqualTo(0));
          expect(d.mobileTx, greaterThanOrEqualTo(0));
        }
        expect(out.fold<int>(0, (a, d) => a + d.wifiRx), total,
            reason: 'nothing is lost or invented');
      }
    });
  });
}
