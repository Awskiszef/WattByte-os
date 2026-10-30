// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../calc/energy.dart';
import '../../cloud_providers.dart';
import '../../core/error_log.dart';
import '../../core/units.dart';
import '../../domain/battery_capacity.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers.dart';
import '../../settings/settings.dart';
import '../../setup/device_specification.dart';
import '../../setup/region_detection.dart';
import 'settings_screen.dart' show showNumberEditor, showTextEditor;

/// Editors and display helpers shared by the setup review and Settings.
/// Every edit here is a conscious choice: it marks the value manual and pushes
/// the account-bound part to the server (`AccountSettingsController.push`, which
/// sends only what this phone decided, with its source).

Future<void> _save(BuildContext context, Settings Function(Settings) change,
    {bool account = true, bool device = false}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(settingsProvider.notifier).update(change);
  final s = container.read(settingsProvider);
  if (account) {
    unawaited(container.read(accountSettingsControllerProvider)?.push());
  }
  if (device) {
    final sync = container.read(syncServiceProvider);
    if (sync != null) {
      // The design capacity goes up with the current estimate of this battery's
      // full-charge capacity, as two separate groups.
      final fullCharge = await _currentFullCharge(container);
      sync.registerDevice(
        DeviceSpecification(
          manufacturer: '',
          model: s.deviceModel,
          modelIdentifier:
              s.deviceModelIdentifier.isEmpty ? null : s.deviceModelIdentifier,
          design: s.designCapacity,
        ),
        fullCharge: fullCharge,
      );
    }
  }
}

/// The collector's estimated full-charge capacity; unavailable when it cannot
/// be read (a missing estimate must never block saving a setting).
Future<EstimatedFullChargeCapacity> _currentFullCharge(
    ProviderContainer container) async {
  try {
    return await container.read(collectorProvider).fullChargeCapacity();
  } catch (e, st) {
    reportError(e, st, 'read full-charge capacity');
    return EstimatedFullChargeCapacity.unavailable;
  }
}

Future<void> editRegion(BuildContext context) async {
  final s =
      ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final l = context.l10n;
  final v = await showTextEditor(context,
      title: l.setupRegion,
      initial: s.countryCode,
      hint: l.countryCodeHint,
      maxLength: 2,
      validate: (t) => RegExp(r'^[A-Za-z]{2}$').hasMatch(t.trim())
          ? null
          : l.editorInvalidCountry);
  if (v == null || !context.mounted) return;
  final cc = v.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(cc)) return;
  await _save(context, (x) {
    var next = x.withManualRegion(cc);
    // A new region implies its currency unless somebody picked one: the user
    // here, or the user on another device (a synced value they chose by hand).
    final currency = currencyForCountry(cc);
    if (!next.isCustom(SettingGroup.currency) && currency.isNotEmpty) {
      next = next.withDetectedCurrency(currency);
    }
    return next;
  });
  if (context.mounted) await refreshAutomaticPrice(context, force: true);
}

Future<void> editCurrency(BuildContext context) async {
  final s =
      ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final l = context.l10n;
  final v = await showTextEditor(context,
      title: l.currency,
      initial: s.currency,
      maxLength: 3,
      validate: (t) => RegExp(r'^[A-Za-z]{3}$').hasMatch(t.trim())
          ? null
          : l.editorInvalidCurrency);
  if (v == null || !context.mounted) return;
  final code = v.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) return;
  await _save(context, (x) => x.withManualCurrency(code));
}

Future<void> useDetectedCurrency(BuildContext context) async {
  final s =
      ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final detected = currencyForCountry(s.countryCode);
  if (detected.isEmpty) return;
  await _save(context, (x) {
    final next = x.withDetectedCurrency(detected);
    // A tariff typed for the old currency no longer fits: the average takes over,
    // and that is a decision about the price (`manual`), so it is uploaded too.
    return next.priceMode == ElectricityPriceMode.manual
        ? next.withAutomaticPrice()
        : next;
  });
}

/// Price editor shared by Settings, the setup review and the dashboard cost card.
/// Saving a number switches to a custom (manual) price.
Future<void> editPrice(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final s = container.read(settingsProvider);
  final units = container.read(unitsProvider(context.localeTag));
  final v = await showNumberEditor(context,
      title: context.l10n.electricityPrice,
      initial: s.priceMode == ElectricityPriceMode.manual
          ? s.manualPricePerKwh
          : s.pricePerKwh,
      suffix: context.l10n.pricePerKwh(s.currency),
      hint: units.number(1.15, 2),
      max: Settings.maxPricePerKwh,
      allowZero: true);
  if (v != null && v.isFinite && v >= 0 && v <= Settings.maxPricePerKwh) {
    if (!context.mounted) return;
    await _save(context, (x) => x.withManualPrice(v));
  }
}

