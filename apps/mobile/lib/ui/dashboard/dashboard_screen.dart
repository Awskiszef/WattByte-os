import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../analytics/dashboard_model.dart';
import '../../app.dart';
import '../../core/error_log.dart';
import '../../core/units.dart';
import '../../providers.dart';
import '../data_by_app/data_by_app_screen.dart';
import '../settings/setup_editors.dart';
import '../statistics/statistics_screen.dart';
import '../theme.dart';
import '../widgets/daily_bar_chart.dart';
import '../widgets/wb_widgets.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _thirtyDays = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = ref.watch(unitsProvider(context.localeTag));
    final settings = ref.watch(settingsProvider);
    final calc = ref.watch(energyCalcProvider);
    final caps = ref.watch(capabilitiesProvider).value;
    final model = ref.watch(dashboardProvider);
    final dateFmt = DateFormat.MMMMd(context.localeTag);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => ref
            .read(refreshControllerProvider)
            .refresh(locale: context.localeTag),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _Header(
              title: l.appName,
              subtitle:
                  '${l.today} · ${dateFmt.format(ref.watch(clockProvider)())}',
              actionLabel: l.statistics,
              onAction: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatisticsScreen())),
            ),
            const SizedBox(height: 20),
            if (caps != null && caps.isAndroid && !caps.usageAccessGranted) ...[
              _PermissionCard(
                  unavailable: caps.usageAccessState == 'unavailable',
                  onOpen: () =>
                      ref.read(systemProvider).openUsageAccessSettings()),
              const SizedBox(height: 12),
            ],
            model.when(
              loading: () => const WbProgress(padding: EdgeInsets.all(48)),
              error: (e, st) {
                reportError(e, st, 'screen');
                return EmptyState(title: l.noDataYet, body: l.genericError);
              },
              data: (m) => _Body(
                model: m,
                units: units,
                currency: settings.currency,
                hasPrice: settings.hasPrice,
                priceIsAverage: settings.priceIsAverage,
                canEstimateMah: calc.canEstimateFromPercent,
                thirtyDays: _thirtyDays,
                onRange: (v) => setState(() => _thirtyDays = v),
                showDataByApp: (caps?.dataByApp ?? false) &&
                    (caps?.usageAccessGranted ?? false),
                isIos: caps != null && !caps.isAndroid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.model,
    required this.units,
    required this.currency,
    required this.hasPrice,
    required this.priceIsAverage,
    required this.canEstimateMah,
    required this.thirtyDays,
    required this.onRange,
    required this.showDataByApp,
    required this.isIos,
  });

  final DashboardModel model;
  final Units units;
  final String currency;
  final bool hasPrice;

  /// The price is a national household average: the cost is labelled as an estimate.
  final bool priceIsAverage;
  final bool canEstimateMah;
  final bool thirtyDays;
  final ValueChanged<bool> onRange;
  final bool showDataByApp;
  final bool isIos;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final series = WbSeries.of(context);
    final m = model;
    final e = m.todayEnergy;
    final days = thirtyDays ? m.last30 : m.last30.sublist(m.last30.length - 7);
    final energy = thirtyDays
        ? m.energyLast30
        : m.energyLast30.sublist(m.energyLast30.length - 7);
    final timeFmt = DateFormat.Hm(context.localeTag);
    final period = thirtyDays ? l.periodLast30Days : l.periodLast7Days;
    final today = m.today;
    final todayEstimated = today.estimated;
    final energyTotal = energy.fold<double>(0, (a, x) => a + x.wallWh);

    return Column(
      // Full-width cards: the battery card used to be as wide as its content.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (m.chargingNow)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child:
                      Icon(Icons.bolt_rounded, color: WbColors.bolt, size: 18),
                ),
                const SizedBox(width: 6),
                Expanded(
                  // Its own node: loose texts would otherwise be merged into
                  // the node of the whole list item.
                  child: Semantics(
                    container: true,
                    child: Text(
                      m.inProgress == null
                          ? l.chargingNow
                          : '${l.chargingNow} · ${l.since(timeFmt.format(m.inProgress!.start))}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Data Used (hero): one node for a screen reader.
        WbCard(
          gradient: accentWash(context, WbColors.byte),
          semanticLabel: joinSpoken([
            l.dataUsed,
            units.bytes(today.total),
            if (todayEstimated) l.estimated,
            '${l.mobile} ${units.bytes(today.mobile)}',
            '${l.wifi} ${units.bytes(today.wifi)}',
            '${l.download} ${units.bytes(today.rx)}',
            '${l.upload} ${units.bytes(today.tx)}',
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (todayEstimated)
                SplitRow(
                  leading: Label(l.dataUsed, dot: series.data),
                  trailing: const EstimatedBadge(),
                  runSpacing: 6,
                )
              else
                Label(l.dataUsed, dot: series.data),
              const SizedBox(height: 10),
              BigNumber(
                value: today.total.toDouble(),
                format: units.bytes,
                estimated: todayEstimated,
              ),
              const SizedBox(height: 18),
              AdaptiveColumns(
                minColumnWidth: 100,
                children: [
                  _Mini(
                    label: l.mobile,
                    value: units.approx(units.bytes(today.mobile),
                        estimated: todayEstimated),
                    dot: series.mobile,
                  ),
                  _Mini(
                    label: l.wifi,
                    value: units.approx(units.bytes(today.wifi),
                        estimated: todayEstimated),
                    dot: series.wifi,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${l.download} ${units.bytes(today.rx)}  ·  ${l.upload} ${units.bytes(today.tx)}',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Energy + cost: side by side while each card has room for its number,
        // stacked (full width) once the text size takes that room away.
        AdaptiveColumns(
          minColumnWidth: 150,
          children: [
            StatCard(
              label: l.energyAdded,
              value: e.batteryWh,
              format: units.wh,
              estimated: e.whEstimated,
              accent: WbColors.bolt,
              sub: units.approx(units.kwh(e.batteryWh),
                  estimated: e.whEstimated),
            ),
            if (hasPrice)
              StatCard(
                label: priceIsAverage
                    ? l.estimatedChargingCost
                    : l.electricityCost,
                value: e.cost,
                format: (v) => units.money(v, currency),
                estimated: true,
                accent: WbColors.cost,
                sub:
                    '${l.wallEnergy}: ${units.approx(units.wh(e.wallWh), estimated: true)}',
              )
            else
              WbCard(
                onTap: () => editPrice(context),
                semanticLabel: joinSpoken(
                    [l.electricityCost, l.priceUnavailable, l.enterManually]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Label(l.electricityCost, dot: WbColors.cost),
                    const SizedBox(height: 10),
                    Text(Units.placeholder,
                        style: theme.textTheme.displayMedium),
                    const SizedBox(height: 6),
                    Text(l.priceUnavailable,
                        style: theme.textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Text(l.enterManually,
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: accentTextOf(context),
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Battery charged. Unknown capacity: say so, never invent a number.
        if (e.mahEstimated && !canEstimateMah)
          WbCard(
            semanticLabel: joinSpoken([l.batteryCharged, l.setCapacityHint]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Label(l.batteryCharged, dot: WbColors.wifi),
                const SizedBox(height: 10),
                Text(Units.placeholder, style: theme.textTheme.displayMedium),
                const SizedBox(height: 6),
                Text(l.setCapacityHint, style: theme.textTheme.labelMedium),
              ],
            ),
          )
        else
          StatCard(
            label: l.batteryCharged,
            value: e.mah,
            format: units.mah,
            estimated: e.mahEstimated,
            accent: WbColors.wifi,
            // "Measured" only describes a real measurement: never an empty
            // total, and not next to the "Estimated" badge (it would say both).
            sub: e.mah == 0 || e.mahEstimated ? null : l.measured,
          ),

        // Data usage chart
        SectionHeader(
          l.dataUsage,
          trailing: _RangeToggle(thirtyDays: thirtyDays, onChanged: onRange),
        ),
        WbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DailyBarChart(
                points: [
                  for (final d in days)
                    ChartPoint(d.day, [d.mobile.toDouble(), d.wifi.toDouble()]),
                ],
                colors: [series.mobile, series.wifi],
                formatValue: units.bytes,
                title: l.dataUsage,
                period: period,
                estimated: days.any((d) => d.estimated),
              ),
              const SizedBox(height: 12),
              // The legend only repeats the colours of the bars; the numbers
              // are in the chart's summary.
              ExcludeSemantics(
                child: SplitRow(
                  leading: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Label(l.mobile, dot: series.mobile),
                      Label(l.wifi, dot: series.wifi),
                    ],
                  ),
                  trailing: Text(
                      units.bytes(days.fold<int>(0, (a, d) => a + d.total)),
                      style: theme.textTheme.titleMedium),
                  runSpacing: 6,
                ),
              ),
            ],
          ),
        ),

        // Energy chart
        SectionHeader(l.energyUsage),
        WbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DailyBarChart(
                points: [
                  for (var i = 0; i < days.length; i++)
                    ChartPoint(days[i].day, [energy[i].wallWh]),
                ],
                colors: [series.energy],
                formatValue: (v) => units.approx(units.wh(v), estimated: true),
                title: l.energyUsage,
                period: period,
                estimated: true,
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: SplitRow(
                  leading: Label(l.wallEnergy, dot: series.energy),
                  trailing: Text(
                      units.approx(units.wh(energyTotal), estimated: true),
                      style: theme.textTheme.titleMedium),
                  runSpacing: 6,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        AdaptiveColumns(
          // Icon, the longest title ("Statistics", "Data by App") and the
          // chevron: about 170 px at the default size.
          minColumnWidth: 172,
          children: [
            _LinkCard(
              icon: Icons.insights_rounded,
              label: l.statistics,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatisticsScreen())),
            ),
            if (showDataByApp)
              _LinkCard(
                icon: Icons.apps_rounded,
                label: l.dataByApp,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DataByAppScreen())),
              ),
          ],
        ),
        if (isIos) ...[
          const SizedBox(height: 16),
          Semantics(
            container: true,
            child: Text(l.iosDataNote, style: theme.textTheme.labelMedium),
          ),
        ],
      ],
    );
  }
}

/// Logo, app name, date and the statistics button. In one line while the name
/// fits next to the logo and the button; at the largest text sizes the logo and
/// the button share the first line and the name and date get the full width
/// (a 66 px "WattByte" is wider than the room left beside them).
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  static const _logo = 36.0;
  static const _button = 48.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleLarge;
    final action = IconButton.filledTonal(
      tooltip: actionLabel,
      onPressed: onAction,
      icon: const Icon(Icons.insights_rounded),
    );
    final heading = Semantics(
      header: true,
      container: true,
      child: Text(title, style: titleStyle),
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final nameWidth = longestWordWidth(title, titleStyle, scaler, direction);
      final inline =
          nameWidth + _logo + _button + 3 * _gap <= constraints.maxWidth;
      if (inline) {
        return Row(
          children: [
            const WattByteMark(),
            const SizedBox(width: _gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  Semantics(
                    container: true,
                    child: Text(subtitle, style: theme.textTheme.labelMedium),
                  ),
                ],
              ),
            ),
            action,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [const WattByteMark(), const Spacer(), action],
          ),
          const SizedBox(height: 8),
          heading,
          Semantics(
            container: true,
            child: Text(subtitle, style: theme.textTheme.labelMedium),
          ),
        ],
      );
    });
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, required this.dot});

  final String label;
  final String value;
  final Color dot;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Label(label, dot: dot),
          const SizedBox(height: 4),
          // One number and its unit: shrunk to the line, never split in two.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                softWrap: false),
          ),
        ],
      );
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.thirtyDays, required this.onChanged});

  final bool thirtyDays;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Default density and tap target size: the compact variant made the
    // segments 32 px tall, below the 44/48 px touch targets. The tooltip is
    // what a screen reader adds after "7D" ("Last 7 Days").
    return Semantics(
      container: true,
      label: l.a11yChartPeriod,
      child: WbSegmented<bool>(
        segments: [
          WbSegment(false, l.days7, tooltip: l.periodLast7Days),
          WbSegment(true, l.days30, tooltip: l.periodLast30Days),
        ],
        selected: thirtyDays,
        onChanged: onChanged,
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WbCard(
        onTap: onTap,
        semanticLabel: label,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: accentTextOf(context)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.titleMedium)),
            Icon(Icons.chevron_right_rounded, color: mutedOf(context)),
          ],
        ),
      );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onOpen, this.unavailable = false});

  final VoidCallback onOpen;

  /// No system screen can grant access on this device: explain, no button.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return WbCard(
      gradient: accentWash(context, WbColors.bolt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.usageAccessTitle,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(l.usageAccessBody,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (unavailable)
            Text(l.usageAccessUnavailable,
                style: Theme.of(context).textTheme.labelMedium)
          else
            FilledButton(onPressed: onOpen, child: Text(l.usageAccessButton)),
        ],
      ),
    );
  }
}
