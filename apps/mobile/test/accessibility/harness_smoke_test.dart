// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Proves the widget-test harness (test/support/app_harness.dart) itself:
// that it pumps the real app, that every knob reaches the app, and - just as
// important - that its checks FAIL when they should. A harness that cannot
// fail would turn every later accessibility test into a rubber stamp.
//
// What is deliberately NOT asserted here: that the Dashboard fits at text scale
// 1.6 and above. It does not yet, and fixing that is someone else's job; these
// tests only show that the harness can see it.
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/app.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/data_by_app/data_by_app_screen.dart';
import 'package:wattbyte/ui/statistics/statistics_screen.dart';

import '../support/app_harness.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// A row that needs 500 logical pixels: overflows every phone screen.
Widget _tooWide() => Row(children: [
      Container(width: 250, height: 20, color: Colors.red),
      Container(width: 250, height: 20, color: Colors.blue),
    ]);

/// For synchronous checks: `expect(() => expectNoFlutterErrors(t), _failureContaining([...]))`.
Matcher _failureContaining(List<String> parts) =>
    throwsA(isA<TestFailure>().having((e) => e.message ?? '', 'message',
        allOf(parts.map(contains).toList())));

/// For async checks. (`expectLater(future, ...)` cannot be used: the future has
/// already started pumping when expectLater begins, which flutter_test rejects.)
Future<void> _expectFailure(
    Future<void> Function() body, List<String> parts) async {
  try {
    await body();
  } on TestFailure catch (e) {
    for (final part in parts) {
      expect(e.message, contains(part));
    }
    return;
  }
  fail('expected a TestFailure containing $parts, but the check passed');
}

