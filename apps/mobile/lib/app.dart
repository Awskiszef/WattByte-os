import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'config/config_providers.dart';
import 'config/local_only_banner.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers.dart';
import 'settings/settings.dart';
import 'setup/setup_controller.dart';
import 'ui/onboarding/settings_load_failed_screen.dart';
import 'ui/onboarding/update_required_screen.dart';
import 'ui/onboarding/setup_screen.dart';
import 'ui/onboarding/welcome_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/wb_widgets.dart';

class WattByteApp extends ConsumerWidget {
  /// [home] replaces the start gate; it exists for tests that want to mount one
  /// screen inside the real MaterialApp (theme, l10n, text scale). The shipped
  /// app never passes it.
  const WattByteApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // The development banner exists only in a debug build that was started
    // with LOCAL_ONLY_DEV=true; `kBuildMode` is a constant, so profile and
    // release builds do not even contain the code.
    final showLocalOnlyBanner = kBuildMode == BuildMode.debug &&
        ref.watch(appConfigProvider).isLocalOnlyDev;
    // The system text scale is honoured in full, up to the largest iOS
    // accessibility size (~3.1x) and Android's 2.0x: there is deliberately NO
    // upper bound here (the layouts adapt instead, see test/accessibility/*;
    // the old 1.35x cap hid overflowing rows and is gone). The only bound is
    // the lower one: text never renders smaller than the design size, whatever
    // "Small" the system offers. Flutter's own fixed-height bars keep their
    // documented caps: NavigationBar labels 1.3x, AppBar title 1.34x.
    return MaterialApp(
      title: 'WattByte',
      debugShowCheckedModeBanner: false,
      theme: wbTheme(Brightness.light),
      darkTheme: wbTheme(Brightness.dark),
      themeMode: switch (settings.theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
      },
      builder: (context, child) {
        final scaled = MediaQuery.withClampedTextScaling(
          minScaleFactor: 1,
          child: child ?? const SizedBox.shrink(),
        );
        return showLocalOnlyBanner ? LocalOnlyDevBanner(child: scaled) : scaled;
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home ?? const StartGate(),
    );
  }
}

/// Launch -> splash (session restore) -> welcome | setup | dashboard.
/// The rule itself is `startDestination` (pure, unit-tested). The account is
/// skipped only in the explicit, debug-only `LOCAL_ONLY_DEV` mode.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The server no longer serves this version: say so before anything else (F-11).
    if (ref.watch(updateRequiredProvider) &&
        !ref.watch(updateNoticeDismissedProvider)) {
      return const UpdateRequiredScreen();
    }
    final destination = startDestination(
      localOnlyDev: ref.watch(appConfigProvider).isLocalOnlyDev,
      auth: ref.watch(authControllerProvider),
      settings: ref.watch(settingsProvider),
      settingsBound: ref.watch(settingsBoundProvider),
      settingsBindFailed: ref.watch(settingsBindFailedProvider),
    );
    return switch (destination) {
      StartDestination.splash => const SplashScreen(),
      StartDestination.welcome => const WelcomeScreen(),
      StartDestination.setup => const SetupScreen(),
      StartDestination.dashboard => const ShellScreen(),
      StartDestination.settingsError => const SettingsLoadFailedScreen(),
    };
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: WattByteMark(size: 96)),
      );
}

/// Shorthands used across the UI layer.
extension WbContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Locale tag for number formatting (e.g. `pl_PL`).
  String get localeTag {
    final l = Localizations.localeOf(this);
    return l.countryCode == null
        ? l.languageCode
        : '${l.languageCode}_${l.countryCode}';
  }
}
