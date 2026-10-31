// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The shell: the bottom NavigationBar at every text size, phone, theme and
// language, how it reads to a screen reader, and the three data tabs inside the
// REAL app (theme, l10n, the real text scaling in lib/app.dart).
//
// Policy for the NavigationBar at huge text sizes (documented here because it
// is a deliberate choice, not an accident):
//   * Flutter's NavigationBar draws its labels at the system text size up to
//     1.3x and no further ("_kMaxLabelTextScaleFactor"): the bar keeps its
//     height and four labels stay side by side on a 375 px phone ("Ustawienia"
//     at 3x would be 190 px wide). That cap is Material 3's own design and is
//     kept; ShellScreen does not add any other clamp.
//   * The labels never disappear and are never cut: all four stay visible, the
//     longest ("Ustawienia") fits its quarter of the screen.
//   * The full text size is still available: a screen reader reads the label
//     and "Tab n of 4" with the selected state, and a long press shows the
//     tooltip (the label) at the FULL system text size.
//   * Every destination is a 94 x 68 touch target on the smallest phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/dashboard/dashboard_screen.dart';
import 'package:wattbyte/ui/history/history_screen.dart';
import 'package:wattbyte/ui/insights/insights_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

Finder get _nav => find.byType(NavigationBar);

Future<void> _checkNav(WidgetTester tester, String screen) async {
  final problems = [
    ...overflowProblems(tester, within: _nav),
    ...textProblems(tester, within: _nav),
  ];
  if (problems.isNotEmpty) {
    fail('$screen: ${problems.map((p) => '  - $p').join('\n')}');
  }
  // All four destinations on screen, side by side, inside the phone.
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final rects = [
    for (final d in tester.widgetList(find.byType(NavigationDestination)))
      tester.getRect(find.byWidget(d))
  ];
  expect(rects, hasLength(4));
  for (var i = 0; i < rects.length; i++) {
    expect(rects[i].left, greaterThanOrEqualTo(-0.5));
    expect(rects[i].right, lessThanOrEqualTo(width + 0.5));
    expect(rects[i].width, greaterThanOrEqualTo(44));
    expect(rects[i].height, greaterThanOrEqualTo(48));
    if (i > 0) {
      expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right - 0.5));
    }
  }
}

void main() {
  group('NavigationBar layout', () {
    testWidgets('every text scale x phone x theme x language', (tester) async {
      final h = await pumpApp(tester);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await sweepLayouts(tester, h,
          screen: 'NavigationBar',
          check: () => _checkNav(tester, 'NavigationBar'));
    });

    testWidgets('wide screens must not throw', (tester) async {
      final h = await pumpApp(tester);
      await sweepLayouts(tester, h,
          screen: 'NavigationBar wide',
          devices: kWideScreens,
          scales: kWideScales,
          brightnesses: const [Brightness.light],
          check: () => _checkNav(tester, 'NavigationBar wide'));
    });

    testWidgets('labels grow with the text size but stop at 1.3x',
        (tester) async {
      final h = await pumpApp(tester, device: kIPhoneSE);
      double labelHeight() => tester.getSize(find.text(_en.tabSettings)).height;
      await h.setTextScale(tester, 1.0);
      final base = labelHeight();
      await h.setTextScale(tester, 1.15);
      expect(labelHeight(), greaterThan(base), reason: 'follows the setting');
      for (final scale in [1.35, 1.6, 2.0, 3.0]) {
        await h.setTextScale(tester, scale);
        expect(labelHeight(), closeTo(base * 1.3, 1.5),
            reason: 'capped by Material at 1.3x, scale $scale');
      }
    });

    testWidgets('the whole app (all tabs) fits at every size, both languages',
        (tester) async {
      final h = await pumpApp(tester);
      await sweepLayouts(tester, h,
          screen: 'whole app',
          brightnesses: const [Brightness.light],
          check: () async => expectNoFlutterErrors(tester, screen: 'app'));
    });
  });

  group('NavigationBar semantics', () {
    testWidgets('four buttons, "Tab n of 4", the selected one is marked',
        (tester) async {
      await pumpApp(tester, semantics: true);
      final tree = semanticsTree(tester);
      for (final (i, name) in [
        _en.tabDashboard,
        _en.tabHistory,
        _en.tabInsights,
        _en.tabSettings
      ].indexed) {
        final tab = oneNodeWith(tree, [name, 'Tab ${i + 1} of 4']);
        expect(tab.tappable && tab.button, isTrue, reason: name);
        expect(tab.selected, i == 0, reason: name);
        expect(tab.rect.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('Polish labels, and tapping selects another tab',
        (tester) async {
      final h =
          await pumpApp(tester, semantics: true, locale: const Locale('pl'));
      var tree = semanticsTree(tester);
      for (final name in [
        _pl.tabDashboard,
        _pl.tabHistory,
        _pl.tabInsights,
        _pl.tabSettings
      ]) {
        oneNodeWith(tree, [name, ' z 4']);
      }
      await h.tapTab(tester, 2);
      tree = semanticsTree(tester);
      expect(
          tree
              .where((n) => n.tappable && n.selected)
              .map((n) => n.spoken)
              .toList(),
          [contains(_pl.tabInsights)]);
    });

    testWidgets('a long press shows the label at the full text size',
        (tester) async {
      await pumpApp(tester, textScale: 3.0, device: kIPhoneSE);
      final barLabel = tester.getSize(find.text(_en.tabHistory)).height;
      await tester.longPress(find.byType(NavigationDestination).at(1));
      await tester.pump(const Duration(milliseconds: 600));
      final labels = find.text(_en.tabHistory);
      expect(labels, findsNWidgets(2), reason: 'bar label + tooltip');
      final tooltipHeight = tester.getSize(labels.last).height;
      expect(tooltipHeight, greaterThan(barLabel * 1.5),
          reason: 'the tooltip is not capped at 1.3x');
    });
  });

  group('the data tabs inside the real app', () {
    for (final (index, name, screen) in [
      (0, 'Dashboard', find.byType(DashboardScreen)),
      (1, 'History', find.byType(HistoryScreen)),
      (2, 'Insights', find.byType(InsightsScreen)),
    ]) {
      testWidgets('$name fits at every size, in every theme and language',
          (tester) async {
        final h = await pumpApp(tester, semantics: true);
        await h.tapTab(tester, index);
        await sweepLayouts(tester, h, screen: 'App: $name tab', positions: 3,
            check: () async {
          final problems = [
            ...overflowProblems(tester, within: screen),
            ...textProblems(tester, within: screen),
            ...tappableProblems(tester, semanticsTree(tester)),
          ];
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      });

      testWidgets('$name has readable text in both themes (real app)',
          (tester) async {
        final h = await pumpApp(tester, semantics: true);
        await h.tapTab(tester, index);
        await sweepLayouts(tester, h,
            screen: 'App: $name contrast',
            scales: const [1.0, 2.0],
            devices: const [kIPhoneSE],
            locales: const [Locale('en')],
            positions: 2,
            settleFully: true, // theme and ink animations finish first
            check: () async =>
                expectTextContrast(tester, screen: 'App: $name tab'));
      });

      testWidgets('$name: touch targets incl. the bar (48 / 44 px)',
          (tester) async {
        final h = await pumpApp(tester, semantics: true);
        await h.tapTab(tester, index);
        await sweepLayouts(tester, h,
            screen: 'App: $name targets',
            scales: const [1.0, 2.0, 3.0],
            brightnesses: const [Brightness.light],
            locales: const [Locale('en')],
            check: () => expectAccessibleTargets(tester, screen: 'App: $name'));
      });
    }
  });
}
