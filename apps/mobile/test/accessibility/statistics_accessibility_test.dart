// Statistics (periods, charging, energy, records) at every text size, phone,
// theme and language; what a screen reader says; touch targets; contrast.
//
// Note: the AppBar title keeps Flutter's own cap (1.34x, `AppBar` clamps its
// title so it stays in its fixed-height bar); everything below the bar follows
// the system text size in full.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/statistics/statistics_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

Future<AppHarness> _pump(
  WidgetTester tester, {
  HarnessPlatform platform = HarnessPlatform.ios,
  int historyDays = 45,
  bool noPrice = false,
  Locale locale = const Locale('en'),
  bool semantics = false,
  bool andSettle = true,
  bool tall = false,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) {
  var settings = AppHarness.defaultSettings(platform);
  if (noPrice) {
    settings = settings.copyWith(
        pricePerKwh: 0,
        manualPricePerKwh: 0,
        priceMode: ElectricityPriceMode.manual,
        clearAutoPrice: true);
  }
  return pumpScreen(tester, const StatisticsScreen(),
      platform: platform,
      settings: settings,
      historyDays: historyDays,
      locale: locale,
      semantics: semantics,
      andSettle: andSettle,
      accessibilityFeatures: accessibilityFeatures,
      size: tall ? const Size(402, 3400) : null);
}

Future<void> _check(WidgetTester tester, String screen) =>
    expectLayoutHealthy(tester, screen);

void main() {
  group('layout: every text scale x phone x theme x language', () {
    for (final (name, platform, days, noPrice) in const [
      ('iPhone, seeded history', HarnessPlatform.ios, 45, false),
      ('Android, measured energy', HarnessPlatform.android, 45, false),
      ('new install: no records', HarnessPlatform.ios, 0, false),
      ('no electricity price', HarnessPlatform.ios, 45, true),
    ]) {
      testWidgets(name, (tester) async {
        final h = await _pump(tester,
            platform: platform, historyDays: days, noPrice: noPrice);
        expect(find.text(_en.internet), findsOneWidget);
        await sweepLayouts(tester, h,
            screen: 'Statistics ($name)',
            positions: 5,
            check: () => _check(tester, 'Statistics ($name)'));
      });
    }

    testWidgets('every period chip', (tester) async {
      final h = await _pump(tester);
      for (final label in [
        _en.periodLast7Days,
        _en.periodLastMonth,
        _en.periodThisYear,
        _en.periodAllTime,
        _en.periodThisMonth,
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await settle(tester);
        await sweepLayouts(tester, h,
            screen: 'Statistics ($label)',
            scales: const [1.0, 3.0],
            brightnesses: const [Brightness.light],
            check: () => _check(tester, 'Statistics ($label)'));
        // Back to English / 1.0 for the next chip.
        await applyView(tester, h,
            textScale: 1.0,
            device: kIPhone17Pro,
            brightness: Brightness.light,
            locale: const Locale('en'));
      }
    });

    testWidgets('loading and error states', (tester) async {
      var h = await _pump(tester, andSettle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Statistics (loading)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'Statistics (loading)'));

      h = await _pump(tester);
      await h.db.close();
      h.container(tester).read(refreshTickProvider.notifier).state++;
      await settle(tester);
      expect(find.text(_en.genericError), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Statistics (error)',
          check: () => _check(tester, 'Statistics (error)'));
    });
  });

  group('layout: wide screens must not throw', () {
    testWidgets('iPhone and Android data', (tester) async {
      for (final platform in HarnessPlatform.values) {
        final h = await _pump(tester, platform: platform);
        await sweepLayouts(tester, h,
            screen: 'Statistics wide (${platform.name})',
            devices: kWideScreens,
            scales: kWideScales,
            brightnesses: const [Brightness.light],
            positions: 4,
            check: () => _check(tester, 'Statistics wide'));
      }
    });
  });

  group('bold text (iOS "Bold Text", Android bold fonts)', () {
    testWidgets('widens every text and still fits', (tester) async {
      final h = await _pump(tester,
          accessibilityFeatures:
              const FakeAccessibilityFeatures(boldText: true));
      await sweepLayouts(tester, h,
          screen: 'Statistics bold',
          scales: const [1.0, 1.6, 3.0],
          brightnesses: const [Brightness.light],
          positions: 5,
          check: () => _check(tester, 'Statistics bold'));
    });
  });

  group('semantics', () {
    testWidgets('title and section titles are headings', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      final headers = semanticsTree(tester)
          .where((n) => n.header)
          .map((n) => n.label)
          .toList();
      expect(
          headers,
          containsAll([
            _en.statistics,
            _en.internet,
            _en.charging,
            _en.energy,
            _en.records
          ]));
    });

    testWidgets('a period is ONE node: label, total, Estimated, split',
        (tester) async {
      final h = await _pump(tester, semantics: true, tall: true);
      const u = Units(locale: 'en');
      final today = h.history.days.last;
      final row = oneNodeWith(semanticsTree(tester), [
        _en.periodToday,
        u.bytes(today.total),
        '${_en.mobile} ${u.bytes(today.mobile)}',
      ]);
      expect(row.spoken, contains(_en.estimated));
      expect(row.spoken, contains('${_en.wifi} ${u.bytes(today.wifi)}'));
      expect(row.spoken, isNot(contains('~')));
      expect(row.spoken, isNot(contains('·')),
          reason: 'middle dots are read aloud');
    });

    testWidgets('charging and energy facts are one node each', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      final tree = semanticsTree(tester);
      oneNodeWith(tree, [_en.sessionsCount]);
      oneNodeWith(tree, [_en.avgDuration, ' min']);
      oneNodeWith(tree, [_en.avgAdded, '%']);
      final charge = oneNodeWith(tree, [_en.totalMah, 'mAh', _en.estimated]);
      expect(charge.spoken, isNot(contains('~')));
      oneNodeWith(tree, [_en.batteryEnergy, 'Wh', _en.estimated]);
      oneNodeWith(tree, [_en.wallEnergy, 'Wh', _en.estimated]);
      oneNodeWith(tree, ['kWh, ', _en.estimated]);
      oneNodeWith(tree, [_en.electricityCost, 'zł', _en.estimated]);
    });

    testWidgets('without a price the cost says "Not set", not an estimate',
        (tester) async {
      await _pump(tester, noPrice: true, semantics: true, tall: true);
      final cost =
          oneNodeWith(semanticsTree(tester), [_en.electricityCost, _en.notSet]);
      expect(cost.spoken, isNot(contains(_en.estimated)));
    });

    testWidgets('records: title, value and date in one node', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      final tree = semanticsTree(tester);
      final most = oneNodeWith(tree, [_en.recordMostDataDay, ' GB']);
      expect(most.spoken, matches(RegExp(r'\d{4}'))); // the date
      oneNodeWith(tree, [_en.recordLongestSession, ' min']);
      final energyDay = oneNodeWith(tree, [_en.recordMostEnergyDay, 'Wh']);
      expect(energyDay.spoken, isNot(contains('~')));
    });

    testWidgets('no records yet is announced', (tester) async {
      await _pump(tester, historyDays: 0, semantics: true, tall: true);
      final empty = oneNodeWith(semanticsTree(tester), [_en.noRecordsYet]);
      expect(empty.liveRegion, isTrue);
    });

    testWidgets('period chips are buttons that know which is selected',
        (tester) async {
      await _pump(tester, semantics: true, tall: true);
      var tree = semanticsTree(tester);
      final chips = {
        for (final l in [
          _en.periodLast7Days,
          _en.periodThisMonth,
          _en.periodLastMonth,
          _en.periodThisYear,
          _en.periodAllTime
        ])
          l: tree.firstWhere((n) => n.label == l && n.tappable)
      };
      expect(chips.values.every((n) => n.tappable), isTrue);
      expect(chips.entries.where((e) => e.value.selected).map((e) => e.key),
          [_en.periodThisMonth]);

      await tester.tap(find.text(_en.periodLastMonth));
      await settle(tester);
      tree = semanticsTree(tester);
      expect(
          tree
              .where((n) => n.tappable && n.selected)
              .map((n) => n.label)
              .toList(),
          [_en.periodLastMonth]);
    });

    testWidgets('Polish', (tester) async {
      await _pump(tester,
          semantics: true, tall: true, locale: const Locale('pl'));
      final tree = semanticsTree(tester);
      expect(tree.where((n) => n.header).map((n) => n.label),
          containsAll([_pl.statistics, _pl.internet, _pl.records]));
      oneNodeWith(tree, [_pl.periodToday, _pl.estimated]);
    });

    testWidgets('loading is labelled; the back button is a labelled button',
        (tester) async {
      await _pump(tester, semantics: true, andSettle: false);
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);
    });
  });

  group('touch targets (Android 48 px, iOS 44 px, labelled)', () {
    testWidgets('seeded history', (tester) async {
      final h = await _pump(tester, semantics: true);
      await sweepLayouts(tester, h,
          screen: 'Statistics targets',
          brightnesses: const [Brightness.light],
          positions: 5, check: () async {
        await expectAccessibleTargets(tester, screen: 'Statistics');
        final problems = tappableProblems(tester, semanticsTree(tester));
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    });
  });

  group('contrast (light and dark)', () {
    testWidgets('seeded history', (tester) async {
      final h = await _pump(tester, semantics: true);
      await sweepLayouts(tester, h,
          screen: 'Statistics contrast',
          scales: const [1.0, 2.0],
          devices: const [kIPhoneSE],
          positions: 5,
          settleFully: true, check: () async {
        expectTextContrast(tester, screen: 'Statistics');
        await expectAccessibleTargets(tester,
            screen: 'Statistics',
            android: false,
            ios: false,
            labeled: false,
            contrast: true);
      });
    });
  });
}
