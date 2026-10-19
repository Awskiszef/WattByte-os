import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import '../settings/settings.dart';
import 'stats.dart';

enum NotificationKind {
  mobileThreshold,
  chargingDone,
  weeklyEnergy,
  aboveWeeklyAverage
}

class PendingNotification {
  const PendingNotification(this.kind, this.key, this.value);

  final NotificationKind kind;

  /// Dedupe key; a notification with a key already sent is skipped.
  final String key;
  final double value;
}

/// Decides which optional notifications are due. Pure; the caller shows them.
List<PendingNotification> evaluateNotifications({
  required Settings settings,
  required List<DailyData> days,
  required List<ChargingSession> sessions,
  required List<ChargingSession> newlyClosed,
  required EnergyCalc calc,
  required DateTime now,
  required Set<String> alreadySent,

  /// Android posts "charging completed" natively from the worker.
  required bool nativeChargingAlerts,
}) {
  final out = <PendingNotification>[];
  void add(NotificationKind k, String key, double v) {
    if (!alreadySent.contains(key)) out.add(PendingNotification(k, key, v));
  }

  final today = dayOf(now);
  final todayKey = dayKey(today);
  final todayData = DailyData.sum(daysIn(days, rangeFor(Period.today, now)));

  if (settings.notifyMobileThreshold &&
      todayData.mobile >= settings.mobileThresholdBytes) {
    add(NotificationKind.mobileThreshold, 'mobile:$todayKey',
        todayData.mobile.toDouble());
  }

  if (settings.notifyAboveAverage) {
    final prevWeek =
        DateRange(DateTime(today.year, today.month, today.day - 7), today);
    final avg = DailyData.sum(daysIn(days, prevWeek)).mobile / 7;
    if (avg > 0 && todayData.mobile >= avg * 1.3) {
      add(NotificationKind.aboveWeeklyAverage, 'avg:$todayKey',
          (todayData.mobile / avg - 1) * 100);
    }
  }

  if (settings.notifyWeeklyEnergy && now.weekday == DateTime.monday) {
    final lastWeek =
        DateRange(DateTime(today.year, today.month, today.day - 7), today);
    final e = calc.total(sessionsIn(sessions, lastWeek));
    if (e.wallWh > 0) {
      add(NotificationKind.weeklyEnergy, 'week:${dayKey(lastWeek.start)}',
          e.wallKwh);
    }
  }

  if (settings.notifyChargingDone && !nativeChargingAlerts) {
    for (final s in newlyClosed) {
      if (now.difference(s.end) < const Duration(minutes: 15)) {
        add(NotificationKind.chargingDone,
            'chg:${s.end.millisecondsSinceEpoch}', calc.session(s).mah);
      }
    }
  }
  return out;
}
