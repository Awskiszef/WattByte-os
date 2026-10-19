import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/settings/settings.dart';

EnergyCalc calc({
  double cap = 4000,
  double v = 3.85,
  double eff = 0.85,
  double price = 1.0,
}) =>
    EnergyCalc(
        batteryCapacityMah: cap,
        nominalVoltage: v,
        efficiency: eff,
        pricePerKwh: price);

ChargingSession session(
        {int? cd, int? ed, int? mv, int from = 20, int to = 80}) =>
    ChargingSession(
      start: DateTime(2026, 1, 1),
      end: DateTime(2026, 1, 1, 1),
      startLevel: from,
      endLevel: to,
      chargeDeltaUah: cd,
      energyDeltaNwh: ed,
      avgVoltageMv: mv,
    );

Matcher get rejects => throwsA(isA<EnergyInputError>());

void main() {
  group('efficiency', () {
    test('0 is rejected (it used to be treated as 100 %)', () {
      expect(() => calc(eff: 0), rejects);
      expect(() => EnergyCalc.wallFromBattery(10, 0), rejects);
    });
    test('negative, above 1, NaN and infinity are rejected', () {
      for (final e in [-0.1, 1.0001, 1.5, double.nan, double.infinity]) {
        expect(() => calc(eff: e), rejects, reason: '$e');
        expect(() => EnergyCalc.wallFromBattery(10, e), rejects, reason: '$e');
      }
    });
    test('1 and small positive values are accepted', () {
      expect(EnergyCalc.wallFromBattery(10, 1), 10);
      expect(EnergyCalc.wallFromBattery(10, 0.5), 20);
    });
  });

  group('inputs', () {
    test('NaN and infinity never reach a result', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        expect(() => calc(cap: bad), rejects);
        expect(() => calc(v: bad), rejects);
        expect(() => calc(price: bad), rejects);
        expect(() => EnergyCalc.whFromMah(bad, 3.85), rejects);
        expect(() => EnergyCalc.whFromMah(100, bad), rejects);
        expect(() => EnergyCalc.kwhFromWh(bad), rejects);
        expect(() => EnergyCalc.costOf(1, bad), rejects);
      }
    });
    test('negative mAh, Wh, voltage, capacity and price are rejected', () {
      expect(() => EnergyCalc.whFromMah(-1, 3.85), rejects);
      expect(() => EnergyCalc.whFromMah(100, -3.85), rejects);
      expect(() => EnergyCalc.whFromMah(100, 0), rejects);
      expect(() => EnergyCalc.kwhFromWh(-1), rejects);
      expect(() => EnergyCalc.wallFromBattery(-1, 0.85), rejects);
      expect(() => EnergyCalc.costOf(-1, 1), rejects);
      expect(() => EnergyCalc.costOf(1, -1), rejects);
      expect(() => calc(cap: -4000), rejects);
      expect(() => calc(price: -1), rejects);
      expect(() => calc(v: -3.85), rejects);
    });
    test('absurd capacity and voltage are rejected, 0 mAh means unknown', () {
      expect(() => calc(cap: 1e9), rejects);
      expect(() => calc(v: 12), rejects);
      expect(() => calc(v: 0.5), rejects);
      expect(calc(cap: 0).canEstimateFromPercent, isFalse);
    });
    test('zero values are legal and give zero, not NaN', () {
      expect(EnergyCalc.whFromMah(0, 3.85), 0);
      final e = calc(cap: 0).session(session());
      expect([e.mah, e.batteryWh, e.wallWh, e.cost], everyElement(0));
    });
  });

  group('sessions', () {
    test('a session never yields NaN or Infinity', () {
      final cases = [
        session(),
        session(cd: -5000000),
        session(ed: -1),
        session(mv: 0),
        session(mv: 2000),
        session(mv: 99999),
        session(from: 80, to: 20),
        session(cd: 9223372036854775807),
        session(ed: 9223372036854775807),
      ];
      for (final s in cases) {
        final e = calc().session(s);
        for (final v in [e.mah, e.batteryWh, e.wallWh, e.cost]) {
          expect(v.isFinite, isTrue, reason: '$s');
          expect(v, greaterThanOrEqualTo(0));
        }
      }
    });
    test('a glitchy counter delta falls back to the estimate and says so', () {
      final e = calc().session(session(ed: 9000000000000000000));
      expect(e.whEstimated, isTrue);
      expect(e.batteryWh, closeTo(4000 * 0.6 * 3.85 / 1000, 1e-9));
    });
    test('a voltage outside the physical range is ignored', () {
      final a = calc().session(session(mv: 99999));
      final b = calc().session(session());
      expect(a.batteryWh, b.batteryWh);
    });
    test('a plausible measurement is still trusted', () {
      final e = calc().session(session(cd: 2400000, ed: 9240000000));
      expect(e.mahEstimated, isFalse);
      expect(e.whEstimated, isFalse);
      expect(e.batteryWh, closeTo(9.24, 1e-9));
    });
  });

  group('settings sanitising', () {
    test('impossible stored values become defaults, valid ones survive', () {
      const bad = Settings(
        pricePerKwh: -3,
        efficiency: 0,
        designCapacityMah: -10,
        designCapacitySource: DesignCapacitySource.manual,
        nominalVoltage: 99,
        mobileThresholdBytes: -1,
      );
      final s = bad.sanitized();
      expect(s.pricePerKwh, 0);
      expect(s.efficiency, 0.85);
      expect(s.designCapacityMah, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.nominalVoltage, 3.85);
      expect(s.mobileThresholdBytes, const Settings().mobileThresholdBytes);
      expect(() => s.energyCalc(), returnsNormally);

      final nan = const Settings().copyWith(
          pricePerKwh: double.nan,
          efficiency: double.nan,
          designCapacityMah: double.infinity,
          designCapacitySource: DesignCapacitySource.localDeviceDatabase);
      expect(() => nan.sanitized().energyCalc(), returnsNormally);
      expect(nan.sanitized().designCapacitySource, DesignCapacitySource.unknown,
          reason: 'a source without a usable capacity does not survive');

      const good = Settings(
          pricePerKwh: 1.15,
          efficiency: 0.9,
          designCapacityMah: 5000,
          designCapacitySource: DesignCapacitySource.manual);
      expect(good.sanitized().efficiency, 0.9);
      expect(good.sanitized().pricePerKwh, 1.15);
      expect(good.sanitized().designCapacityMah, 5000);
    });
  });

  group('which capacity the calculator is built on', () {
    // The `% -> mAh` estimate needs a capacity. The DESIGN capacity of the model
    // always wins; only when none is known does the ESTIMATED full-charge
    // capacity of this battery stand in. Neither is invented.
    final design = const Settings().withDesignCapacity(DesignCapacity(
        mah: 4000, source: DesignCapacitySource.localDeviceDatabase));
    final estimate =
        FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100);

    test('the design capacity still wins over the estimated full-charge one',
        () {
      expect(estimate.mah, 3600);
      final calc = design.energyCalc(estimatedFullChargeCapacityMah: 3600);
      expect(calc.batteryCapacityMah, 4000);
      expect(calc.canEstimateFromPercent, isTrue);
      // 20 % -> 80 % of the DESIGN capacity, not of the estimate.
      expect(calc.session(session()).mah, closeTo(4000 * 0.6, 1e-9));
    });

    test('a manual design capacity wins over the estimate as well', () {
      final manual = const Settings().withDesignCapacity(
          DesignCapacity(mah: 5000, source: DesignCapacitySource.manual));
      expect(
          manual
              .energyCalc(estimatedFullChargeCapacityMah: 3600)
              .batteryCapacityMah,
          5000);
    });

    test('the estimate is used when no design capacity is known', () {
      final calc = const Settings()
          .energyCalc(estimatedFullChargeCapacityMah: estimate.mah!);
      expect(calc.batteryCapacityMah, 3600);
      expect(calc.canEstimateFromPercent, isTrue);
      final e = calc.session(session());
      expect(e.mah, closeTo(3600 * 0.6, 1e-9));
      expect(e.mahEstimated, isTrue);
    });

    test(
        'an unknown design capacity (source unknown) leaves room for the estimate',
        () {
      final calc = const Settings(
              designCapacityMah: 0,
              designCapacitySource: DesignCapacitySource.unknown)
          .energyCalc(estimatedFullChargeCapacityMah: 3600);
      expect(calc.batteryCapacityMah, 3600);
    });

    test(
        'a number without a known source is not a design capacity: the '
        'calculator does not use it', () {
      final incoherent = const Settings(designCapacityMah: 4000)
          .energyCalc(estimatedFullChargeCapacityMah: 3600);
      expect(incoherent.batteryCapacityMah, 3600);
      expect(
          const Settings(designCapacityMah: 4000)
              .energyCalc()
              .batteryCapacityMah,
          0);
    });

    test('neither a design capacity nor an estimate: no % -> mAh estimate', () {
      final none = const Settings().energyCalc();
      expect(none.batteryCapacityMah, 0);
      expect(none.canEstimateFromPercent, isFalse);
      final unavailable = const Settings().energyCalc(
          estimatedFullChargeCapacityMah:
              EstimatedFullChargeCapacity.unavailable.mah ?? 0);
      expect(unavailable.canEstimateFromPercent, isFalse);
      // And a session on it is zero, not NaN and not a guess.
      final e = none.session(session());
      expect([e.mah, e.batteryWh, e.wallWh, e.cost], everyElement(0));
    });

    test('a reading that yields no estimate leaves the calculator without one',
        () {
      for (final chargeUah in <num?>[null, 0, -3600000, double.nan]) {
        final reading = FullChargeCapacityEstimator.estimate(
            chargeUah: chargeUah, level: 100);
        expect(reading.isAvailable, isFalse, reason: '$chargeUah');
        final calc = const Settings().energyCalc(
            estimatedFullChargeCapacityMah:
                reading.isAvailable ? reading.mah ?? 0 : 0);
        expect(calc.canEstimateFromPercent, isFalse, reason: '$chargeUah');
      }
    });
  });
}
