import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../core/error_log.dart';
import '../../export/exporter.dart';
import '../../features/auth/presentation/account_screen.dart';
import '../../providers.dart';
import '../../settings/settings.dart';
import '../../setup/region_detection.dart';
import '../theme.dart';
import '../widgets/wb_widgets.dart';
import 'flow_widgets.dart';
import 'setup_editors.dart';
import 'share_anchor.dart';

const kAppVersion = '1.0.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(settingsProvider);
    final units = ref.watch(unitsProvider(context.localeTag));
    final fullCharge = ref.watch(fullChargeCapacityProvider).value;
    final notifier = ref.read(settingsProvider.notifier);

    Future<void> toggleNotification(
        bool on, Settings Function(Settings, bool) set) async {
      if (on && !await ref.read(notifierProvider).requestPermission()) return;
      await notifier.update((x) => set(x, on));
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          FlowHeading(l.tabSettings,
              style: Theme.of(context).textTheme.titleLarge),
          _Section(l.settingsGeneral, [
            _Tile(
              title: l.setupRegion,
              value: s.countryCode.isEmpty
                  ? l.unknownValue
                  : countryDisplayName(l, s.countryCode),
              subtitle: regionSourceText(context, s),
              onTap: () => editRegion(context),
            ),
            _Tile(
              title: l.currency,
              value: s.hasCurrency ? s.currency : l.unknownValue,
              subtitle: s.currencySource.isConscious
                  ? l.currencyManualNote
                  : settingSourceText(context, s, SettingGroup.currency),
              onTap: () => editCurrency(context),
            ),
            if (s.isCustom(SettingGroup.currency) &&
                currencyForCountry(s.countryCode).isNotEmpty &&
                currencyForCountry(s.countryCode) != s.currency)
              _Action(
                  label:
                      l.useDetectedCurrency(currencyForCountry(s.countryCode)),
                  onTap: () => useDetectedCurrency(context)),
            _Tile(
              title: l.electricityPrice,
              value: s.hasPrice
                  ? '${units.number(s.pricePerKwh, 2)} ${l.pricePerKwh(s.currency)}'
                  : l.priceUnavailable,
              subtitle: s.hasPrice
                  ? priceSourceText(
                      context, s, DateFormat.yMMMd(context.localeTag))
                  : (s.priceMode == ElectricityPriceMode.automatic
                      ? (s.autoPrice != null && !s.autoPriceMatchesCurrency
                          ? l.currencyManualNote
                          : l.priceOfflineBody)
                      : l.priceSourceManual),
              onTap: () => editPrice(context),
            ),
            _Action(
                label: s.priceMode == ElectricityPriceMode.manual
                    ? l.useAutomaticPrice
                    : l.useCustomPrice,
                onTap: () => s.priceMode == ElectricityPriceMode.manual
                    ? useAutomaticPrice(context)
                    : editPrice(context)),
            _Tile(
              title: l.chargingEfficiency,
              value: units.percent(s.efficiency * 100),
              subtitle: '${l.estimated} · ${l.efficiencyHint}',
              onTap: () => editEfficiency(context),
            ),
          ]),
          _Section(l.settingsDevice, [
            _Tile(
              title: l.setupDevice,
              value: s.deviceModel.isEmpty ? l.unknownValue : s.deviceModel,
              subtitle: s.deviceModelIdentifier.isEmpty
                  ? null
                  : s.deviceModelIdentifier,
              onTap: () => redetectCapacity(context),
            ),
            _Tile(
              title: l.batteryCapacity,
              value: capacityText(context, s, units),
              subtitle:
                  '${l.specificationSource}: ${capacitySourceText(context, s.designCapacitySource)}',
              onTap: () => editCapacity(context),
            ),
            // What this battery holds today: an estimate from the charge counter,
            // shown beside (never instead of) the design capacity. Read-only.
            if (fullCharge != null && fullCharge.isAvailable)
              _Tile(
                title: l.estimatedFullChargeCapacity,
                value: units.approx(units.mah(fullCharge.mah ?? 0),
                    estimated: true),
                subtitle: l.estimatedFullChargeCapacityBody(
                    fullChargeConfidenceText(context, fullCharge.confidence)),
              ),
            _Action(
                label: l.detectAgain, onTap: () => redetectCapacity(context)),
            _Choice<bool>(
              title: l.units,
              value: s.binaryUnits,
              options: [(false, l.unitsDecimal), (true, l.unitsBinary)],
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(binaryUnits: v)),
            ),
            _Choice<AppTheme>(
              title: l.appearance,
              value: s.theme,
              options: [
                (AppTheme.system, l.themeSystem),
                (AppTheme.light, l.themeLight),
                (AppTheme.dark, l.themeDark)
              ],
              onChanged: (v) => notifier.update((x) => x.copyWith(theme: v)),
            ),
          ]),
          _Section(l.notifications, [
            FlowSwitchTile(
              title: l.notifMobileThreshold,
              subtitle: l.notifMobileThresholdBody(
                  units.bytes(s.mobileThresholdBytes)),
              value: s.notifyMobileThreshold,
              onChanged: (v) => toggleNotification(
                  v, (x, on) => x.copyWith(notifyMobileThreshold: on)),
            ),
            // The amount is a row of its own: an action hidden behind the
            // switch's subtitle cannot be found by a screen reader.
            _Tile(
              title: l.notifThresholdChange,
              value: units.bytes(s.mobileThresholdBytes),
              onTap: () => _editThreshold(context, ref),
            ),
            FlowSwitchTile(
              title: l.notifChargingDone,
              value: s.notifyChargingDone,
              onChanged: (v) => toggleNotification(
                  v, (x, on) => x.copyWith(notifyChargingDone: on)),
            ),
            FlowSwitchTile(
              title: l.notifWeeklyEnergy,
              value: s.notifyWeeklyEnergy,
              onChanged: (v) => toggleNotification(
                  v, (x, on) => x.copyWith(notifyWeeklyEnergy: on)),
            ),
            FlowSwitchTile(
              title: l.notifAboveAverage,
              value: s.notifyAboveAverage,
              onChanged: (v) => toggleNotification(
                  v, (x, on) => x.copyWith(notifyAboveAverage: on)),
            ),
            Semantics(
              container: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Text(l.notificationsOptional,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          ]),
          _Section(l.privacy, [
            _Tile(
              title: l.account,
              icon: Icons.person_outline_rounded,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen())),
            ),
            FlowSwitchTile(
              title: l.dataCollection,
              subtitle: l.dataCollectionBody,
              value: s.dataCollection,
              onChanged: (v) =>
                  notifier.update((x) => x.copyWith(dataCollection: v)),
            ),
            // The share sheet is anchored to the row that was tapped.
            Builder(
                builder: (rowContext) => _Tile(
                    title: l.exportCsv,
                    icon: Icons.table_chart_outlined,
                    onTap: () => _export(rowContext, ref, json: false))),
            Builder(
                builder: (rowContext) => _Tile(
                    title: l.exportJson,
                    icon: Icons.data_object_rounded,
                    onTap: () => _export(rowContext, ref, json: true))),
            _Tile(
              title: l.resetStatistics,
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onTap: () => _confirmReset(context, ref),
            ),
          ]),
          _Section(l.aboutWattByte, [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AboutHeader(version: l.version(kAppVersion)),
                  const SizedBox(height: 10),
                  Text(l.aboutBody,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// The mobile-data alert amount, in the unit the user reads everywhere else.
  Future<void> _editThreshold(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    final units = ref.read(unitsProvider(context.localeTag));
    final unit = s.binaryUnits ? 1024.0 * 1024 * 1024 : 1e9;
    final v = await showNumberEditor(context,
        title: context.l10n.notifMobileThreshold,
        initial: s.mobileThresholdBytes / unit,
        suffix: s.binaryUnits ? 'GiB' : 'GB',
        hint: units.number(5, 0),
        max: 1000);
    if (v != null && v > 0) {
      await ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(mobileThresholdBytes: (v * unit).round()));
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref,
      {required bool json}) async {
    try {
      await _exportFiles(context, ref, json: json);
    } catch (e, st) {
      reportError(e, st, 'export');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.exportFailed)));
      }
    }
  }

  Future<void> _exportFiles(BuildContext context, WidgetRef ref,
      {required bool json}) async {
    final data = await ref.read(appDataProvider.future);
    final calc = ref.read(energyCalcProvider);
    final s = ref.read(settingsProvider);
    final dir = await getTemporaryDirectory();
    final now = ref.read(clockProvider)();
    final stamp = DateFormat('yyyyMMdd-HHmm').format(now);
    final files = <XFile>[];
    Future<void> write(String name, String content, String mime) async {
      final f = File(p.join(dir.path, name));
      await f.writeAsString(content);
      files.add(XFile(f.path, mimeType: mime));
    }

    if (json) {
      await write(
          'wattbyte-$stamp.json',
          Exporter.json(
              days: data.days,
              sessions: data.sessions,
              calc: calc,
              settings: s,
              now: now),
          'application/json');
    } else {
      await write(
          'wattbyte-data-$stamp.csv', Exporter.dataCsv(data.days), 'text/csv');
      await write('wattbyte-charging-$stamp.csv',
          Exporter.chargingCsv(data.sessions, calc, s.currency), 'text/csv');
    }
    // The share sheet needs a non-empty anchor rectangle on iOS 26+ and iPad.
    if (!context.mounted) return;
    await Share.shareXFiles(files,
        subject: context.l10n.shareSubject,
        sharePositionOrigin: shareAnchorForContext(context));
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => flowDialog(
        context,
        title: l.resetConfirmTitle,
        body: l.resetConfirmBody,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.reset,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dbProvider).resetAll();
    ref.read(refreshTickProvider.notifier).state++;
  }
}

