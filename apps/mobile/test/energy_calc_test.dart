// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';

void main() {
  final calc = EnergyCalc(
    batteryCapacityMah: 4500,
    nominalVoltage: 3.85,
    efficiency: 0.85,
    pricePerKwh: 1.15,
  );
  final t0 = DateTime(2026, 10, 13, 18, 42);
  final t1 = DateTime(2026, 10, 13, 20, 3);

  test('formulas from the spec', () {
    expect(EnergyCalc.whFromMah(1000, 3.85), 3.85);
    expect(EnergyCalc.kwhFromWh(15.2), closeTo(0.0152, 1e-12));
    expect(EnergyCalc.wallFromBattery(15, 0.85), closeTo(17.647, 0.001));
    expect(EnergyCalc.costOf(0.5, 1.15), closeTo(0.575, 1e-12));
  });

  test('charge counter -> measured mAh, estimated Wh via voltage', () {
    final e = calc.session(ChargingSession(
      start: t0,
      end: t1,
      startLevel: 21,
      endLevel: 94,
      chargeDeltaUah: 3285000,
      avgVoltageMv: 3900,
    ));
    expect(e.mah, 3285);
    expect(e.mahEstimated, isFalse);
    expect(e.whEstimated, isTrue);
    expect(e.batteryWh, closeTo(3285 * 3.9 / 1000, 1e-9));
  });

  test('no counters -> capacity x percent, all estimated', () {
    final e = calc.session(
        ChargingSession(start: t0, end: t1, startLevel: 21, endLevel: 94));
    expect(e.mah, closeTo(4500 * 0.73, 1e-9));
    expect(e.mahEstimated, isTrue);
    expect(e.whEstimated, isTrue);
    expect(e.batteryWh, closeTo(EnergyCalc.whFromMah(4500 * 0.73, 3.85), 1e-9));
  });

  test('energy counter wins and feeds wall energy and cost', () {
    final e = calc.session(ChargingSession(
      start: t0,
      end: t1,
      startLevel: 21,
      endLevel: 94,
      chargeDeltaUah: 3285000,
      energyDeltaNwh: 12700000000,
    ));
    expect(e.batteryWh, closeTo(12.7, 1e-9));
    expect(e.whEstimated, isFalse);
    expect(e.wallWh, closeTo(12.7 / 0.85, 1e-9));
    expect(e.cost, closeTo(12.7 / 0.85 / 1000 * 1.15, 1e-9));
  });

  test('a non-positive counter delta falls back to the estimate', () {
    final e = calc.session(ChargingSession(
        start: t0,
        end: t1,
        startLevel: 50,
        endLevel: 60,
        chargeDeltaUah: -5000));
    expect(e.mahEstimated, isTrue);
    expect(e.mah, closeTo(450, 1e-9));
  });
}
