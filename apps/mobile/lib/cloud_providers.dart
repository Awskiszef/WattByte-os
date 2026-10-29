import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_failure.dart';
import 'core/error_log.dart';
import 'domain/battery_capacity.dart';
import 'features/ai/ai_service.dart';
import 'features/auth/domain/auth_models.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'generated/api/api.dart' as api;
import 'providers.dart';
import 'setup/account_settings.dart';
import 'setup/device_specification.dart';
import 'setup/electricity_price.dart';
import 'setup/region_detection.dart';
import 'setup/setup_controller.dart';
import 'sync/sync_models.dart';
import 'sync/sync_ownership.dart';
import 'sync/sync_queue.dart';
import 'sync/sync_service.dart';

/// Cloud features exist only when the build knows an API address (`API_BASE_URL`).
final syncServiceProvider = Provider<SyncService?>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return null;
  return SyncService(
    db: ref.watch(dbProvider),
    apis: ref.watch(apiFactoryProvider),
    sessions: ref.watch(sessionManagerProvider),
    platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    clock: ref.watch(clockProvider),
  );
});

final electricityPriceServiceProvider =
    Provider<ElectricityPriceService?>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return null;
  return ElectricityPriceService(
    apis: ref.watch(apiFactoryProvider),
    sessions: ref.watch(sessionManagerProvider),
  );
});

final accountSettingsSyncProvider = Provider<AccountSettingsSync?>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return null;
  return AccountSettingsSync(
    apis: ref.watch(apiFactoryProvider),
    sessions: ref.watch(sessionManagerProvider),
  );
});

/// Keeps this phone's account-bound settings and the account's in step
/// (`docs/SETTING_SOURCES.md`). Calls are serialised, so a reconcile never races
/// the upload that follows an edit.
class AccountSettingsController {
  AccountSettingsController(this._ref);

  final Ref _ref;
  Future<void> _tail = Future.value();

  Future<void> _serial(Future<void> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// After a local edit: uploads what this phone decided and the account does
  /// not hold yet. Best effort; what fails stays unacknowledged and goes up with
  /// the next [reconcile].
  Future<void> push() => _serial(() => _push(null));

  /// Reads the account, applies the priorities (an unacknowledged local choice,
  /// then the account's value) and uploads what is still only here. Offline, or
  /// before the account's settings are loaded, it changes nothing at all.
  Future<void> reconcile() => _serial(() async {
        final sync = _ref.read(accountSettingsSyncProvider);
        if (sync == null || !_ref.read(settingsBoundProvider)) return;
        if (_ref.read(settingsScopeProvider) == null) return;
        final account = await sync.pull();
        if (account == null) return;
        await _ref
            .read(settingsProvider.notifier)
            .update((s) => mergeAccountSettings(s, account));
        await _push(account);
      });

  Future<void> _push(api.UserSettingsDto? current) async {
    final sync = _ref.read(accountSettingsSyncProvider);
    if (sync == null || _ref.read(settingsScopeProvider) == null) return;
    final result =
        await sync.push(_ref.read(settingsProvider), current: current);
    if (result == null || result.groups.isEmpty) return;
    await _ref
        .read(settingsProvider.notifier)
        .update((s) => s.markInSyncFrom(result.pushed, result.groups));
  }
}

final accountSettingsControllerProvider =
    Provider<AccountSettingsController?>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return null;
  return AccountSettingsController(ref);
});

String _localeTag() {
  final l = PlatformDispatcher.instance.locale;
  return l.countryCode == null
      ? l.languageCode
      : '${l.languageCode}_${l.countryCode}';
}

final regionDetectionProvider = Provider<RegionDetectionService>((ref) {
  final configured = ref.watch(apiConfigProvider).isConfigured;
  final apis = ref.watch(apiFactoryProvider);
  return RegionDetectionService(
    system: ref.watch(systemProvider),
    localeTag: _localeTag,
    backendCountry: !configured
        ? null
        : () async {
            final r = await guarded(
                () => api.RegionApi(apis.anonymous()).apiV1RegionGet());
            return r?.countryCode;
          },
  );
});

final deviceSpecificationProvider = Provider<DeviceSpecificationService>((ref) {
  final configured = ref.watch(apiConfigProvider).isConfigured;
  final apis = ref.watch(apiFactoryProvider);
  final store = ref.watch(settingsStoreProvider);
  return DeviceSpecificationService(
    system: ref.watch(systemProvider),
    loadCatalog: () =>
        rootBundle.loadString('assets/device_specs/devices.json'),
    readCache: () => store.deviceSpecCache,
    writeCache: store.setDeviceSpecCache,
    backendLookup: !configured
        ? null
        : (id) async {
            try {
              final d = await guarded(() => api.DevicesApi(apis.anonymous())
                  .apiV1DevicesSpecificationsIdentifierGet(id));
              if (d == null) return null;
              return DeviceSpecification(
                manufacturer: d.manufacturer,
                model: d.model,
                modelIdentifier: d.modelIdentifier,
                nominalVoltage: d.nominalVoltage?.toDouble(),
                design: DesignCapacity(
                  mah: d.designCapacityMah.toDouble(),
                  wh: d.designCapacityWh?.toDouble(),
                  source: DesignCapacitySource.backendDeviceDatabase,
                ),
              );
            } on ApiFailure catch (f) {
              if (f.kind == ApiFailureKind.notFound) return null;
              rethrow;
            }
          },
  );
});

