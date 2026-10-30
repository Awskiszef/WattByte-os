// Boundaries that decide what is uploaded, what money is shown and which sessions exist (audit F-22). Each test names the
// edge it pins; the mutants it was written against (>= for >, a 24-hour day, a currency left out of ==, ...) are listed in the test names below.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/collection/counter_folder.dart';
import 'package:wattbyte/collection/session_builder.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';

EnergyCalc calc({double capacity = 4000, double efficiency = 0.8}) =>
    EnergyCalc(
        batteryCapacityMah: capacity,
        nominalVoltage: 3.85,
        efficiency: efficiency,
        pricePerKwh: 1);

ChargingSession session({
  DateTime? start,
  Duration length = const Duration(hours: 1),
  int startLevel = 20,
  int endLevel = 70,
  int? chargeUah,
  int? energyNwh,
  int? voltageMv,
}) {
  final s = start ?? DateTime(2026, 10, 14, 22);
  return ChargingSession(
    start: s,
    end: s.add(length),
    startLevel: startLevel,
    endLevel: endLevel,
    chargeDeltaUah: chargeUah,
    energyDeltaNwh: energyNwh,
    avgVoltageMv: voltageMv,
  );
}

DailyAggregate aggregate({
  String date = '2026-10-14',
  int mobile = 1000,
  int wifi = 2000,
  double charged = 10,
  double wall = 12.5,
  int sessions = 1,
  double cost = 0.5,
  String currency = 'PLN',
  bool dataEstimated = false,
  bool energyEstimated = true,
}) =>
    DailyAggregate(
      date: date,
      mobileBytes: mobile,
      wifiBytes: wifi,
      chargedWh: charged,
      wallWh: wall,
      chargingSessions: sessions,
      estimatedCost: cost,
      currency: currency,
      dataEstimated: dataEstimated,
      energyEstimated: energyEstimated,
    );