void main() {
  group('real app', () {
    testWidgets('signed in + onboarded: dashboard with seeded history at 1.0',
        (tester) async {
      final h = await pumpApp(tester);

      expect(find.byType(WattByteApp), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text(_en.dataUsed), findsOneWidget,
          reason: 'the dashboard must show data, not the empty state');
      expect(h.history.days, hasLength(45));
      expect(h.history.sessions, isNotEmpty);
      expect(await h.db.allDaily(), hasLength(45));
      expectNoFlutterErrors(tester, screen: 'Dashboard');
    });

    testWidgets('welcome (signed out) at 1.0 and 1.6', (tester) async {
      final h = await pumpApp(tester, signedIn: false);
      expect(find.text(_en.signUp), findsOneWidget);
      expect(find.text(_en.signIn), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNothing);
      expectNoFlutterErrors(tester, screen: 'Welcome @1.0');

      await h.setTextScale(tester, 1.6);
      expect(find.text(_en.signIn), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'Welcome @1.6');
    });

    testWidgets('signed in but not onboarded starts the device setup',
        (tester) async {
      await pumpApp(tester, onboarded: false);
      expect(find.byType(NavigationDestination), findsNothing);
      expect(find.text(_en.signIn), findsNothing);
      expectNoFlutterErrors(tester, screen: 'Setup');
    });

    testWidgets('a build without API starts at the dashboard, no account',
        (tester) async {
      await pumpApp(tester, apiConfigured: false);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expectNoFlutterErrors(tester, screen: 'Dashboard (LOCAL_ONLY_DEV)');
    });

    testWidgets('empty install (no history) renders', (tester) async {
      final h = await pumpApp(tester, historyDays: 0);
      expect(h.history.days, isEmpty);
      expect(await h.db.allDaily(), isEmpty);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expectNoFlutterErrors(tester, screen: 'Dashboard (no data)');
    });

    testWidgets('"charging now" state is reachable', (tester) async {
      await pumpApp(tester, chargingNow: true);
      expect(find.textContaining(_en.chargingNow), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'Dashboard (charging)');
    });

    testWidgets('home: is pushed on top of the real start destination',
        (tester) async {
      await pumpApp(tester, home: const StatisticsScreen());
      expect(find.byType(StatisticsScreen), findsOneWidget);
      expect(find.byType(WattByteApp), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'Statistics');
    });

    testWidgets('the app sees the requested text scale, or its own clamp',
        (tester) async {
      // lib/app.dart clamps at 1.35 today and a teammate is removing that. The
      // harness must work both ways: what the app's screens see is either the
      // requested scale (no clamp) or 1.35 (clamp), and the platform itself is
      // always asked for exactly the requested one.
      late double seen;
      final h = await pumpApp(tester, home: Builder(builder: (context) {
        seen = MediaQuery.textScalerOf(context).scale(100) / 100;
        return const Scaffold(body: Text('probe'));
      }), textScale: 3.0);
      expect(tester.platformDispatcher.textScaleFactor, 3.0);
      expect(seen, anyOf(closeTo(3.0, 1e-9), closeTo(1.35, 1e-9)));

      await h.setTextScale(tester, 1.0);
      expect(seen, closeTo(1.0, 1e-9), reason: 'the probe rebuilds in place');
    });

    testWidgets('Android: per-app data screen gets the fake system rows',
        (tester) async {
      await pumpApp(tester,
          platform: HarnessPlatform.android, home: const DataByAppScreen());
      expect(find.text('YouTube'), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'Data by app');
    });

    testWidgets('tabs can be visited and the container is reachable',
        (tester) async {
      final h = await pumpApp(tester);
      for (var i = 1; i < 4; i++) {
        await h.tapTab(tester, i);
        expectNoFlutterErrors(tester, screen: 'tab $i');
      }
      expect(h.container(tester).read(settingsProvider).onboarded, isTrue);
    });
  });

  group('knobs reach the app', () {
    testWidgets('text scale, size, safe area, brightness, locale',
        (tester) async {
      final h = await pumpScreen(tester, const Text('probe'), scaffold: true);
      BuildContext probe() => tester.element(find.text('probe'));

      for (final scale in kTextScales) {
        await h.setTextScale(tester, scale);
        expect(MediaQuery.textScalerOf(probe()).scale(10),
            closeTo(10 * scale, 1e-9),
            reason: 'text scale $scale must arrive unclamped');
      }
      for (final screen in kScreenSizes) {
        await h.setDevice(tester, screen);
        final mq = MediaQuery.of(probe());
        expect(mq.size, screen.size, reason: '$screen');
        expect(mq.devicePixelRatio, screen.devicePixelRatio);
        expect(mq.padding.top, closeTo(screen.safeArea.top, 1e-9));
        expect(mq.padding.bottom, closeTo(screen.safeArea.bottom, 1e-9));
        expect(mq.padding.left, closeTo(screen.safeArea.left, 1e-9));
      }
      await h.setBrightness(tester, Brightness.dark);
      expect(Theme.of(probe()).brightness, Brightness.dark);
      await h.setBrightness(tester, Brightness.light);
      expect(Theme.of(probe()).brightness, Brightness.light);

      await h.setLocale(tester, const Locale('pl'));
      expect(Localizations.localeOf(probe()).languageCode, 'pl');
      expect(find.text('probe'), findsOneWidget);
    });

    testWidgets('locale changes the real app strings', (tester) async {
      await pumpApp(tester, signedIn: false, locale: const Locale('pl'));
      expect(find.text(_pl.signIn), findsOneWidget);
      expect(find.text(_en.signIn), findsNothing);
    });

    testWidgets('platform: iOS and Android personalities', (tester) async {
      final ios = await pumpApp(tester);
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      expect(ios.system.callsTo('interfaceCounters'), isNotEmpty);
      expect(ios.system.callsTo('ensureChargingWorker'), isNotEmpty,
          reason: 'the shell talks to the native side through the fake');
      expect((await ios.system.system.capabilities()).platform, 'ios');
      expectNoFlutterErrors(tester, screen: 'iOS dashboard');

      await tester.pumpWidget(const SizedBox());
      expect(defaultTargetPlatform, isNot(TargetPlatform.iOS),
          reason: 'the override is undone when the tree goes away');
    });

    testWidgets('platform: Android reads daily rows from the system',
        (tester) async {
      final h = await pumpApp(tester, platform: HarnessPlatform.android);
      expect(defaultTargetPlatform, TargetPlatform.android);
      expect(h.system.callsTo('queryDataDaily'), isNotEmpty);
      expect(h.system.callsTo('interfaceCounters'), isEmpty);
      expectNoFlutterErrors(tester, screen: 'Android dashboard');
    });

    testWidgets('a revoked Android permission shows in the UI', (tester) async {
      final h = await pumpApp(tester,
          platform: HarnessPlatform.android, andSettle: false);
      h.system.usageAccessGranted = false;
      await h
          .container(tester)
          .read(refreshControllerProvider)
          .refresh(locale: 'en');
      await settle(tester);
      expect(
          (await h.system.system.capabilities()).usageAccessGranted, isFalse);
      expectNoFlutterErrors(tester, screen: 'Android without usage access');
    });
  });

  group('the checks can fail', () {
    testWidgets('real fonts are active (text is not 1em squares)',
        (tester) async {
      // 24 characters at 16 px: ~190 px in Roboto, 384 px in the Ahem test font.
      await pumpScreen(
          tester,
          const Row(children: [
            Text('abcdefghijklmnopqrstuvwx', style: TextStyle(fontSize: 16)),
          ]),
          scaffold: true);
      expectNoFlutterErrors(tester, screen: 'real font width');
      expect(
          tester.getSize(find.byType(Text)).width, inExclusiveRange(150, 260));
    });

    testWidgets('overflow is detected, named, and stays detected',
        (tester) async {
      await pumpScreen(tester, _tooWide(),
          scaffold: true, size: const Size(375, 667));

      expect(
          () => expectNoFlutterErrors(tester, screen: 'Probe row'),
          _failureContaining([
            'Probe row',
            'textScale 1.0x',
            '375x667',
            'overflowing layout',
            'Row created at test/accessibility/harness_smoke_test.dart',
            'overflows by 125 px',
          ]));

      // Flutter reports an overflow once; the render-tree scan must still see it.
      expect(() => expectNoFlutterErrors(tester),
          _failureContaining(['overflows by 125 px']));
    });

    testWidgets('text that fits at 1.0 overflows at 3.0, in place',
        (tester) async {
      final h = await pumpScreen(
          tester,
          const Row(children: [
            Text('Wall energy estimate today', style: TextStyle(fontSize: 16)),
          ]),
          scaffold: true,
          size: const Size(375, 667));
      expectNoFlutterErrors(tester, screen: 'label @1.0');

      await h.setTextScale(tester, 3.0);
      expect(() => expectNoFlutterErrors(tester, screen: 'label @3.0'),
          _failureContaining(['label @3.0', 'textScale 3.0x', 'overflows by']));

      await h.setTextScale(tester, 1.0);
      expectNoFlutterErrors(tester, screen: 'label back at 1.0');
    });

    testWidgets('sweepViews reports every failing configuration',
        (tester) async {
      final h = await pumpScreen(
          tester,
          const Row(children: [
            Text('Wall energy estimate today', style: TextStyle(fontSize: 16)),
          ]),
          scaffold: true);
      var calls = 0;
      await _expectFailure(() async {
        await sweepViews(tester, h, () async {
          calls++;
          expectNoFlutterErrors(tester, screen: 'label');
        }, textScales: const [1.0, 3.0], devices: const [kIPhoneSE, kTablet]);
      }, ['failing view configuration', 'textScale 3.0x', '375x667']);
      expect(calls, 4);
    });

    testWidgets('overflow in a tab that is not visible is found too',
        (tester) async {
      await pumpScreen(tester,
          IndexedStack(index: 0, children: [const SizedBox(), _tooWide()]),
          scaffold: true, size: const Size(375, 667));
      expect(() => expectNoFlutterErrors(tester, screen: 'hidden tab'),
          _failureContaining(['hidden tab', 'overflows by 125 px']));
    });

    testWidgets('a fitting layout passes after a failing one', (tester) async {
      final h = await pumpScreen(tester, _tooWide(), scaffold: true);
      expect(() => expectNoFlutterErrors(tester), throwsA(isA<TestFailure>()));
      await pumpScreen(tester, const SizedBox(width: 100, height: 20),
          harness: h, scaffold: true);
      expectNoFlutterErrors(tester, screen: 'now it fits');
    });

    testWidgets('an exception while building is reported with its place',
        (tester) async {
      await pumpScreen(
          tester, Builder(builder: (_) => throw StateError('boom in build')),
          scaffold: true);
      expect(
          () => expectNoFlutterErrors(tester, screen: 'Exploding'),
          _failureContaining(
              ['Exploding', 'other Flutter error', 'boom in build']));
    });

    testWidgets('tap targets: too small / unlabeled fail, a good button passes',
        (tester) async {
      Future<void> pumpOne(Widget child) =>
          pumpScreen(tester, Center(child: child),
              scaffold: true, semantics: true);

      await pumpOne(Semantics(
          button: true,
          label: 'tiny',
          onTap: () {},
          child: const SizedBox(width: 20, height: 20)));
      await _expectFailure(
          () => expectAccessibleTargets(tester, screen: 'tiny button'),
          ['tiny button', 'Android tap target', 'iOS tap target']);

      await pumpOne(Semantics(
          button: true,
          onTap: () {},
          child: const SizedBox(width: 60, height: 60)));
      await _expectFailure(
          () => expectAccessibleTargets(tester, screen: 'no label'),
          ['no label', 'Labeled tap targets']);

      await pumpOne(FilledButton(onPressed: () {}, child: const Text('Save')));
      await expectAccessibleTargets(tester, screen: 'good button');
    });

    testWidgets('contrast guideline is opt-in and can fail', (tester) async {
      await pumpScreen(
          tester,
          const Center(
              child: Text('barely visible',
                  style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 18))),
          scaffold: true,
          semantics: true);
      await expectAccessibleTargets(tester, screen: 'default ignores contrast');
      await _expectFailure(
          () => expectAccessibleTargets(tester,
              screen: 'low contrast',
              android: false,
              ios: false,
              labeled: false,
              contrast: true),
          ['low contrast', 'Text contrast']);
    });

    testWidgets('semantics helpers find nodes by label', (tester) async {
      await pumpApp(tester, signedIn: false, semantics: true);
      final signIn = semanticsWithLabel(tester, _en.signIn);
      expect(signIn, hasLength(1));
      expect(signIn.single.tappable, isTrue);
      expect(signIn.single.size.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(_en.signUp), findsOneWidget);
      await expectAccessibleTargets(tester, screen: 'Welcome');
    });
  });

  group('isolation', () {
    // Order matters: the first test dirties everything the harness owns, the
    // second must find none of it.
    testWidgets('1/2 dirty the world', (tester) async {
      final h = await pumpScreen(tester, const Text('x'),
          platform: HarnessPlatform.android,
          textScale: 2.0,
          brightness: Brightness.dark,
          locale: const Locale('pl'),
          semantics: true,
          size: const Size(300, 500));
      await h.db.setMeta('leak', '1');
      await h.prefs.setString('leak', '1');
      h.system.batteryLevel = 3;
      h.backend.routes['GET /leak'] = (r) => FakeBackend.json({});
      expect(defaultTargetPlatform, TargetPlatform.android);
      // Deliberately no cleanup: semantics handle, platform override, view size.
    });

    testWidgets('2/2 nothing leaked', (tester) async {
      final h = await pumpApp(tester);
      expect(await h.db.meta('leak'), isNull);
      expect(h.prefs.getString('leak'), isNull);
      expect(h.system.batteryLevel, 78);
      expect(h.backend.routes.containsKey('GET /leak'), isFalse);
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      expect(tester.platformDispatcher.textScaleFactor, 1.0);
      expect(tester.view.physicalSize / tester.view.devicePixelRatio,
          kIPhone17Pro.size);
      expect(tester.platformDispatcher.platformBrightness, Brightness.light);
      expect(tester.platformDispatcher.locale.languageCode, 'en');
      expectNoFlutterErrors(tester, screen: 'Dashboard');
    });

    testWidgets('a second harness replaces the first, never shares its data',
        (tester) async {
      final first = await AppHarness.create(tester);
      await first.db.setMeta('mine', '1');

      final second = await AppHarness.create(tester);
      expect(await second.db.meta('mine'), isNull,
          reason: 'in-memory SQLite is one database per process; the first '
              'must have been closed, not shared');
      await expectLater(first.db.allDaily(), throwsA(anything),
          reason: 'the replaced harness fails loudly instead of sharing');
      expect((await second.db.allDaily()), hasLength(45));
    });

    testWidgets('pumping again with a new harness gets a fresh container',
        (tester) async {
      final a = await pumpScreen(tester, const Text('a'), scaffold: true);
      final b = await pumpScreen(tester, const Text('b'), scaffold: true);
      expect(identical(a, b), isFalse);
      expect(b.container(tester).read(settingsProvider).onboarded, isTrue);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('a'), findsNothing);
    });
  });

  group('seed data', () {
    testWidgets('is deterministic per day offset, not per calendar date',
        (tester) async {
      final h = await AppHarness.create(tester, historyDays: 0);
      final noon = DateTime(2026, 10, 13, 12);

      final a = await seedHistory(h.db, days: 30, now: noon);
      await h.db.resetAll();
      final b = await seedHistory(h.db, days: 30, now: noon);
      expect(
          [for (final d in a.days) d.total], [for (final d in b.days) d.total]);
      expect(a.sessions.length, b.sessions.length);

      // Another "today", same offsets -> same numbers.
      await h.db.resetAll();
      final shifted =
          await seedHistory(h.db, days: 30, now: DateTime(2026, 12, 2, 12));
      expect([for (final d in a.days) d.total],
          [for (final d in shifted.days) d.total]);

      // More history leaves the recent days untouched.
      await h.db.resetAll();
      final longer = await seedHistory(h.db, days: 60, now: noon);
      expect([for (final d in longer.days.skip(30)) d.total],
          [for (final d in a.days) d.total]);
    });

    testWidgets('is realistic: past sessions, plausible bytes, both platforms',
        (tester) async {
      final h = await AppHarness.create(tester, historyDays: 0);
      final now = DateTime(2026, 10, 13, 12);
      final seeded = await seedHistory(h.db,
          days: 45,
          now: now,
          estimated: false,
          measuredEnergy: true,
          capacityMah: 4575);
      for (final s in seeded.sessions) {
        expect(s.end.isAfter(now), isFalse, reason: 'a session in the future');
        expect(s.end.isBefore(s.start), isFalse);
        expect(s.endLevel, greaterThan(s.startLevel));
        expect(s.chargeDeltaUah, isNotNull);
        expect(s.energyDeltaNwh, isNotNull);
      }
      for (final d in seeded.days) {
        expect(d.mobile, inInclusiveRange(1 << 20, 2 * 1024 * 1024 * 1024));
        expect(d.wifi, inInclusiveRange(1 << 20, 10 * 1024 * 1024 * 1024));
        expect(d.estimated, isFalse);
      }
      expect(seeded.days.last.day, DateTime(2026, 10, 13));
      expect(seeded.days.first.day, DateTime(2026, 8, 30));
    });
  });

  group('app is a ProviderScope root', () {
    testWidgets(
        'harness overrides are the only edge: nothing touches the network',
        (tester) async {
      final h = await pumpApp(tester);
      await h
          .container(tester)
          .read(refreshControllerProvider)
          .refresh(locale: 'en');
      // The fake backend saw whatever the app asked; unscripted routes are 404s,
      // never a real request (flutter_test would answer those with 400).
      expect(h.backend.requests.every((r) => r.path.startsWith('/api/v1/')),
          isTrue);
    });
  });
}
