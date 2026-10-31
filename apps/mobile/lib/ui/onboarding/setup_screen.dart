// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../cloud_providers.dart';
import '../../providers.dart';
import '../../settings/settings.dart';
import '../../setup/setup_controller.dart';
import '../settings/flow_widgets.dart';
import '../settings/setup_editors.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';
import 'permissions_screen.dart';

/// Automatic setup after the account exists:
///
///   "Setting up WattByte…" (detections in parallel) -> "Your setup" (review,
///   one Continue, Edit per value) -> Permissions -> Dashboard.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _permissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _detect());
  }

  Future<void> _detect() => ref.read(setupControllerProvider.notifier).run(
        setup: ref.read(autoSetupProvider),
        current: ref.read(settingsProvider),
        save: (s) => ref.read(settingsProvider.notifier).update((_) => s),
        onAccountPushed: (push) => ref
            .read(settingsProvider.notifier)
            .update((s) => s.markInSyncFrom(push.pushed, push.groups)),
      );

  Future<void> _finish() => ref
      .read(settingsProvider.notifier)
      .update((s) => s.copyWith(onboarded: true));

  @override
  Widget build(BuildContext context) {
    if (_permissions) return PermissionsScreen(onDone: _finish);
    final state = ref.watch(setupControllerProvider);
    return switch (state.phase) {
      SetupPhase.idle || SetupPhase.detecting => const SetupDetectingView(),
      SetupPhase.review => _Review(
          result: state.result,
          onDetectAgain: _detect,
          onContinue: () => setState(() => _permissions = true),
        ),
    };
  }
}

/// "Setting up WattByte..." while region, device, battery and price are detected.
class SetupDetectingView extends StatelessWidget {
  const SetupDetectingView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: WattByteMark(size: 72)),
                const SizedBox(height: 28),
                FlowHeading(l.setupDetectingTitle,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(l.setupDetectingBody,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.4, color: mutedOf(context))),
                const SizedBox(height: 28),
                LinearProgressIndicator(semanticsLabel: l.setupDetectingTitle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review(
      {required this.result,
      required this.onDetectAgain,
      required this.onContinue});

  final SetupResult? result;
  final Future<void> Function() onDetectAgain;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final units = ref.watch(unitsProvider(context.localeTag));
    final fmt = DateFormat.yMMMd(context.localeTag);
    final r = result;
    final offline = r?.priceOffline ?? false;
    final unavailable = r?.priceUnavailable ?? false;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  FlowHeading(l.setupReviewTitle,
                      liveRegion: true,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(l.setupReviewBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: mutedOf(context), height: 1.4)),
                  const SizedBox(height: 20),
                  SetupValueTile(
                    label: l.setupRegion,
                    value: s.countryCode.isEmpty
                        ? l.unknownValue
                        : countryDisplayName(l, s.countryCode),
                    note: regionSourceText(context, s),
                    onEdit: () => editRegion(context),
                  ),
                  SetupValueTile(
                    label: l.currency,
                    value: s.hasCurrency ? s.currency : l.unknownValue,
                    note: settingSourceText(context, s, SettingGroup.currency),
                    onEdit: () => editCurrency(context),
                  ),
                  SetupValueTile(
                    label: l.setupDevice,
                    value:
                        s.deviceModel.isEmpty ? l.unknownValue : s.deviceModel,
                    note: s.deviceModelIdentifier.isEmpty
                        ? null
                        : s.deviceModelIdentifier,
                  ),
                  SetupValueTile(
                    label: l.setupBattery,
                    value: capacityText(context, s, units),
                    note: capacitySourceText(context, s.designCapacitySource),
                    warning: s.designCapacityMah <= 0,
                    onEdit: () => editCapacity(context),
                    editLabel:
                        s.designCapacityMah <= 0 ? l.enterManually : null,
                  ),
                  SetupValueTile(
                    label: l.setupElectricity,
                    value: s.hasPrice
                        ? '${units.number(s.pricePerKwh, 2)} ${l.pricePerKwh(s.currency)}'
                        : l.priceUnavailable,
                    note: s.hasPrice
                        ? priceSourceText(context, s, fmt)
                        : offline
                            ? l.priceOfflineBody
                            : unavailable || s.countryCode.isEmpty
                                ? l.priceUnavailableBody(
                                    countryDisplayName(l, s.countryCode))
                                : (s.autoPrice != null &&
                                        !s.autoPriceMatchesCurrency
                                    ? l.currencyManualNote
                                    : l.priceOfflineBody),
                    warning: !s.hasPrice && !offline,
                    // A national household average is an estimate by nature.
                    estimated: s.priceIsAverage,
                    onEdit: () => editPrice(context),
                    editLabel: s.hasPrice ? null : l.enterManually,
                  ),
                  SetupValueTile(
                    label: l.chargingEfficiency,
                    value: units.percent(s.efficiency * 100),
                    note: l.estimated,
                    onEdit: () => editEfficiency(context),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onDetectAgain,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(l.detectAgain),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: onContinue,
                child: Text(l.continueLabel, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One detected value with its source line and an optional Edit action.
///
/// The whole card is the one action (a screen reader finds one node per value:
/// "Region, Poland (PL), Detected automatically, Edit"); "Edit" is part of that
/// node, not a second button. It sits at the end of the card when it fits and
/// under the text otherwise. A [warning] adds an icon and a spoken "Warning",
/// [estimated] the "Estimated" badge.
class SetupValueTile extends StatelessWidget {
  const SetupValueTile({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.warning = false,
    this.estimated = false,
    this.onEdit,
    this.editLabel,
  });

  final String label;
  final String value;
  final String? note;
  final bool warning;
  final bool estimated;
  final VoidCallback? onEdit;
  final String? editLabel;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium;
    final valueStyle = theme.textTheme.titleMedium
        ?.copyWith(color: warning ? Theme.of(context).colorScheme.error : null);
    final noteStyle = theme.textTheme.labelMedium;
    final action = editLabel ?? l.edit;
    final actionStyle =
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    final spokenLabel = joinSpoken([
      label,
      warning ? '${l.warningLabel}: $value' : value,
      note,
      if (estimated) l.estimated,
      if (onEdit != null) action,
    ]);

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlowFitText(label, style: labelStyle),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warning) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.warning_amber_rounded,
                    size: 20, color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: FlowFitText(value, style: valueStyle)),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note!, style: noteStyle),
        ],
        if (estimated) ...[
          const SizedBox(height: 8),
          const EstimatedBadge(),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // One node for the whole card (WbCard.semanticLabel): "Region, Poland
      // (PL), Detected automatically, Edit". "Edit" is part of it, not a
      // second button.
      child: WbCard(
        semanticLabel: spokenLabel,
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        onTap: onEdit,
        child: onEdit == null
            ? main
            : BesideOrBelow(
                main: main,
                side: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(action, style: actionStyle),
                ),
                sideWidth: TextFit.width(context, action, actionStyle) + 4,
                minMainWidth: [
                  TextFit.longestWord(context, label, labelStyle),
                  TextFit.longestWord(context, value, valueStyle) +
                      (warning ? 26 : 0),
                  TextFit.longestWord(context, note, noteStyle),
                ].reduce((a, b) => a > b ? a : b),
                maxSideFraction: 0.4,
                belowGap: 4,
              ),
      ),
    );
  }
}
