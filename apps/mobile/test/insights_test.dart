import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/analytics/insights.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/settings/settings.dart';

void main() {
  final now = DateTime(2026, 10, 13, 20); // Tuesday
  final calc = EnergyCalc(
      batteryCapacityMah: 4000,
      nominalVoltage: 3.85,
      efficiency: 0.85,
      pricePerKwh: 1.15);
  DailyData day(int daysAgo, {int mobile = 0, int wifi = 0}) => DailyData(
        day: DateTime(2026, 10, 13 - daysAgo),
        mobileRx: mobile,
        wifiRx: wifi,
      );

  test('week-over-week mobile change and Wi-Fi share', () {
    final days = [
      for (var i = 0; i < 7; i++) day(i, mobile: 124, wifi: 876),
      for (var i = 7; i < 14; i++) day(i, mobile: 100),
    ];
    final insights =
        generateInsights(days: days, sessions: const [], calc: calc, now: now);
    final change =
        insights.singleWhere((i) => i.kind == InsightKind.mobileVsLastWeek);
    expect(change.value, closeTo(24, 1e-9));
    final share = insights.singleWhere((i) => i.kind == InsightKind.wifiShare);
    // wifi 876*7 / (wifi + 124*7 + 100*7)
    expect(share.value, closeTo(79.64, 0.01));
  });

  test('notification rules respect switches, thresholds and dedupe keys', () {
    final days = [
      day(0, mobile: 5100000000),
      for (var i = 1; i <= 7; i++) day(i, mobile: 1000000000)
    ];
    const settings =
        Settings(notifyMobileThreshold: true, notifyAboveAverage: true);
    final pending = evaluateNotifications(
      settings: settings,
      days: days,
      sessions: const [],
      newlyClosed: const [],
      calc: calc,
      now: now,
      alreadySent: {'avg:2026-10-13'},
      nativeChargingAlerts: true,
    );
    expect(pending.map((p) => p.kind), [NotificationKind.mobileThreshold]);
    expect(pending.single.key, 'mobile:2026-10-13');
  });
}
