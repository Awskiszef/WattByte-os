// Unknown battery capacity is an unknown energy, not a measured zero (audit G-02): the model, every surface that prints
// a number, the records, the export and the payload sent to the AI.
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/analytics/stats.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/ai/ai_input_builder.dart';

void main() {
  final t0 = DateTime(2026, 10, 13, 22);
  final t1 = DateTime(2026, 10, 14, 6);
  EnergyCalc calcWith(double capacityMah) => EnergyCalc(
        batteryCapacityMah: capacityMah,
        nominalVoltage: 3.85,
        efficiency: 0.85,
        pricePerKwh: 1.15,
      );
  ChargingSession plain({int? chargeUah, int? energyNwh, DateTime? start}) =>
      ChargingSession(
        start: start ?? t0,
        end: (start ?? t0).add(const Duration(hours: 8)),
        startLevel: 20,
        endLevel: 90,
        chargeDeltaUah: chargeUah,
        energyDeltaNwh: energyNwh,
      );
  const units = Units(locale: 'en');

  group('EnergyCalc.session', () {
    test(
        'no counters and no capacity: unknown, with the figures behind it flagged as not measured',
        () {
      final e = calcWith(0).session(plain());
      expect(e.isUnknown, isTrue);
      expect(e.isPartial, isFalse);
      expect(e.unknownSessions, 1);
      expect(e.mahEstimated && e.whEstimated, isTrue);
      expect([e.mahShown, e.batteryWhShown, e.wallWhShown, e.costShown],
          everyElement(isNaN));
    });

    test(
        'a capacity makes it an estimate again; a counter makes it known without a capacity',
        () {
      expect(calcWith(4500).session(plain()).isUnknown, isFalse);
      expect(calcWith(0).session(plain(chargeUah: 3000000)).isUnknown, isFalse);
      final byEnergy = calcWith(0).session(plain(energyNwh: 12000000000));
      expect(byEnergy.isUnknown, isFalse);
      expect(byEnergy.batteryWh, closeTo(12, 1e-9));
      expect(byEnergy.whEstimated, isFalse);
      // The charge follows from the measured energy at the cell voltage (an estimate), not 0 mAh.
      expect(byEnergy.mah, closeTo(12 * 1000 / 3.85, 1e-6));
      expect(byEnergy.mahEstimated, isTrue);
    });

    test(
        'a glitching counter (absurdly large) does not make an unknown energy known',
        () {
      final e = calcWith(0).session(plain(chargeUah: 99000000000));
      expect(e.isUnknown, isTrue);
    });

    test('an empty period is a real zero, not unknown', () {
      final total = calcWith(0).total(const []);
      expect(total.isUnknown, isFalse);
      expect(total.isPartial, isFalse);
      expect(total.batteryWhShown, 0);
    });
  });

  group('totals', () {
    test(
        'only unknown sessions: unknown; mixed: partial and the known part is shown',
        () {
      final calc = calcWith(0);
      final allUnknown = calc.total([plain(), plain(start: t1)]);
      expect(allUnknown.isUnknown, isTrue);
      final mixed = calc.total([plain(), plain(chargeUah: 2000000, start: t1)]);
      expect(mixed.isUnknown, isFalse);
      expect(mixed.isPartial, isTrue);
      expect(mixed.knownSessions, 1);
      expect(mixed.unknownSessions, 1);
      expect(mixed.mah, 2000);
    });
  });

  group('what the screens print', () {
    test(
        'Units prints the placeholder for the shown (unknown) values, a real number otherwise',
        () {
      final unknown = calcWith(0).session(plain());
      expect(units.wh(unknown.batteryWhShown), Units.placeholder);
      expect(units.kwh(unknown.wallWhShown), Units.placeholder);
      expect(units.mah(unknown.mahShown), Units.placeholder);
      expect(units.money(unknown.costShown, 'PLN'), Units.placeholder);
      expect(units.approx(units.wh(unknown.batteryWhShown), estimated: true),
          Units.placeholder);
      final known = calcWith(4500).session(plain());
      expect(units.wh(known.batteryWhShown), isNot(Units.placeholder));
    });
  });

  group('records', () {
    test('an unknown session takes part in no energy or cost record', () {
      final calc = calcWith(0);
      final r = Records.of(
          const [], [plain(), plain(chargeUah: 2500000, start: t1)], calc);
      expect(r.largestSessionEnergy!.mah, 2500);
      expect(r.largestSession!.start, t1);
      expect(r.mostEnergyDayEnergy!.isUnknown, isFalse);

      final none = Records.of(const [], [plain()], calc);
      expect(none.largestSession, isNull);
      expect(none.mostEnergyDay, isNull);
      expect(none.mostExpensiveMonth, isNull);
      expect(none.longestSession, isNotNull,
          reason: 'duration needs no capacity');
    });
  });

  group('the AI payload', () {
    test(
        'leaves energy, wall energy, cost and the average charge out when they are unknown',
        () {
      final stats = AiPeriodStats.thisMonth(
        days: const [],
        sessions: [plain(start: DateTime(2026, 10, 3, 22))],
        calc: calcWith(0),
        currency: 'PLN',
        now: DateTime(2026, 10, 20, 12),
      );
      expect(stats.chargingSessions, 1);
      expect(stats.batteryEnergyKwh, isNull);
      expect(stats.wallEnergyKwh, isNull);
      expect(stats.electricityCost, isNull);
      expect(stats.averageSessionMah, isNull);
    });

    test('sends the numbers when the capacity is known', () {
      final stats = AiPeriodStats.thisMonth(
        days: const [],
        sessions: [plain(start: DateTime(2026, 10, 3, 22))],
        calc: calcWith(4500),
        currency: 'PLN',
        now: DateTime(2026, 10, 20, 12),
      );
      expect(stats.batteryEnergyKwh, isNotNull);
      expect(stats.batteryEnergyKwh!, greaterThan(0));
      expect(stats.averageSessionMah, closeTo(4500 * 0.7, 1));
    });

    test('a month with some unknown sessions averages the known ones only', () {
      final stats = AiPeriodStats.thisMonth(
        days: const [],
        sessions: [
          plain(start: DateTime(2026, 10, 3, 22)),
          plain(chargeUah: 3000000, start: DateTime(2026, 10, 5, 22)),
        ],
        calc: calcWith(0),
        currency: 'PLN',
        now: DateTime(2026, 10, 20, 12),
      );
      expect(stats.chargingSessions, 2);
      expect(stats.averageSessionMah, 3000);
    });
  });
}