void main() {
  group('session energy: the counter guards', () {
    final c = calc();

    test(
        'a charge-counter delta is trusted from 1 uAh up to the cap, not at 0 or above it',
        () {
      expect(c.session(session(chargeUah: 0)).mahEstimated, isTrue,
          reason: '0 is a reset, not a measurement');
      expect(c.session(session(chargeUah: 1)).mahEstimated, isFalse);
      expect(
          c
              .session(session(chargeUah: EnergyCalc.maxSessionChargeUah))
              .mahEstimated,
          isFalse);
      final over =
          c.session(session(chargeUah: EnergyCalc.maxSessionChargeUah + 1));
      expect(over.mahEstimated, isTrue,
          reason: '30 Ah in one session is a glitch');
      expect(over.mah, closeTo(4000 * 0.5, 1e-9),
          reason: 'it falls back to capacity x added percent');
    });

    test(
        'an energy-counter delta is trusted from 1 nWh up to the cap, not at 0 or above it',
        () {
      expect(c.session(session(energyNwh: 0)).whEstimated, isTrue);
      expect(c.session(session(energyNwh: 1)).whEstimated, isFalse);
      expect(
          c
              .session(session(energyNwh: EnergyCalc.maxSessionEnergyNwh))
              .whEstimated,
          isFalse);
      expect(
          c
              .session(session(energyNwh: EnergyCalc.maxSessionEnergyNwh + 1))
              .whEstimated,
          isTrue);
    });

    test(
        'the average voltage counts inside [2.5, 5.0] V inclusive, the nominal voltage outside',
        () {
      double whFor(int mv) =>
          c.session(session(chargeUah: 1000000, voltageMv: mv)).batteryWh;
      expect(whFor(2500), closeTo(1 * 2.5, 1e-9));
      expect(whFor(2499), closeTo(1 * 3.85, 1e-9));
      expect(whFor(5000), closeTo(1 * 5.0, 1e-9));
      expect(whFor(5001), closeTo(1 * 3.85, 1e-9));
    });

    test(
        'without any counter and without a capacity the session is unknown, with a capacity it is estimated',
        () {
      expect(calc(capacity: 0).session(session()).isUnknown, isTrue);
      expect(c.session(session()).isUnknown, isFalse);
    });

    test(
        'the wall energy is battery energy over efficiency, the cost is wall kWh x price',
        () {
      final e = calc(efficiency: 0.5)
          .session(session(chargeUah: 2000000, voltageMv: 4000));
      expect(e.batteryWh, closeTo(8, 1e-9));
      expect(e.wallWh, closeTo(16, 1e-9));
      expect(e.cost, closeTo(0.016, 1e-12));
    });
  });

  group('daily aggregate: equality decides what is uploaded again', () {
    test(
        'equal aggregates are equal, hash alike and fingerprint alike; a JSON round trip changes nothing',
        () {
      final a = aggregate();
      expect(a, aggregate());
      expect(a.hashCode, aggregate().hashCode);
      expect(a.fingerprint, aggregate().fingerprint);
      expect(
          DailyAggregate.fromJson(
              jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>),
          a);
    });

    test(
        'changing any single field makes it a different aggregate with a different fingerprint',
        () {
      final base = aggregate();
      final variants = <String, DailyAggregate>{
        'date': aggregate(date: '2026-10-15'),
        'mobileBytes': aggregate(mobile: 1001),
        'wifiBytes': aggregate(wifi: 2001),
        'chargedWh': aggregate(charged: 10.001),
        'wallWh': aggregate(wall: 12.501),
        'chargingSessions': aggregate(sessions: 2),
        'estimatedCost': aggregate(cost: 0.5001),
        'currency': aggregate(currency: 'EUR'),
        'dataEstimated': aggregate(dataEstimated: true),
        'energyEstimated': aggregate(energyEstimated: false),
      };
      expect(variants.keys.length, 10,
          reason: 'one variant per field of the contract');
      for (final e in variants.entries) {
        expect(e.value == base, isFalse, reason: e.key);
        expect(e.value.fingerprint, isNot(base.fingerprint), reason: e.key);
      }
    });
  });

  group(
      'daily aggregate: a day is a calendar day, also when it has 23 or 25 hours',
      () {
    // Spring forward and fall back in Europe/Warsaw and America/New_York. In a zone without a change on that date the
    // days still have 24 hours and the same invariants hold, so the test is meaningful in every zone CI runs it in.
    for (final d in [
      DateTime(2026, 3, 29), DateTime(2026, 10, 25), // Europe
      DateTime(2026, 3, 8), DateTime(2026, 11, 1), // United States
    ]) {
      test(
          '${d.year}-${d.month}-${d.day}: every session belongs to exactly one day, by its local start',
          () {
        DateTime at(int dayOffset, int h, int m) =>
            DateTime(d.year, d.month, d.day + dayOffset, h, m);
        final sessions = [
          session(start: at(-1, 23, 30), length: const Duration(minutes: 20)),
          session(start: at(0, 0, 30), length: const Duration(minutes: 20)),
          session(
              start: at(0, 2, 30),
              length: const Duration(
                  minutes: 20)), // inside the skipped or repeated hour
          session(start: at(0, 23, 30), length: const Duration(minutes: 20)),
          session(start: at(1, 0, 10), length: const Duration(minutes: 20)),
        ];
        int on(int offset) => DailyAggregate.build(
              day: at(offset, 12, 0),
              days: const [],
              sessions: sessions,
              calc: calc(),
              currency: 'PLN',
            ).chargingSessions;
        expect([on(-1), on(0), on(1)], [1, 3, 1],
            reason: 'the session at 00:10 the next day is not on the DST day');
        expect(on(-1) + on(0) + on(1), sessions.length);
      });

      test(
          '${d.year}-${d.month}-${d.day}: the data of the day is summed, not the data of 24 hours',
          () {
        DailyData data(int offset, int bytes) => DailyData(
            day: DateTime(d.year, d.month, d.day + offset), mobileRx: bytes);
        final agg = DailyAggregate.build(
          day: DateTime(d.year, d.month, d.day, 15),
          days: [data(-1, 1), data(0, 10), data(1, 100)],
          sessions: const [],
          calc: calc(),
          currency: 'PLN',
        );
        expect(agg.mobileBytes, 10);
        expect(agg.date,
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      });
    }

    test('rounding: watt-hours to 3 decimals, cost to 4', () {
      final agg = DailyAggregate.build(
        day: DateTime(2026, 10, 14),
        days: const [],
        sessions: [session(chargeUah: 1234567, voltageMv: 3777)],
        calc: calc(efficiency: 0.9),
        currency: 'PLN',
      );
      expect(agg.chargedWh, 4.663); // 1234.567 mAh x 3.777 V
      expect(agg.wallWh, 5.181);
      expect(agg.estimatedCost, 0.0052);
    });

    test(
        'energyEstimated is true for every day that has a session, even one measured by the energy counter',
        () {
      // The rule is deliberate: a day is "measured" only when nothing in it came from a battery model. A day with a session
      // always involves the charge of a battery, whose energy to the wall depends on an assumed efficiency.
      final measured = DailyAggregate.build(
        day: DateTime(2026, 10, 14),
        days: const [],
        sessions: [session(energyNwh: 5000000000)],
        calc: calc(),
        currency: 'PLN',
      );
      expect(measured.energyEstimated, isTrue);
      final none = DailyAggregate.build(
          day: DateTime(2026, 10, 14),
          days: const [],
          sessions: const [],
          calc: calc(),
          currency: 'PLN');
      expect(none.chargingSessions, 0);
      expect(none.energyEstimated, isFalse);
    });
  });

  group(
      'the client mirror of the contract limits equals the published contract',
      () {
    final dto = ((jsonDecode(
                File('../../packages/contracts/openapi/openapi.json')
                    .readAsStringSync()) as Map<String, dynamic>)['components']
            ['schemas']['DailyUsageDto'] as Map<String, dynamic>)['properties']
        as Map<String, dynamic>;
    num max(String field) => dto[field]['maximum'] as num;

    test('every numeric maximum is accepted, and the next value up is not', () {
      final mobileMax = max('mobileBytes').toInt();
      expect(aggregate(mobile: mobileMax).isWithinContract, isTrue);
      expect(aggregate(mobile: mobileMax + 1).isWithinContract, isFalse);
      expect(
          aggregate(wifi: max('wifiBytes').toInt()).isWithinContract, isTrue);
      expect(aggregate(wifi: max('wifiBytes').toInt() + 1).isWithinContract,
          isFalse);
      expect(aggregate(charged: max('chargedWh').toDouble()).isWithinContract,
          isTrue);
      expect(aggregate(charged: max('chargedWh') + 0.001).isWithinContract,
          isFalse);
      expect(
          aggregate(wall: max('wallWh').toDouble()).isWithinContract, isTrue);
      expect(aggregate(wall: max('wallWh') + 0.001).isWithinContract, isFalse);
      expect(aggregate(cost: max('estimatedCost').toDouble()).isWithinContract,
          isTrue);
      expect(aggregate(cost: max('estimatedCost') + 0.001).isWithinContract,
          isFalse);
      expect(
          aggregate(sessions: max('chargingSessions').toInt()).isWithinContract,
          isTrue);
      expect(
          aggregate(sessions: max('chargingSessions').toInt() + 1)
              .isWithinContract,
          isFalse);
    });

    test('the minimums, the currency pattern and non-finite numbers', () {
      expect(
          aggregate(
                  mobile: 0, wifi: 0, charged: 0, wall: 0, cost: 0, sessions: 0)
              .isWithinContract,
          isTrue);
      expect(aggregate(mobile: -1).isWithinContract, isFalse);
      expect(aggregate(charged: -0.001).isWithinContract, isFalse);
      expect(aggregate(charged: double.nan).isWithinContract, isFalse);
      expect(aggregate(wall: double.infinity).isWithinContract, isFalse);
      expect(
          RegExp(dto['currency']['pattern'] as String).hasMatch('PLN'), isTrue);
      for (final bad in ['pln', 'PL', 'PLNN', '']) {
        expect(aggregate(currency: bad).isWithinContract, isFalse, reason: bad);
      }
    });

    test('the date must be from 2015 on', () {
      expect(aggregate(date: '2015-01-01').isWithinContract, isTrue);
      expect(aggregate(date: '2014-12-31').isWithinContract, isFalse);
    });
  });

  group('SessionBuilder: the edges', () {
    const b = SessionBuilder();
    final t0 = DateTime(2026, 10, 14, 22);
    BatterySample sample(Duration at, int level,
            {bool plugged = true, int? charge}) =>
        BatterySample(
            time: t0.add(at),
            level: level,
            plugged: plugged,
            chargeUah: charge);

    test('a level drop of exactly 3 points keeps the session, 4 splits it', () {
      final kept = b.build([
        sample(Duration.zero, 50),
        sample(const Duration(minutes: 5), 47),
        sample(const Duration(minutes: 10), 60),
        sample(const Duration(minutes: 11), 60, plugged: false)
      ]);
      expect(kept.closed, hasLength(1));
      expect(kept.closed.single.startLevel, 50,
          reason:
              'a drop of 3 is tolerated: the run starts at the first sample');
      final split = b.build([
        sample(Duration.zero, 50),
        sample(const Duration(minutes: 5), 46),
        sample(const Duration(minutes: 10), 60),
        sample(const Duration(minutes: 11), 60, plugged: false)
      ]);
      expect(split.closed, hasLength(1));
      expect(split.closed.single.startLevel, 46,
          reason:
              'the first run (50 -> nothing) is too short to be a session; the second starts at 46');
    });

    test(
        'a gap of exactly 30 minutes is one session, one second more splits it when the counter fell',
        () {
      List<ChargingSession> closed(Duration gap) => b.build([
            sample(Duration.zero, 40, charge: 5000000),
            sample(const Duration(minutes: 2), 41, charge: 5100000),
            sample(const Duration(minutes: 2) + gap, 45,
                charge:
                    1000000), // the counter went down: not a mere sampling gap
            sample(const Duration(minutes: 4) + gap, 46, charge: 1100000),
            sample(const Duration(minutes: 5) + gap, 46, plugged: false),
          ]).closed;
      expect(closed(const Duration(minutes: 30)), hasLength(1));
      expect(closed(const Duration(minutes: 30, seconds: 1)), hasLength(2));
    });

    test('a run shorter than a minute is no session, one minute is', () {
      expect(
          b.build([
            sample(Duration.zero, 40),
            sample(const Duration(seconds: 59), 41),
            sample(const Duration(minutes: 2), 41, plugged: false)
          ]).closed,
          isEmpty);
      expect(
          b.build([
            sample(Duration.zero, 40),
            sample(const Duration(minutes: 1), 41),
            sample(const Duration(minutes: 2), 41, plugged: false)
          ]).closed,
          hasLength(1));
    });

    test('a gap of exactly 15 minutes is not sparse, one second more is', () {
      bool sparse(Duration gap) => b
          .build([
            sample(Duration.zero, 40),
            sample(gap, 45),
            sample(gap + const Duration(minutes: 1), 45, plugged: false)
          ])
          .closed
          .single
          .sparse;
      expect(sparse(const Duration(minutes: 15)), isFalse);
      expect(sparse(const Duration(minutes: 15, seconds: 1)), isTrue);
    });
  });

  group('CounterFolder: the edges', () {
    CounterState state(int ms,
            {int wifiRx = 0, int cellRx = 0, int bits = 32, int boot = 1}) =>
        CounterState(
            wifiRx: wifiRx,
            wifiTx: 0,
            cellRx: cellRx,
            cellTx: 0,
            bootTimeMs: boot,
            timeMs: ms,
            bits: bits);
    int total(List<DailyData> days) => days.fold(0, (a, d) => a + d.total);
    final t = DateTime(2026, 10, 14, 12).millisecondsSinceEpoch;

    test('an unchanged counter is zero bytes, not a 4 GiB wrap', () {
      expect(
          CounterFolder.fold(state(t, wifiRx: 12345, cellRx: 678),
              state(t + 60000, wifiRx: 12345, cellRx: 678)),
          isEmpty);
    });

    test(
        'a 32-bit counter that went down is one wrap; the increment is next + 2^32 - prev',
        () {
      final days = CounterFolder.fold(
          state(t, cellRx: 4294967000), state(t + 3600000, cellRx: 1000));
      expect(total(days), 1000 + (1 << 32) - 4294967000);
    });

    test(
        'an increment equal to the link ceiling is kept, one byte more is dropped',
        () {
      const seconds = 100;
      final cap =
          (seconds * CounterFolder.maxBytesPerSecond).ceil() + (16 << 20);
      expect(
          total(CounterFolder.fold(
              state(t), state(t + seconds * 1000, cellRx: cap))),
          cap);
      expect(
          CounterFolder.fold(
              state(t), state(t + seconds * 1000, cellRx: cap + 1)),
          isEmpty);
    });

    test('a snapshot that is not newer than the baseline measures nothing', () {
      expect(CounterFolder.fold(state(t, cellRx: 1), state(t, cellRx: 9999)),
          isEmpty);
      expect(
          CounterFolder.fold(state(t, cellRx: 1), state(t - 1, cellRx: 9999)),
          isEmpty);
      expect(CounterFolder.fold(null, state(t, cellRx: 9999)), isEmpty);
    });

    test('a 32-bit baseline and a 64-bit reading are not compared', () {
      expect(
          CounterFolder.fold(
              state(t, cellRx: 1), state(t + 1000, cellRx: 5000, bits: 64)),
          isEmpty);
    });
  });
}
