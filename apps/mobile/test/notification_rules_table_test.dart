// Every optional notification, at the edges of its rule (audit G-15). The rules run in the background isolate, where
// a wrong one means a message on the lock screen: the boundary values are pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/settings/settings.dart';

final calc = EnergyCalc(
    batteryCapacityMah: 4000,
    nominalVoltage: 3.85,
    efficiency: 0.85,
    pricePerKwh: 1);

DailyData day(DateTime d, {int mobile = 0}) =>
    DailyData(day: d, mobileRx: mobile);

ChargingSession charge(DateTime start, {int hours = 2, int uah = 2000000}) =>
    ChargingSession(
      start: start,
      end: start.add(Duration(hours: hours)),
      startLevel: 20,
      endLevel: 80,
      chargeDeltaUah: uah,
      avgVoltageMv: 3900,
    );

List<PendingNotification> eval(
  Settings settings, {
  required DateTime now,
  List<DailyData> days = const [],
  List<ChargingSession> sessions = const [],
  List<ChargingSession> newlyClosed = const [],
  Set<String> sent = const {},
  bool native = false,
  bool inProgress = false,
}) =>
    evaluateNotifications(
      settings: settings,
      days: days,
      sessions: sessions,
      newlyClosed: newlyClosed,
      calc: calc,
      now: now,
      alreadySent: sent,
      nativeChargingAlerts: native,
      chargeInProgress: inProgress,
    );