Future<void> useAutomaticPrice(BuildContext context) async {
  await _save(context, (x) => x.withAutomaticPrice());
  if (context.mounted) await refreshAutomaticPrice(context, force: true);
}

/// Fetches the household average when automatic mode is on and the stored
/// value is stale; never blocks the UI and never touches a manual price.
Future<void> refreshAutomaticPrice(BuildContext context,
    {bool force = false}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final service = container.read(electricityPriceServiceProvider);
  final s = container.read(settingsProvider);
  if (service == null || s.countryCode.isEmpty) return;
  if (!force && !service.isStale(s)) return;
  try {
    final price = await service.fetch(s.countryCode);
    if (price == null) {
      await container
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(clearAutoPrice: true)._reapply());
    } else {
      await container
          .read(settingsProvider.notifier)
          .update((x) => x.withAutoPrice(price));
    }
  } catch (_) {
    // Offline: the last known value stays.
  }
}

extension on Settings {
  Settings _reapply() => priceMode == ElectricityPriceMode.manual
      ? this
      : copyWith(pricePerKwh: 0);
}

/// Manual entry of the design (nominal) capacity of this phone model.
Future<void> editCapacity(BuildContext context) async {
  final s =
      ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final v = await showNumberEditor(context,
      title: context.l10n.batteryCapacity,
      initial: s.designCapacityMah,
      suffix: 'mAh',
      hint: '4000',
      decimals: 0,
      max: EnergyCalc.maxCapacityMah);
  if (v != null && v > 0 && v <= EnergyCalc.maxCapacityMah) {
    if (!context.mounted) return;
    await _save(
        context,
        (x) => x.withDesignCapacity(
            DesignCapacity(mah: v, source: DesignCapacitySource.manual)),
        account: false,
        device: true);
  }
}

/// Fills in a design capacity that is missing although the model is known to
/// the device database, once per app start.
///
/// Why it exists: an install from before the design / estimated split can hold
/// no design capacity. Its old `system` / `estimated` capacity was a charge-counter
/// measurement, which is never a design capacity, so it was dropped on load; and
/// an offline first setup can have found nothing for a model that only the API
/// catalog lists. The lookup is cheap (the bundled catalog first, the network
/// only for a model the catalog does not list) and never blocks the UI.
///
/// It only ever fills a gap: a known capacity (a manual one included) is never
/// replaced, and a failed or empty lookup changes nothing.
Future<void> resolveMissingDesignCapacity(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final s = container.read(settingsProvider);
  if (!s.onboarded ||
      s.designCapacity.isKnown ||
      s.deviceModelIdentifier.isEmpty) {
    return;
  }
  try {
    final spec = await container.read(autoSetupProvider).device.detect();
    if (!spec.hasDesignCapacity || !context.mounted) return;
    await _save(
        context,
        // Decided on the settings as they are NOW: the user may have typed a
        // capacity while the lookup ran.
        (x) => x.designCapacity.isKnown
            ? x
            : x.withDesignCapacity(spec.design).copyWith(
                nominalVoltage: spec.nominalVoltage ?? x.nominalVoltage),
        account: false,
        device: true);
  } catch (e, st) {
    reportError(e, st, 'resolve missing design capacity');
  }
}

/// Re-runs device detection.
///
/// It only ever writes a capacity it FOUND. A detection that finds nothing (a model the catalogs do not list, no
/// network) leaves a known capacity, a typed one included, exactly as it is: it used to write "unknown" over it, which
/// the app then showed and registered with the server as no capacity at all (G-16). A detected capacity that differs
/// from one the user typed replaces it only after they have seen both numbers and said so.
Future<void> redetectCapacity(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final spec = await container.read(autoSetupProvider).device.detect();
  if (!context.mounted) return;
  final current = container.read(settingsProvider).designCapacity;
  if (!spec.hasDesignCapacity && current.isKnown) {
    return; // nothing found: keep what is there
  }
  if (spec.hasDesignCapacity &&
      current.isKnown &&
      current.source == DesignCapacitySource.manual &&
      current.mah != spec.design.mah) {
    final units = container.read(unitsProvider(context.localeTag));
    final replace = await _confirmReplaceTyped(
        context, units.mah(current.mah!), units.mah(spec.design.mah!));
    if (replace != true || !context.mounted) return;
  }
  await _save(
      context,
      (x) => x
          .copyWith(
            deviceModel: spec.model.isEmpty ? null : spec.model,
            deviceModelIdentifier: spec.modelIdentifier,
            nominalVoltage: spec.nominalVoltage,
          )
          .withDesignCapacity(spec.design),
      account: false,
      device: true);
}

