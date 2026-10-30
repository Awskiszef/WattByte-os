import '../../calc/energy.dart';
import '../../core/periods.dart';
import '../../domain/models.dart';
import '../../analytics/stats.dart';

/// The numbers the AI is allowed to see: finished aggregates for one period.
///
/// Everything is computed here, deterministically; the model only words it. No
/// e-mail, user id, device id, timestamps of sessions or per-app data are included.
class AiPeriodStats {
  const AiPeriodStats({
    required this.period,
    required this.mobileDataGb,
    required this.wifiDataGb,
    required this.totalDataGb,
    required this.chargingSessions,
    this.batteryEnergyKwh,
    this.wallEnergyKwh,
    this.electricityCost,
    required this.currency,
    this.previousPeriodChangePercent,
    this.wifiSharePercent,
    this.averageSessionMah,
  });

  /// `YYYY-MM`.
  final String period;
  final double mobileDataGb;
  final double wifiDataGb;
  final double totalDataGb;
  final int chargingSessions;

  /// null = UNKNOWN (the battery capacity is not set, so no session has a usable energy): left out of the request,
  /// never sent as 0 (the model would read it as a fact).
  final double? batteryEnergyKwh;
  final double? wallEnergyKwh;
  final double? electricityCost;
  final String currency;

  /// Mobile data this month so far vs the same days of last month; null if last month has none.
  final double? previousPeriodChangePercent;
  final double? wifiSharePercent;
  final double? averageSessionMah;

  /// Month to date, compared with the same number of days of the previous month.
  static AiPeriodStats thisMonth({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
    required DateTime now,
  }) {
    final today = LocalDate.of(now);
    final monthStart = LocalDate(today.year, today.month, 1);
    final elapsed = monthStart.daysUntil(today) + 1;
    final range = DateRange(monthStart.midnight, today.plusDays(1).midnight);
    final prevStart = LocalDate(today.year, today.month - 1, 1);
    // The same number of days, but never past the end of the previous month: on 31 March the comparison is all of
    // February, not February plus the first days of March (day 0 of this month is the last day of the previous one).
    final prevLength = DateTime(today.year, today.month, 0).day;
    final prevRange = DateRange(
        prevStart.midnight,
        prevStart
            .plusDays(elapsed < prevLength ? elapsed : prevLength)
            .midnight);

    final data = DailyData.sum(daysIn(days, range));
    final prev = DailyData.sum(daysIn(days, prevRange));
    final mine = sessionsIn(sessions, range);
    final energy = calc.total(mine);

    double gb(int bytes) => _round(bytes / 1e9, 3);
    return AiPeriodStats(
      period: monthKey(monthStart.midnight),
      mobileDataGb: gb(data.mobile),
      wifiDataGb: gb(data.wifi),
      totalDataGb: gb(data.total),
      chargingSessions: mine.length,
      batteryEnergyKwh: energy.isUnknown ? null : _round(energy.batteryKwh, 4),
      wallEnergyKwh: energy.isUnknown ? null : _round(energy.wallKwh, 4),
      electricityCost: energy.isUnknown ? null : _round(energy.cost, 4),
      currency: currency,
      previousPeriodChangePercent: prev.mobile > 0
          ? _round((data.mobile - prev.mobile) / prev.mobile * 100, 1)
          : null,
      wifiSharePercent:
          data.total > 0 ? _round(data.wifi / data.total * 100, 1) : null,
      averageSessionMah: mine.isNotEmpty && !energy.isUnknown
          ? _round(energy.mah / energy.knownSessions, 0)
          : null,
    );
  }

  /// Nothing to talk about yet.
  bool get isEmpty => totalDataGb == 0 && chargingSessions == 0;

  static double _round(double v, int d) {
    final f = [1, 10, 100, 1000, 10000][d].toDouble();
    return (v * f).roundToDouble() / f;
  }
}
