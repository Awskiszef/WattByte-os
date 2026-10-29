import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../analytics/stats.dart';
import '../../app.dart';
import '../../core/error_log.dart';
import '../../core/periods.dart';
import '../../core/units.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

String periodLabel(Period p, AppLocalizations l) => switch (p) {
      Period.today => l.periodToday,
      Period.yesterday => l.periodYesterday,
      Period.last7Days => l.periodLast7Days,
      Period.last30Days => l.periodLast30Days,
      Period.thisWeek => l.periodThisWeek,
      Period.thisMonth => l.periodThisMonth,
      Period.lastMonth => l.periodLastMonth,
      Period.thisYear => l.periodThisYear,
      Period.allTime => l.periodAllTime,
    };

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  Period _period = Period.thisMonth;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = ref.watch(unitsProvider(context.localeTag));
    final calc = ref.watch(energyCalcProvider);
    final currency = ref.watch(settingsProvider).currency;
    final data = ref.watch(appDataProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(title: Text(l.statistics)),
      body: data.when(
        loading: () => const WbProgress(),
        error: (e, st) {
          reportError(e, st, 'screen');
          return ScrollableEmptyState(title: l.noDataYet, body: l.genericError);
        },
        data: (d) {
          final sessions = sessionsIn(d.sessions, rangeFor(_period, now));
          final cs = ChargingStats.of(sessions, calc);
          final records = Records.of(d.days, d.sessions, calc);
          final anyEstimatedData = d.days.any((x) => x.estimated);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              SectionHeader(l.internet,
                  trailing: anyEstimatedData ? const EstimatedBadge() : null),
              WbCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  children: [
                    for (final p in [
                      Period.today,
                      Period.thisWeek,
                      Period.thisMonth,
                      Period.thisYear,
                      Period.allTime
                    ])
                      _DataRow(
                        label: periodLabel(p, l),
                        data: DailyData.sum(daysIn(d.days, rangeFor(p, now))),
                        units: units,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ChipRow<Period>(
                items: const [
                  Period.last7Days,
                  Period.thisMonth,
                  Period.lastMonth,
                  Period.thisYear,
                  Period.allTime
                ],
                selected: _period,
                label: (p) => periodLabel(p, l),
                onSelected: (p) => setState(() => _period = p),
              ),
              SectionHeader(l.charging),
              WbCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  children: [
                    _Row(l.sessionsCount, '${cs.count}'),
                    _Row(l.avgDuration, units.duration(cs.avgDuration)),
                    _Row(l.avgAdded, units.percent(cs.avgAddedPercent)),
                    _Row(
                        l.totalMah,
                        units.approx(units.mah(cs.energy.mahShown),
                            estimated: cs.energy.mahEstimated),
                        estimated: cs.energy.mahEstimated),
                  ],
                ),
              ),
              SectionHeader(l.energy),
              WbCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(
                  children: [
                    _Row(
                        l.batteryEnergy,
                        units.approx(units.wh(cs.energy.batteryWhShown),
                            estimated: cs.energy.whEstimated),
                        estimated: cs.energy.whEstimated),
                    _Row(
                        l.wallEnergy,
                        units.approx(units.wh(cs.energy.wallWhShown),
                            estimated: true),
                        estimated: true),
                    _Row(
                        'kWh',
                        units.approx(units.kwh(cs.energy.wallWhShown),
                            estimated: true),
                        estimated: true),
                    _Row(
                        l.electricityCost,
                        calc.pricePerKwh > 0
                            ? units.approx(
                                units.money(cs.energy.costShown, currency),
                                estimated: true)
                            : l.notSet,
                        estimated: calc.pricePerKwh > 0),
                  ],
                ),
              ),
              SectionHeader(l.records),
              if (records.isEmpty)
                EmptyState(
                    title: l.noRecordsYet, icon: Icons.emoji_events_outlined)
              else
                _RecordsCard(
                    records: records, units: units, currency: currency),
            ],
          );
        },
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow(
      {required this.label, required this.data, required this.units});

  final String label;
  final DailyData data;
  final Units units;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final series = WbSeries.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: joinSpoken([
        label,
        units.bytes(data.total),
        if (data.estimated) l.estimated,
        '${l.mobile} ${units.bytes(data.mobile)}',
        '${l.wifi} ${units.bytes(data.wifi)}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SplitRow(
          leading: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              // Mobile and Wi-Fi are two facts: each stays whole on its line.
              Wrap(
                spacing: 14,
                runSpacing: 2,
                children: [
                  Label('${l.mobile} ${units.bytes(data.mobile)}',
                      dot: series.mobile),
                  Label('${l.wifi} ${units.bytes(data.wifi)}',
                      dot: series.wifi),
                ],
              ),
            ],
          ),
          trailing: Text(
              units.approx(units.bytes(data.total), estimated: data.estimated),
              style: theme.textTheme.titleMedium),
        ),
      ),
    );
  }
}

