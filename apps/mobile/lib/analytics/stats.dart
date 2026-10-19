import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';

/// Aggregations over stored days and sessions. Pure functions.

List<DailyData> daysIn(Iterable<DailyData> days, DateRange r) => [
      for (final d in days)
        if (r.contains(d.day)) d
    ];

/// Sessions are attributed to the day they started.
List<ChargingSession> sessionsIn(
        Iterable<ChargingSession> sessions, DateRange r) =>
    [
      for (final s in sessions)
        if (r.contains(s.start)) s
    ];

class ChargingStats {
  const ChargingStats({
    required this.count,
    required this.avgDuration,
    required this.avgAddedPercent,
    required this.energy,
  });

  static const empty = ChargingStats(
    count: 0,
    avgDuration: Duration.zero,
    avgAddedPercent: 0,
    energy: SessionEnergy.zero,
  );

  final int count;
  final Duration avgDuration;
  final double avgAddedPercent;
  final SessionEnergy energy;

  factory ChargingStats.of(List<ChargingSession> sessions, EnergyCalc calc) {
    if (sessions.isEmpty) return empty;
    final totalMs =
        sessions.fold<int>(0, (a, s) => a + s.duration.inMilliseconds);
    final added = sessions.fold<int>(0, (a, s) => a + s.addedPercent);
    return ChargingStats(
      count: sessions.length,
      avgDuration: Duration(milliseconds: totalMs ~/ sessions.length),
      avgAddedPercent: added / sessions.length,
      energy: calc.total(sessions),
    );
  }
}

/// Energy per local day (keyed by midnight), sessions attributed to their start day.
Map<DateTime, SessionEnergy> energyByDay(
    Iterable<ChargingSession> sessions, EnergyCalc calc) {
  final out = <DateTime, SessionEnergy>{};
  for (final s in sessions) {
    final d = dayOf(s.start);
    out[d] = (out[d] ?? SessionEnergy.zero).plus(calc.session(s));
  }
  return out;
}

class Records {
  const Records({
    this.mostDataDay,
    this.longestSession,
    this.mostEnergyDay,
    this.mostEnergyDayEnergy,
    this.largestSession,
    this.largestSessionEnergy,
    this.mostExpensiveMonth,
    this.mostExpensiveMonthCost = 0,
    this.avgDailyDataBytes = 0,
    this.avgMonthlyEnergyWh = 0,
  });

  final DailyData? mostDataDay;
  final ChargingSession? longestSession;
  final DateTime? mostEnergyDay;
  final SessionEnergy? mostEnergyDayEnergy;
  final ChargingSession? largestSession;
  final SessionEnergy? largestSessionEnergy;

  /// `yyyy-MM` of the month with the highest estimated cost.
  final String? mostExpensiveMonth;
  final double mostExpensiveMonthCost;

  /// Over days that have any record.
  final double avgDailyDataBytes;

  /// Wall energy over months that have any session.
  final double avgMonthlyEnergyWh;

  bool get isEmpty => mostDataDay == null && longestSession == null;

  factory Records.of(
      List<DailyData> days, List<ChargingSession> sessions, EnergyCalc calc) {
    DailyData? mostData;
    for (final d in days) {
      if (d.total > 0 && (mostData == null || d.total > mostData.total)) {
        mostData = d;
      }
    }

    ChargingSession? longest;
    ChargingSession? largest;
    SessionEnergy? largestEnergy;
    final byMonth = <String, double>{};
    var totalWallWh = 0.0;
    for (final s in sessions) {
      if (longest == null || s.duration > longest.duration) longest = s;
      final e = calc.session(s);
      if (largestEnergy == null || e.batteryWh > largestEnergy.batteryWh) {
        largest = s;
        largestEnergy = e;
      }
      final m = monthKey(s.start);
      byMonth[m] = (byMonth[m] ?? 0) + e.cost;
      totalWallWh += e.wallWh;
    }

    DateTime? energyDay;
    SessionEnergy? energyDayEnergy;
    energyByDay(sessions, calc).forEach((day, e) {
      if (energyDayEnergy == null || e.wallWh > energyDayEnergy!.wallWh) {
        energyDay = day;
        energyDayEnergy = e;
      }
    });

    String? month;
    var monthCost = 0.0;
    byMonth.forEach((m, c) {
      if (month == null || c > monthCost) {
        month = m;
        monthCost = c;
      }
    });

    final daysWithData = days.where((d) => d.total > 0).toList();
    return Records(
      mostDataDay: mostData,
      longestSession: longest,
      mostEnergyDay: energyDay,
      mostEnergyDayEnergy: energyDayEnergy,
      largestSession: largest,
      largestSessionEnergy: largestEnergy,
      mostExpensiveMonth: month,
      mostExpensiveMonthCost: monthCost,
      avgDailyDataBytes: daysWithData.isEmpty
          ? 0
          : daysWithData.fold<int>(0, (a, d) => a + d.total) /
              daysWithData.length,
      avgMonthlyEnergyWh: byMonth.isEmpty ? 0 : totalWallWh / byMonth.length,
    );
  }
}
