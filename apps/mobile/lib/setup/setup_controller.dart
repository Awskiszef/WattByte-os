import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_failure.dart';
import '../core/error_log.dart';
import '../domain/battery_capacity.dart';
import '../features/auth/domain/auth_models.dart';
import '../generated/api/api.dart' as api;
import '../settings/settings.dart';
import 'account_settings.dart';
import 'device_specification.dart';
import 'electricity_price.dart';
import 'region_detection.dart';

/// What the start-up gate shows.
enum StartDestination {
  /// Session being restored.
  splash,

  /// No account: Welcome -> Create account / Sign in.
  welcome,

  /// Account present, automatic setup not finished.
  setup,
  dashboard,

  /// Account present, but the settings of THIS account could not be loaded (the previous user's are still on the
  /// phone): a blocking message with a retry, never the previous user's values under the new account (F-21).
  settingsError,
}

/// Pure routing rule for app start (see `docs/AUTO_SETUP.md`):
///
///   localOnlyDev       -> debug-only development mode (`LOCAL_ONLY_DEV=true`,
///                         no backend): setup, then dashboard, no account
///   session restoring  -> splash
///   unauthenticated    -> welcome (account required before any configuration)
///   authenticated      -> setup until finished, then dashboard
///   authenticated, but the account's own settings are not loaded yet -> splash
///                         (what is on the phone may belong to the previous user)
///
/// [localOnlyDev] is `AppConfig.isLocalOnlyDev` and nothing else. The account is
/// never skipped because an API address is missing or broken: without
/// [localOnlyDev] this build requires a session, whatever the address says.
StartDestination startDestination({
  required bool localOnlyDev,
  required AsyncValue<AuthState> auth,
  required Settings settings,
  bool settingsBound = true,
  bool settingsBindFailed = false,
}) {
  if (localOnlyDev) {
    return settings.onboarded
        ? StartDestination.dashboard
        : StartDestination.setup;
  }
  // `AsyncValue.value` rethrows an error that has no value; a failed session
  // restore is "no session": the account screen, never the app.
  if (auth.hasError && !auth.hasValue) return StartDestination.welcome;
  final state = auth.value;
  if (auth.isLoading || state == null || state is AuthUnknown) {
    return StartDestination.splash;
  }
  if (state is! SignedIn) return StartDestination.welcome;
  if (!settingsBound) {
    return settingsBindFailed
        ? StartDestination.settingsError
        : StartDestination.splash;
  }
  return settings.onboarded
      ? StartDestination.dashboard
      : StartDestination.setup;
}

/// Result of one automatic detection pass; every field may be unknown.
class SetupResult {
  const SetupResult({
    this.region,
    this.device,
    this.price,
    this.priceUnavailable = false,
    this.priceOffline = false,
    this.accountSettings,
    this.fullCharge = EstimatedFullChargeCapacity.unavailable,
  });

  final DetectedRegion? region;

  /// The phone model and its design capacity (unknown when no database has it).
  final DeviceSpecification? device;
  final AutoPrice? price;

  /// No source covers the country (as opposed to "could not ask").
  final bool priceUnavailable;

  /// The API could not be reached; the price will be fetched when online.
  final bool priceOffline;

  /// What the account holds (possibly nothing yet); null when the account could
  /// not be reached, which changes nothing about the settings of this phone.
  final api.UserSettingsDto? accountSettings;

  /// The collector's estimate of this battery's full-charge capacity. It is
  /// only sent with the device registration; it never becomes a setting and is
  /// never a design capacity.
  final EstimatedFullChargeCapacity fullCharge;
}

/// Runs the detections in parallel and writes the outcome into [Settings]
/// without touching anything the user set by hand.
class AutoSetup {
  AutoSetup({
    required this.region,
    required this.device,
    this.price,
    this.account,
    this.registerDevice,
    this.fullCharge,
  });

  final RegionDetectionService region;
  final DeviceSpecificationService device;

  /// Null in builds without an API.
  final ElectricityPriceService? price;
  final AccountSettingsSync? account;

  /// Sends the device-bound specification (design capacity) and the estimated
  /// full-charge capacity with the device registration.
  final Future<void> Function(
          DeviceSpecification spec, EstimatedFullChargeCapacity fullCharge)?
      registerDevice;

  /// The estimated full-charge capacity of this battery (the collector's
  /// reading of the Android charge counter), when the app has one.
  final Future<EstimatedFullChargeCapacity> Function()? fullCharge;

  /// Detects region, device and price in parallel; the price needs the region first.
  Future<SetupResult> detect(Settings current) async {
    // A region the user chose is not detected again (and the lookup is skipped).
    final regionFuture = current.regionSource.isConscious
        ? Future.value(DetectedRegion(
            countryCode: current.countryCode,
            currencyCode: current.currency,
            source: RegionDetectionSource.manual,
            confidence: 1))
        : region.detect();
    final deviceFuture = _detectDevice();
    final fullChargeFuture = _detectFullCharge();
    final accountFuture =
        account?.pull() ?? Future<api.UserSettingsDto?>.value();

    final detectedRegion = await regionFuture;
    final accountSettings = await accountFuture;
    // The household price is asked for the region the settings will end up
    // with: the same priorities as `apply` (own choice, account, detection).
    final resolved = mergeAccountSettings(current, accountSettings);
    final country = resolved.regionSource != SettingSource.detected &&
            resolved.countryCode.isNotEmpty
        ? resolved.countryCode
        : detectedRegion?.countryCode;

    AutoPrice? price;
    var unavailable = false;
    var offline = false;
    final priceService = this.price;
    if (priceService != null && country != null) {
      try {
        price = await priceService.fetch(country);
        unavailable = price == null;
      } on ApiFailure catch (e) {
        offline = e.isTransient;
        unavailable = !offline;
      } catch (e, st) {
        reportError(e, st, 'setup price');
        offline = true;
      }
    }
    return SetupResult(
      region: detectedRegion,
      device: await deviceFuture,
      price: price,
      priceUnavailable: unavailable,
      priceOffline: offline,
      accountSettings: accountSettings,
      fullCharge: await fullChargeFuture,
    );
  }

