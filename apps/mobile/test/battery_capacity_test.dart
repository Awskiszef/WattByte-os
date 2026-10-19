import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/battery_capacity.dart';

/// Charge counter (uAh) of a 3600 mAh battery holding [level] percent.
int _chargeAt(int level, {double fullMah = 3600}) =>
    (fullMah * 1000 * level / 100).round();

EstimatedFullChargeCapacity _estimateAt(int level, {int? energyNwh}) =>
    FullChargeCapacityEstimator.estimate(
      chargeUah: _chargeAt(level),
      energyNwh: energyNwh,
      level: level,
      measuredAt: DateTime(2026, 10, 13, 12),
    );

DesignCapacity _design(double mah,
        {double? wh,
        DesignCapacitySource source =
            DesignCapacitySource.localDeviceDatabase}) =>
    DesignCapacity(mah: mah, wh: wh, source: source);

EstimatedFullChargeCapacity _estimate(
  double mah, {
  FullChargeCapacityConfidence confidence = FullChargeCapacityConfidence.high,
  DateTime? measuredAt,
}) =>
    EstimatedFullChargeCapacity(
      mah: mah,
      source: FullChargeCapacitySource.androidChargeCounter,
      confidence: confidence,
      level: 100,
      measuredAt: measuredAt,
    );

