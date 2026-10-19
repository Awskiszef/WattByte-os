// The estimated full-charge capacity as the Collector keeps it.
//
// Driven through the REAL Collector with a scripted native side (FakeSystem) and
// a real in-memory SQLite database, exactly like the app's refresh does. The
// Android charge counter (BATTERY_PROPERTY_CHARGE_COUNTER) is the charge
// currently STORED in the battery, so every reading below is "this much is in
// the battery at this level"; the collector extrapolates it to a full battery
// (FullChargeCapacityEstimator) and keeps the best estimate it has seen
// (FullChargeCapacityEstimator.prefer). It never produces a design capacity: the
// design capacity of a phone model lives in Settings and comes from a catalog or
// the user (see battery_capacity_regression_test.dart for that boundary).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/storage/database.dart';

import 'support/fake_system.dart';

/// A battery that holds 3600 mAh when full.
const _full = 3600.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final t0 = DateTime(2026, 9, 1, 8);
  late DateTime now;
  late FakeSystem fake;
  late WattByteDb db;
  late Collector collector;

  setUp(() async {
    now = t0;
    fake = FakeSystem(
        platform: HarnessPlatform.android, batteryLevel: 100, clock: () => now);
    db = await WattByteDb.openInMemory();
    collector = Collector(system: fake.system, db: db);
  });

  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  /// One refresh with [level] percent on the display and [storedMah] currently
  /// stored in the battery (default: a battery that holds [_full] when full).
  /// Time moves on by [after] first. Returns what the collector now keeps.
  Future<EstimatedFullChargeCapacity> read(
    int level, {
    double? storedMah,
    int? energyNwh,
    bool noCounter = false,
    Duration after = Duration.zero,
  }) async {
    now = now.add(after);
    fake.setReading(level,
        storedMah: noCounter ? null : storedMah ?? _full * level / 100,
        energyNwh: energyNwh);
    await collector.collect(now: now);
    return collector.fullChargeCapacity();
  }

  /// Everything the collector keeps about the estimate, raw.
  Future<Map<String, String?>> metaRows() async => {
        for (final k in await db.metaKeys('calibrated_capacity_'))
          k: await db.meta(k),
      };

  group('what a single reading becomes', () {
    test('a fresh database has no estimate and no stored keys', () async {
      expect(await collector.fullChargeCapacity(),
          EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
      expect((await collector.fullChargeCapacity()).isAvailable, isFalse);
      expect((await collector.fullChargeCapacity()).confidence,
          FullChargeCapacityConfidence.none);
    });

    test(
        '100 %: the estimate is the counter, confidence high, source '
        'androidChargeCounter, stamped with the reading', () async {
      final e = await read(100, storedMah: 3600);
      expect(e.isAvailable, isTrue);
      expect(e.mah, closeTo(3600, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.high);
      expect(e.source, FullChargeCapacitySource.androidChargeCounter);
      expect(e.level, 100);
      expect(e.measuredAt, now);
      expect(e.wh, isNull, reason: 'no energy counter, no Wh');
      expect(e.isReliableForHealth, isTrue);

      expect(
          (await metaRows()).keys,
          unorderedEquals([
            'calibrated_capacity_mah',
            'calibrated_capacity_level',
            'calibrated_capacity_at_ms',
          ]),
          reason: 'the same keys the older installs used, plus the time');
      expect(await db.meta('calibrated_capacity_level'), '100');
    });

    test('95 %: 3420 mAh stored extrapolate to 3600, confidence high',
        () async {
      final e = await read(95, storedMah: 3420);
      expect(e.mah, closeTo(3600, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.high);
      expect(e.level, 95);
    });

    for (final (level, expected) in [
      (94, FullChargeCapacityConfidence.medium),
      (75, FullChargeCapacityConfidence.medium),
      (74, FullChargeCapacityConfidence.low),
      (50, FullChargeCapacityConfidence.low),
      (40, FullChargeCapacityConfidence.low),
    ]) {
      test(
          '$level %: confidence ${expected.name}, extrapolated to the full '
          'battery', () async {
        final e = await read(level);
        expect(e.mah, closeTo(_full, 0.01),
            reason: 'charge / (level / 100), not the raw counter');
        expect(e.confidence, expected);
        expect(e.level, level);
        expect(
            e.isReliableForHealth, expected != FullChargeCapacityConfidence.low,
            reason: 'a low confidence extrapolation is no basis for a health');
      });
    }

    test(
        '50 %: the raw counter (1800) is not the estimate; the full battery is',
        () async {
      final e = await read(50, storedMah: 1800);
      expect(e.mah, isNot(closeTo(1800, 1)));
      expect(e.mah, closeTo(3600, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.low);
    });

    for (final (level, stored) in [
      (39, 1404.0),
      (20, 720.0),
      (1, 36.0),
      (0, 3600.0),
      (0, 120.0),
      (-1, 3600.0),
    ]) {
      test(
          'level $level % (counter ${stored.toStringAsFixed(0)} mAh): nothing '
          'is stored', () async {
        final e = await read(level, storedMah: stored);
        expect(e, EstimatedFullChargeCapacity.unavailable);
        expect(await metaRows(), isEmpty,
            reason: 'below 40 % the extrapolation is too far; 0 and -1 are '
                '"empty" and "unknown", never a divide-by-zero');
      });
    }
  });

  group('unsupported, zero, negative and implausible counters', () {
    test('an unsupported counter (null) stores nothing', () async {
      final e = await read(100, noCounter: true);
      expect(fake.capabilities['chargeCounter'], isFalse);
      expect(e, EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
    });

    for (final (name, stored) in [
      ('zero', 0.0),
      ('negative', -3600.0),
      ('slightly negative', -0.001),
    ]) {
      test('a $name counter stores nothing on a fresh database', () async {
        final e = await read(100, storedMah: stored);
        expect(e, EstimatedFullChargeCapacity.unavailable);
        expect(await metaRows(), isEmpty);
      });
    }

    test(
        'null, zero and negative counters leave the previous estimate '
        'completely untouched', () async {
      final first = await read(100, storedMah: 3600, energyNwh: 13860000000);
      expect(first.isAvailable, isTrue);
      final rowsBefore = await metaRows();

      for (final (name, stored) in [
        ('unsupported', null),
        ('zero', 0.0),
        ('negative', -3600.0),
      ]) {
        final after = await read(100,
            storedMah: stored,
            noCounter: stored == null,
            after: const Duration(days: 1));
        expect(after, first, reason: '$name counter must not replace it');
        expect(await metaRows(), rowsBefore, reason: name);
      }
    });

    test('an unknown or too low level leaves the previous estimate untouched',
        () async {
      final first = await read(100);
      for (final level in [-1, 0, 20, 39]) {
        final after =
            await read(level, after: const Duration(days: 40)); // even stale
        expect(after, first, reason: 'level $level');
      }
    });

    test(
        'a counter that reports mAh instead of microampere-hours (3.6 mAh) '
        'is rejected as implausible', () async {
      // The platform delivers 3 600 "uAh" = 3.6 mAh at 100 %.
      expect(await read(100, storedMah: 3.6),
          EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
    });

    test('an absurdly large counter (1 000 000 mAh) is rejected', () async {
      expect(await read(100, storedMah: 1000000),
          EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
    });

    test('an energy counter alone is no estimate (Wh needs mAh)', () async {
      final e = await read(100, noCounter: true, energyNwh: 13860000000);
      expect(fake.capabilities['energyCounter'], isTrue);
      expect(e, EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
    });

    test('the raw counter stays a sample\'s charge; it is not the estimate',
        () async {
      await read(80, storedMah: 2880);
      final samples = await db.samples();
      expect(samples.last.chargeUah, 2880000,
          reason: 'history keeps the charge that was in the battery');
      expect((await collector.fullChargeCapacity()).mah, closeTo(3600, 0.01),
          reason: '... and the estimate is the extrapolation');
    });
  });

  group('the collector keeps the best estimate it has seen', () {
    test('a 45 % reading after a 100 % reading does NOT overwrite it',
        () async {
      final high = await read(100, storedMah: 3500);
      final rows = await metaRows();
      expect(high.confidence, FullChargeCapacityConfidence.high);

      // 45 % of a battery that now extrapolates to 3000 mAh.
      final after = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(days: 7));
      expect(after, high);
      expect(after.mah, closeTo(3500, 0.01));
      expect(after.confidence, FullChargeCapacityConfidence.high);
      expect(await metaRows(), rows,
          reason: 'not even the timestamp of the kept reading moves');
    });

    test('a lower confidence reading of the same day never replaces it',
        () async {
      await read(100, storedMah: 3500);
      for (final level in [94, 80, 75, 74, 50, 40]) {
        final e = await read(level,
            storedMah: 3000.0 * level / 100, after: const Duration(hours: 1));
        expect(e.mah, closeTo(3500, 0.01), reason: 'level $level');
        expect(e.confidence, FullChargeCapacityConfidence.high);
      }
    });

    test('a newer reading of EQUAL confidence replaces it', () async {
      await read(100, storedMah: 3600);
      final e = await read(98,
          storedMah: 3400 * 0.98, after: const Duration(days: 2));
      expect(e.mah, closeTo(3400, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.high);
      expect(e.level, 98);
      expect(e.measuredAt, now);
    });

    test('a newer reading of HIGHER confidence replaces it', () async {
      final low = await read(50, storedMah: 1500); // 3000 mAh, low
      expect(low.confidence, FullChargeCapacityConfidence.low);
      final medium = await read(80,
          storedMah: 3200 * 0.8, after: const Duration(hours: 5));
      expect(medium.mah, closeTo(3200, 0.01));
      expect(medium.confidence, FullChargeCapacityConfidence.medium);
      final high =
          await read(100, storedMah: 3300, after: const Duration(hours: 5));
      expect(high.mah, closeTo(3300, 0.01));
      expect(high.confidence, FullChargeCapacityConfidence.high);
    });

    test('a newer low reading replaces an older low one', () async {
      await read(45, storedMah: 3000 * 0.45);
      final e = await read(60,
          storedMah: 3100 * 0.6, after: const Duration(hours: 1));
      expect(e.mah, closeTo(3100, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.low);
    });

    test(
        'a stored reading older than 30 days IS replaced by a newer '
        'lower-confidence one', () async {
      final high = await read(100, storedMah: 3600);
      final e = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(days: 30, minutes: 1));
      expect(e.mah, closeTo(3000, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.low);
      expect(e.level, 45);
      expect(e.measuredAt, now);
      expect(e, isNot(high));
    });

    test('exactly 30 days is not yet old; one minute more is', () async {
      final high = await read(100, storedMah: 3600);
      final kept = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(days: 30));
      expect(kept, high, reason: '30 days exactly: still fresh');

      final replaced = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(minutes: 1));
      expect(replaced.confidence, FullChargeCapacityConfidence.low);
      expect(replaced.mah, closeTo(3000, 0.01));
    });

    test('a replaced estimate is stamped, so the next 30 days start over',
        () async {
      await read(100, storedMah: 3600);
      final low = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(days: 40));
      expect(low.confidence, FullChargeCapacityConfidence.low);
      // A second low reading a day later is just as good: it replaces too.
      final next =
          await read(50, storedMah: 3100 * 0.5, after: const Duration(days: 1));
      expect(next.mah, closeTo(3100, 0.01));
      // ... but a high one stays against a low one for the next 30 days.
      await read(100, storedMah: 3300, after: const Duration(days: 1));
      final stays = await read(45,
          storedMah: 3000 * 0.45, after: const Duration(days: 10));
      expect(stays.mah, closeTo(3300, 0.01));
      expect(stays.confidence, FullChargeCapacityConfidence.high);
    });

    test('a refresh without a usable reading never ages or erases the estimate',
        () async {
      final high = await read(100, storedMah: 3600);
      for (var i = 0; i < 5; i++) {
        await read(100, noCounter: true, after: const Duration(days: 20));
      }
      expect(await collector.fullChargeCapacity(), high,
          reason: '100 days later the estimate is still the last good one');
    });
  });

  group('Wh comes from a valid energy counter only', () {
    // 3600 mAh at 3.85 V = 13.86 Wh = 13 860 000 000 nWh.
    const fullEnergyNwh = 13860000000;

    test('a valid energy counter gives Wh, extrapolated like the charge',
        () async {
      final e = await read(100, energyNwh: fullEnergyNwh);
      expect(e.mah, closeTo(3600, 0.01));
      expect(e.wh, closeTo(13.86, 0.001));
      expect(fake.capabilities['energyCounter'], isTrue);
      expect(await db.meta('calibrated_capacity_wh'), isNotNull);
    });

    test('at 50 % the energy counter is extrapolated too', () async {
      final e = await read(50, energyNwh: fullEnergyNwh ~/ 2);
      expect(e.wh, closeTo(13.86, 0.001));
      expect(e.confidence, FullChargeCapacityConfidence.low);
    });

    for (final (name, energy) in <(String, int?)>[
      ('unsupported', null),
      ('zero', 0),
      ('negative', -13860000000),
      ('implying a 0.8 V cell', 3000000000),
      ('implying a 11 V cell', 40000000000),
    ]) {
      test('an energy counter that is $name gives no Wh, the mAh stay',
          () async {
        final e = await read(100, energyNwh: energy);
        expect(e.mah, closeTo(3600, 0.01));
        expect(e.confidence, FullChargeCapacityConfidence.high);
        expect(e.wh, isNull, reason: 'never derived from an assumed voltage');
        expect(await db.meta('calibrated_capacity_wh'), isNull);
      });
    }

    test('a newer reading without Wh does not keep the older reading\'s Wh',
        () async {
      final first = await read(100, energyNwh: fullEnergyNwh);
      expect(first.wh, isNotNull);
      final second = await read(100,
          storedMah: 3500, after: const Duration(days: 1)); // no energy counter
      expect(second.mah, closeTo(3500, 0.01));
      expect(second.wh, isNull,
          reason: 'Wh of a different reading must not be grafted on');
      expect(await db.meta('calibrated_capacity_wh'), isNull);
    });

    test('a kept (higher confidence) reading keeps its own Wh', () async {
      final first = await read(100, energyNwh: fullEnergyNwh);
      final after = await read(50,
          storedMah: 1500,
          energyNwh: 5000000000,
          after: const Duration(days: 1));
      expect(after, first);
      expect(after.wh, closeTo(13.86, 0.001));
    });
  });

  group('installs from before the split (the older meta layout)', () {
    // Older builds stored only calibrated_capacity_mah and
    // calibrated_capacity_level; the reading is still an estimate.
    Future<EstimatedFullChargeCapacity> legacy(String mah, String level) async {
      await db.setMeta('calibrated_capacity_mah', mah);
      await db.setMeta('calibrated_capacity_level', level);
      return collector.fullChargeCapacity();
    }

    for (final (level, expected) in [
      ('100', FullChargeCapacityConfidence.high),
      ('96', FullChargeCapacityConfidence.high),
      ('95', FullChargeCapacityConfidence.high),
      ('94', FullChargeCapacityConfidence.medium),
      ('80', FullChargeCapacityConfidence.medium),
      ('75', FullChargeCapacityConfidence.medium),
      ('74', FullChargeCapacityConfidence.low),
      ('70', FullChargeCapacityConfidence.low),
      ('40', FullChargeCapacityConfidence.low),
    ]) {
      test(
          '3600 mAh at level $level reads back as an estimate, confidence '
          '${expected.name}', () async {
        final e = await legacy('3600', level);
        expect(e.isAvailable, isTrue);
        expect(e.mah, 3600);
        expect(e.confidence, expected);
        expect(e.level, int.parse(level));
        expect(e.source, FullChargeCapacitySource.androidChargeCounter,
            reason: 'an estimate, never a design capacity');
        expect(e.measuredAt, isNull, reason: 'the old layout had no time');
        expect(e.wh, isNull);
      });
    }

    for (final (name, mah, level) in [
      ('a level below 40 %', '2000', '30'),
      ('level 0', '3600', '0'),
      ('a level above 100', '3600', '101'),
      ('a missing level', '3600', ''),
      ('an unparsable capacity', 'abc', '100'),
      ('an empty capacity', '', '100'),
      ('NaN', 'NaN', '100'),
      ('Infinity', 'Infinity', '100'),
      ('-Infinity', '-Infinity', '100'),
      ('a negative capacity', '-3600', '100'),
      ('zero', '0', '100'),
      ('a capacity below 100 mAh', '50', '100'),
      ('a capacity above 30 000 mAh', '30001', '100'),
    ]) {
      test('$name reads back as no estimate', () async {
        final e = await legacy(mah, level);
        expect(e, EstimatedFullChargeCapacity.unavailable);
        expect(e.isAvailable, isFalse);
      });
    }

    test('a stored Wh that is NaN or implausible is dropped, the mAh stay',
        () async {
      for (final wh in ['NaN', 'Infinity', '-5', '200.5', '1.0', '99']) {
        await legacy('3600', '100');
        await db.setMeta('calibrated_capacity_wh', wh);
        final e = await collector.fullChargeCapacity();
        expect(e.mah, 3600, reason: 'wh=$wh');
        expect(e.wh, isNull, reason: 'wh=$wh');
      }
    });

    test('an unusable timestamp is ignored, the estimate stays', () async {
      for (final at in ['-5', '0', 'x', '99999999999999999999']) {
        await legacy('3600', '100');
        await db.setMeta('calibrated_capacity_at_ms', at);
        final e = await collector.fullChargeCapacity();
        expect(e.isAvailable, isTrue, reason: 'at=$at');
        expect(e.measuredAt, isNull, reason: 'at=$at');
      }
    });

    test(
        'a legacy reading (no timestamp) is replaced by any newer reading, and '
        'the result carries a timestamp from then on', () async {
      await legacy('3600', '100');
      final e = await read(45, storedMah: 3000 * 0.45);
      expect(e.mah, closeTo(3000, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.low);
      expect(e.measuredAt, now);
      expect(await db.meta('calibrated_capacity_at_ms'), isNotNull);
    });

    test('a newer reading of equal or higher confidence replaces a legacy one',
        () async {
      await legacy('3000', '80'); // medium
      final e = await read(100, storedMah: 3500);
      expect(e.mah, closeTo(3500, 0.01));
      expect(e.confidence, FullChargeCapacityConfidence.high);
    });

    test('an unusable reading leaves a legacy estimate exactly as it was',
        () async {
      await legacy('3600', '70');
      await read(100, noCounter: true);
      await read(0, storedMah: 0);
      final e = await collector.fullChargeCapacity();
      expect(e.mah, 3600);
      expect(e.confidence, FullChargeCapacityConfidence.low);
      expect(e.level, 70);
    });
  });

  group('platforms and housekeeping', () {
    test('iOS has no charge counter: nothing is ever estimated', () async {
      final ios = FakeSystem(
          platform: HarnessPlatform.ios,
          batteryLevel: 100,
          // Ignored on iOS, like the native side that has no such API.
          chargeCounterMah: 3600,
          clock: () => now);
      addTearDown(ios.dispose);
      final c = Collector(system: ios.system, db: db);
      await c.collect(now: now);
      expect(ios.capabilities['chargeCounter'], isFalse);
      expect(await c.fullChargeCapacity(),
          EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty);
      expect(ios.batterySnapshot.containsKey('chargeUah'), isFalse);
    });

    test('"Reset statistics" wipes the estimate with the other measurements',
        () async {
      await read(100, energyNwh: 13860000000);
      expect((await collector.fullChargeCapacity()).isAvailable, isTrue);
      await db.resetAll();
      expect(await collector.fullChargeCapacity(),
          EstimatedFullChargeCapacity.unavailable);
      expect(await metaRows(), isEmpty,
          reason: 'all four keys, the Wh and the time included');
    });

    test('the collector writes only the four estimate keys for it', () async {
      await read(100, energyNwh: 13860000000);
      final keys = await db.metaKeys('');
      expect(
          keys,
          unorderedEquals([
            Collector.metaFullChargeCapacityMah,
            Collector.metaFullChargeCapacityLevel,
            Collector.metaFullChargeCapacityWh,
            Collector.metaFullChargeCapacityMeasuredAt,
          ]),
          reason:
              'no design-capacity key, no "capacity" key of any other name');
      for (final k in keys) {
        expect(k.toLowerCase(), isNot(contains('design')));
      }
    });
  });
}
