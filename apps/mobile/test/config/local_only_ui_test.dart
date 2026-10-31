// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/local_only_banner.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/onboarding/setup_screen.dart';
import 'package:wattbyte/ui/onboarding/welcome_screen.dart';
import 'package:wattbyte/ui/shell.dart';

import '../support/app_harness.dart';

/// The explicit, debug-only `LOCAL_ONLY_DEV` mode and the configurations that
/// must NOT become it, through the REAL `WattByteApp` (harness: fake native
/// side, fake backend, in-memory token store).
///
///   apiConfigured: false  = `AppConfig.fromDefines(buildMode: debug,
///                           localOnlyDev: 'true')`, no API: the only way the
///                           account is skipped, and the only time the banner shows
///   apiConfigured: true   = a normal build with an API address: account first,
///                           never a banner
///   appConfig: ...        = any other combination of defines, fed in directly
///
/// The decision itself is unit-tested in the backend-config tests and its
/// source-level invariants in `backend_config_invariants_test.dart`; this file
/// proves what the USER sees.
void main() {
  final en = AppLocalizationsEn();

  // The device setup reads an asset (real file I/O). `rootBundle` caches the
  // future of every asset for the whole process and a future born in one test's
  // fake-async zone can never complete in the next test's zone, so it is
  // cleared before each test (as test/onboarding_persistence_test.dart does).
  setUp(rootBundle.clear);

  /// The literal the spec asks for; written out here on purpose so that a
  /// change of the constant is a visible, deliberate change of this test too.
  const bannerLiteral = 'LOCAL ONLY DEVELOPMENT MODE';

  Finder banner() => find.text(bannerLiteral);
  Finder review() => find.text(en.setupReviewTitle);
  Finder welcome() => find.byType(WelcomeScreen);
  Finder setup() => find.byType(SetupScreen);
  Finder shell() => find.byType(ShellScreen);
  Finder tabs() => find.byType(NavigationDestination);

  /// Fails when the development banner exists anywhere in the tree, painted or
  /// not (`skipOffstage: false`), as a widget or as any text that spells it.
  void expectNoBanner(String where) {
    expect(find.byType(LocalOnlyDevBanner, skipOffstage: false), findsNothing,
        reason: '$where: the development banner widget must not exist');
    expect(
        find.textContaining(bannerLiteral, skipOffstage: false), findsNothing,
        reason: '$where: the banner text must not exist');
    expect(find.textContaining('LOCAL ONLY', skipOffstage: false), findsNothing,
        reason: '$where: no "LOCAL ONLY ..." text of any kind');
    expect(find.textContaining('DEVELOPMENT MODE', skipOffstage: false),
        findsNothing,
        reason: '$where: no "... DEVELOPMENT MODE" text of any kind');
  }

  /// Waits (in real time, pumping fake time) until [finder] matches. The setup
  /// detection reads an asset, which fake time alone does not wait for.
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

  test('the banner constant is the text the spec asks for', () {
    expect(kLocalOnlyDevBannerText, bannerLiteral);
  });

  group('explicit LOCAL_ONLY_DEV mode (apiConfigured: false)', () {
    testWidgets(
        'not onboarded: the banner is there exactly once, the app is on the '
        'local setup, there is no Welcome screen', (tester) async {
      final h = await pumpApp(tester,
          apiConfigured: false,
          onboarded: false,
          settings: const Settings(),
          historyDays: 0);
      expect(h.appConfig.isLocalOnlyDev, isTrue,
          reason: 'precondition: the harness really is in LOCAL_ONLY_DEV mode');
      expect(h.appConfig.buildMode, BuildMode.debug);

      expect(find.text(kLocalOnlyDevBannerText), findsOneWidget);
      expect(banner(), findsOneWidget);
      expect(find.byType(LocalOnlyDevBanner), findsOneWidget);
      expect(find.textContaining('LOCAL ONLY', skipOffstage: false),
          findsOneWidget,
          reason: 'one text with the words, offstage or not');

      expect(setup(), findsOneWidget, reason: 'the local setup');
      expect(welcome(), findsNothing, reason: 'no account in this mode');
      expect(find.text(en.welcomeTagline), findsNothing);
      expect(find.text(en.signIn), findsNothing);
      expect(find.text(en.signUp), findsNothing);
      expect(shell(), findsNothing);

      // Let the detection finish so nothing is pending, then look again.
      await until(tester, review());
      expect(banner(), findsOneWidget,
          reason: 'the banner outlives the setup screens');
      expect(welcome(), findsNothing);
      expectNoFlutterErrors(tester, screen: 'LOCAL_ONLY_DEV setup');
    });

    testWidgets(
        'onboarded: the banner is there exactly once, above the dashboard; '
        'no Welcome, no setup', (tester) async {
      final h = await pumpApp(tester,
          apiConfigured: false, onboarded: true, historyDays: 0);
      expect(h.appConfig.isLocalOnlyDev, isTrue);

      expect(banner(), findsOneWidget);
      expect(find.byType(LocalOnlyDevBanner), findsOneWidget);
      expect(shell(), findsOneWidget);
      expect(tabs(), findsNWidgets(4));
      expect(welcome(), findsNothing);
      expect(setup(), findsNothing);
      expectNoFlutterErrors(tester, screen: 'LOCAL_ONLY_DEV dashboard');
    });

    for (final signedIn in [true, false]) {
      for (final onboarded in [false, true]) {
        testWidgets(
            'signedIn=$signedIn, onboarded=$onboarded: the account is not '
            'part of this mode', (tester) async {
          await pumpApp(tester,
              apiConfigured: false,
              signedIn: signedIn,
              onboarded: onboarded,
              historyDays: 0);
          expect(banner(), findsOneWidget);
          expect(welcome(), findsNothing);
          expect(find.text(en.signIn), findsNothing);
          expect(onboarded ? shell() : setup(), findsOneWidget);
          expect(onboarded ? setup() : shell(), findsNothing);
        });
      }
    }

    testWidgets('both platforms show it exactly once', (tester) async {
      for (final platform in HarnessPlatform.values) {
        await pumpApp(tester,
            platform: platform,
            apiConfigured: false,
            onboarded: true,
            historyDays: 0);
        expect(banner(), findsOneWidget, reason: platform.name);
        expect(find.byType(LocalOnlyDevBanner), findsOneWidget,
            reason: platform.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the banner stays on top of a pushed screen, still once',
        (tester) async {
      await pumpApp(tester,
          apiConfigured: false,
          onboarded: true,
          historyDays: 0,
          home: const Scaffold(body: Center(child: Text('pushed screen'))));
      expect(find.text('pushed screen'), findsOneWidget);
      expect(banner(), findsOneWidget,
          reason: 'it lives in the MaterialApp builder, not in one screen');
    });

    testWidgets('the banner is the first thing on screen', (tester) async {
      await pumpApp(tester,
          apiConfigured: false, onboarded: true, historyDays: 0);
      final text = tester.getRect(banner());
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(text.top, greaterThanOrEqualTo(0));
      expect(text.bottom, lessThan(view.height / 4),
          reason: 'a strip at the top of the screen');
      expect(text.left, greaterThanOrEqualTo(0));
      expect(text.right, lessThanOrEqualTo(view.width));
      expect(text.bottom, lessThanOrEqualTo(tester.getTopLeft(shell()).dy),
          reason: 'the app starts below the strip, nothing is covered');
      // Deliberately NOT asserted: that screen readers announce it. The strip
      // sits before the Navigator in a Column, and a route's BlockSemantics
      // removes everything painted before it from the semantics tree (see the
      // report of this test file); it is a visual, developer-only marker.
    });
  });

  group('normal builds (API address configured) never show it', () {
    testWidgets('signed out: Welcome, no banner anywhere', (tester) async {
      final h = await pumpApp(tester, signedIn: false, onboarded: false);
      expect(h.appConfig.isLocalOnlyDev, isFalse);
      expect(h.appConfig.backendMode, BackendMode.online);
      expect(welcome(), findsOneWidget);
      expect(find.text(en.welcomeTagline), findsOneWidget);
      expect(setup(), findsNothing);
      expectNoBanner('Welcome');
      expectNoFlutterErrors(tester, screen: 'Welcome');
    });

    testWidgets('signed out with the setup flag already set: still Welcome',
        (tester) async {
      await pumpApp(tester, signedIn: false, onboarded: true);
      expect(welcome(), findsOneWidget);
      expect(shell(), findsNothing);
      expectNoBanner('Welcome (onboarded flag set)');
    });

    testWidgets('signed in: the dashboard, no banner anywhere', (tester) async {
      final h = await pumpApp(tester);
      expect(h.appConfig.isLocalOnlyDev, isFalse);
      expect(shell(), findsOneWidget);
      expect(tabs(), findsNWidgets(4));
      expect(welcome(), findsNothing);
      expectNoBanner('Dashboard');
      for (var i = 1; i < 4; i++) {
        await h.tapTab(tester, i);
        expectNoBanner('tab $i');
      }
      expectNoFlutterErrors(tester, screen: 'Dashboard');
    });

    testWidgets('signed in but not onboarded: the setup, no banner',
        (tester) async {
      await pumpApp(tester, onboarded: false, historyDays: 0);
      expect(setup(), findsOneWidget);
      expect(welcome(), findsNothing);
      expectNoBanner('Setup');
      await until(tester, review());
      expectNoBanner('Setup review');
    });

    testWidgets('signed out, the account screens carry no banner either',
        (tester) async {
      await pumpApp(tester, signedIn: false, onboarded: false);
      await tester.tap(find.widgetWithText(FilledButton, en.signUp));
      await settle(tester);
      expect(find.text(en.authCreateTitle), findsOneWidget);
      expectNoBanner('Create account');
    });

    testWidgets('a pushed screen carries no banner', (tester) async {
      await pumpApp(tester,
          home: const Scaffold(body: Center(child: Text('pushed screen'))));
      expect(find.text('pushed screen'), findsOneWidget);
      expectNoBanner('pushed screen');
    });

    // Configurations a profile or release build may legitimately have: an API
    // address, no flag. The UI must be the normal one, whatever mode the
    // configuration was validated for.
    final valid = <String, AppConfig>{
      'debug + API address': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'https://api.sample-company.io'),
      'debug + API address + LOCAL_ONLY_DEV=false': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'http://127.0.0.1:8080',
          localOnlyDev: 'false'),
      'profile + API address': AppConfig.fromDefines(
          buildMode: BuildMode.profile,
          apiBaseUrl: 'https://api.sample-company.io'),
      'release + API address': AppConfig.fromDefines(
          buildMode: BuildMode.release,
          apiBaseUrl: 'https://api.sample-company.io'),
    };
    for (final entry in valid.entries) {
      testWidgets(
          'valid ${entry.key}: Welcome when signed out, dashboard '
          'when signed in, never a banner', (tester) async {
        final config = entry.value;
        expect(config.isValid, isTrue, reason: 'precondition: ${entry.key}');
        expect(config.backendMode, BackendMode.online);

        await pumpApp(tester,
            appConfig: config,
            signedIn: false,
            onboarded: true,
            historyDays: 0);
        expect(welcome(), findsOneWidget);
        expect(shell(), findsNothing);
        expectNoBanner('${entry.key}, signed out');

        await tester.pumpWidget(const SizedBox());
        await pumpApp(tester,
            appConfig: config, signedIn: true, onboarded: true, historyDays: 0);
        expect(shell(), findsOneWidget);
        expect(welcome(), findsNothing);
        expectNoBanner('${entry.key}, signed in');
      });
    }
  });

  group('the banner does not break the layout', () {
    /// The banner of the running app: not text-scaled, one line, the same
    /// height at every scale, inside the screen, above the app. (Its WIDTH is
    /// the width of the screen: the text is centred in a full-width strip.)
    void expectStableBanner(WidgetTester tester, double lineHeight,
        {required Finder below}) {
      final text = tester.widget<Text>(banner());
      expect(text.textScaler, TextScaler.noScaling,
          reason: 'the banner is a fixed-size strip: TextScaler.noScaling');
      expect(tester.getSize(banner()).height, lineHeight,
          reason: 'its height must not follow the system text scale');
      final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: banner(), matching: find.byType(RichText)));
      final lines = {
        for (final box in paragraph.getBoxesForSelection(const TextSelection(
            baseOffset: 0, extentOffset: kLocalOnlyDevBannerText.length)))
          box.top.round(),
      };
      expect(lines, hasLength(1), reason: 'the banner text stays on one line');
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(banner());
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(view.width));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(tester.getTopLeft(below).dy),
          reason: 'the app below the strip is not covered by it');
      expect(banner(), findsOneWidget);
    }

    for (final onboarded in [true, false]) {
      final screen = onboarded ? 'dashboard' : 'setup';
      testWidgets(
          'iPhone SE at every text scale ($screen): no overflow, banner '
          'unscaled and unmoved', (tester) async {
        final h = await pumpApp(tester,
            apiConfigured: false,
            onboarded: onboarded,
            device: kIPhoneSE,
            textScale: 1.0,
            historyDays: onboarded ? 45 : 0);
        final below = onboarded ? shell() : setup();
        expect(below, findsOneWidget);
        final lineHeight = tester.getSize(banner()).height;
        expect(lineHeight, greaterThan(0));

        await sweepViews(tester, h, () async {
          expectNoFlutterErrors(tester, screen: 'LOCAL_ONLY_DEV $screen');
          expectStableBanner(tester, lineHeight, below: below);
        }, devices: const [kIPhoneSE], textScales: kTextScales);
      });
    }

    testWidgets('every screen size, light and dark, at 1.0 and 3.0',
        (tester) async {
      final h = await pumpApp(tester,
          apiConfigured: false, onboarded: true, historyDays: 45);
      final lineHeight = tester.getSize(banner()).height;
      await sweepViews(tester, h, () async {
        expectNoFlutterErrors(tester, screen: 'LOCAL_ONLY_DEV dashboard');
        expectStableBanner(tester, lineHeight, below: shell());
      },
          devices: kScreenSizes,
          textScales: const [1.0, 3.0],
          brightnesses: Brightness.values);
    });

    testWidgets('a locale with longer words does not matter (Polish)',
        (tester) async {
      await pumpApp(tester,
          apiConfigured: false,
          onboarded: true,
          historyDays: 0,
          device: kIPhoneSE,
          textScale: 3.0,
          locale: const Locale('pl'));
      expect(banner(), findsOneWidget,
          reason: 'developer-facing text, not localised');
      expectNoFlutterErrors(tester, screen: 'LOCAL_ONLY_DEV dashboard (pl)');
    });
  });

  group(
      'fail closed: a configuration that is not valid never skips the '
      'account', () {
    // Every one of these is rejected by `validateBackendConfig`; `main()` shows
    // the configuration error instead of the app. Should the app ever be
    // mounted with one of them (a regression of `main()`, a test, a future
    // entry point), it must still ask for an account first.
    final invalid = <String, AppConfig>{
      'debug, no API, no flag':
          AppConfig.fromDefines(buildMode: BuildMode.debug),
      'debug, no API, LOCAL_ONLY_DEV=false': AppConfig.fromDefines(
          buildMode: BuildMode.debug, localOnlyDev: 'false'),
      'debug, malformed LOCAL_ONLY_DEV (yes)': AppConfig.fromDefines(
          buildMode: BuildMode.debug, localOnlyDev: 'yes'),
      'debug, broken API address (ftp scheme)': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'ftp://api.sample-company.io'),
      'debug, API address with credentials': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'https://user:secret-token@api.sample-company.io'),
      'debug, broken API address + LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'not-a-url',
          localOnlyDev: 'true'),
      'debug, valid API address + LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
          buildMode: BuildMode.debug,
          apiBaseUrl: 'https://api.sample-company.io',
          localOnlyDev: 'true'),
      'profile, no API': AppConfig.fromDefines(buildMode: BuildMode.profile),
      'profile, no API, LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
          buildMode: BuildMode.profile, localOnlyDev: 'true'),
      'release, no API': AppConfig.fromDefines(buildMode: BuildMode.release),
      'release, no API, LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
          buildMode: BuildMode.release, localOnlyDev: 'true'),
      'release, API address + LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
          buildMode: BuildMode.release,
          apiBaseUrl: 'https://api.sample-company.io',
          localOnlyDev: 'true'),
    };

    for (final entry in invalid.entries) {
      for (final onboarded in [true, false]) {
        testWidgets(
            '${entry.key} (setup flag $onboarded): Welcome, never setup or '
            'dashboard, no banner', (tester) async {
          final config = entry.value;
          expect(config.isValid, isFalse,
              reason: 'precondition: "${entry.key}" must be an invalid '
                  'configuration (see lib/config/backend_config.dart)');
          expect(config.isLocalOnlyDev, isFalse);
          expect(config.backendMode, isNull);

          final h = await pumpApp(tester,
              appConfig: config,
              signedIn: false,
              onboarded: onboarded,
              historyDays: 0);

          expect(welcome(), findsOneWidget,
              reason: 'an account is required: the user must land on Welcome');
          expect(find.text(en.welcomeTagline), findsOneWidget);
          expect(setup(), findsNothing,
              reason: 'the local setup must not be reachable without an '
                  'account (${entry.key})');
          expect(shell(), findsNothing,
              reason: 'the dashboard must not be reachable without an '
                  'account (${entry.key})');
          expect(tabs(), findsNothing);
          expectNoBanner(entry.key);

          // Nothing about the phone was looked up on behalf of a build that
          // has no account.
          expect(h.backend.requests, isEmpty);
          expect(h.system.callsTo('deviceInfo'), isEmpty);
          expect(h.system.callsTo('batterySnapshot'), isEmpty);
          expectNoFlutterErrors(tester, screen: 'Welcome (${entry.key})');
        });
      }
    }

    testWidgets(
        'release, no API, LOCAL_ONLY_DEV=true (the spec case): the account '
        'is not skipped', (tester) async {
      final config = AppConfig.fromDefines(
          buildMode: BuildMode.release, localOnlyDev: 'true');
      expect(config.isValid, isFalse);
      await pumpApp(tester,
          appConfig: config, signedIn: false, onboarded: false, historyDays: 0);
      expect(welcome(), findsOneWidget);
      expect(setup(), findsNothing);
      expect(shell(), findsNothing);
      expectNoBanner('release + LOCAL_ONLY_DEV=true');
    });

    testWidgets(
        'AppConfig.fromDefines(buildMode: debug) - no API, no flag - is the '
        'configuration of an unconfigured `flutter run`: Welcome',
        (tester) async {
      final config = AppConfig.fromDefines(buildMode: BuildMode.debug);
      expect(config.isValid, isFalse);
      await pumpApp(tester,
          appConfig: config, signedIn: false, onboarded: true, historyDays: 0);
      expect(welcome(), findsOneWidget);
      expect(shell(), findsNothing);
      expectNoBanner('debug without defines');
    });

    testWidgets(
        'an invalid configuration with a stored session does not turn '
        'into the explicit local-only mode either', (tester) async {
      // Not a path a real build can take (main() stops first). It pins that the
      // only thing that skips the account is `isLocalOnlyDev`, and that the
      // banner follows the same single flag: no banner without it.
      final config = AppConfig.fromDefines(buildMode: BuildMode.debug);
      await pumpApp(tester,
          appConfig: config, signedIn: true, onboarded: true, historyDays: 0);
      expectNoBanner('invalid configuration, session present');
    });
  });
}