/// Everything the first-run setup and the "detect again" actions need.
final autoSetupProvider = Provider<AutoSetup>((ref) {
  final sync = ref.watch(syncServiceProvider);
  final collector = ref.watch(collectorProvider);
  return AutoSetup(
    region: ref.watch(regionDetectionProvider),
    device: ref.watch(deviceSpecificationProvider),
    price: ref.watch(electricityPriceServiceProvider),
    account: ref.watch(accountSettingsSyncProvider),
    registerDevice: sync == null
        ? null
        : (spec, fullCharge) =>
            sync.registerDevice(spec, fullCharge: fullCharge),
    fullCharge: collector.fullChargeCapacity,
  );
});

final aiServiceProvider = Provider<AiService?>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return null;
  return AiService(
    apis: ref.watch(apiFactoryProvider),
    sessions: ref.watch(sessionManagerProvider),
  );
});

/// What the Account screen shows about the signed-in account's sync. All zeros
/// when signed out, when the build has no API, or for an account that never enabled
/// sync on this phone.
class SyncSummary {
  const SyncSummary({
    this.pending = 0,
    this.synced = 0,
    this.failed = 0,
    this.lastSync,
    this.enabled = false,
    this.scope,
    this.halted = false,
    this.nextRetryAt,
  });

  final int pending;
  final int synced;
  final int failed;
  final DateTime? lastSync;
  final bool enabled;
  final SyncScope? scope;

  /// Repeated server errors stopped the automatic retries; "retry" continues.
  final bool halted;
  final DateTime? nextRetryAt;
}

final syncSummaryProvider =
    FutureProvider.autoDispose<SyncSummary>((ref) async {
  ref.watch(refreshTickProvider);
  ref.watch(syncAccountProvider); // the account or its switch changed
  final snap = await ref.watch(syncServiceProvider)?.snapshot();
  if (snap == null) return const SyncSummary();
  return SyncSummary(
    pending: snap.pending,
    synced: snap.synced,
    failed: snap.failed,
    lastSync: snap.lastSync,
    enabled: snap.enabled,
    scope: snap.scope,
    halted: snap.halted,
    nextRetryAt: snap.nextRetryAt,
  );
});

/// Cloud sync of the signed-in account as the UI sees it.
class SyncAccountInfo {
  const SyncAccountInfo(
      {this.accountKey, this.enabled = false, this.scope, this.enabledOn});

  /// Signed out, no API in this build, or not loaded yet.
  static const none = SyncAccountInfo();

  /// One-way key of the signed-in account on this phone (never the user id).
  final String? accountKey;

  /// Sync is switched on for this account on this phone. False for every account
  /// that never enabled it here, including a second user of the same phone.
  final bool enabled;
  final SyncScope? scope;
  final String? enabledOn;
}

/// Follows the signed-in account and mirrors its sync switch from the ledger
/// (`SyncOwnership`). `settingsProvider` feeds `Settings.cloudSync` from it.
class SyncAccountNotifier extends Notifier<SyncAccountInfo> {
  var _generation = 0;
  var _disposed = false;
  var _legacyChecked = false;

  @override
  SyncAccountInfo build() {
    ref.onDispose(() => _disposed = true);
    ref.listen(authControllerProvider, (prev, next) {
      if (_userId(prev) != _userId(next)) unawaited(refresh());
    });
    // After build() has returned: `state` may not be written while it runs.
    unawaited(Future.microtask(refresh));
    return SyncAccountInfo.none;
  }

  static String? _userId(AsyncValue<AuthState>? v) {
    final s = v?.valueOrNull;
    return s is SignedIn ? s.user.id : null;
  }

  /// Re-reads the signed-in account's state from the ledger.
  Future<void> refresh() async {
    final g = ++_generation;
    var info = SyncAccountInfo.none;
    try {
      await _adoptLegacyPreference();
      final service = ref.read(syncServiceProvider);
      final st = await service?.accountState();
      if (st != null) {
        info = SyncAccountInfo(
            accountKey: st.key,
            enabled: st.enabled,
            scope: st.scope,
            enabledOn: st.enabledOn);
      }
    } catch (e, st) {
      // Unreadable ledger: show sync as off (the service itself refuses to upload).
      reportError(e, st, 'sync account state');
    }
    if (_disposed || g != _generation) return;
    state = info;
  }

  /// One-time: the pre-v5 global `wb.cloudSync` switch moves to the account that
  /// owned the legacy queue (see `SyncOwnership.adoptLegacyPreference`; the marker
  /// in the database makes it happen once).
  Future<void> _adoptLegacyPreference() async {
    if (_legacyChecked || !ref.read(apiConfigProvider).isConfigured) return;
    await SyncOwnership(ref.read(dbProvider)).adoptLegacyPreference(
        legacyEnabled: ref.read(settingsStoreProvider).legacyCloudSync ?? false,
        now: ref.read(clockProvider)());
    _legacyChecked = true;
  }
}