Future<bool?> _confirmReplaceTyped(
    BuildContext context, String typed, String detected) {
  final l = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.redetectKeepsTypedTitle),
      content: Text(l.redetectKeepsTypedBody(typed, detected)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.redetectKeepMine)),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.redetectUseDetected)),
      ],
    ),
  );
}

Future<void> editEfficiency(BuildContext context) async {
  final s =
      ProviderScope.containerOf(context, listen: false).read(settingsProvider);
  final v = await showNumberEditor(context,
      title: context.l10n.chargingEfficiency,
      initial: s.efficiency * 100,
      suffix: '%',
      hint: '85',
      max: 100);
  if (v != null && v > 0 && v <= 100) {
    if (!context.mounted) return;
    await _save(context, (x) => x.copyWith(efficiency: v / 100),
        account: false);
  }
}

// ------------------------------------------------------------------ display

/// "Poland (PL)" in the app language; a code without a name shows as the code.
String countryDisplayName(AppLocalizations l, String code) {
  if (code.isEmpty) return '';
  final name = l.countryName(code);
  return name == code ? code : '$name ($code)';
}

String regionSourceText(BuildContext context, Settings s) {
  final l = context.l10n;
  if (s.countryCode.isEmpty) return l.unknownValue;
  return settingSourceText(context, s, SettingGroup.region,
      detected: s.regionDetection == 'backendCountry'
          ? l.detectedFromNetwork
          : l.detectedAutomatically);
}

/// Why a region, currency or price decision has its value, in the user's words:
/// "Detected automatically", "Chosen manually", "Synced from your account" (with
/// "Chosen manually" added when the account holds a choice the user made on
/// another device). The enum names never reach the screen.
String settingSourceText(BuildContext context, Settings s, SettingGroup group,
    {String? detected}) {
  final l = context.l10n;
  return switch (s.sourceOf(group)) {
    SettingSource.detected => detected ?? l.detectedAutomatically,
    SettingSource.manual || SettingSource.migratedManual => l.regionManual,
    SettingSource.accountSynced =>
      (s.originalSourceOf(group)?.isConscious ?? false)
          ? '${l.sourceAccountSynced} · ${l.regionManual}'
          : l.sourceAccountSynced,
  };
}

/// The design (nominal) capacity, shown exactly: it is a published or a typed
/// figure. Unknown says so; there is no "typical" number.
String capacityText(BuildContext context, Settings s, Units units) {
  if (s.designCapacityMah <= 0) return context.l10n.capacityUnavailable;
  return units.mah(s.designCapacityMah);
}

String capacitySourceText(BuildContext context, DesignCapacitySource source) {
  final l = context.l10n;
  return switch (source) {
    DesignCapacitySource.manufacturerSpecification =>
      l.detectedFromManufacturer,
    DesignCapacitySource.localDeviceDatabase => l.detectedFromSpecs,
    DesignCapacitySource.backendDeviceDatabase => l.detectedFromCatalogOnline,
    DesignCapacitySource.manual => l.regionManual,
    DesignCapacitySource.unknown => l.capacityUnavailableBody,
  };
}

/// "high" / "medium" / "low". `none` means "no estimate", so it is never shown
/// next to a number; it reads as unknown.
String fullChargeConfidenceText(
    BuildContext context, FullChargeCapacityConfidence confidence) {
  final l = context.l10n;
  return switch (confidence) {
    FullChargeCapacityConfidence.high => l.confidenceHigh,
    FullChargeCapacityConfidence.medium => l.confidenceMedium,
    FullChargeCapacityConfidence.low => l.confidenceLow,
    FullChargeCapacityConfidence.none => l.unknownValue,
  };
}

String priceSourceText(BuildContext context, Settings s, DateFormat fmt) {
  final l = context.l10n;
  // The decision (mode and tariff) may come from the account; the household
  // average is data from the API and is described on its own.
  final synced = s.priceSource == SettingSource.accountSynced
      ? l.sourceAccountSynced
      : null;
  String withSync(String text) => synced == null ? text : '$text · $synced';
  if (s.priceMode == ElectricityPriceMode.manual) {
    return withSync(l.priceSourceManual);
  }
  final a = s.autoPrice;
  if (a == null) return withSync(l.priceSourceAutomatic);
  final basis = l.householdAverage(countryDisplayName(l, a.countryCode));
  final updated = l.priceUpdated(fmt.format(a.updatedAt));
  return '${withSync(l.priceSourceAutomatic)} · $basis · $updated${a.stale ? '\n${l.priceStaleNote}' : ''}';
}
