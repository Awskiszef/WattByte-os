// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The code that runs while the app is closed, driven end to end with fakes for the platform edge (audit G-15, H-04): the real
// RefreshService, Collector, SQLite file, settings store and notification rules, the system channel, widgets and notifier
// replaced. Before this, nothing called runBackgroundRefresh.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/background/background_tasks.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/core/error_log.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/storage/database.dart';

import 'support/app_harness.dart';

/// Records the order in which the pipeline touches its edges.
class _RecordingStore extends SettingsStore {
  _RecordingStore(super.p, this.log);
  final List<String> log;

  @override
  Future<void> reload() {
    log.add('reload');
    return super.reload();
  }
}

class _OrderedNotifier extends FakeAppNotifier {
  _OrderedNotifier(this.log);
  final List<String> log;
  @override
  Future<void> showAll(
    List<PendingNotification> pending, {
    required SettingsStore store,
    required l10n,
    required units,
    required String currency,
  }) {
    log.add('notify:${pending.length}');
    return super.showAll(pending,
        store: store, l10n: l10n, units: units, currency: currency);
  }
}

Map<String, Object?> row(String day, {int mobile = 0, int wifi = 0}) => {
      'day': day,
      'mobileRx': mobile,
      'mobileTx': 0,
      'wifiRx': wifi,
      'wifiTx': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late String path;
  late FakeSystem system;
  late FakeWidgetPublisher widgets;
  late FakeAppNotifier notifier;
  late SharedPreferences prefs;
  var now = DateTime(2026, 10, 20, 12);

  setUp(() async {
    databaseFactory = databaseFactoryFfiNoIsolate;
    dir = await Directory.systemTemp.createTemp('wb_g15_');
    path = '${dir.path}/wattbyte.db';
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 10, 20, 12);
    system = FakeSystem(platform: HarnessPlatform.android, clock: () => now);
    widgets = FakeWidgetPublisher();
    notifier = FakeAppNotifier();
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> run({SettingsStore? store}) => runBackgroundRefresh(
        store: store ?? SettingsStore(prefs),
        system: system.system,
        widgets: widgets,
        notifier: notifier,
        clock: () => now,
        dbPath: path,
      );

  Future<T> inDb<T>(Future<T> Function(WattByteDb db) body) =>
      withBackgroundDb(path: path, body);

  test(
      'stores the days the system reports, publishes the widgets and queues the days for sync',
      () async {
    // A day is queued only with a valid currency (the contract): settings as they are after the setup.
    await SettingsStore(prefs).save(const Settings(currency: 'PLN'));
    system.dailyRows = [
      row('2026-10-19', mobile: 3000000, wifi: 5000000),
      row('2026-10-20', mobile: 1000000),
    ];
    await run();
    final days = await inDb((db) => db.allDaily());
    expect([
      for (final d in days) (d.day, d.mobile, d.wifi)
    ], [
      (DateTime(2026, 10, 19), 3000000, 5000000),
      (DateTime(2026, 10, 20), 1000000, 0),
    ]);
    expect(widgets.publishCount, 1);
    expect(widgets.lastModel, isNotNull);
    final queued = await inDb((db) => db.syncItems());
    expect(queued.map((q) => q.payload.date),
        containsAll(['2026-10-19', '2026-10-20']));
    expect(queued.every((q) => q.payload.currency == 'PLN'), isTrue);
  });

  test(
      'asks the system for the window it needs: the first run looks back androidHistoryDays, later runs only re-read the last two stored days',
      () async {
    system.dailyRows = [
      row('2026-10-20', mobile: 1000),
      row('2026-10-19', mobile: 2000),
      row('2026-10-18', mobile: 3000),
      row('2026-07-10', // 102 days back: outside the 90-day floor
          mobile: 999),
    ];
    await run();
    expect(
        (await inDb((db) => db.allDaily())).map((d) => d.day),
        [
          DateTime(2026, 10, 18),
          DateTime(2026, 10, 19),
          DateTime(2026, 10, 20),
        ],
        reason: 'the 102-day-old row is never requested');
    expect(Collector.androidHistoryDays, 90);

    // The system "restates" an old day and today; only the window [latest - 1 day, tomorrow) is read again.
    system.dailyRows = [
      row('2026-10-18',
          mobile: 7777), // two days before the latest stored day: not re-read
      row('2026-10-19', mobile: 2500),
      row('2026-10-20', mobile: 1500),
    ];
    await run();
    final byDay = {
      for (final d in await inDb((db) => db.allDaily())) d.day.day: d.mobile
    };
    expect(byDay, {18: 3000, 19: 2500, 20: 1500});
  });

  test('does nothing when data collection is switched off', () async {
    await SettingsStore(prefs).save(const Settings(dataCollection: false));
    system.dailyRows = [row('2026-10-20', mobile: 1000)];
    await run();
    expect(await inDb((db) => db.allDaily()), isEmpty);
    expect(widgets.publishCount, 0);
    expect(notifier.shown, isEmpty);
  });

  test(
      'reloads the preferences before it collects, so a notification already sent by the UI isolate is not sent again',
      () async {
    final log = <String>[];
    final store = _RecordingStore(prefs, log);
    final recording = _OrderedNotifier(log);
    notifier = recording;
    await SettingsStore(prefs).save(const Settings(
        notifyMobileThreshold: true, mobileThresholdBytes: 1000000));
    system.dailyRows = [row('2026-10-20', mobile: 5000000)];
    await run(store: store);
    expect(log, ['reload', 'notify:1'], reason: 'reload first, then the rules');
    expect(recording.shown.single.kind, NotificationKind.mobileThreshold);
    expect(recording.shown.single.key, 'mobile:2026-10-20');

    // The same day again, with the key now in the shared store: nothing more is shown.
    log.clear();
    recording.shown.clear();
    await run(store: _RecordingStore(prefs, log));
    expect(recording.shown, isEmpty);
    expect(prefs.getStringList('wb.sentNotifications'),
        contains('mobile:2026-10-20'));
  });

  test(
      'a failure reaches the scheduler as "retry" and is recorded, and the database is closed',
      () async {
    system.dailyRows = [row('2026-10-20', mobile: 1000)];
    // A failing network-statistics query is recorded and survived (the battery step still runs); a failing battery read is not.
    system.failing.add('batterySnapshot');
    final before = recentErrors.length;
    final ok = await backgroundTaskResult(() => run());
    expect(ok, isFalse);
    expect(recentErrors.length, before + 1);
    expect(recentErrors.last, contains('background refresh'));
    // A second run on the same file works: the first one released it.
    system.failing.remove('batterySnapshot');
    expect(await backgroundTaskResult(() => run()), isTrue);
    expect(await inDb((db) => db.allDaily()), isNotEmpty);
  });

  test('a successful run reports "done"', () async {
    expect(await backgroundTaskResult(() => run()), isTrue);
  });
}
