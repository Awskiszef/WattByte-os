// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';

void main() {
  final calc = EnergyCalc(
      batteryCapacityMah: 4000,
      nominalVoltage: 3.85,
      efficiency: 0.85,
      pricePerKwh: 1.15);
  final day = DateTime(2026, 10, 13);

  test('aggregates one local day and survives a JSON round trip', () {
    final agg = DailyAggregate.build(
      day: DateTime(2026, 10, 13, 15, 30),
      days: [
        DailyData(
            day: day, mobileRx: 1000, mobileTx: 200, wifiRx: 5000, wifiTx: 100),
        DailyData(
            day: DateTime(2026, 10, 12),
            mobileRx: 999999), // other day: ignored
      ],
      sessions: [
        ChargingSession(
            start: DateTime(2026, 10, 13, 18, 42),
            end: DateTime(2026, 10, 13, 20, 3),
            startLevel: 21,
            endLevel: 94,
            energyDeltaNwh: 12700000000),
        ChargingSession(
            start: DateTime(2026, 10, 13, 23, 50),
            end: DateTime(2026, 10, 14, 1,
                0), // crosses midnight: counted on its start day
            startLevel: 50,
            endLevel: 60,
            energyDeltaNwh: 1000000000),
        ChargingSession(
            start: DateTime(2026, 10, 14, 8),
            end: DateTime(2026, 10, 14, 9),
            startLevel: 1,
            endLevel: 2),
      ],
      calc: calc,
      currency: 'PLN',
    );
    expect(agg.date, '2026-10-13');
    expect(agg.mobileBytes, 1200);
    expect(agg.wifiBytes, 5100);
    expect(agg.chargingSessions, 2);
    expect(agg.chargedWh, 13.7);
    expect(agg.wallWh, closeTo(13.7 / 0.85, 0.001));
    expect(agg.estimatedCost, closeTo(13.7 / 0.85 / 1000 * 1.15, 0.0001));
    expect(DailyAggregate.fromJson(agg.toJson()), agg);
  });

  test('empty day is flagged so it is not queued', () {
    final agg = DailyAggregate.build(
        day: day,
        days: const [],
        sessions: const [],
        calc: calc,
        currency: 'PLN');
    expect(agg.isEmpty, isTrue);
  });
}
