import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import 'analytics/dashboard_model.dart';
import 'background/app_notifier.dart';
import 'background/background_tasks.dart';
import 'background/refresh_service.dart';
import 'background/widget_publisher.dart';
import 'calc/energy.dart';
import 'collection/collector.dart';
import 'collection/session_builder.dart';
import 'core/units.dart';
import 'cloud_providers.dart';
import 'core/error_log.dart';
import 'domain/battery_capacity.dart';
import 'domain/models.dart';
import 'features/auth/domain/auth_models.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'settings/settings.dart';
import 'storage/database.dart';
import 'sync/sync_ownership.dart';

// ----------------------------------------------------------------- services

/// Overridden in `main()` with the loaded instance.
final prefsProvider =
    Provider<SharedPreferences>((_) => throw UnimplementedError());

/// Overridden in `main()` with the opened database.
final dbProvider = Provider<WattByteDb>((_) => throw UnimplementedError());

final systemProvider = Provider<WattByteSystem>((_) => WattByteSystem());

final collectorProvider = Provider<Collector>((ref) =>
    Collector(system: ref.watch(systemProvider), db: ref.watch(dbProvider)));

final notifierProvider = Provider<AppNotifier>((_) => AppNotifier());

/// Pushes the home-screen widget values. A provider so tests can replace it.
final widgetPublisherProvider =
    Provider<WidgetPublisher>((_) => WidgetPublisher());

/// "Now" for screen periods, date labels, refresh and sync timestamps.
/// Tests override it with a controllable clock.
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final refreshServiceProvider = Provider<RefreshService>((ref) => RefreshService(
      collector: ref.watch(collectorProvider),
      db: ref.watch(dbProvider),
      widgets: ref.watch(widgetPublisherProvider),
      notifier: ref.watch(notifierProvider),
      sync: ref.watch(syncServiceProvider),
    ));

final settingsStoreProvider =
    Provider<SettingsStore>((ref) => SettingsStore(ref.watch(prefsProvider)));

// ----------------------------------------------------------------- settings

class SettingsNotifier extends Notifier<Settings> {
  var _bindGeneration = 0;
  var _disposed = false;

  @override
  Settings build() {
    ref.onDispose(() => _disposed = true);
    // `Settings.cloudSync` is a view of the signed-in account's sync switch (a
    // per-account record in the sync ledger, the real consent): it follows the
    // account, so a second user of the phone sees it OFF. Until an account is known
    // the last stored view stands.
    ref.listen(syncAccountProvider, (_, next) {
      if (next.accountKey != null && state.cloudSync != next.enabled) {
        state = state.copyWith(cloudSync: next.enabled);
      }
    });
    // The account-bound settings (region, currency, price decision and where
    // they came from, the setup flag) belong to ONE account: they are swapped
    // when another account signs in. Until that is done `settingsScopeProvider`
    // does not name the signed-in user and the start gate keeps the splash.
    ref.listen(authControllerProvider, (_, next) {
      unawaited(_bind(next.valueOrNull));
    });
    unawaited(Future.microtask(
        () => _bind(ref.read(authControllerProvider).valueOrNull)));
    return _load();
  }

  Settings _load() {
    final stored = ref.read(settingsStoreProvider).load();
    final account = ref.read(syncAccountProvider);
    return account.accountKey == null
        ? stored
        : stored.copyWith(cloudSync: account.enabled);
  }

  /// Loads the settings of the signed-in account.
  ///
  /// The preferences hold the settings of ONE account at a time
  /// (`SettingsStore.accountOwner`). When another account signs in, the live ones
  /// are put away under their owner's one-way key and the new account's own come
  /// back (or nothing, for an account that was never here): nothing the previous
  /// user chose, a manual currency or tariff included, can reach the next user.
  /// The first account on a phone adopts what is there (the old onboarding's
  /// answers).
  Future<void> _bind(AuthState? auth) async {
    if (_disposed) return;
    final scope = ref.read(settingsScopeProvider.notifier);
    if (auth is! SignedIn) {
      scope.state = null;
      return;
    }
    if (!ref.read(apiConfigProvider).isConfigured) return;
    final userId = auth.user.id;
    if (scope.state == userId) return;
    final generation = ++_bindGeneration;
    try {
      final key = await SyncOwnership(ref.read(dbProvider)).accountKey(userId);
      if (_disposed || generation != _bindGeneration) return;
      final store = ref.read(settingsStoreProvider);
      final owner = store.accountOwner;
      if (owner == null) {
        await store.adoptAccount(key);
      } else if (owner != key) {
        await store.switchAccount(key);
        state = _load();
      }
    } catch (e, st) {
      if (_disposed) return;
      // An unreadable local database: the settings stay as they are and the
      // account is not blocked from using the app.
      reportError(e, st, 'bind account settings');
    }
    if (!_disposed && generation == _bindGeneration) scope.state = userId;
  }

