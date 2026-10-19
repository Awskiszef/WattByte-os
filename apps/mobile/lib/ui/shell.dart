import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../background/foreground_refresh.dart';
import '../cloud_providers.dart';
import '../core/error_log.dart';
import '../features/auth/domain/auth_models.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../providers.dart';
import 'dashboard/dashboard_screen.dart';
import 'history/history_screen.dart';
import 'insights/insights_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/setup_editors.dart';

/// Bottom navigation host. Also owns the foreground refresh loop.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with WidgetsBindingObserver {
  int _index = 0;

  /// Keeps "Today" and an in-progress charge live while the app is open: 60 s
  /// ticks while resumed, paused in the background, stopped on sign-out and here.
  late final ForegroundRefresh _loop = ForegroundRefresh(onTick: _refresh);
  ProviderSubscription<AsyncValue<AuthState>>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncNative();
      _refresh();
      // Household price: cache first, API only when stale; never blocks the dashboard.
      refreshAutomaticPrice(context);
      // A model the catalog knows must not stay "unavailable" after an upgrade.
      resolveMissingDesignCapacity(context);
      // Another device may have changed the account's settings, and a change made
      // here while offline has not reached it yet.
      _reconcileAccountSettings();
    });
    _loop.start();
    // The loop belongs to the signed-in account: it stops on sign-out and restarts
    // for the next account (a build without an API has no accounts to follow).
    _authSub = ref.listenManual(authControllerProvider, (_, next) {
      if (!ref.read(apiConfigProvider).isConfigured) return;
      final auth = next.valueOrNull;
      if (auth is SignedIn) {
        _loop.onAccountChanged(auth.user.id);
      } else if (auth is SignedOut) {
        _loop.onAccountChanged(null);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.close();
    _loop.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _loop.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _reconcileAccountSettings();
  }

  /// Best effort and silent: offline it changes nothing, the value and the
  /// source this phone has keep working.
  void _reconcileAccountSettings() {
    if (!mounted) return;
    unawaited(ref.read(accountSettingsControllerProvider)?.reconcile());
  }

  Future<void> _refresh() =>
      ref.read(refreshControllerProvider).refresh(locale: context.localeTag);

  /// Android: schedule the charging worker and hand it localized alert text.
  Future<void> _syncNative() async {
    final system = ref.read(systemProvider);
    final settings = ref.read(settingsProvider);
    final l = context.l10n;
    try {
      if (!settings.dataCollection) {
        // The privacy switch must really stop sampling, not only hide the results.
        await system.cancelChargingWorker();
        return;
      }
      await system.ensureChargingWorker();
      await system.setChargingNotification(
        enabled: settings.notifyChargingDone,
        title: l.notifChargingTitle,
        body: l.notifChargingBody,
        channelName: l.notifChannelName,
        channelDescription: l.notifChannelDescription,
      );
    } on MissingPluginException catch (e, st) {
      // The platform side does not implement the call (tests, an unsupported
      // platform). The iOS plugin answers these calls with no-ops, so this is not
      // the normal iOS path; record it rather than hide it.
      reportError(e, st, 'native sync');
    } on PlatformException catch (e, st) {
      reportError(e, st, 'native sync');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (prev, next) {
      if (prev?.notifyChargingDone != next.notifyChargingDone ||
          prev?.dataCollection != next.dataCollection) {
        _syncNative();
      }
    });
    final l = context.l10n;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          DashboardScreen(),
          HistoryScreen(),
          InsightsScreen(),
          SettingsScreen(),
        ],
      ),
      // Text size policy of the bar (test/accessibility/shell_accessibility_test.dart):
      // Material's NavigationBar draws its labels at the system text size up to
      // 1.3x and no further, so the bar keeps its height and the four labels
      // stay side by side ("Ustawienia" at 3x would be 190 px wide). All four
      // labels stay visible; the full size is still there for a screen reader
      // (label + "Tab n of 4" + selected state) and for the long-press tooltip.
      // Every destination is at least 48 px high. No other clamp is applied.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.bolt_outlined),
              selectedIcon: const Icon(Icons.bolt_rounded),
              label: l.tabDashboard),
          NavigationDestination(
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history_rounded),
              label: l.tabHistory),
          NavigationDestination(
              icon: const Icon(Icons.auto_awesome_outlined),
              selectedIcon: const Icon(Icons.auto_awesome_rounded),
              label: l.tabInsights),
          NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune_rounded),
              label: l.tabSettings),
        ],
      ),
    );
  }
}
