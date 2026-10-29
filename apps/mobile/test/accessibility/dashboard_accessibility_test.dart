// The Dashboard at every text size, on both phones, in both themes and both
// languages, with every kind of data it can show; what a screen reader says
// about it; its touch targets; its contrast.
//
// Before the work these tests guard, DashboardScreen overflowed on an iPhone SE
// at 1.6x (dashboard_screen.dart:353 by 8.6 px), at 2.0x (:324 by 13 px and
// :353 by 80 px) and at 3.0x (:174, :324, :353, up to 258 px), always in Rows
// whose children did not fit side by side.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/dashboard/dashboard_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// One kind of data the dashboard can be showing.
class _Scenario {
  const _Scenario(
    this.name, {
    this.platform = HarnessPlatform.ios,
    this.historyDays = 45,
    this.chargingNow = false,
    this.noPrice = false,
    this.manualPrice = false,
    this.unknownCapacity = false,
    this.noUsageAccess = false,
  });

  final String name;
  final HarnessPlatform platform;
  final int historyDays;
  final bool chargingNow;
  final bool noPrice;
  final bool manualPrice;
  final bool unknownCapacity;
  final bool noUsageAccess;

  Settings settings() {
    var s = AppHarness.defaultSettings(platform);
    if (noPrice) {
      s = s.copyWith(
          pricePerKwh: 0,
          manualPricePerKwh: 0,
          priceMode: ElectricityPriceMode.manual,
          clearAutoPrice: true);
    }
    if (manualPrice) {
      s = s.copyWith(
          pricePerKwh: 0.9,
          manualPricePerKwh: 0.9,
          priceMode: ElectricityPriceMode.manual);
    }
    if (unknownCapacity) {
      // Nothing is known about the nominal capacity of this model: no number,
      // no "typical" figure, no estimate standing in for it.
      s = s.withDesignCapacity(DesignCapacity.unknown);
    }
    return s;
  }
}

const _scenarios = <_Scenario>[
  _Scenario('iPhone, seeded history (estimated data)'),
  _Scenario('iPhone, charging now', chargingNow: true),
  _Scenario('new install, no data', historyDays: 0),
  _Scenario('Android, measured energy, Data by app',
      platform: HarnessPlatform.android),
  _Scenario('Android without usage access',
      platform: HarnessPlatform.android, noUsageAccess: true),
  _Scenario('no electricity price, unknown battery capacity',
      noPrice: true, unknownCapacity: true),
  _Scenario('own tariff (label without "Estimated")', manualPrice: true),
];