  Future<void> update(Settings Function(Settings) change) async {
    state = change(state);
    await ref.read(settingsStoreProvider).save(state);
  }

  /// The account behind [accountKey] is gone: its settings are erased from this
  /// phone, the live ones included when they are its own.
  Future<void> forgetAccount(String accountKey) async {
    await ref.read(settingsStoreProvider).forgetAccount(accountKey);
    state = _load();
  }
}

/// The user whose account-bound settings are loaded into [settingsProvider]
/// (memory only; null while nobody is signed in or the swap is still running).
final settingsScopeProvider = StateProvider<String?>((_) => null);

/// False between a sign-in and the moment the settings of that account are
/// loaded: nothing may be shown or detected from settings that belong to the
/// previous user. Always true without an account (local-only development, tests
/// without a backend).
final settingsBoundProvider = Provider<bool>((ref) {
  if (!ref.watch(apiConfigProvider).isConfigured) return true;
  final auth = ref.watch(authControllerProvider).valueOrNull;
  if (auth is! SignedIn) return true;
  return ref.watch(settingsScopeProvider) == auth.user.id;
});

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// --------------------------------------------------------------------- data

/// Bumped after every refresh so the data providers below reload.
final refreshTickProvider = StateProvider<int>((_) => 0);

final capabilitiesProvider = FutureProvider<SystemCapabilities>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(systemProvider).capabilities();
});

final daysProvider = FutureProvider<List<DailyData>>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(dbProvider).allDaily();
});

final sessionsProvider = FutureProvider<List<ChargingSession>>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(dbProvider).allSessions();
});

final samplesProvider = FutureProvider<List<BatterySample>>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(dbProvider).samples();
});

/// The collector's estimate of this battery's full-charge capacity (an
/// estimate, never the design capacity).
final fullChargeCapacityProvider =
    FutureProvider<EstimatedFullChargeCapacity>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(collectorProvider).fullChargeCapacity();
});

final energyCalcProvider = Provider<EnergyCalc>((ref) {
  final s = ref.watch(settingsProvider);
  final fullCharge = ref.watch(fullChargeCapacityProvider).value;
  return s.energyCalc(
      estimatedFullChargeCapacityMah:
          fullCharge != null && fullCharge.isAvailable
              ? fullCharge.mah ?? 0
              : 0);
});

/// Everything the screens need, loaded together.
class AppData {
  const AppData({
    required this.days,
    required this.sessions,
    required this.open,
    required this.chargingNow,
  });

  final List<DailyData> days;
  final List<ChargingSession> sessions;
  final List<BatterySample> open;
  final bool chargingNow;
}

final appDataProvider = FutureProvider<AppData>((ref) async {
  final days = await ref.watch(daysProvider.future);
  final sessions = await ref.watch(sessionsProvider.future);
  final samples = await ref.watch(samplesProvider.future);
  // Stored samples are only the trailing run; a wide gap keeps it in one piece.
  final open =
      const SessionBuilder(maxGap: Duration(hours: 8)).build(samples).open;
  return AppData(
    days: days,
    sessions: sessions,
    open: open,
    chargingNow: samples.isNotEmpty && samples.last.plugged,
  );
});

final dashboardProvider = Provider<AsyncValue<DashboardModel>>((ref) {
  final calc = ref.watch(energyCalcProvider);
  final now = ref.watch(clockProvider)();
  return ref.watch(appDataProvider).whenData((d) => DashboardModel.build(
        days: d.days,
        sessions: d.sessions,
        open: d.open,
        chargingNow: d.chargingNow,
        calc: calc,
        now: now,
      ));
});

/// Units bound to the current settings; the locale comes from the UI.
final unitsProvider = Provider.family<Units, String>((ref, locale) =>
    Units(locale: locale, binary: ref.watch(settingsProvider).binaryUnits));

// ------------------------------------------------------------------ refresh

class RefreshController {
  RefreshController(this._ref);

  final Ref _ref;
  bool _busy = false;

  Future<void> refresh({required String locale}) async {
    if (_busy) return;
    _busy = true;
    try {
      final settings = _ref.read(settingsProvider);
      await _ref.read(refreshServiceProvider).run(
            settings: settings,
            store: _ref.read(settingsStoreProvider),
            l10n: localizationsFor(locale),
            units: Units(locale: locale, binary: settings.binaryUnits),
            now: _ref.read(clockProvider)(),
          );
    } on PlatformException catch (e, st) {
      // The native side failed (permission revoked mid-read, service gone). Not fatal.
      reportError(e, st, 'native refresh');
    } finally {
      _busy = false;
      _ref.read(refreshTickProvider.notifier).state++;
    }
  }
}

final refreshControllerProvider =
    Provider<RefreshController>((ref) => RefreshController(ref));
