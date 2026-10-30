// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

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
  Workmanager().executeTask(
      (task, inputData) => backgroundTaskResult(runBackgroundRefresh));
}

/// What the scheduler is told about one run: `true` = done, `false` = retry. The reason a run failed is recorded, not dropped.
@visibleForTesting
Future<bool> backgroundTaskResult(Future<void> Function() run) async {
  try {
    await run();
    return true;
  } catch (e, st) {
    reportError(e, st, 'background refresh');
    return false;
  }
}

/// Runs the same pipeline as the foreground app, in the background isolate.
///
/// Every dependency defaults to the real one; the parameters exist so a test can drive the whole path (store, system
/// channel, widgets, notifications, clock, database file) with fakes (G-15, H-04).
Future<void> runBackgroundRefresh({
  SettingsStore? store,
  WattByteSystem? system,
  WidgetPublisher? widgets,
  AppNotifier? notifier,
  DateTime Function()? clock,
  String? dbPath,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsStore =
      store ?? SettingsStore(await SharedPreferences.getInstance());
  final settings = settingsStore.load();
  final text =
      backgroundText(settingsStore.locale, binaryUnits: settings.binaryUnits);
  await withBackgroundDb(path: dbPath, (db) async {
    final service = RefreshService(
      collector: Collector(system: system ?? WattByteSystem(), db: db),
      db: db,
      widgets: widgets ?? WidgetPublisher(),
      notifier: notifier ?? AppNotifier(),
    );
    await service.run(
      settings: settings,
      store: settingsStore,
      l10n: text.l10n,
      units: text.units,
      now: (clock ?? DateTime.now)(),
    );
  });
}

/// Runs [body] on a connection that belongs to this isolate and closes it afterwards.
///
/// Never `WattByteDb.open()` here: that is the process-wide single instance the UI
/// isolate keeps using, and on Android closing it from the WorkManager engine closes
/// it for the UI too (G-01). [path] is for tests.
@visibleForTesting
Future<T> withBackgroundDb<T>(Future<T> Function(WattByteDb db) body,
    {String? path}) async {
  final db = await WattByteDb.openPrivate(path: path);
  try {
    return await body(db);
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