Future<AppHarness> _pump(
  WidgetTester tester,
  _Scenario s, {
  double textScale = 1.0,
  ScreenSpec device = kIPhone17Pro,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  bool semantics = false,
  bool andSettle = true,

  /// A screen so tall that the whole dashboard is on it: a screen reader only
  /// sees what is on screen, and the tests of what it says need all of it.
  bool tall = false,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) async {
  final system = FakeSystem(
    platform: s.platform,
    usageAccessGranted: !s.noUsageAccess,
    chargeCounterMah: s.platform.isIos ? null : 4575 * 0.78,
  );
  final h = await AppHarness.create(tester,
      platform: s.platform,
      settings: s.settings(),
      historyDays: s.historyDays,
      chargingNow: s.chargingNow,
      locale: locale,
      system: system);
  return pumpScreen(tester, const DashboardScreen(),
      harness: h,
      scaffold: true,
      textScale: textScale,
      device: device,
      size: tall ? const Size(402, 3400) : null,
      brightness: brightness,
      locale: locale,
      semantics: semantics,
      andSettle: andSettle,
      accessibilityFeatures: accessibilityFeatures);
}

Future<void> _check(WidgetTester tester, String screen) =>
    expectLayoutHealthy(tester, screen, semantics: false);

/// The day labels under the bars of both charts that are not drawn whole: a
/// paragraph shorter than its text (it clips the bottom of the glyphs) or one
/// reaching below or above its chart.
List<String> _chartLabelProblems(WidgetTester tester) {
  final charts = find.byType(BarChart).evaluate().toList();
  final out = <String>[
    if (charts.length != 2) 'expected 2 charts, found ${charts.length}',
  ];
  for (final chart in charts) {
    final box = chart.renderObject! as RenderBox;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    var labels = 0;
    void visit(RenderObject r) {
      if (r is RenderParagraph && r.hasSize) {
        labels++;
        final text = r.text.toPlainText();
        final needed = r.getMaxIntrinsicHeight(r.size.width);
        if (r.size.height + 0.5 < needed) {
          out.add('"$text" is cut off at the bottom: '
              '${r.size.height.toStringAsFixed(1)} px tall, its text needs '
              '${needed.toStringAsFixed(1)} px');
        }
        final rect = r.localToGlobal(Offset.zero) & r.size;
        if (rect.top < bounds.top - 0.5 || rect.bottom > bounds.bottom + 0.5) {
          out.add('"$text" reaches out of its chart '
              '(${rect.top.toStringAsFixed(1)}-'
              '${rect.bottom.toStringAsFixed(1)}, chart '
              '${bounds.top.toStringAsFixed(1)}-'
              '${bounds.bottom.toStringAsFixed(1)})');
        }
      }
      r.visitChildren(visit);
    }

    box.visitChildren(visit);
    if (labels == 0) out.add('a chart has no day labels');
  }
  return out;
}

void main() {
  group('layout: every text scale x phone x theme x language', () {
    for (final s in _scenarios) {
      testWidgets(s.name, (tester) async {
        final h = await _pump(tester, s);
        // Not a vacuous pass: the cards are really there.
        expect(find.text(_en.dataUsed), findsOneWidget);
        expect(find.text(_en.dataUsage), findsOneWidget);
        await sweepLayouts(tester, h,
            screen: 'Dashboard (${s.name})',
            positions: 4,
            check: () => _check(tester, 'Dashboard (${s.name})'));
      });
    }

    testWidgets('error state (database closed) fits too', (tester) async {
      final h = await _pump(tester, _scenarios.first);
      await h.db.close();
      h.container(tester).read(refreshTickProvider.notifier).state++;
      await settle(tester);
      expect(find.text(_en.noDataYet), findsOneWidget);
      expect(find.text(_en.genericError), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Dashboard (error)',
          check: () => _check(tester, 'Dashboard (error)'));
    });

    testWidgets('loading state fits too', (tester) async {
      final h = await _pump(tester, _scenarios.first, andSettle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Dashboard (loading)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'Dashboard (loading)'));
    });
  });

  group('layout: wide screens must not throw (Android 16 ignores the lock)',
      () {
    for (final s in const [
      _Scenario('iPhone'),
      _Scenario('Android', platform: HarnessPlatform.android)
    ]) {
      testWidgets(s.name, (tester) async {
        final h = await _pump(tester, s);
        await sweepLayouts(tester, h,
            screen: 'Dashboard wide (${s.name})',
            devices: kWideScreens,
            scales: kWideScales,
            brightnesses: const [Brightness.light],
            positions: 3,
            check: () => _check(tester, 'Dashboard wide'));
      });
    }
  });

  group('chart day labels are drawn whole (not clipped at the bottom)', () {
    // Both phones at their width, tall enough that the whole dashboard - both
    // charts - is laid out at every text size.
    const tallPhones = [
      ScreenSpec.custom(Size(375, 9000)),
      ScreenSpec.custom(Size(402, 9000)),
    ];
    for (final s in const [
      _Scenario('iPhone'),
      _Scenario('Android', platform: HarnessPlatform.android)
    ]) {
      testWidgets(s.name, (tester) async {
        final h = await _pump(tester, s);
        for (final range in [_en.days7, _en.days30]) {
          // Back to the view the toggle can be found in (English, top).
          await h.configure(tester,
              textScale: 1.0, device: kIPhone17Pro, locale: const Locale('en'));
          await tester.tap(find.text(range));
          await settle(tester);
          await sweepLayouts(tester, h,
              screen: 'Dashboard charts (${s.name}, $range)',
              devices: tallPhones,
              brightnesses: const [Brightness.dark], check: () async {
            final problems = _chartLabelProblems(tester);
            if (problems.isNotEmpty) fail(problems.join('\n'));
          });
        }
      });
    }
  });

  group('numbers keep their size', () {
    testWidgets(
        'no value is drawn below 75% of its style anywhere in the matrix',
        (tester) async {
      final h = await _pump(tester, _scenarios.first);
      final low = <String>[];
      await sweepLayouts(tester, h,
          screen: 'Dashboard (number size)',
          brightnesses: const [Brightness.light], check: () async {
        final scale = tester.platformDispatcher.textScaleFactor;
        for (final (text, fit) in fittedScales(tester)) {
          // What counts is the size on screen relative to the size the
          // style asks for at the default text size.
          if (fit * scale < 0.75) {
            low.add('"$text" at ${(fit * scale * 100).round()}% '
                '[${describeView(tester)}]');
          }
        }
      });
      expect(low, isEmpty, reason: low.join('\n'));
    });

    testWidgets('big numbers are complete: nothing is cut off or abbreviated',
        (tester) async {
      final h = await _pump(tester, _scenarios.first, semantics: true);
      final today = h.history.days.last;
      const units = Units(locale: 'en');
      await sweepLayouts(tester, h,
          screen: 'Dashboard (numbers)',
          scales: const [1.0, 3.0],
          brightnesses: const [Brightness.light],
          locales: const [Locale('en')], check: () async {
        expect(find.textContaining(units.bytes(today.total)), findsWidgets);
        expect(textProblems(tester), isEmpty);
      });
    });
  });

  group('semantics', () {
    testWidgets('the data card is ONE node: label, value, Estimated, breakdown',
        (tester) async {
      final h =
          await _pump(tester, _scenarios.first, semantics: true, tall: true);
      final today = h.history.days.last;
      const u = Units(locale: 'en');
      final tree = semanticsTree(tester);

      final hero = oneNodeWith(tree, [_en.dataUsed, u.bytes(today.total)]);
      expect(hero.spoken, contains(_en.estimated));
      expect(hero.spoken, contains('${_en.mobile} ${u.bytes(today.mobile)}'));
      expect(hero.spoken, contains('${_en.wifi} ${u.bytes(today.wifi)}'));
      expect(hero.spoken, contains('${_en.download} ${u.bytes(today.rx)}'));
      expect(hero.spoken, isNot(contains('~')),
          reason: 'a screen reader would say "tilde"');
      expect(nodesContaining(tree, _en.dataUsed), hasLength(1),
          reason: 'the label must not be a node of its own as well');
    });

    testWidgets('stat cards: label, value, sub-line and badge in one phrase',
        (tester) async {
      final h =
          await _pump(tester, _scenarios.first, semantics: true, tall: true);
      final tree = semanticsTree(tester);

      final energy = oneNodeWith(tree, [_en.energyAdded, 'Wh', _en.estimated]);
      expect(energy.spoken, contains('kWh'), reason: 'the sub-line is merged');
      expect(energy.spoken, isNot(contains('~')));

      // The default settings use the national average price.
      expect(h.container(tester).read(settingsProvider).priceIsAverage, isTrue);
      final cost = oneNodeWith(
          tree, [_en.estimatedChargingCost, _en.wallEnergy, _en.estimated]);
      expect(cost.spoken, contains('zł'));

      final battery = oneNodeWith(tree, [_en.batteryCharged, 'mAh']);
      expect(battery.spoken, contains(_en.estimated));
    });

    testWidgets('the same cards in Polish', (tester) async {
      await _pump(tester, _scenarios.first,
          semantics: true, tall: true, locale: const Locale('pl'));
      final tree = semanticsTree(tester);
      oneNodeWith(tree, [_pl.dataUsed, _pl.estimated, _pl.mobile]);
      oneNodeWith(tree, [_pl.energyAdded, _pl.estimated]);
      oneNodeWith(tree, [_pl.estimatedChargingCost, 'zł', _pl.estimated]);
    });

    testWidgets('an own tariff is a plain "Electricity Cost" card',
        (tester) async {
      await _pump(tester, _scenarios.last, semantics: true, tall: true);
      final tree = semanticsTree(tester);
      oneNodeWith(tree, [_en.electricityCost, _en.wallEnergy]);
      expect(nodesContaining(tree, _en.estimatedChargingCost), isEmpty);
    });

    testWidgets('"Measured" appears for a real measurement, never for zero',
        (tester) async {
      // Android with a charge counter: measured energy.
      await _pump(tester, _scenarios[3], semantics: true, tall: true);
      expect(find.text(_en.measured), findsOneWidget);
      oneNodeWith(semanticsTree(tester), [_en.batteryCharged, _en.measured]);

      // A new install has measured nothing: 0 mAh, and no claim about it.
      await _pump(
          tester,
          const _Scenario('new Android',
              platform: HarnessPlatform.android, historyDays: 0),
          semantics: true,
          tall: true);
      expect(find.text(_en.batteryCharged), findsOneWidget);
      expect(find.text(_en.measured), findsNothing);
    });

    testWidgets('unknown battery capacity says so and invents no number',
        (tester) async {
      await _pump(tester, _scenarios[5], semantics: true, tall: true);
      final tree = semanticsTree(tester);
      final card = oneNodeWith(tree, [_en.batteryCharged, _en.setCapacityHint]);
      expect(card.spoken, isNot(matches(RegExp(r'\d\s*mAh'))),
          reason: 'no invented number');
      expect(find.text(Units.placeholder), findsWidgets);
    });

    testWidgets(
        'unknown battery capacity with a price: energy and cost say so too, no zero (G-02)',
        (tester) async {
      await _pump(tester,
          const _Scenario('unknown capacity, priced', unknownCapacity: true),
          semantics: true, tall: true);
      final tree = semanticsTree(tester);
      final energy = oneNodeWith(tree, [_en.energyAdded, _en.setCapacityHint]);
      expect(energy.spoken, isNot(matches(RegExp(r'\d\s*(Wh|kWh)'))),
          reason: 'no invented energy');
      final cost = tree.where((n) =>
          (n.spoken.contains(_en.electricityCost) ||
              n.spoken.contains(_en.estimatedChargingCost)) &&
          n.spoken.contains(_en.setCapacityHint));
      expect(cost, isNotEmpty, reason: 'the cost card asks for the capacity');
      for (final n in cost) {
        expect(n.spoken, isNot(matches(RegExp(r'\d'))), reason: n.spoken);
      }
    });

    testWidgets('no price: one tappable card that offers to enter it',
        (tester) async {
      await _pump(tester, _scenarios[5], semantics: true, tall: true);
      final card = oneNodeWith(semanticsTree(tester),
          [_en.electricityCost, _en.priceUnavailable, _en.enterManually]);
      expect(card.tappable, isTrue);
      expect(card.button, isTrue);
    });

    testWidgets(
        'charts: one image node each with a real summary, painted children hidden',
        (tester) async {
      final h =
          await _pump(tester, _scenarios.first, semantics: true, tall: true);
      const u = Units(locale: 'en');
      final tree = semanticsTree(tester);

      final images = tree.where((n) => n.image).toList();
      expect(images, hasLength(2), reason: images.join('\n'));
      final data = images.firstWhere((n) => n.label.startsWith(_en.dataUsage));
      final energy =
          images.firstWhere((n) => n.label.startsWith(_en.energyUsage));

      // Period, total, highest and lowest day, and "Estimated".
      expect(data.label, contains(_en.periodLast7Days));
      expect(data.label, contains('total'));
      expect(data.label, contains('highest'));
      expect(data.label, contains('lowest'));
      expect(data.label, contains(_en.estimated));
      final last7 = h.history.days.reversed.take(7).toList();
      final total = last7.fold<int>(0, (a, d) => a + d.total);
      expect(data.label, contains(u.bytes(total)));
      expect(energy.label, contains(_en.periodLast7Days));
      expect(energy.label, contains('Wh'));
      expect(energy.label, isNot(contains('~')));

      // The axis labels under the bars are painted, not spoken.
      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(tree.where((n) => n.label == day), isEmpty,
            reason: 'axis label "$day" leaked into semantics');
      }

      // 30D changes what the summary says.
      await tester.tap(find.text(_en.days30));
      await settle(tester);
      final tree30 = semanticsTree(tester);
      expect(
          tree30
              .where((n) => n.image && n.label.contains(_en.periodLast30Days)),
          hasLength(2));
    });

    testWidgets('an empty chart says there is no data', (tester) async {
      await _pump(tester, _scenarios[2], semantics: true, tall: true);
      final images = semanticsTree(tester).where((n) => n.image).toList();
      expect(images, hasLength(2));
      expect(images.every((n) => n.label.contains('no data')), isTrue,
          reason: images.join('\n'));
    });

    testWidgets('section titles are headings', (tester) async {
      await _pump(tester, _scenarios.first, semantics: true, tall: true);
      final headers = semanticsTree(tester).where((n) => n.header).toList();
      expect(headers.map((n) => n.label),
          containsAll([_en.appName, _en.dataUsage, _en.energyUsage]));
    });

    testWidgets('the 7D / 30D selector exposes its selected state',
        (tester) async {
      await _pump(tester, _scenarios.first, semantics: true, tall: true);
      var tree = semanticsTree(tester);
      expect(nodesContaining(tree, _en.a11yChartPeriod), isNotEmpty);
      final seven = tree.firstWhere((n) => n.label.startsWith(_en.days7));
      final thirty = tree.firstWhere((n) => n.label.startsWith(_en.days30));
      expect(seven.selected, isTrue);
      expect(thirty.selected, isFalse);
      expect(seven.tappable && thirty.tappable, isTrue);
      expect(seven.tooltip, _en.periodLast7Days);
      expect(thirty.tooltip, _en.periodLast30Days);

      await tester.tap(find.text(_en.days30));
      await settle(tester);
      tree = semanticsTree(tester);
      expect(tree.firstWhere((n) => n.label.startsWith(_en.days30)).selected,
          isTrue);
      expect(tree.firstWhere((n) => n.label.startsWith(_en.days7)).selected,
          isFalse);
    });

    testWidgets('icon-only button and link cards are labelled buttons',
        (tester) async {
      await _pump(tester, _scenarios.first, semantics: true, tall: true);
      final stats = semanticsTree(tester)
          .where((n) => n.spoken == _en.statistics && n.tappable)
          .toList();
      expect(stats, hasLength(2), reason: 'toolbar button + link card');
      expect(stats.every((n) => n.button), isTrue);
    });

    testWidgets('Android: Data by app link; permission card when revoked',
        (tester) async {
      await _pump(tester, _scenarios[3], semantics: true, tall: true);
      expect(
          semanticsTree(tester)
              .where((n) => n.label == _en.dataByApp && n.tappable),
          hasLength(1));

      await _pump(tester, _scenarios[4], semantics: true, tall: true);
      final tree = semanticsTree(tester);
      expect(nodesContaining(tree, _en.usageAccessTitle), isNotEmpty);
      final open = tree.where((n) => n.label == _en.usageAccessButton);
      expect(open, hasLength(1));
      expect(open.single.tappable, isTrue);
      expect(nodesContaining(tree, _en.dataByApp), isEmpty,
          reason: 'no per-app link without the permission');
    });

    testWidgets('loading is labelled; an error is a live announcement',
        (tester) async {
      final h = await _pump(tester, _scenarios.first,
          semantics: true, andSettle: false);
      // Straight after the first frame: the database has not answered yet.
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);

      await settle(tester);
      await h.db.close();
      h.container(tester).read(refreshTickProvider.notifier).state++;
      await settle(tester);
      final error =
          oneNodeWith(semanticsTree(tester), [_en.noDataYet, _en.genericError]);
      expect(error.liveRegion, isTrue);
    });

    testWidgets('charging now is announced as text', (tester) async {
      await _pump(tester, _scenarios[1], semantics: true, tall: true);
      expect(
          nodesContaining(semanticsTree(tester), _en.chargingNow), isNotEmpty);
    });
  });

  group('touch targets (Android 48 px, iOS 44 px, labelled)', () {
    for (final s in [
      _scenarios[0],
      _scenarios[3],
      _scenarios[4],
      _scenarios[5]
    ]) {
      testWidgets(s.name, (tester) async {
        final h = await _pump(tester, s, semantics: true);
        await sweepLayouts(tester, h,
            screen: 'Dashboard targets (${s.name})',
            brightnesses: const [Brightness.light],
            positions: 3, check: () async {
          await expectAccessibleTargets(tester,
              screen: 'Dashboard (${s.name})');
          final problems = tappableProblems(tester, semanticsTree(tester));
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      });
    }
  });

  group('contrast (WCAG text contrast, light and dark)', () {
    for (final s in [_scenarios[0], _scenarios[3], _scenarios[5]]) {
      testWidgets(s.name, (tester) async {
        final h = await _pump(tester, s, semantics: true);
        await sweepLayouts(tester, h,
            screen: 'Dashboard contrast (${s.name})',
            scales: const [1.0, 2.0],
            devices: const [kIPhoneSE],
            locales: const [Locale('en')],
            positions: 4,
            settleFully: true, check: () async {
          expectTextContrast(tester, screen: 'Dashboard (${s.name})');
          await expectAccessibleTargets(tester,
              screen: 'Dashboard (${s.name})',
              android: false,
              ios: false,
              labeled: false,
              contrast: true);
        });
      });
    }
  });

  group('themes', () {
    testWidgets('system, light and dark all render the dashboard',
        (tester) async {
      final h = await _pump(tester, _scenarios.first);
      for (final theme in AppTheme.values) {
        await h
            .container(tester)
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(theme: theme));
        await settle(tester);
        expect(find.text(_en.dataUsed), findsOneWidget, reason: '$theme');
        expectNoFlutterErrors(tester, screen: 'theme $theme');
      }
    });
  });

  group('bold text (iOS "Bold Text", Android bold fonts)', () {
    testWidgets('widens every text and still fits', (tester) async {
      for (final scenario in [_scenarios[0], _scenarios[3]]) {
        final h = await _pump(tester, scenario,
            accessibilityFeatures:
                const FakeAccessibilityFeatures(boldText: true));
        expect(MediaQuery.boldTextOf(tester.element(find.text(_en.dataUsed))),
            isTrue,
            reason: 'the harness really switched bold text on');
        await sweepLayouts(tester, h,
            screen: 'Dashboard bold (${scenario.name})',
            scales: const [1.0, 1.6, 3.0],
            brightnesses: const [Brightness.light],
            positions: 4,
            check: () => _check(tester, 'Dashboard bold'));
      }
    });
  });

  group('reduced motion', () {
    testWidgets('numbers do not count up when animations are disabled',
        (tester) async {
      final h = await _pump(tester, _scenarios.first,
          andSettle: false,
          accessibilityFeatures:
              const FakeAccessibilityFeatures(disableAnimations: true));
      final today = h.history.days.last;
      const u = Units(locale: 'en');
      // A few frames: the database answers, the cards appear.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.textContaining(u.bytes(today.total)), findsWidgets,
          reason: 'the final value from the first frame on, no 0.00 -> value');
    });
  });
}