void main() {
  final now = DateTime(2026, 10, 13, 12);

  group('enums', () {
    test('design capacity source has no measurement member', () {
      expect(DesignCapacitySource.values.map((e) => e.name), [
        'manufacturerSpecification',
        'localDeviceDatabase',
        'backendDeviceDatabase',
        'manual',
        'unknown',
      ]);
    });

    test('tryParse accepts the wire names and nothing else', () {
      for (final s in DesignCapacitySource.values) {
        expect(DesignCapacitySource.tryParse(s.name), s);
      }
      expect(DesignCapacitySource.tryParse(null), isNull);
      expect(DesignCapacitySource.tryParse(''), isNull);
      expect(DesignCapacitySource.tryParse('system'), isNull);
      expect(DesignCapacitySource.tryParse('estimated'), isNull);
      expect(DesignCapacitySource.tryParse('localDatabase'), isNull);

      for (final s in FullChargeCapacitySource.values) {
        expect(FullChargeCapacitySource.tryParse(s.name), s);
      }
      expect(FullChargeCapacitySource.tryParse(null), isNull);
      expect(FullChargeCapacitySource.tryParse('charge_counter'), isNull);

      for (final c in FullChargeCapacityConfidence.values) {
        expect(FullChargeCapacityConfidence.tryParse(c.name), c);
      }
      expect(FullChargeCapacityConfidence.tryParse(null), isNull);
      expect(FullChargeCapacityConfidence.tryParse('certain'), isNull);
    });

    test('confidence is ordered none < low < medium < high', () {
      const none = FullChargeCapacityConfidence.none;
      const low = FullChargeCapacityConfidence.low;
      const medium = FullChargeCapacityConfidence.medium;
      const high = FullChargeCapacityConfidence.high;
      expect(high.atLeast(high), isTrue);
      expect(high.atLeast(medium), isTrue);
      expect(medium.atLeast(high), isFalse);
      expect(low.atLeast(medium), isFalse);
      expect(low.atLeast(none), isTrue);
      expect(none.atLeast(low), isFalse);
      expect(high.strongerThan(high), isFalse);
      expect(high.strongerThan(medium), isTrue);
    });

    test('none is never sent over the wire', () {
      expect(FullChargeCapacityConfidence.none.wireName, isNull);
      expect(FullChargeCapacityConfidence.low.wireName, 'low');
      expect(FullChargeCapacityConfidence.medium.wireName, 'medium');
      expect(FullChargeCapacityConfidence.high.wireName, 'high');
    });
  });

  group('estimate from the charge counter', () {
    test('charge counter at 100 % -> high confidence', () {
      final e = _estimateAt(100);
      expect(e.isAvailable, isTrue);
      expect(e.mah, closeTo(3600, 1e-9));
      expect(e.level, 100);
      expect(e.confidence, FullChargeCapacityConfidence.high);
      expect(e.source, FullChargeCapacitySource.androidChargeCounter);
      expect(e.measuredAt, now);
      expect(e.wh, isNull); // no energy counter: Wh is not invented
    });

    test('charge counter at 95 % -> high confidence', () {
      final e = _estimateAt(95);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.level, 95);
      expect(e.confidence, FullChargeCapacityConfidence.high);
    });

    test('charge counter at 94 % -> medium confidence', () {
      final e = _estimateAt(94);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.level, 94);
      expect(e.confidence, FullChargeCapacityConfidence.medium);
    });

    test('charge counter at 75 % -> medium confidence', () {
      final e = _estimateAt(75);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.confidence, FullChargeCapacityConfidence.medium);
    });

    test('charge counter at 74 % -> low confidence', () {
      final e = _estimateAt(74);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.level, 74);
      expect(e.confidence, FullChargeCapacityConfidence.low);
    });

    test('charge counter at 50 % -> low confidence, still an estimate', () {
      final e = _estimateAt(50);
      expect(e.isAvailable, isTrue);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.level, 50);
      expect(e.confidence, FullChargeCapacityConfidence.low);
      expect(e.source, FullChargeCapacitySource.androidChargeCounter);
    });

    test('charge counter at 40 % -> low confidence (the minimum level)', () {
      final e = _estimateAt(40);
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.confidence, FullChargeCapacityConfidence.low);
    });

    test('charge counter at 39 % -> no estimate (too far to extrapolate)', () {
      final e = _estimateAt(39);
      expect(e, EstimatedFullChargeCapacity.unavailable);
      expect(e.isAvailable, isFalse);
      expect(e.confidence, FullChargeCapacityConfidence.none);
    });

    test('an aged battery shows up as a lower estimate, not a changed model',
        () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 3420000, // 3420 mAh stored at 95 % -> 3600 mAh full
        level: 95,
      );
      expect(e.mah, closeTo(3600, 1e-6));
      final aged = FullChargeCapacityEstimator.estimate(
        chargeUah: 3150000, // 3150 mAh stored at 100 %
        level: 100,
      );
      expect(aged.mah, 3150);
    });

    test('confidence tracks the level, including fractional levels', () {
      FullChargeCapacityConfidence c(num l) =>
          FullChargeCapacityEstimator.confidenceForLevel(l);
      expect(c(100), FullChargeCapacityConfidence.high);
      expect(c(95), FullChargeCapacityConfidence.high);
      expect(c(94.9), FullChargeCapacityConfidence.medium);
      expect(c(75), FullChargeCapacityConfidence.medium);
      expect(c(74.9), FullChargeCapacityConfidence.low);
      expect(c(40), FullChargeCapacityConfidence.low);
      expect(c(39.9), FullChargeCapacityConfidence.none);
      expect(c(0), FullChargeCapacityConfidence.none);
      expect(c(-1), FullChargeCapacityConfidence.none);
      expect(c(100.1), FullChargeCapacityConfidence.none);
      expect(c(double.nan), FullChargeCapacityConfidence.none);
      expect(c(double.infinity), FullChargeCapacityConfidence.none);
      expect(c(double.negativeInfinity), FullChargeCapacityConfidence.none);
    });

    test('a fractional level is floored in the result', () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 3400000,
        level: 94.6,
      );
      expect(e.level, 94);
      expect(e.confidence, FullChargeCapacityConfidence.medium);
    });
  });

  group('invalid readings never produce an estimate', () {
    const unavailable = EstimatedFullChargeCapacity.unavailable;

    void expectUnavailable(EstimatedFullChargeCapacity e) {
      expect(e, unavailable);
      expect(e.isAvailable, isFalse);
      expect(e.mah, isNull);
      expect(e.wh, isNull);
      expect(e.level, isNull);
      expect(e.confidence, FullChargeCapacityConfidence.none);
      expect(e.source, FullChargeCapacitySource.unknown);
    }

    test('unsupported charge counter (null)', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
        chargeUah: null,
        energyNwh: 13860000000,
        level: 100,
      ));
    });

    test('negative charge counter', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: -3600000, level: 100));
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: -1, level: 100));
    });

    test('zero charge counter', () {
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 0, level: 100));
    });

    test('battery level = 0', () {
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 120000, level: 0));
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 0));
    });

    test('negative level (unknown level is -1)', () {
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: -1));
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: -50));
    });

    test('level above 100', () {
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 101));
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 250));
    });

    test('NaN in the charge, the level and the energy', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: double.nan, level: 100));
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000, level: double.nan));
      // A NaN energy counter only costs the Wh value, never the mAh estimate.
      final e = FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000, energyNwh: double.nan, level: 100);
      expect(e.isAvailable, isTrue);
      expect(e.mah, 3600);
      expect(e.wh, isNull);
    });

    test('+Infinity and -Infinity in the charge', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: double.infinity, level: 100));
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: double.negativeInfinity, level: 100));
    });

    test('+Infinity and -Infinity in the level', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000, level: double.infinity));
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000, level: double.negativeInfinity));
    });

    test('+Infinity and -Infinity in the energy drop only the Wh value', () {
      for (final v in [double.infinity, double.negativeInfinity]) {
        final e = FullChargeCapacityEstimator.estimate(
            chargeUah: 3600000, energyNwh: v, level: 100);
        expect(e.mah, 3600);
        expect(e.wh, isNull);
      }
    });

    test('a counter that reports mAh instead of uAh is implausible', () {
      // 3600 "uAh" is 3.6 mAh: not a phone battery.
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600, level: 100));
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 3600, level: 95));
      // 99 mAh at 100 % is below the plausibility floor, 100 mAh is allowed.
      expectUnavailable(
          FullChargeCapacityEstimator.estimate(chargeUah: 99000, level: 100));
      expect(
          FullChargeCapacityEstimator.estimate(chargeUah: 100000, level: 100)
              .isAvailable,
          isTrue);
    });

    test('an absurdly large counter is implausible', () {
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 90000000000, level: 100));
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 30001000, level: 100)); // just above 30 000 mAh
      expect(
          FullChargeCapacityEstimator.estimate(chargeUah: 30000000, level: 100)
              .mah,
          30000);
      // Extrapolating a small plausible counter at a low level can overshoot.
      expectUnavailable(FullChargeCapacityEstimator.estimate(
          chargeUah: 13000000, level: 40)); // 32 500 mAh
    });

    test('failures are a plain result, never an exception', () {
      expect(
          () => FullChargeCapacityEstimator.estimate(
              chargeUah: double.nan, energyNwh: double.nan, level: double.nan),
          returnsNormally);
    });
  });

  group('Wh from the energy counter', () {
    // 3600 mAh at 3.85 V = 13.86 Wh
    const energyNwh = 13860000000;

    test('a valid energy counter gives Wh next to mAh', () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 3600000,
        energyNwh: energyNwh,
        level: 100,
      );
      expect(e.mah, 3600);
      expect(e.wh, closeTo(13.86, 1e-9));
    });

    test('Wh is extrapolated with the same fraction as mAh', () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 1800000,
        energyNwh: energyNwh ~/ 2,
        level: 50,
      );
      expect(e.mah, closeTo(3600, 1e-6));
      expect(e.wh, closeTo(13.86, 1e-6));
    });

    test('an unsupported energy counter keeps mAh and leaves Wh null', () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 3600000,
        energyNwh: null,
        level: 100,
      );
      expect(e.mah, 3600);
      expect(e.wh, isNull);
    });

    test('a zero or negative energy counter keeps mAh and leaves Wh null', () {
      for (final v in [0, -13860000000]) {
        final e = FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000,
          energyNwh: v,
          level: 100,
        );
        expect(e.mah, 3600);
        expect(e.wh, isNull);
      }
    });

    test('an energy counter above 200 Wh is dropped', () {
      final e = FullChargeCapacityEstimator.estimate(
        chargeUah: 30000000, // 30 000 mAh: plausible edge
        energyNwh: 201000000000, // 201 Wh
        level: 100,
      );
      expect(e.mah, 30000);
      expect(e.wh, isNull);
    });

    test('an energy counter implying an impossible voltage is dropped', () {
      // 100 Wh for 3.6 Ah is 27.8 V
      final high = FullChargeCapacityEstimator.estimate(
        chargeUah: 3600000,
        energyNwh: 100000000000,
        level: 100,
      );
      expect(high.mah, 3600);
      expect(high.wh, isNull);
      // 5 Wh for 3.6 Ah is 1.4 V
      final low = FullChargeCapacityEstimator.estimate(
        chargeUah: 3600000,
        energyNwh: 5000000000,
        level: 100,
      );
      expect(low.mah, 3600);
      expect(low.wh, isNull);
    });

    test('voltage bounds follow EnergyCalc and are inclusive', () {
      final lo = FullChargeCapacityEstimator.estimate(
        chargeUah: 4000000,
        energyNwh: (EnergyCalc.minVoltage * 4 * 1e9).round(),
        level: 100,
      );
      expect(lo.wh, closeTo(10, 1e-9));
      final hi = FullChargeCapacityEstimator.estimate(
        chargeUah: 4000000,
        energyNwh: (EnergyCalc.maxVoltage * 4 * 1e9).round(),
        level: 100,
      );
      expect(hi.wh, closeTo(20, 1e-9));
    });

    test('Wh is never derived from an assumed voltage', () {
      expect(_estimateAt(100).wh, isNull);
      expect(_estimateAt(60).wh, isNull);
    });
  });

  group('DesignCapacity normalisation', () {
    test('a valid design capacity keeps its numbers and source', () {
      final d = DesignCapacity(
        mah: 4000,
        wh: 15.4,
        source: DesignCapacitySource.localDeviceDatabase,
      );
      expect(d.isKnown, isTrue);
      expect(d.mah, 4000);
      expect(d.wh, 15.4);
      expect(d.source, DesignCapacitySource.localDeviceDatabase);
    });

    test('NaN, infinite, negative, zero and null mAh become unknown', () {
      for (final v in <double?>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -4000,
        -0.0,
        0,
        null,
      ]) {
        final d = DesignCapacity(
            mah: v, wh: 15.4, source: DesignCapacitySource.localDeviceDatabase);
        expect(d, DesignCapacity.unknown, reason: 'mah=$v');
        expect(d.isKnown, isFalse);
        expect(d.mah, isNull);
        expect(d.wh, isNull);
        expect(d.source, DesignCapacitySource.unknown);
      }
    });

    test('mAh above the maximum becomes unknown, the maximum is allowed', () {
      expect(
        DesignCapacity(
            mah: EnergyCalc.maxCapacityMah + 1,
            source: DesignCapacitySource.manual),
        DesignCapacity.unknown,
      );
      expect(
        DesignCapacity(
                mah: EnergyCalc.maxCapacityMah,
                source: DesignCapacitySource.manual)
            .mah,
        EnergyCalc.maxCapacityMah,
      );
    });

    test('source unknown carries no numbers even when numbers are given', () {
      final d = DesignCapacity(
          mah: 4000, wh: 15.4, source: DesignCapacitySource.unknown);
      expect(d, DesignCapacity.unknown);
      expect(d.mah, isNull);
      expect(d.wh, isNull);
    });

    test('an invalid Wh is dropped while a valid mAh stays', () {
      for (final w in <double?>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
        0,
        EnergyCalc.maxCapacityWh + 1,
        null,
      ]) {
        final d = DesignCapacity(
            mah: 4000, wh: w, source: DesignCapacitySource.manual);
        expect(d.isKnown, isTrue, reason: 'wh=$w');
        expect(d.mah, 4000);
        expect(d.wh, isNull);
        expect(d.source, DesignCapacitySource.manual);
      }
    });

    test('every non-unknown source is accepted', () {
      for (final s in DesignCapacitySource.values) {
        final d = DesignCapacity(mah: 4000, source: s);
        expect(d.isKnown, s != DesignCapacitySource.unknown);
      }
    });

    test('equality and toString', () {
      final a = DesignCapacity(mah: 4000, source: DesignCapacitySource.manual);
      final b = DesignCapacity(mah: 4000, source: DesignCapacitySource.manual);
      final c = DesignCapacity(
          mah: 4000, source: DesignCapacitySource.localDeviceDatabase);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('manual'));
    });
  });

  group('DesignCapacity.resolve priority', () {
    final local = _design(4000, wh: 15.4);
    final backend =
        _design(3900, source: DesignCapacitySource.backendDeviceDatabase);
    final manual = _design(3800, source: DesignCapacitySource.manual);

    test('known device from the local catalog wins over everything', () {
      final d = DesignCapacity.resolve(
          local: local, backend: backend, manual: manual);
      expect(d, local);
      expect(d.source, DesignCapacitySource.localDeviceDatabase);
    });

    test('backend catalog fallback when the local catalog does not know', () {
      final d = DesignCapacity.resolve(
          local: DesignCapacity.unknown, backend: backend, manual: manual);
      expect(d, backend);
      expect(d.source, DesignCapacitySource.backendDeviceDatabase);
      expect(DesignCapacity.resolve(backend: backend, manual: manual), backend);
    });

    test('manual design capacity when no catalog knows the device', () {
      final d = DesignCapacity.resolve(
          local: DesignCapacity.unknown,
          backend: DesignCapacity.unknown,
          manual: manual);
      expect(d, manual);
      expect(d.source, DesignCapacitySource.manual);
      expect(DesignCapacity.resolve(manual: manual), manual);
    });

    test('manual value survives when the catalogs are empty (null)', () {
      expect(DesignCapacity.resolve(local: null, backend: null, manual: manual),
          manual);
    });

    test('unknown device: nothing known stays unknown', () {
      expect(DesignCapacity.resolve(), DesignCapacity.unknown);
      expect(
        DesignCapacity.resolve(
            local: DesignCapacity.unknown,
            backend: DesignCapacity.unknown,
            manual: DesignCapacity.unknown),
        DesignCapacity.unknown,
      );
      expect(DesignCapacity.resolve().isKnown, isFalse);
    });

    test('an unknown candidate is skipped, not returned early', () {
      expect(
        DesignCapacity.resolve(local: DesignCapacity.unknown, backend: backend),
        backend,
      );
      // A candidate that normalised to unknown (invalid number) is skipped too.
      final broken = DesignCapacity(
          mah: double.nan, source: DesignCapacitySource.localDeviceDatabase);
      expect(DesignCapacity.resolve(local: broken, manual: manual), manual);
    });
  });

  group('prefer()', () {
    final fresh = now.subtract(const Duration(days: 7));

    test('the higher confidence is kept against a newer lower one', () {
      final stored = _estimate(3600, measuredAt: fresh);
      final candidate = _estimate(3590,
          confidence: FullChargeCapacityConfidence.low, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        stored,
      );
    });

    test('a 45 % reading does not overwrite a 100 % reading from last week',
        () {
      final stored = FullChargeCapacityEstimator.estimate(
        chargeUah: 3600000,
        level: 100,
        measuredAt: fresh,
      );
      final candidate = FullChargeCapacityEstimator.estimate(
        chargeUah: 1600000,
        level: 45,
        measuredAt: now,
      );
      expect(candidate.confidence, FullChargeCapacityConfidence.low);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        stored,
      );
    });

    test('an equal confidence is replaced by the newer reading', () {
      final stored = _estimate(3600, measuredAt: fresh);
      final candidate = _estimate(3580, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        candidate,
      );
    });

    test('a higher confidence replaces a lower stored one', () {
      final stored = _estimate(3500,
          confidence: FullChargeCapacityConfidence.low, measuredAt: fresh);
      final candidate = _estimate(3600, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        candidate,
      );
    });

    test('a stale stored estimate is replaced even by a lower confidence', () {
      final stale = now.subtract(const Duration(days: 31));
      final stored = _estimate(3600, measuredAt: stale);
      final candidate = _estimate(3400,
          confidence: FullChargeCapacityConfidence.low, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        candidate,
      );
    });

    test('exactly 30 days old is not yet stale', () {
      final edge = now.subtract(FullChargeCapacityEstimator.staleAfter);
      final stored = _estimate(3600, measuredAt: edge);
      final candidate = _estimate(3400,
          confidence: FullChargeCapacityConfidence.low, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        stored,
      );
    });

    test('a stored estimate without a timestamp is replaced', () {
      final stored = _estimate(3600); // measuredAt: null
      final candidate = _estimate(3400,
          confidence: FullChargeCapacityConfidence.low, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now),
        candidate,
      );
    });

    test('absent stored estimate: the candidate is taken', () {
      final candidate = _estimate(3600, measuredAt: now);
      expect(
        FullChargeCapacityEstimator.prefer(null, candidate, now: now),
        candidate,
      );
      expect(
        FullChargeCapacityEstimator.prefer(
            EstimatedFullChargeCapacity.unavailable, candidate,
            now: now),
        candidate,
      );
    });

    test('an unavailable candidate never replaces anything', () {
      final stored = _estimate(3600, measuredAt: fresh);
      expect(
        FullChargeCapacityEstimator.prefer(
            stored, EstimatedFullChargeCapacity.unavailable,
            now: now),
        stored,
      );
      expect(
        FullChargeCapacityEstimator.prefer(
            stored, EstimatedFullChargeCapacity.unavailable,
            now: now.add(const Duration(days: 400))),
        stored,
      );
      expect(
        FullChargeCapacityEstimator.prefer(
            null, EstimatedFullChargeCapacity.unavailable,
            now: now),
        EstimatedFullChargeCapacity.unavailable,
      );
    });
  });

  group('meta table round trip', () {
    test('an estimate survives toMeta / fromMeta', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1760352000000);
      final original = FullChargeCapacityEstimator.estimate(
        chargeUah: 3420000,
        energyNwh: 13167000000,
        level: 95,
        measuredAt: at,
      );
      final meta = original.toMeta();
      expect(
          meta.keys,
          containsAll([
            EstimatedFullChargeCapacity.metaMahKey,
            EstimatedFullChargeCapacity.metaLevelKey,
            EstimatedFullChargeCapacity.metaWhKey,
            EstimatedFullChargeCapacity.metaMeasuredAtKey,
          ]));
      expect(EstimatedFullChargeCapacity.fromMeta(meta), original);
    });

    test('an unavailable estimate writes nothing', () {
      expect(EstimatedFullChargeCapacity.unavailable.toMeta(), isEmpty);
    });

    test('the older layout (mAh + level only) is read as an estimate', () {
      final e = EstimatedFullChargeCapacity.fromMeta({
        EstimatedFullChargeCapacity.metaMahKey: '3600',
        EstimatedFullChargeCapacity.metaLevelKey: '97',
      });
      expect(e.mah, 3600);
      expect(e.level, 97);
      expect(e.confidence, FullChargeCapacityConfidence.high);
      expect(e.source, FullChargeCapacitySource.androidChargeCounter);
      expect(e.wh, isNull);
      expect(e.measuredAt, isNull);
      final partial = EstimatedFullChargeCapacity.fromMeta({
        EstimatedFullChargeCapacity.metaMahKey: '3600',
        EstimatedFullChargeCapacity.metaLevelKey: '60',
      });
      expect(partial.confidence, FullChargeCapacityConfidence.low);
    });

    test('missing, unparsable and implausible meta values give no estimate',
        () {
      const unavailable = EstimatedFullChargeCapacity.unavailable;
      const mahKey = EstimatedFullChargeCapacity.metaMahKey;
      const levelKey = EstimatedFullChargeCapacity.metaLevelKey;
      expect(EstimatedFullChargeCapacity.fromMeta({}), unavailable);
      expect(EstimatedFullChargeCapacity.fromMeta({mahKey: '3600'}),
          unavailable); // no level: no confidence
      expect(
          EstimatedFullChargeCapacity.fromMeta({levelKey: '100'}), unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta(
              {mahKey: 'NaN', levelKey: '100'}),
          unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta(
              {mahKey: 'Infinity', levelKey: '100'}),
          unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta({mahKey: '-3', levelKey: '100'}),
          unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta(
              {mahKey: '999999', levelKey: '100'}),
          unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta(
              {mahKey: '3600', levelKey: '10'}),
          unavailable);
      expect(
          EstimatedFullChargeCapacity.fromMeta(
              {mahKey: '3600', levelKey: '1000'}),
          unavailable);
    });

    test('an implausible stored Wh or timestamp is dropped, mAh stays', () {
      final e = EstimatedFullChargeCapacity.fromMeta({
        EstimatedFullChargeCapacity.metaMahKey: '3600',
        EstimatedFullChargeCapacity.metaLevelKey: '100',
        EstimatedFullChargeCapacity.metaWhKey: '90', // 25 V
        EstimatedFullChargeCapacity.metaMeasuredAtKey: '99999999999999999999',
      });
      expect(e.mah, 3600);
      expect(e.wh, isNull);
      expect(e.measuredAt, isNull);
    });
  });

  group('estimated battery health', () {
    test('design = 4000, estimatedFull = 3600 -> health = 90 %', () {
      final h = calculateEstimatedBatteryHealth(
        _design(4000),
        _estimate(3600),
      );
      expect(h, isNotNull);
      expect(h!.percent, 90.0);
      expect(h.confidence, FullChargeCapacityConfidence.high);
    });

    test('the same figures from a real 100 % reading', () {
      final h = calculateEstimatedBatteryHealth(
        _design(4000),
        FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100),
      );
      expect(h!.percent, 90.0);
    });

    test('medium confidence is accepted and reported', () {
      final h = calculateEstimatedBatteryHealth(
        _design(4000),
        _estimate(3600, confidence: FullChargeCapacityConfidence.medium),
      );
      expect(h!.percent, 90.0);
      expect(h.confidence, FullChargeCapacityConfidence.medium);
    });

    test('low confidence -> no result', () {
      expect(
        calculateEstimatedBatteryHealth(
          _design(4000),
          _estimate(3600, confidence: FullChargeCapacityConfidence.low),
        ),
        isNull,
      );
      expect(
        calculateEstimatedBatteryHealth(
            _design(4000), _estimateAt(50)), // a real 50 % reading
        isNull,
      );
    });

    test('unavailable estimate -> no result', () {
      expect(
        calculateEstimatedBatteryHealth(
            _design(4000), EstimatedFullChargeCapacity.unavailable),
        isNull,
      );
      expect(
        calculateEstimatedBatteryHealth(
            _design(4000), _estimateAt(39)), // too low to estimate at all
        isNull,
      );
    });

    test('estimate with an unknown source or confidence none -> no result', () {
      expect(
        calculateEstimatedBatteryHealth(
          _design(4000),
          const EstimatedFullChargeCapacity(
            mah: 3600,
            source: FullChargeCapacitySource.unknown,
            confidence: FullChargeCapacityConfidence.high,
          ),
        ),
        isNull,
      );
      expect(
        calculateEstimatedBatteryHealth(
          _design(4000),
          const EstimatedFullChargeCapacity(
            mah: 3600,
            source: FullChargeCapacitySource.androidChargeCounter,
          ),
        ),
        isNull,
      );
    });

    test('unknown design capacity -> no result', () {
      expect(
        calculateEstimatedBatteryHealth(
            DesignCapacity.unknown, _estimate(3600)),
        isNull,
      );
      expect(
        calculateEstimatedBatteryHealth(
          DesignCapacity(
              mah: double.nan,
              source: DesignCapacitySource.localDeviceDatabase),
          _estimate(3600),
        ),
        isNull,
      );
    });

    test('a ratio above 1.0 is capped at 100 %', () {
      final h = calculateEstimatedBatteryHealth(
        _design(3000),
        _estimate(3300), // 110 %
      );
      expect(h!.percent, 100.0);
    });

    test('a ratio of exactly 1.0 is 100 %', () {
      expect(
        calculateEstimatedBatteryHealth(_design(3600), _estimate(3600))!
            .percent,
        100.0,
      );
    });

    test('ratio bounds 0.30 and 1.20 are inclusive, outside is no result', () {
      expect(
        calculateEstimatedBatteryHealth(_design(4000), _estimate(1200))!
            .percent,
        30.0,
      );
      expect(
        calculateEstimatedBatteryHealth(_design(4000), _estimate(1199)),
        isNull,
      );
      expect(
        calculateEstimatedBatteryHealth(_design(4000), _estimate(4800))!
            .percent,
        100.0,
      );
      expect(
        calculateEstimatedBatteryHealth(_design(4000), _estimate(4801)),
        isNull,
      );
      // 8000 mAh estimated against a 3000 mAh design: the design figure is wrong.
      expect(
        calculateEstimatedBatteryHealth(_design(3000), _estimate(8000)),
        isNull,
      );
      // 900 mAh against 4000 mAh: the reading is wrong.
      expect(
        calculateEstimatedBatteryHealth(_design(4000), _estimate(900)),
        isNull,
      );
    });

    test('NaN and Infinity -> no result, never a NaN percentage', () {
      for (final v in [double.nan, double.infinity, double.negativeInfinity]) {
        final broken = EstimatedFullChargeCapacity(
          mah: v,
          source: FullChargeCapacitySource.androidChargeCounter,
          confidence: FullChargeCapacityConfidence.high,
        );
        expect(broken.isAvailable, isFalse, reason: 'mah=$v');
        expect(calculateEstimatedBatteryHealth(_design(4000), broken), isNull,
            reason: 'mah=$v');
      }
    });

    test('a manual design capacity is a valid basis', () {
      final h = calculateEstimatedBatteryHealth(
        _design(4000, source: DesignCapacitySource.manual),
        _estimate(3800),
      );
      expect(h!.percent, 95.0);
    });

    test('equality and toString', () {
      const a = EstimatedBatteryHealth(
          percent: 90, confidence: FullChargeCapacityConfidence.high);
      const b = EstimatedBatteryHealth(
          percent: 90, confidence: FullChargeCapacityConfidence.high);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('90'));
    });
  });

  group('Android charge counter != design capacity', () {
    // A 3600 mAh charge counter reading at 100 % exists, but the catalogs do not
    // know this device: the design capacity must stay unknown.
    final estimate = FullChargeCapacityEstimator.estimate(
      chargeUah: 3600000,
      level: 100,
      measuredAt: now,
    );

    test('an estimate exists but resolve() on an unknown device stays unknown',
        () {
      expect(estimate.isAvailable, isTrue);
      expect(estimate.mah, 3600);

      final design = DesignCapacity.resolve(
        local: DesignCapacity.unknown,
        backend: DesignCapacity.unknown,
      );
      expect(design, DesignCapacity.unknown);
      expect(design.isKnown, isFalse);
      expect(design.mah, isNull);
      expect(design.wh, isNull);
      expect(design.source, DesignCapacitySource.unknown);
    });

    test('with no design capacity there is no battery health either', () {
      final design = DesignCapacity.resolve();
      expect(calculateEstimatedBatteryHealth(design, estimate), isNull);
    });

    test('the two values are different objects with different sources', () {
      final design = _design(4000);
      expect(design, isNot(same(estimate)));
      expect(design.runtimeType, isNot(estimate.runtimeType));
      expect(design.source, isA<DesignCapacitySource>());
      expect(estimate.source, isA<FullChargeCapacitySource>());
      expect(design.source.name, isNot(estimate.source.name));
      // Same wire vocabulary never overlaps except the shared word "unknown".
      final designNames =
          DesignCapacitySource.values.map((e) => e.name).toSet();
      final measuredNames =
          FullChargeCapacitySource.values.map((e) => e.name).toSet();
      expect(designNames.intersection(measuredNames), {'unknown'});
      expect(designNames, isNot(contains('androidChargeCounter')));
      expect(designNames, isNot(contains('system')));
      expect(designNames, isNot(contains('estimated')));
    });

    test('a design capacity cannot be built from a measurement source', () {
      expect(DesignCapacitySource.tryParse('androidChargeCounter'), isNull);
      expect(DesignCapacitySource.tryParse('system'), isNull);
      expect(DesignCapacitySource.tryParse('estimated'), isNull);
    });

    test('a known design capacity is not changed by an estimate', () {
      final design = DesignCapacity.resolve(local: _design(4000));
      expect(design.mah, 4000);
      expect(design.mah, isNot(estimate.mah));
      expect(design.source, DesignCapacitySource.localDeviceDatabase);
    });

    test('only user input fills the gap, and it is labelled manual', () {
      final design = DesignCapacity.resolve(
        manual: DesignCapacity(mah: 4100, source: DesignCapacitySource.manual),
      );
      expect(design.source, DesignCapacitySource.manual);
      expect(design.mah, 4100);
      expect(design.mah, isNot(estimate.mah));
    });
  });
}
