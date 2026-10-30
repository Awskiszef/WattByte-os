// The AI request compares this month so far with the same number of days of the previous month (audit G-14): when the previous
// month is shorter than the days elapsed, the window ends with that month, it never reaches into the current one.
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/ai/ai_input_builder.dart';

DailyData day(int y, int m, int d, int mobileMb) =>
    DailyData(day: DateTime(y, m, d), mobileRx: mobileMb * 1000000);

AiPeriodStats stats(List<DailyData> days, DateTime now) =>
    AiPeriodStats.thisMonth(
      days: days,
      sessions: const [],
      calc: EnergyCalc(
          batteryCapacityMah: 4000,
          nominalVoltage: 3.85,
          efficiency: 0.8,
          pricePerKwh: 1),
      currency: 'PLN',
      now: now,
    );

void main() {
  test(
      'on 31 March the previous period is all of February, not February plus the first days of March',
      () {
    final days = [
      for (var d = 1; d <= 28; d++) day(2026, 2, d, 10), // February: 280 MB
      for (var d = 1; d <= 31; d++) day(2026, 3, d, 20), // March so far: 620 MB
    ];
    final s = stats(days, DateTime(2026, 3, 31, 12));
    expect(s.mobileDataGb, closeTo(0.62, 1e-9));
    // (620 - 280) / 280, not (620 - 280 - 60 spilled-in March days) / 340
    expect(s.previousPeriodChangePercent, closeTo(121.4, 0.05));
  });

  test(
      'on 30 March the same cap applies (28 days of February against 30 elapsed)',
      () {
    final days = [
      for (var d = 1; d <= 28; d++) day(2026, 2, d, 10),
      for (var d = 1; d <= 30; d++) day(2026, 3, d, 20),
    ];
    expect(stats(days, DateTime(2026, 3, 30, 12)).previousPeriodChangePercent,
        closeTo((600 - 280) / 280 * 100, 0.05));
  });

  test('a mid-month day still compares equally long windows', () {
    final days = [
      for (var d = 1; d <= 31; d++) day(2026, 1, d, 10),
      for (var d = 1; d <= 15; d++) day(2026, 2, d, 30),
    ];
    // Feb 1-15 (450 MB) against Jan 1-15 (150 MB)
    expect(stats(days, DateTime(2026, 2, 15, 9)).previousPeriodChangePercent,
        closeTo(200, 0.05));
  });

  test('January looks back to December of the year before', () {
    final days = [
      for (var d = 1; d <= 31; d++) day(2025, 12, d, 10),
      for (var d = 1; d <= 10; d++) day(2026, 1, d, 20),
    ];
    expect(stats(days, DateTime(2026, 1, 10, 9)).previousPeriodChangePercent,
        closeTo(100, 0.05));
  });

  test('no data last month means no percentage', () {
    final days = [for (var d = 1; d <= 5; d++) day(2026, 3, d, 20)];
    expect(stats(days, DateTime(2026, 3, 5, 9)).previousPeriodChangePercent,
        isNull);
  });
}
