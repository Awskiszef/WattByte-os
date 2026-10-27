import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import '../../app.dart';
import '../../core/periods.dart';
import '../../providers.dart';
import '../statistics/statistics_screen.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';

/// Android only: per-app totals from NetworkStatsManager.querySummary.
/// Not offered on iOS, which exposes no per-app data usage to third parties.
class DataByAppScreen extends ConsumerStatefulWidget {
  const DataByAppScreen({super.key});

  @override
  ConsumerState<DataByAppScreen> createState() => _DataByAppScreenState();
}

class _DataByAppScreenState extends ConsumerState<DataByAppScreen> {
  Period _period = Period.last7Days;
  late Future<List<RawAppData>> _future = _load();

  Future<List<RawAppData>> _load() {
    final r = rangeFor(_period, ref.read(clockProvider)());
    return ref.read(systemProvider).queryAppData(r.start, r.end);
  }

  void _select(Period p) => setState(() {
        _period = p;
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = ref.watch(unitsProvider(context.localeTag));
    final theme = Theme.of(context);
    final series = WbSeries.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.dataByApp)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ChipRow<Period>(
                items: const [
                  Period.today,
                  Period.last7Days,
                  Period.last30Days,
                  Period.thisMonth
                ],
                selected: _period,
                label: (p) => periodLabel(p, l),
                onSelected: _select,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RawAppData>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const WbProgress();
                }
                if (snap.hasError) {
                  // Usage access revoked meanwhile: explain instead of crashing.
                  return ScrollableEmptyState(
                    title: l.usageAccessTitle,
                    body: l.usageAccessBody,
                    icon: Icons.lock_outline_rounded,
                  );
                }
                final apps = (snap.data ?? const <RawAppData>[])
                    .where((a) => a.mobile + a.wifi > 0)
                    .toList();
                if (apps.isEmpty) {
                  return ScrollableEmptyState(
                      title: l.dataByAppEmpty, icon: Icons.apps_rounded);
                }
                final max = apps.first.mobile + apps.first.wifi;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  itemCount: apps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = apps[i];
                    final total = a.mobile + a.wifi;
                    final name = switch (a.kind) {
                      'system' => l.appSystem,
                      'tethering' => l.appTethering,
                      'removed' => l.appRemoved,
                      'unknown' => l.appOther,
                      _ => a.name,
                    };
                    return WbCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      semanticLabel: joinSpoken([
                        name,
                        units.bytes(total),
                        '${l.mobile} ${units.bytes(a.mobile)}',
                        '${l.wifi} ${units.bytes(a.wifi)}',
                      ]),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: a.icon != null
                                  ? Image.memory(a.icon!,
                                      gaplessPlayback: true,
                                      excludeFromSemantics: true)
                                  : ColoredBox(
                                      color:
                                          series.data.withValues(alpha: 0.18),
                                      child: Icon(Icons.android_rounded,
                                          color: series.data),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SplitRow(
                                  // App names are whatever the app store
                                  // says: no word of one may be cut in half.
                                  leading: WordFitText(name,
                                      style: theme.textTheme.titleMedium),
                                  trailing: Text(units.bytes(total),
                                      style: theme.textTheme.titleMedium),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: SizedBox(
                                    height: 5,
                                    child: Row(
                                      children: [
                                        Expanded(
                                            flex: a.mobile,
                                            child: ColoredBox(
                                                color: series.mobile)),
                                        Expanded(
                                            flex: a.wifi,
                                            child:
                                                ColoredBox(color: series.wifi)),
                                        Expanded(
                                            // The list is sorted by size; never
                                            // let a stray order make this negative.
                                            flex: (max - total).clamp(0, max),
                                            child: ColoredBox(
                                                color: theme
                                                    .colorScheme.onSurface
                                                    .withValues(alpha: 0.05))),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 14,
                                  runSpacing: 2,
                                  children: [
                                    Label(
                                        '${l.mobile} ${units.bytes(a.mobile)}',
                                        dot: series.mobile),
                                    Label('${l.wifi} ${units.bytes(a.wifi)}',
                                        dot: series.wifi),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