// -------------------------------------------------------------------- editors

/// A number in a bottom sheet. Returns null when dismissed. The sheet itself
/// refuses (and says why) anything that is not a number in `(0, max]`
/// (`[0, max]` with [allowZero]).
Future<double?> showNumberEditor(
  BuildContext context, {
  required String title,
  required double initial,
  required String suffix,
  required String hint,
  int decimals = 2,
  double max = 1e9,
  bool allowZero = false,
}) async {
  final l = context.l10n;
  double? parse(String t) => double.tryParse(t.replaceAll(',', '.').trim());
  final text = await showTextEditor(
    context,
    title: title,
    initial: initial > 0 ? _plain(initial, decimals) : '',
    hint: hint,
    suffix: suffix,
    numeric: true,
    validate: (t) {
      final v = parse(t);
      final ok =
          v != null && v.isFinite && (allowZero ? v >= 0 : v > 0) && v <= max;
      return ok ? null : l.editorInvalidNumber(_plain(max, 0));
    },
  );
  return text == null ? null : parse(text);
}

/// `85` for 85.0, `1.15` for 1.15, `0.95` for 0.9500000000000001.
String _plain(double v, int decimals) {
  final fixed = v.toStringAsFixed(decimals < 0 ? 0 : math.max(decimals, 4));
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// One text field in a bottom sheet: scrolls with large text, keeps its Save
/// button above the keyboard and shows [validate]'s message instead of closing.
Future<String?> showTextEditor(
  BuildContext context, {
  required String title,
  required String initial,
  String? hint,
  String? suffix,
  bool numeric = false,
  int? maxLength,
  String? Function(String text)? validate,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TextEditorSheet(
        title: title,
        initial: initial,
        hint: hint,
        suffix: suffix,
        numeric: numeric,
        maxLength: maxLength,
        validate: validate,
      ),
    );

class _TextEditorSheet extends StatefulWidget {
  const _TextEditorSheet({
    required this.title,
    required this.initial,
    this.hint,
    this.suffix,
    this.numeric = false,
    this.maxLength,
    this.validate,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? suffix;
  final bool numeric;
  final int? maxLength;
  final String? Function(String text)? validate;

  @override
  State<_TextEditorSheet> createState() => _TextEditorSheetState();
}

class _TextEditorSheetState extends State<_TextEditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text;
    final error = widget.validate?.call(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      // The keyboard pushes the sheet up; the part above it scrolls, the Save
      // button below it never leaves the screen.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FlowHeading(widget.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    // The visible title names the field for a screen reader.
                    Semantics(
                      label: widget.title,
                      child: LayoutBuilder(builder: (context, constraints) {
                        // A unit beside the number is fine while the number
                        // keeps most of the field; at large text it would
                        // leave a few pixels for the digits, so it moves
                        // under the field.
                        final suffix = widget.suffix;
                        final unitWidth = suffix == null
                            ? 0.0
                            : TextFit.width(context, suffix,
                                Theme.of(context).textTheme.bodyLarge);
                        final unitBeside =
                            unitWidth <= constraints.maxWidth * 0.3;
                        return TextField(
                          controller: _controller,
                          autofocus: true,
                          maxLength: widget.maxLength,
                          keyboardType: widget.numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : TextInputType.text,
                          textInputAction: TextInputAction.done,
                          textCapitalization: widget.numeric
                              ? TextCapitalization.none
                              : TextCapitalization.characters,
                          autocorrect: false,
                          enableSuggestions: false,
                          inputFormatters: widget.numeric
                              ? [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'))
                                ]
                              : null,
                          decoration: InputDecoration(
                            hintText: widget.hint,
                            suffixText: unitBeside ? suffix : null,
                            helperText: unitBeside ? null : suffix,
                            helperMaxLines: 2,
                            counterText: '',
                            errorText: _error,
                            errorMaxLines: 4,
                          ),
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _save(),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: _save,
                child: Text(l.save, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- list parts

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
            child: FlowHeading(title,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          WbCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(indent: 18, endIndent: 18),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      );
}

/// "Version 1.0.0" beside the app name, or below it when they do not fit.
class _AboutHeader extends StatelessWidget {
  const _AboutHeader({required this.version});

  final String version;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.titleMedium;
    final versionStyle = theme.textTheme.labelMedium;
    return BesideOrBelow(
      sideWidth: TextFit.width(context, version, versionStyle),
      minMainWidth: 38 + TextFit.longestWord(context, l.appName, nameStyle),
      main: Row(
        children: [
          const ExcludeSemantics(child: WattByteMark(size: 28)),
          const SizedBox(width: 10),
          Expanded(child: FlowFitText(l.appName, style: nameStyle)),
        ],
      ),
      side: Text(version, style: versionStyle),
    );
  }
}

/// A row that opens an editor or a screen. One merged, tappable node for a
/// screen reader ("Region, Poland (PL), Detected automatically"). The value
/// sits at the end of the row when it fits, otherwise under the title.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    this.value,
    this.subtitle,
    this.icon,
    this.destructive = false,
    this.onTap,
  });

  final String title;
  final String? value;
  final String? subtitle;
  final IconData? icon;
  final bool destructive;

  /// Null makes the tile a read-only row.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    final titleStyle = theme.textTheme.bodyLarge
        ?.copyWith(color: color, fontWeight: FontWeight.w600);
    final valueStyle =
        theme.textTheme.bodyMedium?.copyWith(color: mutedOf(context));
    final subtitleStyle = theme.textTheme.labelMedium;
    final label = joinSpoken([title, value, subtitle]);

    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: LayoutBuilder(builder: (context, constraints) {
              final lead = icon == null ? 0.0 : 24.0 + 16;
              final trail = value == null ? 24.0 + 12 : 0.0;
              final beside = value != null &&
                  fitsBeside(
                    available: constraints.maxWidth - lead - trail,
                    sideWidth: TextFit.width(context, value!, valueStyle),
                    minMain: math.max(
                        TextFit.longestWord(context, title, titleStyle),
                        TextFit.longestWord(context, subtitle, subtitleStyle)),
                  );
              return Row(
                children: [
                  if (icon != null) ...[
                    ExcludeSemantics(
                        child: Icon(icon, color: color ?? WbColors.byte)),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FlowFitText(title, style: titleStyle),
                        if (!beside && value != null) ...[
                          const SizedBox(height: 2),
                          FlowFitText(value!, style: valueStyle),
                        ],
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: subtitleStyle),
                        ],
                      ],
                    ),
                  ),
                  if (beside) ...[
                    const SizedBox(width: 12),
                    Text(value!, style: valueStyle, textAlign: TextAlign.end),
                  ],
                  if (value == null) ...[
                    const SizedBox(width: 12),
                    ExcludeSemantics(
                        child: Icon(Icons.chevron_right_rounded,
                            color: mutedOf(context))),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// A single tappable action line inside a section (e.g. "Use custom price").
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: FlowFitText(label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: accentTextOf(context), fontWeight: FontWeight.w700)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
        dense: true,
        onTap: onTap,
      );
}

/// Pick one of a few options: the shared segmented control, which stacks its
/// segments when a label would not fit on one line.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The group has one name; the visible title is not read a second time.
    return Semantics(
      container: true,
      label: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: FlowFitText(title,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: WbSegmented<T>(
                segments: [
                  for (final (v, label) in options) WbSegment(v, label)
                ],
                selected: value,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
