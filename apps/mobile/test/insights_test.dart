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

  group('weekly energy notification (G-07)', () {
    // Monday 2026-10-19 is the first day after the week 2026-10-12 .. 2026-10-18.
    ChargingSession charge(DateTime start, {int hours = 2}) => ChargingSession(
          start: start,
          end: start.add(Duration(hours: hours)),
          startLevel: 20,
          endLevel: 80,
          chargeDeltaUah: 2000000,
          avgVoltageMv: 3900,
        );
    final week = [
      charge(DateTime(2026, 10, 13, 22)),
      charge(DateTime(2026, 10, 16, 23)),
    ];
    const settings = Settings(notifyWeeklyEnergy: true);

    List<PendingNotification> at(DateTime now,
            {List<ChargingSession>? sessions,
            bool chargeInProgress = false,
            Set<String> sent = const {}}) =>
        evaluateNotifications(
          settings: settings,
          days: const [],
          sessions: sessions ?? week,
          newlyClosed: const [],
          calc: calc,
          now: now,
          alreadySent: sent,
          nativeChargingAlerts: true,
          chargeInProgress: chargeInProgress,
        );

    test('not at midnight: nothing before 08:00 on Monday', () {
      expect(at(DateTime(2026, 10, 19, 0, 5)), isEmpty);
      expect(at(DateTime(2026, 10, 19, 7, 59)), isEmpty);
    });

    test(
        'Monday morning: one summary for the week that ended, with every closed session',
        () {
      final p = at(DateTime(2026, 10, 19, 8, 1));
      expect(p, hasLength(1));
      expect(p.single.kind, NotificationKind.weeklyEnergy);
      expect(p.single.key, 'week:2026-10-12');
      expect(p.single.value, closeTo(calc.total(week).wallKwh, 1e-9));
    });

    test(
        'a charge still in progress holds it back; once it is over the figure includes it',
        () {
      final sundayNight = charge(DateTime(2026, 10, 18, 22), hours: 9);
      final all = [...week, sundayNight];
      expect(
          at(DateTime(2026, 10, 19, 8, 30),
              sessions: week, chargeInProgress: true),
          isEmpty);
      final done = at(DateTime(2026, 10, 19, 9, 30), sessions: all);
      expect(done.single.value, closeTo(calc.total(all).wallKwh, 1e-9));
      expect(done.single.value, greaterThan(calc.total(week).wallKwh),
          reason: 'the Sunday-night charge is in the figure');
    });

    test(
        'Tuesday delivers it when Monday never had a quiet moment, for the same week',
        () {
      final p = at(DateTime(2026, 10, 20, 9));
      expect(p.single.key, 'week:2026-10-12');
      expect(at(DateTime(2026, 10, 20, 9), sent: {'week:2026-10-12'}), isEmpty);
    });

    test('other days, no sessions and an unknown energy send nothing', () {
      expect(at(DateTime(2026, 10, 21, 9)), isEmpty);
      expect(at(DateTime(2026, 10, 19, 9), sessions: const []), isEmpty);
      final noCapacity = EnergyCalc(
          batteryCapacityMah: 0,
          nominalVoltage: 3.85,
          efficiency: 0.85,
          pricePerKwh: 1);
      final unknown = evaluateNotifications(
        settings: settings,
        days: const [],
        sessions: [
          ChargingSession(
              start: DateTime(2026, 10, 14, 22),
              end: DateTime(2026, 10, 15, 6),
              startLevel: 10,
              endLevel: 90)
        ],
        newlyClosed: const [],
        calc: noCapacity,
        now: DateTime(2026, 10, 19, 9),
        alreadySent: const {},
        nativeChargingAlerts: true,
      );
      expect(unknown, isEmpty, reason: 'not announced as 0 kWh');
    });
  });
}