/// A fact in a card: "label ........ value [Estimated]". At large text sizes
/// the value (and badge) move under the label instead of squeezing it.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.estimated = false});

  final String label;
  final String value;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: joinSpoken([label, value, if (estimated) context.l10n.estimated]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SplitRow(
          leading: Text(label, style: theme.textTheme.bodyMedium),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(value, style: theme.textTheme.titleMedium),
              if (estimated) const EstimatedBadge(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard(
      {required this.records, required this.units, required this.currency});

  final Records records;
  final Units units;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = records;
    final dateFmt = DateFormat.yMMMd(context.localeTag);
    final monthFmt = DateFormat.yMMMM(context.localeTag);
    final items = <(IconData, String, String, String?)>[
      if (r.mostDataDay != null)
        (
          Icons.swap_vert_rounded,
          l.recordMostDataDay,
          units.bytes(r.mostDataDay!.total),
          dateFmt.format(r.mostDataDay!.day)
        ),
      if (r.longestSession != null)
        (
          Icons.timer_outlined,
          l.recordLongestSession,
          units.duration(r.longestSession!.duration),
          dateFmt.format(r.longestSession!.start)
        ),
      if (r.mostEnergyDay != null)
        (
          Icons.bolt_rounded,
          l.recordMostEnergyDay,
          units.approx(units.wh(r.mostEnergyDayEnergy!.wallWhShown),
              estimated: true),
          dateFmt.format(r.mostEnergyDay!)
        ),
      if (r.largestSession != null)
        (
          Icons.battery_charging_full_rounded,
          l.recordLargestSession,
          units.approx(units.mah(r.largestSessionEnergy!.mahShown),
              estimated: r.largestSessionEnergy!.mahEstimated),
          dateFmt.format(r.largestSession!.start)
        ),
      if (r.mostExpensiveMonth != null && r.mostExpensiveMonthCost > 0)
        (
          Icons.payments_outlined,
          l.recordMostExpensiveMonth,
          units.approx(units.money(r.mostExpensiveMonthCost, currency),
              estimated: true),
          monthFmt.format(DateTime(
              int.parse(r.mostExpensiveMonth!.substring(0, 4)),
              int.parse(r.mostExpensiveMonth!.substring(5, 7))))
        ),
      if (r.avgDailyDataBytes > 0)
        (
          Icons.today_rounded,
          l.recordAvgDailyData,
          units.bytes(r.avgDailyDataBytes),
          null
        ),
      if (r.avgMonthlyEnergyWh > 0)
        (
          Icons.calendar_month_rounded,
          l.recordAvgMonthlyEnergy,
          units.approx(units.kwh(r.avgMonthlyEnergyWh), estimated: true),
          null
        ),
    ];
    final theme = Theme.of(context);
    return WbCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Column(
        children: [
          for (final (icon, title, value, sub) in items)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: joinSpoken([title, value, sub]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: WbSeries.of(context).energy, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SplitRow(
                        leading: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.bodyMedium),
                            if (sub != null)
                              Text(sub, style: theme.textTheme.labelMedium),
                          ],
                        ),
                        trailing:
                            Text(value, style: theme.textTheme.titleMedium),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
