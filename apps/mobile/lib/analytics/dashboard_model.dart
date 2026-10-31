// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import '../calc/energy.dart';
import '../collection/session_builder.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import 'stats.dart';

/// Everything the dashboard shows, computed once from stored data.
class DashboardModel {
  const DashboardModel({
    required this.today,
    required this.todayEnergy,
    required this.chargingNow,
    required this.inProgress,
    required this.last30,
    required this.energyLast30,
    required this.month,
    required this.monthEnergy,
  });

  final DailyData today;

  /// Sessions started today plus the one in progress, if any.
  final SessionEnergy todayEnergy;
  final bool chargingNow;
  final ChargingSession? inProgress;

  /// One entry per day, oldest first, zero-filled.
  final List<DailyData> last30;

  /// Aligned with [last30].
  final List<SessionEnergy> energyLast30;
  final DailyData month;
  final SessionEnergy monthEnergy;

  factory DashboardModel.build({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required List<BatterySample> open,
    required bool chargingNow,
    required EnergyCalc calc,
    required DateTime now,
  }) {
    final todayRange = rangeFor(Period.today, now);
    final today =
        DailyData.sum(daysIn(days, todayRange), day: todayRange.start);

    final inProgress =
        chargingNow ? const SessionBuilder().toSession(open) : null;
    final todaySessions = [
      ...sessionsIn(sessions, todayRange),
      if (inProgress != null && todayRange.contains(inProgress.start))
        inProgress,
    ];

    final r30 = rangeFor(Period.last30Days, now);
    final byDay = {for (final d in daysIn(days, r30)) dayKey(d.day): d};
    final last30 = [
      for (final d in r30.eachDay) byDay[dayKey(d)] ?? DailyData(day: d)
    ];
    final eByDay = energyByDay(sessionsIn(sessions, r30), calc);
    final energyLast30 = [
      for (final d in r30.eachDay) eByDay[d] ?? SessionEnergy.zero
    ];

    final mr = rangeFor(Period.thisMonth, now);
    return DashboardModel(
      today: today,
      todayEnergy: calc.total(todaySessions),
      chargingNow: chargingNow,
      inProgress: inProgress,
      last30: last30,
      energyLast30: energyLast30,
      month: DailyData.sum(daysIn(days, mr), day: mr.start),
      monthEnergy: calc.total(sessionsIn(sessions, mr)),
    );
  }
}
