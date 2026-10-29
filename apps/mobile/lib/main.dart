import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'background/background_tasks.dart';
import 'config/app_config.dart';
import 'config/config_error_app.dart';
import 'config/startup.dart';
import 'config/startup_failure.dart';
import 'core/error_log.dart';
import 'providers.dart';
import 'settings/settings.dart';
import 'storage/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No crash-reporting SDK: errors go to a local, bounded log (see core/error_log.dart).
  FlutterError.onError = (d) => reportError(d.exception, d.stack, 'flutter');
  PlatformDispatcher.instance.onError = (e, st) {
    reportError(e, st, 'platform');
    return true;
  };
  // Debug builds only: the effective configuration and what is missing (no values).
  final config = AppConfig.fromEnvironment;
  logStartupConfiguration(config);
  // A build without a valid backend configuration (no API_BASE_URL outside the
  // debug-only LOCAL_ONLY_DEV mode, a broken address, LOCAL_ONLY_DEV in a
  // profile or release build) stops here, before any storage, session or
  // background work is touched. It never falls back to a local-only app.
  if (!config.isValid) {
    runApp(ConfigErrorApp(config: config));
    return;
  }
  // Portrait only, like the native projects; must be in place before the first frame.
  await lockOrientation();
  // Storage can fail to open (corrupt file, full disk, failed upgrade): a recovery screen, not a blank launch screen.
  await startGuarded(
    build: () async {
      final prefs = await SharedPreferences.getInstance();
      final db = await WattByteDb.open();
      await SettingsStore(prefs)
          .setLocale(_localeTag(PlatformDispatcher.instance.locale));
      try {
        await registerBackgroundRefresh();
      } catch (e, st) {
        // Background refresh is best-effort; the app works without it, but the failure is logged.
        reportError(e, st, 'background registration');
      }
      return ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          dbProvider.overrideWithValue(db),
        ],
        child: const WattByteApp(),
      );
    },
    resetLocalData: WattByteDb.moveBrokenFileAside,
  );
}

String _localeTag(Locale l) => l.countryCode == null
    ? l.languageCode
    : '${l.languageCode}_${l.countryCode}';