void main() {
  group('mobile data threshold', () {
    const s = Settings(notifyMobileThreshold: true, mobileThresholdBytes: 1000);
    final now = DateTime(2026, 10, 14, 15); // Wednesday

    test('fires at the threshold, not one byte below it', () {
      expect(
          eval(s, now: now, days: [day(DateTime(2026, 10, 14), mobile: 1000)])
              .map((p) => p.kind),
          [NotificationKind.mobileThreshold]);
      expect(
          eval(s, now: now, days: [day(DateTime(2026, 10, 14), mobile: 999)]),
          isEmpty);
    });

    test('counts today only, and yesterday does not count', () {
      expect(
          eval(s, now: now, days: [day(DateTime(2026, 10, 13), mobile: 5000)]),
          isEmpty);
    });

    test(
        'carries today\'s bytes and a key per day, and respects the switch and the ledger',
        () {
      final d = [day(DateTime(2026, 10, 14), mobile: 4321)];
      final p = eval(s, now: now, days: d).single;
      expect((p.key, p.value), ('mobile:2026-10-14', 4321));
      expect(eval(s, now: now, days: d, sent: {'mobile:2026-10-14'}), isEmpty);
      expect(
          eval(const Settings(mobileThresholdBytes: 1000), now: now, days: d),
          isEmpty);
      // The next day is a new key.
      expect(
          eval(s,
              now: DateTime(2026, 10, 15, 9),
              days: [day(DateTime(2026, 10, 15), mobile: 1000)]).single.key,
          'mobile:2026-10-15');
    });
  });

  group('above the weekly average', () {
    const s = Settings(notifyAboveAverage: true);
    final now = DateTime(2026, 10, 14, 15);
    // The seven days before today average 1000 bytes a day.
    List<DailyData> week() => [
          for (var i = 1; i <= 7; i++)
            day(DateTime(2026, 10, 14 - i), mobile: 1000)
        ];

    test('fires from exactly 1.3 times the average, not below', () {
      expect(
          eval(s,
                  now: now,
                  days: [...week(), day(DateTime(2026, 10, 14), mobile: 1300)])
              .map((p) => p.kind),
          [NotificationKind.aboveWeeklyAverage]);
      expect(
          eval(s,
              now: now,
              days: [...week(), day(DateTime(2026, 10, 14), mobile: 1299)]),
          isEmpty);
    });

    test('reports the excess in percent and keys it by day', () {
      final p = eval(s,
          now: now,
          days: [...week(), day(DateTime(2026, 10, 14), mobile: 2000)]).single;
      expect(p.value, closeTo(100, 1e-9));
      expect(p.key, 'avg:2026-10-14');
    });

    test('needs a week to compare with, and the 8th day back is not part of it',
        () {
      expect(
          eval(s, now: now, days: [day(DateTime(2026, 10, 14), mobile: 99999)]),
          isEmpty,
          reason: 'no average, no comparison');
      final withOld = [
        ...week(),
        day(DateTime(2026, 10, 6), mobile: 70000),
        day(DateTime(2026, 10, 14), mobile: 1300)
      ];
      expect(eval(s, now: now, days: withOld).length, 1,
          reason: 'the day 8 days back does not raise the average');
    });
  });

  group('weekly energy (G-07)', () {
    const s = Settings(notifyWeeklyEnergy: true);
    // The week 2026-10-12 .. 2026-10-18; Monday 2026-10-19.
    final sessions = [charge(DateTime(2026, 10, 14, 22))];
    List<PendingNotification> at(DateTime now,
            {bool inProgress = false, List<ChargingSession>? sess}) =>
        eval(s, now: now, sessions: sess ?? sessions, inProgress: inProgress);

    test('Monday from 08:00: not at 07:59, yes at 08:00', () {
      expect(at(DateTime(2026, 10, 19, 7, 59)), isEmpty);
      expect(at(DateTime(2026, 10, 19, 8)).map((p) => p.kind),
          [NotificationKind.weeklyEnergy]);
      expect(weeklySummaryFromHour, 8);
    });

    test('Tuesday still delivers it, Wednesday and Sunday do not', () {
      expect(at(DateTime(2026, 10, 20, 9)), hasLength(1));
      expect(at(DateTime(2026, 10, 21, 9)), isEmpty);
      expect(at(DateTime(2026, 10, 25, 9)), isEmpty);
    });

    test('waits while a charge is in progress', () {
      expect(at(DateTime(2026, 10, 19, 9), inProgress: true), isEmpty);
      expect(at(DateTime(2026, 10, 19, 9)), hasLength(1));
    });

    test('is keyed by the Monday that opened the week and carries the wall kWh',
        () {
      final p = at(DateTime(2026, 10, 19, 9)).single;
      expect(p.key, 'week:2026-10-12');
      expect(p.value, closeTo(calc.total(sessions).wallKwh, 1e-9));
      expect(at(DateTime(2026, 10, 20, 9)).single.key, 'week:2026-10-12',
          reason:
              'Tuesday uses the same key, so Monday\'s send is not repeated');
      expect(
          eval(s,
              now: DateTime(2026, 10, 20, 9),
              sessions: sessions,
              sent: {'week:2026-10-12'}),
          isEmpty);
    });

    test('a week without charging, or only the week before, announces nothing',
        () {
      expect(at(DateTime(2026, 10, 19, 9), sess: const []), isEmpty);
      expect(
          at(DateTime(2026, 10, 19, 9),
              sess: [charge(DateTime(2026, 10, 5, 22))]),
          isEmpty);
      expect(
          at(DateTime(2026, 10, 19, 9),
              sess: [charge(DateTime(2026, 10, 19, 1))]),
          isEmpty,
          reason: 'this week\'s charge is not last week\'s');
    });
  });

  group('charging done', () {
    const s = Settings(notifyChargingDone: true);
    final end = DateTime(2026, 10, 14, 23, 0);
    final closed = ChargingSession(
        start: end.subtract(const Duration(hours: 2)),
        end: end,
        startLevel: 20,
        endLevel: 90,
        chargeDeltaUah: 3000000,
        avgVoltageMv: 3900);

    test('only for a session that ended less than 15 minutes ago', () {
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 14, seconds: 59)),
              newlyClosed: [closed]),
          hasLength(1));
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 15)), newlyClosed: [closed]),
          isEmpty);
    });

    test('carries the charge in mAh and is keyed by the end instant', () {
      final p = eval(s,
          now: end.add(const Duration(minutes: 1)),
          newlyClosed: [closed]).single;
      expect(p.key, 'chg:${end.millisecondsSinceEpoch}');
      expect(p.value, closeTo(calc.session(closed).mah, 1e-9));
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 1)),
              newlyClosed: [closed],
              sent: {p.key}),
          isEmpty);
    });

    test(
        'Android posts it natively, so the rule stays silent there; the switch is respected',
        () {
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 1)),
              newlyClosed: [closed],
              native: true),
          isEmpty);
      expect(
          eval(const Settings(),
              now: end.add(const Duration(minutes: 1)), newlyClosed: [closed]),
          isEmpty);
    });

    test('each session is judged by its own end', () {
      final other = ChargingSession(
          start: end.add(const Duration(minutes: 10)),
          end: end.add(const Duration(minutes: 40)),
          startLevel: 90,
          endLevel: 95,
          chargeDeltaUah: 100000,
          avgVoltageMv: 3900);
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 41)),
              newlyClosed: [closed, other]).map((p) => p.key),
          ['chg:${other.end.millisecondsSinceEpoch}'],
          reason: 'the first ended 41 minutes ago, the second one minute ago');
      expect(
          eval(s,
              now: end.add(const Duration(minutes: 14)),
              newlyClosed: [closed, other]),
          hasLength(2));
    });
  });

  test('all switches off means no notification, whatever the data', () {
    final now = DateTime(2026, 10, 19, 9);
    expect(
        eval(const Settings(),
            now: now,
            days: [day(DateTime(2026, 10, 19), mobile: 999999999999)],
            sessions: [charge(DateTime(2026, 10, 14, 22))]),
        isEmpty);
  });
}
