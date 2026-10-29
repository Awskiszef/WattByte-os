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

/// The weekly energy summary is not sent before this local hour (not at midnight, not with the sound at night).
const weeklySummaryFromHour = 8;

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

  /// A charge is in progress (a plugged phone, an open run of samples): its energy is not in any closed session yet.
  bool chargeInProgress = false,
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

  // The summary of the week that just ended. It used to fire on the first pass after Monday 00:00 from the CLOSED sessions
  // only: a charge that started on Sunday evening was missing from the figure, the dedupe key was spent on that
  // understated number, and the notification arrived at five past midnight (G-07). Now it waits for a civil hour and for
  // the charge to finish, and Tuesday still delivers it if Monday never had a quiet moment.
  if (settings.notifyWeeklyEnergy &&
      (now.weekday == DateTime.monday || now.weekday == DateTime.tuesday) &&
      now.hour >= weeklySummaryFromHour &&
      !chargeInProgress) {
    final thisMonday =
        DateTime(today.year, today.month, today.day - (now.weekday - 1));
    final lastWeek = DateRange(
        DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7),
        thisMonday);
    final e = calc.total(sessionsIn(sessions, lastWeek));
    // An unknown energy is not announced as 0 kWh, and a week without any is not announced at all.
    if (!e.isUnknown && e.wallWh > 0) {
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
