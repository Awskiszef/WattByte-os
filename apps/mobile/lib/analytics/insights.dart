// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import 'stats.dart';

/// Kinds of automatic, non-alarmist observations. The UI owns the wording.
enum InsightKind {
  /// [Insight.value] = percent change of mobile data, last 7 days vs the 7 before.
  mobileVsLastWeek,

  /// value = number of charging sessions in the last 7 days.
  chargesThisWeek,

  /// value = wall kWh this month.
  energyThisMonth,

  /// value = estimated cost this month.
  costThisMonth,

  /// value = Wi-Fi share of total data (percent) over the last 30 days.
  wifiShare,

  /// value = average mAh per session over the last 30 days.
  avgSessionMah,
}

class Insight {
  const Insight(this.kind, this.value, {this.estimated = false});

  final InsightKind kind;
  final double value;
  final bool estimated;
}

List<Insight> generateInsights({
  required List<DailyData> days,
  required List<ChargingSession> sessions,
  required EnergyCalc calc,
  required DateTime now,
}) {
  final out = <Insight>[];

  final cur = DailyData.sum(daysIn(days, rangeFor(Period.last7Days, now)));
  final prev = DailyData.sum(daysIn(days, previous7Days(now)));
  if (prev.mobile > 0 && cur.mobile > 0) {
    final pct = (cur.mobile - prev.mobile) / prev.mobile * 100;
    if (pct.abs() >= 1) {
      out.add(Insight(InsightKind.mobileVsLastWeek, pct,
          estimated: cur.estimated || prev.estimated));
    }
  }

  final week = sessionsIn(sessions, rangeFor(Period.last7Days, now));
  if (week.isNotEmpty) {
    out.add(Insight(InsightKind.chargesThisWeek, week.length.toDouble()));
  }

  final month = sessionsIn(sessions, rangeFor(Period.thisMonth, now));
  if (month.isNotEmpty) {
    final e = calc.total(month);
    if (e.wallWh > 0) {
      // Wall energy always goes through the efficiency assumption -> estimated.
      out.add(Insight(InsightKind.energyThisMonth, e.wallKwh, estimated: true));
      if (calc.pricePerKwh > 0) {
        out.add(Insight(InsightKind.costThisMonth, e.cost, estimated: true));
      }
    }
  }

  final last30 = DailyData.sum(daysIn(days, rangeFor(Period.last30Days, now)));
  if (last30.total > 0) {
    out.add(Insight(InsightKind.wifiShare, last30.wifi / last30.total * 100,
        estimated: last30.estimated));
  }

  final recent = sessionsIn(sessions, rangeFor(Period.last30Days, now));
  if (recent.length >= 2) {
    final e = calc.total(recent);
    if (e.mah > 0) {
      out.add(Insight(InsightKind.avgSessionMah, e.mah / recent.length,
          estimated: e.mahEstimated));
    }
  }
  return out;
}
