import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/analytics/dashboard_model.dart';
import 'package:wattbyte/analytics/notification_rules.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/background/app_notifier.dart';
import 'package:wattbyte/background/widget_publisher.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/setup_controller.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/account_key.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import 'support/fake_backend.dart';
import 'support/fake_system.dart';
import 'sync_support.dart';

/// The same policy through the real providers: RefreshController -> RefreshService
/// (real collector on a fake native side) -> SyncQueue -> SyncService ->
/// refreshTickProvider, plus the account / settings / delete-account wiring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final report = <String>[];
  tearDownAll(() => debugPrint(
      '\nREQUEST COUNTS (real providers, 60 s ticks)\n${report.join('\n')}\n'));

  late ProviderRig rig;

  setUp(() async => rig = await ProviderRig.create());

  group('the refresh -> enqueue -> sync -> tick chain does not loop', () {
    test('an hour online, today changing every minute, with UI watchers',
        () async {
      await rig.enable(SyncScope.fromNow);
      final collectsBefore = rig.fake.callsTo('interfaceCounters').length;
      for (var m = 0; m < 60; m++) {
        await rig.tick();
        // What the screens do after every tick: watch the data and the summary.
        await rig.c.read(appDataProvider.future);
        await rig.c.read(syncSummaryProvider.future);
        rig.advance(const Duration(minutes: 1));
      }
      final collects =
          rig.fake.callsTo('interfaceCounters').length - collectsBefore;
      final uploads = rig.cloud.uploads.length;
      report.add(
          '| online | 60 ticks | $collects collections, $uploads uploads, '
          '${rig.net.attempts} HTTP requests, refreshTick=${rig.c.read(refreshTickProvider)} |');
      expect(collects, 60,
          reason: 'one collection per tick: nothing re-triggers a refresh');
      expect(uploads, lessThanOrEqualTo(12));
      expect(uploads, greaterThanOrEqualTo(10));
      expect(rig.net.attempts, lessThanOrEqualTo(13));
      final summary = await rig.c.read(syncSummaryProvider.future);
      expect(summary.enabled, isTrue);
      expect(summary.failed, 0);
    });

    test(
        'an hour offline: the attempts follow the backoff, collection continues',
        () async {
      await rig.enable(SyncScope.fromNow);
      rig.backend.offline = true;
      final collectsBefore = rig.fake.callsTo('interfaceCounters').length;
      final before = rig.net.attempts;
      for (var m = 0; m < 60; m++) {
        await rig.tick();
        await rig.c.read(syncSummaryProvider.future);
        rig.advance(const Duration(minutes: 1));
      }
      final attempts = rig.net.attempts - before;
      report.add(
          '| offline | 60 ticks | ${rig.fake.callsTo('interfaceCounters').length - collectsBefore} '
          'collections, $attempts HTTP attempts, 0 uploads |');
      expect(rig.fake.callsTo('interfaceCounters').length - collectsBefore, 60);
      expect(attempts, inInclusiveRange(5, 9));
      expect(rig.cloud.uploads, isEmpty);
      final summary = await rig.c.read(syncSummaryProvider.future);
      expect(summary.pending, greaterThan(0));
      expect(summary.nextRetryAt, isNotNull);
    });

    test('an account that never enabled sync: ticks never touch the network',
        () async {
      for (var m = 0; m < 30; m++) {
        await rig.tick();
        rig.advance(const Duration(minutes: 1));
      }
      expect(rig.net.attempts, 0);
      final s = await rig.c.read(syncSummaryProvider.future);
      expect(s.enabled, isFalse);
      expect(s.pending, 0);
    });

    test('signed out: ticks collect locally and never touch the network',
        () async {
      await rig.enable(SyncScope.fromNow);
      await rig.c.read(authControllerProvider.notifier).signOut();
      final before = rig.net.attempts;
      for (var m = 0; m < 10; m++) {
        await rig.tick();
        rig.advance(const Duration(minutes: 1));
      }
      expect(rig.net.attempts, before);
      expect((await rig.db.allDaily()), isNotEmpty);
    });
  });

  group('Settings.cloudSync follows the signed-in account', () {
    test('a second user of the phone sees sync OFF, the first one ON again',
        () async {
      await rig.enable(SyncScope.history);
      expect(rig.c.read(settingsProvider).cloudSync, isTrue);

      await rig.signInAs('user-b');
      expect(rig.c.read(settingsProvider).cloudSync, isFalse);
      expect((await rig.service.accountState())!.enabled, isFalse);

      await rig.signInAs('user-a');
      expect(rig.c.read(settingsProvider).cloudSync, isTrue);
    });

    test('the view alone never enables anything (it is not the consent)',
        () async {
      await rig.c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(cloudSync: true));
      await rig.db
          .replaceDaily([DailyData(day: DateTime(2026, 10, 13), mobileRx: 10)]);
      for (var m = 0; m < 5; m++) {
        await rig.tick();
        rig.advance(const Duration(minutes: 1));
      }
      expect(rig.net.attempts, 0,
          reason: 'only the per-account ledger can start an upload');
      expect(await rig.service.isEnabled(), isFalse);
    });

    test('disable switches the view off and keeps the receipts', () async {
      await rig.seedDays();
      await rig.c.read(cloudSyncProvider).enableWith(SyncScope.history);
      expect(rig.c.read(settingsProvider).cloudSync, isTrue);
      await rig.c.read(cloudSyncProvider).disable();
      expect(rig.c.read(settingsProvider).cloudSync, isFalse);
      expect(
          await rig.db
              .receiptCount(await rig.service.currentAccountKey() ?? ''),
          7);
    });
  });

  group('CloudSync actions', () {
    test('enableWith(history) queues every local day and uploads them',
        () async {
      await rig.seedDays();
      final o =
          await rig.c.read(cloudSyncProvider).enableWith(SyncScope.history);
      expect(o!.status, SyncStatus.synced);
      expect(rig.cloud.datesOf('user-a'), sevenDays());
      final s = await rig.c.read(syncSummaryProvider.future);
      expect([s.pending, s.synced, s.failed], [0, 7, 0]);
      expect(s.scope, SyncScope.history);
    });

    test(
        'enableWith(fromNow) uploads today only; the backlog is offered, not uploaded',
        () async {
      await rig.seedDays();
      final sync = rig.c.read(cloudSyncProvider);
      expect(await sync.historyBacklog(), 6,
          reason: 'asked BEFORE enabling: six days older than today');
      expect(await rig.c.read(historyBacklogProvider.future), 6,
          reason: 'the same number as a provider for the UI');
      final o = await sync.enableWith(SyncScope.fromNow);
      expect(o!.uploaded, 1);
      expect(rig.cloud.datesOf('user-a'), ['2026-10-13']);
      expect(await sync.historyBacklog(), 6);

      // The user agrees to the history.
      final up = await sync.uploadHistory();
      expect(up!.uploaded, 6);
      expect(rig.cloud.datesOf('user-a'), sevenDays());
      expect(await sync.historyBacklog(), 0);
    });

    test('the compatibility shim enable() never uploads history', () async {
      await rig.seedDays();
      final o = await rig.c.read(cloudSyncProvider).enable();
      expect(o!.uploaded, 1);
      expect(rig.cloud.datesOf('user-a'), ['2026-10-13']);
      expect((await rig.service.accountState())!.scope, SyncScope.fromNow);
    });

    test('a second account on the same phone gets its own choice', () async {
      await rig.seedDays();
      await rig.c.read(cloudSyncProvider).enableWith(SyncScope.history);
      await rig.signInAs('user-b');
      expect(await rig.c.read(cloudSyncProvider).historyBacklog(), 6,
          reason: 'A\'s receipts say nothing about B');
      final syncB = await rig.c.read(cloudSyncProvider).syncNow();
      expect(syncB!.skip, SyncSkip.notEnabled);
      expect(rig.cloud.datesOf('user-b'), isEmpty);
      await rig.c.read(cloudSyncProvider).enableWith(SyncScope.fromNow);
      expect(rig.cloud.datesOf('user-b'), ['2026-10-13']);
      expect(rig.cloud.datesOf('user-a'), sevenDays());
    });

    test('syncNow without a configured API does nothing', () async {
      final c = ProviderContainer(overrides: [
        apiConfigProvider.overrideWithValue(const ApiConfig('')),
        dbProvider.overrideWithValue(rig.db),
        prefsProvider.overrideWithValue(rig.prefs),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(cloudSyncProvider).syncNow(), isNull);
      expect(await c.read(cloudSyncProvider).enableWith(SyncScope.history),
          isNull);
      expect(await c.read(cloudSyncProvider).historyBacklog(), 0);
      expect(c.read(syncServiceProvider), isNull);
      expect((await c.read(syncSummaryProvider.future)).enabled, isFalse);
    });
  });

  group('the old global switch (schema v4) moves to the queue owner', () {
    test(
        'wb.cloudSync = true and a legacy owner: that account is enabled, history',
        () async {
      final owner = await ProviderRig.create(
          prefs: {'wb.cloudSync': true}, legacyOwner: 'user-a');
      await owner.c.read(syncAccountProvider.notifier).refresh();
      final info = owner.c.read(syncAccountProvider);
      expect(info.enabled, isTrue);
      expect(info.scope, SyncScope.history);
      expect(owner.c.read(settingsProvider).cloudSync, isTrue);
      expect(await owner.db.meta('sync_legacy_owner'), isNull);

      // Another account: off.
      await owner.signInAs('user-b');
      expect(owner.c.read(syncAccountProvider).enabled, isFalse);
      expect(owner.c.read(settingsProvider).cloudSync, isFalse);
    });

    test('wb.cloudSync = true but nobody to attribute it to: nobody is enabled',
        () async {
      final r = await ProviderRig.create(prefs: {'wb.cloudSync': true});
      await r.c.read(syncAccountProvider.notifier).refresh();
      expect(r.c.read(syncAccountProvider).enabled, isFalse);
      expect(r.c.read(settingsProvider).cloudSync, isFalse,
          reason:
              'the stored view yields to the ledger once an account is known');
    });

    test('wb.cloudSync = false: nobody is enabled', () async {
      final r = await ProviderRig.create(
          prefs: {'wb.cloudSync': false}, legacyOwner: 'user-a');
      await r.c.read(syncAccountProvider.notifier).refresh();
      expect(r.c.read(syncAccountProvider).enabled, isFalse);
      expect(await r.db.meta('sync_legacy_owner'), isNull);
    });
  });

  group('deleting the account', () {
    test(
        'AuthController.deleteAccount erases its ledger, keeps local data and the other account',
        () async {
      await rig.seedDays();
      await rig.c.read(cloudSyncProvider).enableWith(SyncScope.history);
      final keyA = (await rig.service.currentAccountKey())!;
      await rig.service.registerDevice(DeviceSpecification(
          manufacturer: 'Google',
          model: 'Pixel 8',
          modelIdentifier: 'Pixel 8',
          design: DesignCapacity(
              mah: 4575, source: DesignCapacitySource.localDeviceDatabase)));
      await rig.signInAs('user-b');
      await rig.c.read(cloudSyncProvider).enableWith(SyncScope.fromNow);
      final keyB = (await rig.service.currentAccountKey())!;
      await rig.signInAs('user-a');

      final deleted =
          await rig.c.read(authControllerProvider.notifier).deleteAccount();
      expect(deleted, isTrue);

      expect(await rig.db.receiptCount(keyA), 0);
      expect(await rig.db.meta('sync_account:$keyA'), isNull);
      expect(await rig.db.meta('server_device_id:$keyA'), isNull);
      expect(await rig.db.receiptCount(keyB), 1, reason: 'B untouched');
      expect(await rig.db.meta('sync_account:$keyB'), isNotNull);
      expect((await rig.db.allDaily()), hasLength(7),
          reason: 'local data stays');
      expect(await rig.store.read(), isNull);
      expect(rig.c.read(authControllerProvider).value, isA<SignedOut>());
      expect(rig.c.read(syncAccountProvider).accountKey, isNull);
      // The same e-mail registering again is a NEW account: sync off, no receipts.
      await rig.signInAs('user-a');
      expect(rig.c.read(syncAccountProvider).enabled, isFalse);
      expect(await rig.c.read(cloudSyncProvider).historyBacklog(), 6);
    });
  });

  group('battery capacity on the registration path (real providers)', () {
    /// An Android phone whose model identifier is [identifier].
    Future<ProviderRig> android(String identifier) =>
        ProviderRig.create(platform: HarnessPlatform.android, deviceInfo: {
          'manufacturer': 'Acme',
          'model': identifier,
          'modelIdentifier': identifier,
          'regionCode': 'PL',
          'localeTag': 'en-PL',
          'isSimulator': false,
        });

    /// The first-run setup, wired by the real providers: detection (catalog,
    /// backend, the collector's estimate) -> settings -> registration.
    Future<({Settings saved, Map<String, dynamic> body})> runSetup(
        ProviderRig r) async {
      var saved = const Settings();
      await r.c.read(setupControllerProvider.notifier).run(
            setup: r.c.read(autoSetupProvider),
            current: const Settings(),
            save: (s) async => saved = s,
          );
      // The registration is fire-and-forget behind the review screen.
      for (var i = 0;
          i < 200 && r.backend.where('POST', '/api/v1/devices').isEmpty;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final sent = r.backend.where('POST', '/api/v1/devices');
      expect(sent, hasLength(1), reason: 'the setup registers the device once');
      return (saved: saved, body: sent.single.body!);
    }

    test(
        'Android charge counter != design capacity: a model no catalog knows '
        'stays unknown, the reading travels as an estimate only', () async {
      final r = await android('Acme Z1');
      // 100 % and 4321 mAh stored: the best reading there is.
      r.fake.setReading(100, storedMah: 4321);
      await r.tick();
      final estimate = await r.c.read(collectorProvider).fullChargeCapacity();
      expect(estimate.mah, 4321);
      expect(estimate.confidence, FullChargeCapacityConfidence.high);

      final (:saved, :body) = await runSetup(r);
      expect(saved.designCapacityMah, 0,
          reason: 'the settings never learn a capacity from the counter');
      expect(saved.designCapacitySource, DesignCapacitySource.unknown);
      expect(body['designCapacitySource'], 'unknown');
      expect(body['designCapacityMah'], isNull);
      expect(body['designCapacityWh'], isNull);
      expect(body['estimatedFullChargeCapacityMah'], 4321);
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'high');
      expect([
        for (final e in body.entries)
          if (e.value == 4321) e.key
      ], [
        'estimatedFullChargeCapacityMah'
      ]);
      final stored = r.cloud.deviceTable.rowsOf('user-a').single;
      expect(stored['designCapacityMah'], isNull);
      expect(stored['estimatedFullChargeCapacityMah'], 4321);
    });

    test(
        'a model in the local catalog: the catalog is the design capacity, '
        'the half-charged reading is a low-confidence estimate next to it',
        () async {
      final r = await android('Pixel 8');
      r.fake.setReading(50, storedMah: 1800); // 3600 mAh battery at 50 %
      await r.tick();

      final (:saved, :body) = await runSetup(r);
      expect(saved.designCapacityMah, 4575);
      expect(
          saved.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(body['designCapacityMah'], 4575);
      expect(body['designCapacitySource'], 'localDeviceDatabase');
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'low');
    });

    test(
        'no usable counter (unsupported, zero, negative, level 0): the '
        'estimate group is null and the design is whatever the catalog says',
        () async {
      for (final (level, stored) in <(int, double?)>[
        (80, null), // counter unsupported
        (80, 0), // zero
        (80, -2500), // negative
        (0, 2500), // level 0
      ]) {
        final r = await android('Pixel 8');
        r.fake.setReading(level, storedMah: stored);
        await r.tick();
        expect(
            (await r.c.read(collectorProvider).fullChargeCapacity())
                .isAvailable,
            isFalse,
            reason: 'level $level, counter $stored');
        final (:saved, :body) = await runSetup(r);
        expect(saved.designCapacityMah, 4575,
            reason: 'the catalog figure, not the counter ($stored)');
        expect(body['designCapacityMah'], 4575);
        for (final key in FakeBackend.estimateKeys) {
          expect(body[key], isNull, reason: '$key at level $level, $stored');
        }
      }
    });

    test(
        'a model only the backend catalog knows: backendDeviceDatabase, cached '
        'for the next launch, next to the estimate', () async {
      final r = await android('AcmeZ9');
      r.backend.routes['GET /api/v1/devices/specifications/AcmeZ9'] =
          (_) => FakeBackend.json({
                'manufacturer': 'Acme',
                'model': 'Z9',
                'modelIdentifier': 'AcmeZ9',
                'designCapacityMah': 4400,
                'designCapacityWh': 17,
                'nominalVoltage': 3.86,
                'catalogVersion': '2026.10',
              });
      r.fake.setReading(100, storedMah: 3900);
      await r.tick();

      final (:saved, :body) = await runSetup(r);
      expect(saved.designCapacityMah, 4400);
      expect(saved.designCapacityWh, 17);
      expect(saved.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(body['designCapacityMah'], 4400);
      expect(body['designCapacityWh'], 17);
      expect(body['designCapacitySource'], 'backendDeviceDatabase');
      expect(body['estimatedFullChargeCapacityMah'], 3900);
      expect(body['fullChargeCapacityConfidence'], 'high');
      expect([
        for (final e in body.entries)
          if (e.value == 3900) e.key
      ], [
        'estimatedFullChargeCapacityMah'
      ], reason: 'the 3900 mAh reading is only an estimate');
      expect(r.c.read(settingsStoreProvider).deviceSpecCache, contains('4400'),
          reason: 'cached for an offline launch');
    });

    test(
        'iOS, a model in no catalog: the design stays unknown, nothing is '
        'estimated (there is no counter), nothing is invented', () async {
      final r = await ProviderRig.create(deviceInfo: {
        'manufacturer': 'Apple',
        'model': 'iPhone',
        'modelIdentifier': 'iPhone99,9',
        'regionCode': 'PL',
        'localeTag': 'en-PL',
        'isSimulator': false,
      });
      final (:saved, :body) = await runSetup(r);
      expect(saved.designCapacityMah, 0);
      expect(saved.designCapacitySource, DesignCapacitySource.unknown);
      expect(body['designCapacitySource'], 'unknown');
      expect(body['designCapacityMah'], isNull);
      expect(body['designCapacityWh'], isNull);
      for (final key in FakeBackend.estimateKeys) {
        expect(body[key], isNull, reason: key);
      }
      expect(body['modelIdentifier'], 'iPhone99,9');
    });

    test('a later registration without a reading keeps the stored estimate',
        () async {
      final r = await android('Pixel 8');
      r.fake.setReading(100, storedMah: 3600);
      await r.tick();
      await runSetup(r);
      // The same phone registers again, now without any usable reading.
      await r.service.registerDevice(DeviceSpecification(
          manufacturer: 'Google',
          model: 'Pixel 8',
          modelIdentifier: 'Pixel 8',
          design: DesignCapacity(
              mah: 4575, source: DesignCapacitySource.localDeviceDatabase)));
      final stored = r.cloud.deviceTable.rowsOf('user-a').single;
      expect(stored['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
      expect(stored['fullChargeCapacitySource'], 'androidChargeCounter');
    });
  });

  test('account keys on the provider path are the documented one-way keys',
      () async {
    final installation = await rig.service.installationId();
    expect(await rig.service.currentAccountKey(),
        accountKeyFor(installation, 'user-a'));
  });
}

class _NoNotifier implements AppNotifier {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showAll(
    List<PendingNotification> pending, {
    required SettingsStore store,
    required AppLocalizations l10n,
    required Units units,
    required String currency,
  }) async {}
}

class _NoWidgets implements WidgetPublisher {
  @override
  Future<void> publish({
    required DashboardModel model,
    required Units units,
    required AppLocalizations l10n,
    required String currency,
    required bool hasPrice,
  }) async {}
}

class _Now {
  _Now(this.value);

  DateTime value;
}

/// A ProviderContainer wired like the app, with every edge faked: SQLite in memory,
/// the native side (`FakeSystem`), the network (`FakeBackend` behind a counting
/// client), the token store and the auth backend.
class ProviderRig {
  ProviderRig._(this.c, this.db, this.prefs, this.backend, this.cloud,
      this.fake, this.net, this.store, this._now);

  final ProviderContainer c;
  final WattByteDb db;
  final SharedPreferences prefs;
  final FakeBackend backend;
  final FakeCloud cloud;
  final FakeSystem fake;
  final CountingClient net;
  final InMemoryTokenStore store;
  final _Now _now;
  var _bytes = 0;

  DateTime get now => _now.value;
  void advance(Duration d) => _now.value = _now.value.add(d);

  SyncService get service => c.read(syncServiceProvider)!;

  static Future<ProviderRig> create({
    String? signedInAs = 'user-a',
    Map<String, Object> prefs = const {},
    String? legacyOwner,
    HarnessPlatform platform = HarnessPlatform.ios,
    Map<String, Object?>? deviceInfo,
  }) async {
    ensureSqliteFfi();
    final now = _Now(DateTime(2026, 10, 13, 12));
    final db = await WattByteDb.openInMemory();
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    await SettingsStore(p).save(const Settings(
        currency: 'PLN',
        countryCode: 'PL',
        pricePerKwh: 1.0,
        designCapacityMah: 4000,
        designCapacitySource: DesignCapacitySource.manual,
        onboarded: true));
    // Restore what a pre-v5 store would have written back over the cached view.
    for (final e in prefs.entries) {
      if (e.value is bool) await p.setBool(e.key, e.value as bool);
    }
    final backend = FakeBackend();
    final cloud = FakeCloud(backend);
    final net = CountingClient(backend.client);
    final fake = FakeSystem(platform: platform, deviceInfo: deviceInfo);
    final store = InMemoryTokenStore();
    if (signedInAs != null) await store.write(sessionOf(signedInAs));
    if (legacyOwner != null) {
      // What the v5 migration leaves behind for the owner of the old queue.
      const installation = 'abcdef0123456789abcdef0123456789';
      await db.setMeta('installation_id', installation);
      await db.setMeta(
          'sync_legacy_owner', accountKeyFor(installation, legacyOwner));
    }
    const config = ApiConfig('http://api.test');
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(p),
      dbProvider.overrideWithValue(db),
      systemProvider.overrideWithValue(fake.system),
      apiConfigProvider.overrideWithValue(config),
      apiFactoryProvider.overrideWithValue(
          ApiFactory(config, httpClient: net, clock: () => now.value)),
      authRepositoryProvider.overrideWithValue(UserAwareRepo()),
      tokenStoreProvider.overrideWithValue(store),
      notifierProvider.overrideWithValue(_NoNotifier()),
      widgetPublisherProvider.overrideWithValue(_NoWidgets()),
      clockProvider.overrideWithValue(() => now.value),
    ]);
    addTearDown(() async {
      c.dispose();
      fake.dispose();
      await db.close();
    });
    final rig = ProviderRig._(c, db, p, backend, cloud, fake, net, store, now);
    if (signedInAs != null) {
      await c.read(authControllerProvider.future);
      await c.read(syncAccountProvider.notifier).refresh();
    }
    return rig;
  }

  /// One foreground refresh: the real RefreshController -> RefreshService.
  Future<void> tick() async {
    _bytes += 4096;
    fake.counters = RawInterfaceCounters(
      wifiRx: 10 << 20,
      wifiTx: 1 << 20,
      cellRx: (9 << 30) + _bytes,
      cellTx: 1 << 20,
      bootTimeMs: DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
      timeMs: now.millisecondsSinceEpoch,
    );
    await c.read(refreshControllerProvider).refresh(locale: 'en');
  }

  Future<void> enable(SyncScope scope) async {
    await tick(); // a first collection so that today exists
    await c.read(cloudSyncProvider).enableWith(scope);
  }

  /// Seven local days of statistics: 2026-10-07 .. 2026-10-13.
  Future<void> seedDays() => db.replaceDaily([
        for (var d = 7; d <= 13; d++)
          DailyData(
              day: DateTime(2026, 10, d), mobileRx: d * 1000, wifiRx: d * 5000),
      ]);

  /// Signs out and in as [userId] the way the UI does, and lets the account state follow.
  ///
  /// The account-bound settings are per account: the phone's settings follow the
  /// account that signed in (an account that was never here starts with none), so
  /// this waits for them and then gives the account the currency a finished setup
  /// would have given it. Sync needs one, and an account without one uploads nothing.
  Future<void> signInAs(String userId) async {
    final auth = c.read(authControllerProvider.notifier);
    await auth.signOut();
    await auth.signInWithEmail(userId, 'password');
    await c.read(syncAccountProvider.notifier).refresh();
    c.read(settingsProvider); // builds the notifier, which binds the account
    final id = (c.read(authControllerProvider).value as SignedIn).user.id;
    for (var i = 0; i < 500 && c.read(settingsScopeProvider) != id; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.read(settingsScopeProvider), id, reason: 'settings were bound');
    await c
        .read(settingsProvider.notifier)
        .update((s) => s.currency.isEmpty ? s.copyWith(currency: 'PLN') : s);
  }
}
