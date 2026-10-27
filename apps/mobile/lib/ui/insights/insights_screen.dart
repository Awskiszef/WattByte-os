import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analytics/insights.dart';
import '../../app.dart';
import '../../core/error_log.dart';
import '../../core/units.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';
import 'ai_card.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final units = ref.watch(unitsProvider(context.localeTag));
    final calc = ref.watch(energyCalcProvider);
    final currency = ref.watch(settingsProvider).currency;
    final data = ref.watch(appDataProvider);
    final now = ref.watch(clockProvider)();

    return SafeArea(
      bottom: false,
      child: data.when(
        loading: () => const WbProgress(),
        error: (e, st) {
          reportError(e, st, 'screen');
          return ScrollableEmptyState(title: l.noDataYet, body: l.genericError);
        },
        data: (d) {
          final insights = generateInsights(
            days: d.days,
            sessions: d.sessions,
            calc: calc,
            now: now,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Semantics(
                header: true,
                container: true,
                child: Text(l.tabInsights,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 16),
              const AiCard(),
              const SizedBox(height: 12),
              if (insights.isEmpty)
                EmptyState(
                    title: l.insightsEmpty, icon: Icons.auto_awesome_outlined)
              else
                for (final i in insights) ...[
                  _InsightCard(
                      insight: i, text: insightText(i, l, units, currency)),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

String insightText(Insight i, AppLocalizations l, Units u, String currency) =>
    switch (i.kind) {
      InsightKind.mobileVsLastWeek => i.value >= 0
          ? l.insightMobileMore(i.value.round())
          : l.insightMobileLess(i.value.abs().round()),
      InsightKind.chargesThisWeek => l.insightCharges(i.value.round()),
      InsightKind.energyThisMonth =>
        l.insightEnergyMonth(u.kwh(i.value * 1000)),
      InsightKind.costThisMonth =>
        l.insightCostMonth(u.money(i.value, currency)),
      InsightKind.wifiShare => l.insightWifiShare(i.value.round()),
      InsightKind.avgSessionMah => l.insightAvgSession(u.mah(i.value)),
    };

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.text});

  final Insight insight;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Series colours: the brand pastels are 1.5 to 2.7:1 on a light card.
    final series = WbSeries.of(context);
    final (icon, color) = switch (insight.kind) {
      InsightKind.mobileVsLastWeek => (Icons.cell_tower_rounded, series.mobile),
      InsightKind.chargesThisWeek => (
          Icons.battery_charging_full_rounded,
          series.wifi
        ),
      InsightKind.energyThisMonth => (Icons.bolt_rounded, series.energy),
      InsightKind.costThisMonth => (Icons.payments_outlined, series.cost),
      InsightKind.wifiShare => (Icons.wifi_rounded, series.wifi),
      InsightKind.avgSessionMah => (Icons.battery_std_rounded, series.data),
    };
    final badge = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A long word ("elektrycznej") must never be cut in half.
        WordFitText(text,
            style:
                Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35)),
        if (insight.estimated) ...[
          const SizedBox(height: 8),
          const EstimatedBadge(),
        ],
      ],
    );
    // Large text: the icon moves above the sentence so the sentence gets the
    // whole width of the card instead of what is left beside the icon.
    final stacked = systemTextScale(context) > 1.3;
    return WbCard(
      padding: const EdgeInsets.all(18),
      semanticLabel:
          joinSpoken([text, if (insight.estimated) context.l10n.estimated]),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [badge, const SizedBox(height: 12), message],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge,
                const SizedBox(width: 14),
                Expanded(child: message)
              ],
            ),
    );
  }
}