  Future<DeviceSpecification?> _detectDevice() async {
    try {
      return await device.detect();
    } catch (e, st) {
      reportError(e, st, 'setup device');
      return null;
    }
  }

  Future<EstimatedFullChargeCapacity> _detectFullCharge() async {
    final read = fullCharge;
    if (read == null) return EstimatedFullChargeCapacity.unavailable;
    try {
      return await read();
    } catch (e, st) {
      reportError(e, st, 'setup full-charge capacity');
      return EstimatedFullChargeCapacity.unavailable;
    }
  }

  /// Merges a detection into the settings, by the priorities of
  /// `docs/SETTING_SOURCES.md`:
  ///
  ///   1. an explicit local choice (`manual`, `migratedManual`) that the account
  ///      has not acknowledged yet
  ///   2. the account's value, recorded as `accountSynced` with the account's
  ///      origin as `originalSource` (never as `manual`)
  ///   3. fresh detection, for what is still undecided
  ///   4. the fallback: what the phone already had
  ///
  /// No account answer (`accountSettings` null, e.g. offline) leaves every value
  /// and every source of this phone as it was.
  @visibleForTesting
  static Settings apply(Settings s, SetupResult r) {
    var next = mergeAccountSettings(s, r.accountSettings);

    // Region and currency: detection only fills what nobody decided.
    final region = r.region;
    if (next.regionSource == SettingSource.detected &&
        region != null &&
        region.source != RegionDetectionSource.manual &&
        region.countryCode.isNotEmpty) {
      // The same region found again is no new decision to upload.
      next = next.countryCode == region.countryCode
          ? next.copyWith(regionDetection: region.source.name)
          : next.withDetectedRegion(region.countryCode,
              detection: region.source.name);
    }
    if (next.currencySource == SettingSource.detected) {
      // The currency of the region the settings ended up with (an account
      // region is not the region this phone detected).
      final detected = next.countryCode == region?.countryCode
          ? (region?.currencyCode ?? '')
          : currencyForCountry(next.countryCode);
      if (detected.isNotEmpty && next.currency != detected) {
        next = next.withDetectedCurrency(detected);
      }
    }

    // Device: the model and its design capacity. A manual capacity is sticky for
    // automatic detection, and a detection without a capacity (unknown model,
    // failed lookup) never downgrades a known one. The estimated full-charge
    // capacity is not a setting: it stays in the collector.
    final d = r.device;
    if (d != null) {
      next = next.copyWith(
        deviceModel: d.model.isEmpty ? null : d.model,
        deviceModelIdentifier: d.modelIdentifier,
      );
      if (next.designCapacitySource != DesignCapacitySource.manual &&
          d.hasDesignCapacity) {
        next = next.withDesignCapacity(d.design).copyWith(
              nominalVoltage: d.nominalVoltage ?? next.nominalVoltage,
            );
      }
    }

    // Price: stored always, applied only in automatic mode (inside withAutoPrice).
    if (r.price != null) next = next.withAutoPrice(r.price!);
    return next;
  }
}

/// Owns the setup flow state for the UI: idle -> detecting -> review -> done.
class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  /// [onAccountPushed] is told which groups the account took, with the settings
  /// they were uploaded from; the upload does not hold the review screen back.
  Future<void> run({
    required AutoSetup setup,
    required Settings current,
    required Future<void> Function(Settings) save,
    Future<void> Function(AccountPush)? onAccountPushed,
  }) async {
    state = state.copyWith(phase: SetupPhase.detecting);
    final result = await setup.detect(current);
    final merged = AutoSetup.apply(current, result);
    await save(merged);
    final spec = result.device;
    final register = setup.registerDevice;
    if (register != null && spec != null) {
      // Device-bound facts go with the registration; failure is not a setup failure.
      // The design capacity sent is the one the app KEEPS (a manual value survives
      // detection), so the server's record never disagrees with the app.
      final registered = DeviceSpecification(
        manufacturer: spec.manufacturer,
        model: spec.model,
        modelIdentifier: spec.modelIdentifier,
        nominalVoltage: spec.nominalVoltage,
        design: merged.designCapacity,
      );
      unawaited(register(registered, result.fullCharge)
          .catchError((Object e, StackTrace st) {
        reportError(e, st, 'setup register');
      }));
    }
    final account = setup.account;
    if (account != null) {
      unawaited(account
          .push(merged, current: result.accountSettings)
          .then((push) async {
        if (push != null && onAccountPushed != null) {
          await onAccountPushed(push);
        }
      }).catchError((Object e, StackTrace st) {
        reportError(e, st, 'setup account settings');
      }));
    }
    state = SetupState(phase: SetupPhase.review, result: result);
  }
}

enum SetupPhase { idle, detecting, review }

class SetupState {
  const SetupState({this.phase = SetupPhase.idle, this.result});

  final SetupPhase phase;
  final SetupResult? result;

  SetupState copyWith({SetupPhase? phase, SetupResult? result}) =>
      SetupState(phase: phase ?? this.phase, result: result ?? this.result);
}

final setupControllerProvider =
    NotifierProvider<SetupController, SetupState>(SetupController.new);
