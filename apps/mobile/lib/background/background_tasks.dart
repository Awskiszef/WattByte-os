import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte_system/wattbyte_system.dart';
import 'package:workmanager/workmanager.dart';

import '../collection/collector.dart';
import '../core/error_log.dart';
import '../core/units.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings/settings.dart';
import '../storage/database.dart';
import 'app_notifier.dart';
import 'refresh_service.dart';
import 'widget_publisher.dart';

/// Android: WorkManager periodic task. iOS: BGAppRefreshTask with the same id
/// (declared in Info.plist and registered in AppDelegate).
const kRefreshTask = 'pl.wattbyte.refresh';

@pragma('vm:entry-point')
void wattbyteBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundRefresh();
      return true;
    } catch (e, st) {
      // `false` asks the scheduler to retry; the reason is recorded, not dropped.
      reportError(e, st, 'background refresh');
      return false;
    }
  });
}

/// Runs the same pipeline as the foreground app, in the background isolate.
Future<void> runBackgroundRefresh() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final store = SettingsStore(prefs);
  final settings = store.load();
  final text = backgroundText(store.locale, binaryUnits: settings.binaryUnits);
  final db = await WattByteDb.open();
  try {
    final service = RefreshService(
      collector: Collector(system: WattByteSystem(), db: db),
      db: db,
      widgets: WidgetPublisher(),
      notifier: AppNotifier(),
    );
    await service.run(
      settings: settings,
      store: store,
      l10n: text.l10n,
      units: text.units,
      now: DateTime.now(),
    );
  } finally {
    await db.close();
  }
}

Future<void> registerBackgroundRefresh() async {
  await Workmanager().initialize(wattbyteBackgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    kRefreshTask,
    kRefreshTask,
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

/// Language and number formatting for widget and notification text.
///
/// [deviceLocaleTag] is what `SettingsStore.locale` recorded at app start (the
/// raw device tag: `en_PL`, `pl_PL`, `de_DE`, null before the first start). It
/// is reduced to the locale the UI resolved to, `pl` or `en`, so the lock
/// screen and the widgets read and format exactly like the screens: an English
/// phone with a Polish region gets English text with English separators in both
/// places, a German phone gets the English fallback in both places.
({AppLocalizations l10n, Units units}) backgroundText(
  String? deviceLocaleTag, {
  required bool binaryUnits,
}) {
  final locale = Units.resolveAppLocale(deviceLocaleTag);
  return (
    l10n: localizationsFor(locale),
    units: Units(locale: locale, binary: binaryUnits),
  );
}

/// Localizations without a BuildContext (background isolate, widgets, alerts).
///
/// [tag] may be any device locale tag (`pl_PL`, `en-PL`, `de_DE`); unsupported
/// languages get English, the same fallback Flutter's locale resolution uses.
AppLocalizations localizationsFor(String tag) =>
    lookupAppLocalizations(Locale(Units.resolveAppLocale(tag)));
