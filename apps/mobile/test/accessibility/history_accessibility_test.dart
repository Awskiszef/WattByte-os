// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// History (Data / Charging / Energy tabs and the session sheet) at every text
// size, phone, theme and language; what a screen reader says about its rows;
// touch targets; contrast.
//
// Before the work these tests guard, the charging rows overflowed at 3.0x
// (history_screen.dart:218, a Row of icon + text + value, by 26 to 53 px) and
// the session sheet had no way to scroll.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/history/history_screen.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

enum _Tab { data, charging, energy }

String _tabLabel(_Tab t, {bool pl = false}) {
  final l = pl ? _pl : _en;
  return switch (t) {
    _Tab.data => l.historyData,
    _Tab.charging => l.historyCharging,
    _Tab.energy => l.historyEnergy,
  };
}

Future<AppHarness> _pump(
  WidgetTester tester, {
  HarnessPlatform platform = HarnessPlatform.ios,
  int historyDays = 45,
  Locale locale = const Locale('en'),
  bool semantics = false,
  bool andSettle = true,
  bool tall = false,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) =>
    pumpScreen(tester, const HistoryScreen(),
        scaffold: true,
        accessibilityFeatures: accessibilityFeatures,
        platform: platform,
        historyDays: historyDays,
        locale: locale,
        semantics: semantics,
        andSettle: andSettle,
        size: tall ? const Size(402, 3000) : null);

/// Opens [tab] in whatever layout the selector currently has.
Future<void> _open(WidgetTester tester, _Tab tab, {bool pl = false}) async {
  await tester.tap(find.text(_tabLabel(tab, pl: pl)));
  await settle(tester);
}

Future<void> _check(WidgetTester tester, String screen) =>
    expectLayoutHealthy(tester, screen);

final _hm = DateFormat.Hm('en');

void main() {
  group('layout: every text scale x phone x theme x language', () {
    for (final tab in _Tab.values) {
      for (final android in [false, true]) {
        final name = '${tab.name} tab, ${android ? 'Android' : 'iPhone'}';
        testWidgets(name, (tester) async {
          final h = await _pump(tester,
              platform:
                  android ? HarnessPlatform.android : HarnessPlatform.ios);
          await _open(tester, tab);
          await sweepLayouts(tester, h,
              screen: 'History ($name)',
              positions: 4,
              check: () => _check(tester, 'History ($name)'));
        });
      }
      testWidgets('${tab.name} tab, new install (empty state)', (tester) async {
        final h = await _pump(tester, historyDays: 0);
        await _open(tester, tab);
        expect(find.text(tab == _Tab.data ? _en.noDataYet : _en.noSessionsYet),
            findsOneWidget);
        await sweepLayouts(tester, h,
            screen: 'History (${tab.name}, empty)',
            check: () => _check(tester, 'History (${tab.name}, empty)'));
      });
    }

    testWidgets('error state fits too', (tester) async {
      final h = await _pump(tester);
      await h.db.close();
      h.container(tester).read(refreshTickProvider.notifier).state++;
      await settle(tester);
      expect(find.text(_en.genericError), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'History (error)',
          check: () => _check(tester, 'History (error)'));
    });

    testWidgets('loading state fits too', (tester) async {
      final h = await _pump(tester, andSettle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'History (loading)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'History (loading)'));
    });

    testWidgets('the session sheet fits and scrolls at every size',
        (tester) async {
      final h = await _pump(tester);
      await _open(tester, _Tab.charging);
      await tester.tap(find.byType(WbCard).first);
      await settle(tester);
      expect(find.text(_en.sessionTitle), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Session sheet',
          positions: 3,
          scrollable: find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable)), check: () async {
        await _check(tester, 'Session sheet');
        // Everything in the sheet can be reached by scrolling it.
        await tester.scrollUntilVisible(find.text(_en.cost), 100,
            scrollable: find
                .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable))
                .first);
      });
    });
  });

  group('layout: wide screens must not throw', () {
    for (final tab in _Tab.values) {
      testWidgets('${tab.name} tab', (tester) async {
        final h = await _pump(tester);
        await _open(tester, tab);
        await sweepLayouts(tester, h,
            screen: 'History wide (${tab.name})',
            devices: kWideScreens,
            scales: kWideScales,
            brightnesses: const [Brightness.light],
            positions: 3,
            check: () => _check(tester, 'History wide (${tab.name})'));
      });
    }
  });

  group('bold text (iOS "Bold Text", Android bold fonts)', () {
    for (final tab in _Tab.values) {
      testWidgets('${tab.name} tab widens every text and still fits',
          (tester) async {
        final h = await _pump(tester,
            accessibilityFeatures:
                const FakeAccessibilityFeatures(boldText: true));
        await _open(tester, tab);
        await sweepLayouts(tester, h,
            screen: 'History bold (${tab.name})',
            scales: const [1.0, 1.6, 3.0],
            brightnesses: const [Brightness.light],
            positions: 3,
            check: () => _check(tester, 'History bold (${tab.name})'));
      });
    }
  });

  group('semantics', () {
    testWidgets(
        'the title is a heading; the tabs are buttons that know which is selected',
        (tester) async {
      await _pump(tester, semantics: true);
      var tree = semanticsTree(tester);
      expect(tree.where((n) => n.header).map((n) => n.label),
          contains(_en.tabHistory));
      SemNode tab(_Tab t) =>
          tree.firstWhere((n) => n.label.startsWith(_tabLabel(t)));
      expect(_Tab.values.map((t) => tab(t).selected),
          [false, true, false]); // charging is the default tab
      expect(_Tab.values.every((t) => tab(t).tappable), isTrue);

      await _open(tester, _Tab.energy);
      tree = semanticsTree(tester);
      expect(_Tab.values.map((t) => tab(t).selected), [false, false, true]);
    });

    testWidgets('a charging row is ONE button with times, levels, energy',
        (tester) async {
      final h = await _pump(tester, semantics: true, tall: true);
      final last = h.history.sessions.last;
      final tree = semanticsTree(tester);

      final row = oneNodeWith(tree, [
        'Charging from ${_hm.format(last.start)} to ${_hm.format(last.end)}',
        'battery ${last.startLevel}% to ${last.endLevel}%',
        'mAh',
        'Wh',
      ]);
      expect(row.tappable && row.button, isTrue);
      expect(row.spoken, contains(_en.estimated),
          reason: 'iPhone sessions are estimates');
      expect(row.spoken, isNot(contains('~')));
      expect(row.spoken, isNot(contains('→')),
          reason: 'arrows are read as "rightwards arrow"');
      // The day is a heading of its own.
      expect(
          tree.where((n) => n.header).map((n) => n.label), contains(_en.today));
    });

    testWidgets('the same row in Polish', (tester) async {
      final h = await _pump(tester,
          semantics: true, tall: true, locale: const Locale('pl'));
      final last = h.history.sessions.last;
      oneNodeWith(semanticsTree(tester), [
        'Ładowanie od ${_hm.format(last.start)} do ${_hm.format(last.end)}',
        'bateria z ${last.startLevel}% do ${last.endLevel}%',
        _pl.estimated,
      ]);
    });

    testWidgets('a measured session (Android) does not say Estimated',
        (tester) async {
      final h = await _pump(tester,
          platform: HarnessPlatform.android, semantics: true, tall: true);
      final last = h.history.sessions.last;
      final prefix = 'Charging from ${_hm.format(last.start)} to '
          '${_hm.format(last.end)}, battery ${last.startLevel}%';
      // The newest session is the first row (rows are newest first).
      final row = semanticsTree(tester)
          .firstWhere((n) => n.tappable && n.spoken.startsWith(prefix));
      expect(row.spoken, isNot(contains(_en.estimated)));
      expect(row.spoken, contains('mAh'));
    });

    testWidgets('the session sheet reads one fact per line, with Estimated',
        (tester) async {
      await _pump(tester, semantics: true, tall: true);
      await tester.tap(find.byType(WbCard).first);
      await settle(tester);
      final tree = semanticsTree(tester);
      expect(tree.where((n) => n.header).map((n) => n.label),
          contains(_en.sessionTitle));
      final charge =
          oneNodeWith(tree, ['${_en.charge}, ', 'mAh', _en.estimated]);
      expect(charge.spoken, isNot(contains('~')));
      oneNodeWith(tree, [_en.batteryEnergy, 'Wh', _en.estimated]);
      oneNodeWith(tree, [_en.wallEnergy, 'Wh', _en.estimated]);
      oneNodeWith(tree, ['${_en.cost}, ', _en.estimated]);
      oneNodeWith(tree, [_en.duration, ' min']);
    });

    testWidgets('the data tab: one node per day', (tester) async {
      final h = await _pump(tester, semantics: true, tall: true);
      await _open(tester, _Tab.data);
      final today = h.history.days.last;
      const u = Units(locale: 'en');
      final row = oneNodeWith(semanticsTree(tester), [
        _en.today,
        u.bytes(today.total),
        '${_en.mobile} ${u.bytes(today.mobile)}'
      ]);
      expect(row.spoken, contains(_en.estimated));
      expect(row.spoken, contains('${_en.wifi} ${u.bytes(today.wifi)}'));
      expect(row.spoken, isNot(contains('·')));
    });

    testWidgets('the energy tab: one node per day', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      await _open(tester, _Tab.energy);
      final tree = semanticsTree(tester);
      final row = oneNodeWith(tree, [_en.today, _en.batteryEnergy, 'kWh']);
      expect(row.spoken, contains(_en.estimated));
      expect(row.spoken, isNot(contains('~')));
    });

    testWidgets('empty tabs are announced', (tester) async {
      await _pump(tester, historyDays: 0, semantics: true);
      for (final tab in _Tab.values) {
        await _open(tester, tab);
        final empty = oneNodeWith(semanticsTree(tester),
            [tab == _Tab.data ? _en.noDataYet : _en.noSessionsYet]);
        expect(empty.liveRegion, isTrue, reason: tab.name);
      }
    });

    testWidgets('loading is labelled', (tester) async {
      await _pump(tester, semantics: true, andSettle: false);
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);
    });
  });

  group('touch targets (Android 48 px, iOS 44 px, labelled)', () {
    for (final tab in _Tab.values) {
      testWidgets('${tab.name} tab', (tester) async {
        final h = await _pump(tester, semantics: true);
        await _open(tester, tab);
        await sweepLayouts(tester, h,
            screen: 'History targets (${tab.name})',
            brightnesses: const [Brightness.light],
            positions: 3, check: () async {
          await expectAccessibleTargets(tester,
              screen: 'History (${tab.name})');
          final problems = tappableProblems(tester, semanticsTree(tester));
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      });
    }

    testWidgets('session sheet', (tester) async {
      final h = await _pump(tester, semantics: true);
      await _open(tester, _Tab.charging);
      await tester.tap(find.byType(WbCard).first);
      await settle(tester);
      await sweepLayouts(tester, h,
          screen: 'Session sheet targets',
          brightnesses: const [Brightness.light],
          check: () =>
              expectAccessibleTargets(tester, screen: 'Session sheet'));
    });
  });

  group('contrast (light and dark)', () {
    for (final tab in _Tab.values) {
      testWidgets('${tab.name} tab', (tester) async {
        final h = await _pump(tester, semantics: true);
        await _open(tester, tab);
        await sweepLayouts(tester, h,
            screen: 'History contrast (${tab.name})',
            scales: const [1.0, 2.0],
            devices: const [kIPhoneSE],
            locales: const [Locale('en')],
            positions: 3,
            settleFully: true, check: () async {
          expectTextContrast(tester, screen: 'History (${tab.name})');
          await expectAccessibleTargets(tester,
              screen: 'History (${tab.name})',
              android: false,
              ios: false,
              labeled: false,
              contrast: true);
        });
      });
    }
  });
}
