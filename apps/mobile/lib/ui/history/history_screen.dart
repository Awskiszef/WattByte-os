import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../analytics/stats.dart';
import '../../app.dart';
import '../../core/error_log.dart';
import '../../calc/energy.dart';
import '../../core/periods.dart';
import '../../core/units.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

enum _Tab { data, charging, energy }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Tab _tab = _Tab.charging;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = ref.watch(unitsProvider(context.localeTag));
    final calc = ref.watch(energyCalcProvider);
    final currency = ref.watch(settingsProvider).currency;
    final data = ref.watch(appDataProvider);
    final now = ref.watch(clockProvider)();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Semantics(
              header: true,
              container: true,
              child: Text(l.tabHistory,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: WbSegmented<_Tab>(
              segments: [
                WbSegment(_Tab.data, l.historyData),
                WbSegment(_Tab.charging, l.historyCharging),
                WbSegment(_Tab.energy, l.historyEnergy),
              ],
              selected: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const WbProgress(),
              error: (e, st) {
                reportError(e, st, 'screen');
                return ScrollableEmptyState(
                    title: l.noDataYet, body: l.genericError);
              },
              data: (d) => AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                child: switch (_tab) {
                  _Tab.data => _DataList(
                      key: const ValueKey('data'),
                      days: d.days,
                      units: units,
                      now: now),
                  _Tab.charging => _ChargingList(
                      key: const ValueKey('charging'),
                      sessions: d.sessions,
                      units: units,
                      calc: calc,
                      currency: currency,
                      now: now),
                  _Tab.energy => _EnergyList(
                      key: const ValueKey('energy'),
                      sessions: d.sessions,
                      units: units,
                      calc: calc,
                      currency: currency,
                      now: now),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String dayTitle(BuildContext context, DateTime day, DateTime now) {
  final l = context.l10n;
  final today = dayOf(now);
  if (day == today) return l.today;
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return l.yesterday;
  }
  return DateFormat.MMMEd(context.localeTag).format(day);
}

class _DataList extends StatelessWidget {
  const _DataList(
      {super.key, required this.days, required this.units, required this.now});

  final List<DailyData> days;
  final Units units;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final series = WbSeries.of(context);
    final rows = days.where((d) => d.total > 0).toList().reversed.toList();
    if (rows.isEmpty) {
      return ScrollableEmptyState(title: l.noDataYet, body: l.noDataBody);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = rows[i];
        final title = dayTitle(context, d.day, now);
        final mobileShare = d.total == 0 ? 0.0 : d.mobile / d.total;
        return WbCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          semanticLabel: joinSpoken([
            title,
            units.bytes(d.total),
            if (d.estimated) l.estimated,
            '${l.mobile} ${units.bytes(d.mobile)}',
            '${l.wifi} ${units.bytes(d.wifi)}',
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SplitRow(
                leading: Text(title, style: theme.textTheme.titleMedium),
                trailing: Text(
                    units.approx(units.bytes(d.total), estimated: d.estimated),
                    style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      Expanded(
                          flex: (mobileShare * 1000).round(),
                          child: ColoredBox(color: series.mobile)),
                      Expanded(
                          flex: ((1 - mobileShare) * 1000).round(),
                          child: ColoredBox(color: series.wifi)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  Label('${l.mobile} ${units.bytes(d.mobile)}',
                      dot: series.mobile),
                  Label('${l.wifi} ${units.bytes(d.wifi)}', dot: series.wifi),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChargingList extends StatelessWidget {
  const _ChargingList({
    super.key,
    required this.sessions,
    required this.units,
    required this.calc,
    required this.currency,
    required this.now,
  });

  final List<ChargingSession> sessions;
  final Units units;
  final EnergyCalc calc;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final series = WbSeries.of(context);
    if (sessions.isEmpty) {
      return ScrollableEmptyState(title: l.noSessionsYet, body: l.noDataBody);
    }
    final timeFmt = DateFormat.Hm(context.localeTag);
    final groups = <DateTime, List<ChargingSession>>{};
    for (final s in sessions.reversed) {
      groups.putIfAbsent(dayOf(s.start), () => []).add(s);
    }
    final days = groups.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final day = days[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(dayTitle(context, day, now)),
            for (final s in groups[day]!) ...[
              Builder(builder: (context) {
                final e = calc.session(s);
                final charge = units.mah(e.mahShown);
                final energy = units.wh(e.batteryWhShown);
                return WbCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  onTap: () => showSessionSheet(context, s, e, units, currency),
                  semanticLabel: joinSpoken([
                    l.a11ySessionRow(
                        timeFmt.format(s.start),
                        timeFmt.format(s.end),
                        s.startLevel,
                        s.endLevel,
                        spoken(charge),
                        spoken(energy)),
                    if (e.mahEstimated || e.whEstimated) l.estimated,
                  ]),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: series.energy.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.bolt_rounded, color: series.energy),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SplitRow(
                          leading: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${timeFmt.format(s.start)} → ${timeFmt.format(s.end)}',
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text('${s.startLevel}% → ${s.endLevel}%',
                                  style: theme.textTheme.labelMedium),
                            ],
                          ),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  '+${units.approx(charge, estimated: e.mahEstimated)}',
                                  style: theme.textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                  units.approx(energy,
                                      estimated: e.whEstimated),
                                  style: theme.textTheme.labelMedium),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _EnergyList extends StatelessWidget {
  const _EnergyList({
    super.key,
    required this.sessions,
    required this.units,
    required this.calc,
    required this.currency,
    required this.now,
  });

  final List<ChargingSession> sessions;
  final Units units;
  final EnergyCalc calc;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final byDay = energyByDay(sessions, calc);
    if (byDay.isEmpty) {
      return ScrollableEmptyState(title: l.noSessionsYet, body: l.noDataBody);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final hasPrice = calc.pricePerKwh > 0;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final e = byDay[days[i]]!;
        final title = dayTitle(context, days[i], now);
        final battery =
            units.approx(units.wh(e.batteryWhShown), estimated: e.whEstimated);
        final wall = units.approx(units.kwh(e.wallWhShown), estimated: true);
        final second = hasPrice
            ? units.approx(units.money(e.costShown, currency), estimated: true)
            : units.approx(units.wh(e.wallWhShown), estimated: true);
        return WbCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          semanticLabel: joinSpoken([
            title,
            '${l.batteryEnergy} $battery',
            wall,
            second,
            l.estimated,
          ]),
          child: SplitRow(
            leading: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('${l.batteryEnergy} $battery',
                    style: theme.textTheme.labelMedium),
              ],
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(wall, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(second, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full detail of one session, with battery vs wall energy clearly separated.
/// Scrolls when the text size makes it taller than the screen.
Future<void> showSessionSheet(
  BuildContext context,
  ChargingSession s,
  SessionEnergy e,
  Units units,
  String currency,
) {
  final l = context.l10n;
  final theme = Theme.of(context);
  final timeFmt = DateFormat.Hm(context.localeTag);
  final dateFmt = DateFormat.yMMMEd(context.localeTag);
  // One line per fact: "Charge, 3 988 mAh, Estimated" for a screen reader; the
  // value moves under its label (instead of squeezing it) at large text sizes.
  Widget row(String label, String value, {bool estimated = false}) => Semantics(
        container: true,
        excludeSemantics: true,
        label: joinSpoken([label, value, if (estimated) l.estimated]),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              container: true,
              child: Text(l.sessionTitle, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: 4),
            Text(
                '${dateFmt.format(s.start)} · ${timeFmt.format(s.start)} → ${timeFmt.format(s.end)}',
                style: theme.textTheme.labelMedium),
            const SizedBox(height: 12),
            row(l.batteryLabel, '${s.startLevel}% → ${s.endLevel}%'),
            row(l.added, '${s.addedPercent}%'),
            row(l.duration, units.duration(s.duration)),
            const Divider(),
            row(l.charge,
                units.approx(units.mah(e.mahShown), estimated: e.mahEstimated),
                estimated: e.mahEstimated),
            row(
                l.batteryEnergy,
                units.approx(units.wh(e.batteryWhShown),
                    estimated: e.whEstimated),
                estimated: e.whEstimated),
            row(
                l.energy,
                units.approx(units.kwh(e.batteryWhShown),
                    estimated: e.whEstimated)),
            const Divider(),
            row(l.wallEnergy,
                units.approx(units.wh(e.wallWhShown), estimated: true),
                estimated: true),
            row(
                l.cost,
                units.approx(units.money(e.costShown, currency),
                    estimated: true),
                estimated: true),
            if (e.isUnknown) ...[
              const SizedBox(height: 8),
              Text(l.setCapacityHint, style: theme.textTheme.labelMedium),
            ],
            if (s.sparse) ...[
              const SizedBox(height: 8),
              Text(l.sparseNote, style: theme.textTheme.labelMedium),
            ],
          ],
        ),
      ),
    ),
  );
}
