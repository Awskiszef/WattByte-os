import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';

import 'support/app_harness.dart';

/// The first launch, end to end, through the REAL app (harness: fake native
/// side, fake backend, in-memory token store):
///
///   fresh install, signed out        -> Welcome (an account comes first)
///   Create account                   -> automatic setup -> review
///   Continue                         -> Permissions
///   Get started                      -> Dashboard, `onboarded = true`
///   restart (same storage)           -> Dashboard, straight away
///
/// and the corners: setup interrupted after the account exists, signed out
/// with the flag set, and the values chosen in setup surviving the restart.
///
/// "Restart" here is: unmount the whole app (the Riverpod container with it) and
/// pump it again over the SAME `SharedPreferences` and the SAME token store, which
/// is what a process restart finds. That the preferences really are on disk is
/// proven separately (`settings_persistence_test.dart`).
void main() {
  final en = AppLocalizationsEn();

  // `rootBundle` caches the FUTURE of every asset it loads, for the whole
  // process. A future created in one test's fake-async zone can never be awaited
  // from the next test's zone (its continuation is scheduled on the dead zone),
  // so the second test that runs the device detection hangs on the catalog.
  setUp(rootBundle.clear);

  // Texts that identify a screen (ARB keys, stable across layout rework).
  Finder welcome() => find.text(en.welcomeTagline);
  Finder detecting() => find.text(en.setupDetectingTitle);
  Finder review() => find.text(en.setupReviewTitle);
  Finder permissions() => find.text(en.permissionsTitle);
  Finder dashboard() => find.byType(NavigationDestination);

  Settings stored(AppHarness h) => SettingsStore(h.prefs).load();

  /// Pumps frame by frame after a launch and records which start screens were
  /// ever visible (the "flash of the wrong screen" problem), until [done]
  /// matches, then for another second to catch a late change.
  Future<Set<String>> screensUntil(WidgetTester tester, Finder done) async {
    final seen = <String>{};
    void look() {
      if (welcome().evaluate().isNotEmpty) seen.add('welcome');
      if (detecting().evaluate().isNotEmpty) seen.add('detecting');
      if (review().evaluate().isNotEmpty) seen.add('review');
      if (permissions().evaluate().isNotEmpty) seen.add('permissions');
      if (dashboard().evaluate().isNotEmpty) seen.add('dashboard');
    }

    final end = DateTime.now().add(const Duration(seconds: 30));
    while (done.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('timed out waiting for ${done.describeMatch(Plurality.one)}; '
            'saw $seen');
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
      look();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      look();
    }
    return seen;
  }

  /// Waits until [finder] matches. The detection reads an asset (real file
  /// I/O), which pumping fake time alone does not wait for, so real time passes
  /// between the pumps.
  Future<void> until(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('timed out waiting for ${finder.describeMatch(Plurality.one)}');
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await settle(tester);
  }

  /// Welcome -> Create account -> e-mail and password -> submit -> the review.
  Future<void> createAccount(WidgetTester tester,
      {String email = 'new@user.test'}) async {
    await tester.tap(find.widgetWithText(FilledButton, en.signUp));
    await settle(tester);
    expect(find.text(en.authCreateTitle), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), 'correct horse battery');
    await tester.tap(find.widgetWithText(FilledButton, en.signUp));
    await settle(tester, timeout: const Duration(seconds: 10));
    await until(tester, review());
  }

  testWidgets('fresh install, signed out: Welcome, and nothing is asked yet',
      (tester) async {
    final h = await pumpApp(tester,
        signedIn: false, onboarded: false, settings: const Settings());

    expect(welcome(), findsOneWidget);
    expect(find.widgetWithText(FilledButton, en.signUp), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, en.signIn), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'no question of any kind on the first screen');
    expect(dashboard(), findsNothing);

    // Nothing about the phone, the region, the price or the battery was
    // looked up or asked before an account exists...
    expect(h.backend.requests, isEmpty,
        reason: 'no electricity-price, region or device request yet');
    expect(h.system.callsTo('deviceInfo'), isEmpty);
    expect(h.system.callsTo('batterySnapshot'), isEmpty);
    expect(h.notifier.permissionRequests, 0,
        reason: 'no notification prompt before the explanation screen');
    // ... and nothing was configured.
    final s = stored(h);
    expect([s.currency, s.countryCode, s.deviceModel], ['', '', '']);
    expect(s.hasPrice, isFalse);
    expect(s.designCapacityMah, 0);
    expect(s.designCapacitySource, DesignCapacitySource.unknown);
    expect(s.onboarded, isFalse);
    // None of the setup vocabulary is on screen.
    for (final text in [
      en.setupReviewTitle,
      en.setupDetectingTitle,
      en.permissionsTitle,
      en.setupBattery,
      en.setupElectricity,
      en.currency,
    ]) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expectNoFlutterErrors(tester, screen: 'Welcome');
  });

  testWidgets(
      'Create account -> setup -> review -> permissions -> Get started: '
      'the dashboard, and onboarded is stored', (tester) async {
    final h = await pumpApp(tester,
        signedIn: false, onboarded: false, settings: const Settings());

    await createAccount(tester);
    // The account exists; the automatic setup runs and shows its review.
    expect(h.tokenStore, isNotNull);
    expect((await h.tokenStore.read())?.user.email, 'new@user.test');
    expect(review(), findsOneWidget,
        reason: 'after the account comes the review of what was detected');
    expect(stored(h).onboarded, isFalse, reason: 'not finished yet');

    await tester.tap(find.widgetWithText(FilledButton, en.continueLabel));
    await settle(tester);
    expect(permissions(), findsOneWidget);
    expect(stored(h).onboarded, isFalse,
        reason: 'the permissions screen is still part of the setup');
    expect(h.notifier.permissionRequests, 0,
        reason: 'the system prompt only appears on an explicit tap');

    await tester.tap(find.widgetWithText(FilledButton, en.getStarted));
    await settle(tester);
    expect(dashboard(), findsNWidgets(4));
    expect(permissions(), findsNothing);
    expect(stored(h).onboarded, isTrue);
    expect(h.prefs.getBool('wb.onboarded'), isTrue);
    expectNoFlutterErrors(tester, screen: 'Dashboard after setup');
  });

  testWidgets(
      'restarting after a finished setup lands on the Dashboard '
      'directly, without Welcome or setup in between', (tester) async {
    final h = await pumpApp(tester,
        signedIn: false, onboarded: false, settings: const Settings());
    await createAccount(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.continueLabel));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.getStarted));
    await settle(tester);
    expect(dashboard(), findsNWidgets(4));

    // Restart: same preferences, same token store.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness: h, andSettle: false);
    final seen = await screensUntil(tester, dashboard());
    expect(seen, {'dashboard'},
        reason: 'no flash of Welcome, the detection or the permissions');
    await settle(tester);
    expect(dashboard(), findsNWidgets(4));
    expect(h.container(tester).read(authControllerProvider).value,
        isA<SignedIn>());
  });

  testWidgets(
      'an interrupted setup (account exists, not onboarded) resumes at '
      'the setup', (tester) async {
    final h = await pumpApp(tester,
        signedIn: true, onboarded: false, settings: const Settings());
    // The detection finished and wrote its values, then the app was killed on the
    // review screen: the flag was never set.
    await until(tester, review());
    expect(stored(h).onboarded, isFalse);
    final before = stored(h);
    expect(before.countryCode, isNotEmpty,
        reason: 'the detected values are saved as soon as they exist');

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness: h, andSettle: false);
    final seen = await screensUntil(tester, review());
    expect(seen, isNot(contains('dashboard')));
    expect(seen, isNot(contains('welcome')),
        reason: 'the account is still there');
    expect(seen, contains('review'),
        reason: 'the setup runs again and ends on its review');
    expect(stored(h).onboarded, isFalse);
  });

  testWidgets('signed out with onboarded=true still starts at Welcome',
      (tester) async {
    final h = await pumpApp(tester,
        signedIn: false,
        onboarded: true,
        settings: AppHarness.defaultSettings(HarnessPlatform.ios));
    expect(welcome(), findsOneWidget);
    expect(dashboard(), findsNothing);
    expect(review(), findsNothing);
    expect(stored(h).onboarded, isTrue,
        reason: 'the flag is not cleared by being signed out');
    final seen = await screensUntil(tester, welcome());
    expect(seen, {'welcome'});
  });

  testWidgets(
      'signing out after onboarding returns to Welcome; signing in again '
      'goes straight to the Dashboard', (tester) async {
    final h = await pumpApp(tester);
    expect(dashboard(), findsNWidgets(4));
    final container = h.container(tester);
    await container.read(authControllerProvider.notifier).signOut();
    await settle(tester);
    expect(welcome(), findsOneWidget);
    expect(stored(h).onboarded, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, en.signIn));
    await settle(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'tester@example.com');
    await tester.enterText(fields.at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, en.signIn));
    await settle(tester, timeout: const Duration(seconds: 10));
    expect(dashboard(), findsNWidgets(4),
        reason: 'a returning user is not put through the setup again');
    expect(review(), findsNothing);
  });

  testWidgets('the values chosen in setup are the same after a restart',
      (tester) async {
    final h = await pumpApp(tester,
        signedIn: false, onboarded: false, settings: const Settings());
    await createAccount(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.continueLabel));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.getStarted));
    await settle(tester);

    final chosen = stored(h);
    // What the harness's phone and backend say: iPhone in Poland, the
    // household price from the API.
    expect(chosen.countryCode, 'PL');
    expect(chosen.currency, 'PLN');
    expect(chosen.regionSource, SettingSource.detected);
    expect(chosen.regionDetection, isNotEmpty);
    expect(chosen.priceMode, ElectricityPriceMode.automatic);
    expect(chosen.pricePerKwh, 1.15);
    expect(chosen.autoPrice, isNotNull);
    expect(chosen.deviceModelIdentifier, 'iPhone18,1');
    // iPhone 17 Pro is in the bundled catalog: its DESIGN capacity, labelled as
    // such. (iOS has no charge counter, hence no estimated full charge either.)
    expect(chosen.designCapacityMah, 3988);
    expect(
        chosen.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    expect(chosen.onboarded, isTrue);

    // A restart that really reads storage again: a new SharedPreferences
    // instance built from what the old one holds.
    final onDisk = {for (final k in h.prefs.getKeys()) k: h.prefs.get(k)!};
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(onDisk);
    final reopened =
        SettingsStore(await SharedPreferences.getInstance()).load();
    expect(_describe(reopened), _describe(chosen));

    // And through the running app after the restart.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness: h);
    final live = h.container(tester).read(settingsProvider);
    expect(_describe(live), _describe(chosen));
  });

  testWidgets(
      'a manual choice made during setup survives the restart and is '
      'not replaced by detection', (tester) async {
    final h = await pumpApp(tester,
        signedIn: false, onboarded: false, settings: const Settings());
    await createAccount(tester);
    // The user edits the battery on the review screen (what "Edit" does).
    await h.container(tester).read(settingsProvider.notifier).update((s) =>
        s.withDesignCapacity(
            DesignCapacity(mah: 4100, source: DesignCapacitySource.manual)));
    await tester.tap(find.widgetWithText(FilledButton, en.continueLabel));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.getStarted));
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness: h);
    final s = h.container(tester).read(settingsProvider);
    expect(s.designCapacityMah, 4100);
    expect(s.designCapacitySource, DesignCapacitySource.manual);
    expect(stored(h).designCapacityMah, 4100);
    expect(stored(h).designCapacitySource, DesignCapacitySource.manual);
  });

  /// The device registrations the SETUP sent (the first-run registration that
  /// carries the design capacity), as request bodies.
  List<Map<String, dynamic>> setupRegistrations(AppHarness h) => [
        for (final r in h.backend.where('POST', '/api/v1/devices'))
          if (r.body!['designCapacitySource'] != null) r.body!
      ];

  /// A first launch on [system], through account creation up to the review.
  Future<AppHarness> firstLaunchOn(WidgetTester tester, FakeSystem system,
      {Future<void> Function(AppHarness h)? seed}) async {
    final h = await AppHarness.create(tester,
        platform: system.platform,
        signedIn: false,
        onboarded: false,
        settings: const Settings(),
        system: system);
    await seed?.call(h);
    await pumpApp(tester, harness: h);
    await createAccount(tester);
    // The registration is sent right after the settings are saved.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
    return h;
  }

  Map<String, Object?> info(String id, HarnessPlatform platform) => {
        'manufacturer': platform.isIos ? 'Apple' : 'Google',
        'model': platform.isIos ? 'iPhone' : id,
        'modelIdentifier': id,
        'regionCode': 'PL',
        'localeTag': 'en-PL',
        'isSimulator': false,
      };

  testWidgets(
      'an iPhone the catalog does not know: "Battery capacity unavailable", '
      'nothing is guessed and the registration says unknown', (tester) async {
    final system =
        FakeSystem(deviceInfo: info('iPhone99,1', HarnessPlatform.ios));
    final h = await firstLaunchOn(tester, system);

    expect(review(), findsOneWidget);
    expect(find.text(en.capacityUnavailable), findsOneWidget);
    expect(find.text(en.capacityUnavailableBody), findsOneWidget);
    final s = stored(h);
    expect(s.deviceModelIdentifier, 'iPhone99,1');
    expect(s.designCapacityMah, 0);
    expect(s.designCapacityWh, 0);
    expect(s.designCapacitySource, DesignCapacitySource.unknown);

    final sent = setupRegistrations(h);
    expect(sent, hasLength(1));
    expect(sent.single['designCapacitySource'], 'unknown');
    expect(sent.single['designCapacityMah'], isNull);
    expect(sent.single['designCapacityWh'], isNull);
    for (final key in FakeBackend.estimateKeys) {
      expect(sent.single[key], isNull,
          reason: 'iOS has no estimate; $key stays null');
    }
    expectNoFlutterErrors(tester, screen: 'Setup review, unknown iPhone');
  });

  testWidgets(
      'ANDROID CHARGE COUNTER != DESIGN CAPACITY: an unknown Android model '
      'with a 3600 mAh / 100 % reading stays unknown; the estimate travels '
      'beside it', (tester) async {
    final system = FakeSystem(
        platform: HarnessPlatform.android,
        batteryLevel: 100,
        chargeCounterMah: 3600,
        deviceInfo: info('Pixel 99', HarnessPlatform.android));
    final h = await firstLaunchOn(tester, system, seed: (h) async {
      final seeded = await seedFullChargeEstimate(h.db, mah: 3600, level: 100);
      expect(seeded.mah, 3600);
      expect(seeded.confidence, FullChargeCapacityConfidence.high);
    });

    // Settings: the model is recorded, its design capacity is unknown.
    expect(review(), findsOneWidget);
    expect(find.text(en.capacityUnavailable), findsOneWidget,
        reason: 'the reading is not shown as the battery capacity');
    final s = stored(h);
    expect(s.deviceModelIdentifier, 'Pixel 99');
    expect(s.designCapacityMah, 0);
    expect(s.designCapacityWh, 0);
    expect(s.designCapacitySource, DesignCapacitySource.unknown);
    // Persistence: no stored number is the reading, in any key.
    for (final key in h.prefs.getKeys()) {
      final v = h.prefs.get(key);
      expect(v, isNot(3600.0), reason: key);
      expect(v, isNot(3600), reason: key);
    }

    // Registration: an UNKNOWN design capacity without numbers, and the
    // estimate in its own group with its confidence.
    final sent = setupRegistrations(h);
    expect(sent, hasLength(1));
    final body = sent.single;
    expect(body['modelIdentifier'], 'Pixel 99');
    expect(body['designCapacitySource'], 'unknown');
    expect(body['designCapacityMah'], isNull);
    expect(body['designCapacityWh'], isNull);
    expect(body['estimatedFullChargeCapacityMah'], 3600);
    expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
    expect(body['fullChargeCapacityConfidence'], 'high');
    for (final key in FakeBackend.retiredBatteryKeys) {
      expect(body.containsKey(key), isFalse, reason: '$key is retired');
    }
  });

  testWidgets(
      'a known Android model keeps its catalog design capacity next to a '
      'different estimate', (tester) async {
    final system = FakeSystem(
        platform: HarnessPlatform.android,
        batteryLevel: 100,
        chargeCounterMah: 3600,
        deviceInfo: info('Pixel 8', HarnessPlatform.android));
    final h = await firstLaunchOn(tester, system, seed: (h) async {
      await seedFullChargeEstimate(h.db, mah: 3600, level: 100);
    });

    final s = stored(h);
    expect(s.designCapacityMah, 4575, reason: 'the catalog figure');
    expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    expect(find.text(en.capacityUnavailable), findsNothing);

    final body = setupRegistrations(h).single;
    expect(body['designCapacityMah'], 4575);
    expect(body['designCapacitySource'], 'localDeviceDatabase');
    expect(body['estimatedFullChargeCapacityMah'], 3600);
    expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
  });

  testWidgets(
      'an explicit LOCAL_ONLY_DEV build skips the account but still '
      'remembers that setup is done', (tester) async {
    final h = await pumpApp(tester,
        apiConfigured: false, onboarded: false, settings: const Settings());
    // No account is possible: straight to the setup.
    expect(welcome(), findsNothing);
    await until(tester, review());
    await tester.tap(find.widgetWithText(FilledButton, en.continueLabel));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, en.getStarted));
    await settle(tester);
    expect(dashboard(), findsNWidgets(4));
    expect(stored(h).onboarded, isTrue);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, harness: h);
    expect(dashboard(), findsNWidgets(4));
  });
}

/// The settings as plain values (a `Settings` has no `==`).
Map<String, Object?> _describe(Settings s) => {
      'currency': s.currency,
      'currencySource': s.currencySource,
      'countryCode': s.countryCode,
      'regionSource': s.regionSource,
      'pricePerKwh': s.pricePerKwh,
      'priceMode': s.priceMode,
      'manualPricePerKwh': s.manualPricePerKwh,
      'autoPrice': s.autoPrice == null
          ? null
          : [
              s.autoPrice!.pricePerKwh,
              s.autoPrice!.currency,
              s.autoPrice!.countryCode,
              s.autoPrice!.period,
              s.autoPrice!.source,
              s.autoPrice!.updatedAt.millisecondsSinceEpoch,
            ],
      'designCapacityMah': s.designCapacityMah,
      'designCapacityWh': s.designCapacityWh,
      'designCapacitySource': s.designCapacitySource,
      'deviceModel': s.deviceModel,
      'deviceModelIdentifier': s.deviceModelIdentifier,
      'nominalVoltage': s.nominalVoltage,
      'efficiency': s.efficiency,
      'onboarded': s.onboarded,
    };