final syncAccountProvider =
    NotifierProvider<SyncAccountNotifier, SyncAccountInfo>(
        SyncAccountNotifier.new);

/// What must happen on this phone when the server has deleted [user]'s account.
/// Installed as the default so that deleting an account can never skip it; tests
/// override it to observe or fail it.
typedef AccountDeletedHook = Future<void> Function(User user);

final accountDeletedHookProvider = Provider<AccountDeletedHook>((ref) {
  return (user) async {
    // The settings the deleted account left on this phone go first: its manual
    // currency or tariff must not become the next user's.
    try {
      final key = await SyncOwnership(ref.read(dbProvider)).accountKey(user.id);
      await ref.read(settingsProvider.notifier).forgetAccount(key);
    } catch (e, st) {
      reportError(e, st, 'account deletion settings cleanup');
    }
    final service = ref.read(syncServiceProvider);
    if (service != null) {
      await service.forgetAccount(user.id);
    } else {
      await SyncOwnership(ref.read(dbProvider)).forgetUser(user.id);
    }
  };
});

/// The N of "Upload this phone's N days of history to <account>?": local days older
/// than the day sync was enabled (before enabling: older than today) that have no
/// receipt for the signed-in account. 0 when signed out. The UI asks only when N > 0.
final historyBacklogProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(refreshTickProvider);
  ref.watch(syncAccountProvider);
  return ref.read(cloudSyncProvider).historyBacklog();
});

/// User-driven cloud sync actions.
class CloudSync {
  CloudSync(this._ref);

  final Ref _ref;

  /// Turns sync ON for the signed-in account with an explicit [scope], makes sure
  /// the queue holds the days that scope allows, and uploads.
  ///
  /// * [SyncScope.fromNow]: only days from today on.
  /// * [SyncScope.history]: every local day of this phone. Offer it only after the
  ///   user agreed to "Upload this phone's N days of history to <account>?"
  ///   ([historyBacklog] gives N).
  Future<SyncOutcome?> enableWith(SyncScope scope) async {
    final service = _ref.read(syncServiceProvider);
    if (service == null) return null;
    await _fillQueue(scope);
    await service.enable(scope);
    await _ref.read(syncAccountProvider.notifier).refresh();
    return syncNow();
  }

  /// COMPATIBILITY SHIM (kept so existing screens compile): enables with
  /// [SyncScope.fromNow], which never uploads history. New UI calls [enableWith].
  Future<SyncOutcome?> enable() => enableWith(SyncScope.fromNow);

  /// Switches sync off for the signed-in account (its receipts are kept, so enabling
  /// again uploads only what changed). Does nothing when signed out.
  Future<void> disable() async {
    await _ref.read(syncServiceProvider)?.disable();
    await _ref.read(syncAccountProvider.notifier).refresh();
  }

  /// How many local days older than the day sync was enabled (or, before enabling,
  /// older than today) have no receipt for the signed-in account: the N of "Upload
  /// this phone's N days of history to <account>?". Ask only when N > 0.
  Future<int> historyBacklog() async {
    final service = _ref.read(syncServiceProvider);
    if (service == null) return 0;
    final data = await _ref.read(appDataProvider.future);
    return service.daysWithoutReceipt(SyncQueue.buildAll(
      days: data.days,
      sessions: data.sessions,
      calc: _ref.read(energyCalcProvider),
      currency: _ref.read(settingsProvider).currency,
      now: _ref.read(clockProvider)(),
    ));
  }

  /// Widens an enabled `fromNow` sync to the whole history of this phone.
  Future<SyncOutcome?> uploadHistory() => enableWith(SyncScope.history);

  Future<SyncOutcome?> syncNow({bool retryFailed = false}) async {
    final service = _ref.read(syncServiceProvider);
    if (service == null) return null;
    final outcome = await service.syncNow(retryFailed: retryFailed);
    _ref.read(refreshTickProvider.notifier).state++;
    return outcome;
  }

  Future<void> _fillQueue(SyncScope scope) async {
    final data = await _ref.read(appDataProvider.future);
    final queue = SyncQueue(_ref.read(dbProvider));
    final calc = _ref.read(energyCalcProvider);
    final currency = _ref.read(settingsProvider).currency;
    final now = _ref.read(clockProvider)();
    final owner = _ref.read(settingsStoreProvider).accountOwner ?? '';
    if (scope == SyncScope.history) {
      await queue.enqueueAll(
          days: data.days,
          sessions: data.sessions,
          calc: calc,
          currency: currency,
          now: now,
          settingsOwner: owner);
    } else {
      await queue.enqueueRecent(
          days: data.days,
          sessions: data.sessions,
          calc: calc,
          currency: currency,
          now: now,
          settingsOwner: owner);
    }
  }
}

final cloudSyncProvider = Provider<CloudSync>(CloudSync.new);
