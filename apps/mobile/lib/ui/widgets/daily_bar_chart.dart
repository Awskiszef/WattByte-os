import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../theme.dart';
import 'wb_widgets.dart' show spoken;

/// One bar per day; `values` are stacked bottom-to-top.
class ChartPoint {
  const ChartPoint(this.day, this.values);

  final DateTime day;
  final List<double> values;

  double get total => values.fold(0, (a, b) => a + b);
}

/// Interactive daily bar chart with stacked segments and a touch tooltip.
///
/// Accessibility. The painted bars are not reachable by a screen reader (and
/// the touch tooltip needs a finger), so the chart is ONE node that reads a
/// summary - what it shows, the period, the total, the highest and the lowest
/// day - and everything drawn inside it (axis labels) is hidden from the
/// screen reader. [title] and [period] are the words for that summary.
///
/// Text size. The day labels under the bars follow the system text size. When
/// they no longer fit side by side, only every n-th one is drawn (always
/// including the latest day), never overlapping ones, and the strip they live
/// in grows with them.
class DailyBarChart extends StatelessWidget {
  const DailyBarChart({
    super.key,
    required this.points,
    required this.colors,
    required this.formatValue,
    required this.title,
    required this.period,
    this.estimated = false,
    this.height = 180,
  });

  final List<ChartPoint> points;
  final List<Color> colors;
  final String Function(double) formatValue;

  /// What the chart shows ("Data Usage").
  final String title;

  /// The period it covers ("Last 7 Days").
  final String period;

  /// The values are estimates (the summary then says "Estimated").
  final bool estimated;
  final double height;

  /// The bars at least this many pixels apart carry a label.
  static const _labelGap = 6.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = mutedOf(context);
    final maxY = points.fold<double>(0, (m, p) => p.total > m ? p.total : m);
    final top = maxY <= 0 ? 1.0 : maxY * 1.15;
    final dense = points.length > 10;
    final locale = Localizations.localeOf(context).toString();
    final dayFmt = DateFormat.E(locale);
    final dateFmt = DateFormat.MMMd(locale);
    final longDateFmt = DateFormat.MMMEd(locale);
    final labelStyle = TextStyle(color: muted, fontSize: 11);
    final scaler = MediaQuery.textScalerOf(context);
    // The touch tooltip is painted by fl_chart without a text scaler, so its
    // sizes are scaled here; it sits inside the chart, hence the 1.6x cap.
    final tipScaler = scaler.clamp(maxScaleFactor: 1.6);
    final labels = [
      for (final p in points) dense ? '${p.day.day}' : dayFmt.format(p.day),
    ];

    var labelWidth = 0.0;
    var labelHeight = 0.0;
    for (final t in labels) {
      final p = TextPainter(
        text: TextSpan(text: t, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      labelWidth = math.max(labelWidth, p.width);
      labelHeight = math.max(labelHeight, p.height);
      p.dispose();
    }

    final summary = _summary(context, longDateFmt);

    return Semantics(
      container: true,
      image: true,
      label: summary,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          // Every n-th label so that neighbours never touch; at least every
          // 5th for a month of bars. The newest bar is always labelled.
          final slot = constraints.maxWidth / math.max(1, points.length);
          var stride = math.max(1, ((labelWidth + _labelGap) / slot).ceil());
          if (dense) stride = math.max(stride, 5);
          return BarChart(
            BarChartData(
              maxY: top,
              minY: 0,
              alignment: BarChartAlignment.spaceBetween,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: top / 3,
                getDrawingHorizontalLine: (_) => FlLine(
                    color: scheme.onSurface.withValues(alpha: 0.06),
                    strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: labelHeight + 8,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 ||
                          i >= points.length ||
                          (points.length - 1 - i) % stride != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(labels[i],
                            style: labelStyle, maxLines: 1, softWrap: false),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => scheme.onSurface,
                  tooltipRoundedRadius: 12,
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${dateFmt.format(points[group.x].day)}\n',
                    TextStyle(
                        color: scheme.surface.withValues(alpha: 0.7),
                        fontSize: tipScaler.scale(11)),
                    children: [
                      TextSpan(
                        text: formatValue(rod.toY),
                        style: TextStyle(
                            color: scheme.surface,
                            fontWeight: FontWeight.w700,
                            fontSize: tipScaler.scale(14)),
                      ),
                    ],
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].total,
                        width: dense ? 6 : 18,
                        borderRadius: BorderRadius.circular(dense ? 3 : 6),
                        color: colors.first,
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: top,
                          color: scheme.onSurface.withValues(alpha: 0.035),
                        ),
                        rodStackItems: _stack(points[i]),
                      ),
                    ],
                  ),
              ],
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }),
      ),
    );
  }

  /// "Data Usage, Last 7 Days: total 12.3 GB, highest 2.4 GB on Tue, Oct 7,
  /// lowest 0.9 GB on Sun, Oct 5. Estimated."
  String _summary(BuildContext context, DateFormat dateFmt) {
    final l = context.l10n;
    if (points.every((p) => p.total <= 0)) {
      return l.a11yChartEmpty(title, period);
    }
    var high = points.first;
    var low = points.first;
    var total = 0.0;
    for (final p in points) {
      total += p.total;
      if (p.total > high.total) high = p;
      if (p.total < low.total) low = p;
    }
    final text = l.a11yChartSummary(
      title,
      period,
      spoken(formatValue(total)),
      spoken(formatValue(high.total)),
      dateFmt.format(high.day),
      spoken(formatValue(low.total)),
      dateFmt.format(low.day),
    );
    return estimated ? '$text ${l.estimated}.' : text;
  }

  List<BarChartRodStackItem> _stack(ChartPoint p) {
    final out = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var i = 0; i < p.values.length; i++) {
      final to = from + p.values[i];
      out.add(BarChartRodStackItem(from, to, colors[i % colors.length]));
      from = to;
    }
    return out;
  }
}
