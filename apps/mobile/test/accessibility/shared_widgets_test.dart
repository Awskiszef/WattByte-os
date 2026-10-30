// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The shared building blocks (lib/ui/widgets, lib/ui/theme.dart): what they
// promise at any text size, what a screen reader gets, and the colour contrast
// of the theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/theme.dart';
import 'package:wattbyte/ui/widgets/daily_bar_chart.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

const _phone = Size(375, 667);

Future<AppHarness> _pump(
  WidgetTester tester,
  Widget child, {
  bool andSettle = true,
  double textScale = 1.0,
  Size size = _phone,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  bool semantics = false,
  bool scroll = false,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) =>
    pumpScreen(
        tester,
        scroll
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20), child: child)
            : Padding(padding: const EdgeInsets.all(20), child: child),
        scaffold: true,
        size: size,
        textScale: textScale,
        locale: locale,
        brightness: brightness,
        semantics: semantics,
        andSettle: andSettle,
        accessibilityFeatures: accessibilityFeatures);

String _bigNumberText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byType(BigNumber), matching: find.byType(Text)))
    .data!;

void main() {
  group('BigNumber', () {
    const units = Units(locale: 'en');

    testWidgets('a long value in a narrow card is shown whole, scaled down',
        (tester) async {
      await _pump(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            child: Builder(
                builder: (context) => BigNumber(
                      value: 98765.4321,
                      format: (v) => '${v.toStringAsFixed(2)} MB',
                      estimated: true,
                      style: Theme.of(context).textTheme.displayMedium,
                    )),
          ),
        ),
      );
      expect(find.text('~98765.43 MB'), findsOneWidget);
      final scales = fittedScales(tester);
      expect(scales, hasLength(1));
      expect(scales.single.$2, lessThan(1.0), reason: 'it had to shrink');
      expect(scales.single.$2, greaterThan(0.3));
      expect(textProblems(tester), isEmpty);
      expectNoFlutterErrors(tester, screen: 'BigNumber narrow');
    });

    testWidgets('a "~" only goes in front of a number', (tester) async {
      expect(BigNumber.shown('12.3 MB', estimated: true), '~12.3 MB');
      expect(BigNumber.shown('12.3 MB', estimated: false), '12.3 MB');
      expect(BigNumber.shown('<0,001 zł', estimated: true), '<0,001 zł');
      expect(BigNumber.shown('>-0,001 zł', estimated: true), '>-0,001 zł');
      expect(BigNumber.shown(Units.placeholder, estimated: true), '—');
      expect(BigNumber.shown('0,00 zł', estimated: true), '~0,00 zł');
    });

    testWidgets('the count-up never shows "~<" or "~—" on its way',
        (tester) async {
      const pl = Units(locale: 'pl');
      await _pump(
          tester,
          BigNumber(
              value: 0.0002, // prints "<0,001 zł" for most of the animation
              format: (v) => pl.money(v, 'PLN'),
              estimated: true));
      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        seen.add(_bigNumberText(tester));
        await tester.pump(const Duration(milliseconds: 50));
      }
      seen.add(_bigNumberText(tester));
      expect(
          seen.where((t) => t.startsWith('~<') || t.startsWith('~>')), isEmpty,
          reason: '$seen');
      expect(seen.where((t) => t.startsWith('<0,001')), isNotEmpty,
          reason: '$seen');
    });

    testWidgets('a number that does not exist is a dash, not "~—"',
        (tester) async {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        await _pump(tester,
            BigNumber(value: value, format: units.bytes, estimated: true));
        await settle(tester);
        expect(_bigNumberText(tester), '—', reason: '$value');
      }
    });

    testWidgets('it counts up, unless the system asks for less motion',
        (tester) async {
      await _pump(tester,
          BigNumber(value: 5e6, format: units.bytes.call, estimated: false),
          andSettle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = _bigNumberText(tester);
      expect(mid, isNot(units.bytes(5e6)), reason: 'still on its way');
      await settle(tester);
      expect(_bigNumberText(tester), units.bytes(5e6));

      await _pump(tester,
          BigNumber(value: 5e6, format: units.bytes.call, estimated: false),
          accessibilityFeatures:
              const FakeAccessibilityFeatures(disableAnimations: true));
      expect(_bigNumberText(tester), units.bytes(5e6),
          reason: 'reduce motion: the final value at once');
    });

    testWidgets('a screen reader gets the final value, never a half way one',
        (tester) async {
      await _pump(tester,
          BigNumber(value: 1810000, format: units.bytes.call, estimated: true),
          semantics: true);
      await tester.pump(const Duration(milliseconds: 50));
      final tree = semanticsTree(tester);
      final node = oneNodeWith(tree, [units.bytes(1810000)]);
      expect(node.spoken, contains(_en.estimated));
      expect(node.spoken, isNot(contains('~')));
      expect(tree.where((n) => n.spoken.contains('0.00')), isEmpty);
    });
  });

  group('StatCard', () {
    testWidgets('one node: label, value, sub-line, Estimated', (tester) async {
      await _pump(
          tester,
          StatCard(
              label: 'Data used',
              value: 1810000,
              format: const Units(locale: 'en').bytes,
              estimated: true,
              accent: WbColors.byte,
              sub: '~0.0152 kWh'),
          semantics: true);
      await settle(tester);
      final tree = semanticsTree(tester);
      final card = oneNodeWith(tree, ['Data used', '1.81 MB', _en.estimated]);
      expect(card.spoken, 'Data used, 1.81 MB, 0.0152 kWh, ${_en.estimated}');
      expect(tree.where((n) => n.label == _en.estimated), isEmpty,
          reason: 'the badge is part of the card, not a node of its own');
    });

    testWidgets('a measured value says nothing about estimates',
        (tester) async {
      await _pump(
          tester,
          StatCard(
              label: 'Battery charged',
              value: 3988,
              format: const Units(locale: 'en').mah,
              sub: _en.measured),
          semantics: true);
      await settle(tester);
      final card = oneNodeWith(semanticsTree(tester), ['Battery charged']);
      expect(card.spoken, 'Battery charged, 3,988 mAh, ${_en.measured}');
    });

    testWidgets('a tappable card is one button', (tester) async {
      var taps = 0;
      await _pump(
          tester,
          StatCard(
              label: 'Cost',
              value: 1,
              format: (v) => '${v.round()} zł',
              onTap: () => taps++),
          semantics: true);
      await settle(tester);
      final card = oneNodeWith(semanticsTree(tester), ['Cost', '1 zł']);
      expect(card.tappable && card.button, isTrue);
      await tester.tap(find.text('Cost'));
      expect(taps, 1);
    });

    testWidgets('the label wraps instead of being cut off', (tester) async {
      Widget card() => Row(children: [
            Expanded(
              child: StatCard(
                  label: _en.estimatedChargingCost,
                  value: 0.021,
                  format: (v) => const Units(locale: 'en').money(v, 'PLN'),
                  estimated: true),
            ),
          ]);
      // A narrow card at the default size: two lines, whole words.
      await _pump(tester, card(), size: const Size(150, 667));
      await settle(tester);
      expect(find.text(_en.estimatedChargingCost), findsOneWidget);
      final narrow = tester.getSize(find.text(_en.estimatedChargingCost));
      expect(narrow.height, greaterThan(18), reason: 'wrapped onto two lines');
      expect(textProblems(tester), isEmpty);

      // Full width card at the largest size (what the dashboard stacks to).
      await _pump(tester, card(), textScale: 3.0);
      await settle(tester);
      expect(textProblems(tester), isEmpty);
      expectNoFlutterErrors(tester, screen: 'StatCard label @3.0');
    });
  });

  group('Label', () {
    testWidgets('wraps long text and keeps its dot on the first line',
        (tester) async {
      await _pump(
          tester,
          const SizedBox(
              width: 110,
              child: Label('Wall energy estimate for today', dot: Colors.red)),
          textScale: 2.0);
      expect(textProblems(tester), isEmpty);
      final text = tester.getRect(find.text('Wall energy estimate for today'));
      expect(text.height, greaterThan(40), reason: 'several lines');
      final dot = tester.getRect(find
          .descendant(of: find.byType(Label), matching: find.byType(Container))
          .first);
      expect(dot.top, lessThan(text.top + 30), reason: 'beside the first line');
      expectNoFlutterErrors(tester, screen: 'Label');
    });
  });

  group('SplitRow', () {
    Widget row() => SplitRow(
        leading: Text(_en.batteryEnergy, key: const ValueKey('leading')),
        trailing: const Text('~3 988 mAh', key: ValueKey('trailing')));

    testWidgets('fits: value at the far end, one line', (tester) async {
      await _pump(tester, row());
      final a = tester.getRect(find.byKey(const ValueKey('leading')));
      final b = tester.getRect(find.byKey(const ValueKey('trailing')));
      expect(b.center.dy, closeTo(a.center.dy, 2));
      expect(b.right, closeTo(_phone.width - 20, 1));
    });

    testWidgets('does not fit: value moves below, nothing overflows',
        (tester) async {
      await _pump(tester, row(), textScale: 3.0);
      final a = tester.getRect(find.byKey(const ValueKey('leading')));
      final b = tester.getRect(find.byKey(const ValueKey('trailing')));
      expect(b.top, greaterThanOrEqualTo(a.bottom - 1));
      expect(textProblems(tester), isEmpty);
      expectNoFlutterErrors(tester, screen: 'SplitRow @3.0');
    });
  });

  group('AdaptiveColumns', () {
    test('the need grows with the text scale and never drops below 1.0', () {
      bool fits(double width, double scale) => AdaptiveColumns.fitsSideBySide(
          maxWidth: width, count: 2, minColumnWidth: 150, scale: scale);
      expect(fits(335, 1.0), isTrue); // iPhone SE content width
      expect(fits(335, 1.35), isFalse);
      expect(fits(362, 1.0), isTrue); // iPhone 17 Pro
      expect(fits(362, 1.35), isFalse);
      expect(fits(335, 0.8), isTrue, reason: 'smaller text needs no less room');
      expect(fits(700, 2.0), isTrue, reason: 'a wide screen keeps two columns');
    });

    testWidgets('two columns at 1.0, stacked at 3.0', (tester) async {
      Widget two() => const AdaptiveColumns(children: [
            SizedBox(key: ValueKey('a'), height: 40),
            SizedBox(key: ValueKey('b'), height: 40),
          ]);
      await _pump(tester, two());
      var a = tester.getRect(find.byKey(const ValueKey('a')));
      var b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(b.left, greaterThan(a.right));
      expect(b.top, a.top);
      expect(a.width, closeTo(b.width, 0.01));

      await _pump(tester, two(), textScale: 3.0);
      a = tester.getRect(find.byKey(const ValueKey('a')));
      b = tester.getRect(find.byKey(const ValueKey('b')));
      expect(b.top, greaterThan(a.bottom));
      expect(a.width, b.width);
      expect(a.width, _phone.width - 40, reason: 'full width when stacked');
    });
  });

  group('SectionHeader', () {
    testWidgets('is a heading; the trailing widget moves below at 3.0',
        (tester) async {
      Widget header() => const SectionHeader('Data Usage',
          trailing: SizedBox(key: ValueKey('t'), width: 150, height: 48));
      await _pump(tester, header(), semantics: true);
      final heading = semanticsTree(tester).where((n) => n.header).toList();
      expect(heading.map((n) => n.label), ['Data Usage']);
      final title = tester.getRect(find.text('Data Usage'));
      expect(tester.getRect(find.byKey(const ValueKey('t'))).center.dy,
          closeTo(title.center.dy, 4));

      await _pump(tester, header(), textScale: 3.0);
      expect(
          tester.getRect(find.byKey(const ValueKey('t'))).top,
          greaterThanOrEqualTo(
              tester.getRect(find.text('Data Usage')).bottom - 1));
      expect(textProblems(tester), isEmpty);
      expectNoFlutterErrors(tester, screen: 'SectionHeader @3.0');
    });
  });

  group('WbSegmented', () {
    Widget history(void Function(int) onChanged, int selected, Locale locale) {
      final l = locale.languageCode == 'pl' ? _pl : _en;
      return WbSegmented<int>(segments: [
        WbSegment(0, l.historyData),
        WbSegment(1, l.historyCharging),
        WbSegment(2, l.historyEnergy),
      ], selected: selected, onChanged: onChanged);
    }

    testWidgets(
        'one row while the labels fit, wrapping chips when they would break',
        (tester) async {
      for (final locale in const [Locale('en'), Locale('pl')]) {
        await _pump(tester, history((_) {}, 1, locale), locale: locale);
        expect(find.byType(SegmentedButton<int>), findsOneWidget,
            reason: '$locale @1.0');
        expect(find.byType(ChoiceChip), findsNothing);
        await _pump(tester, history((_) {}, 1, locale),
            locale: locale, textScale: 3.0);
        expect(find.byType(SegmentedButton<int>), findsNothing,
            reason: '$locale @3.0');
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        expect(textProblems(tester), isEmpty, reason: '$locale @3.0');
        expectNoFlutterErrors(tester, screen: 'WbSegmented $locale');
      }
    });

    testWidgets(
        'every segment is a labelled button >= 44 px, selection exposed',
        (tester) async {
      var chosen = -1;
      for (final scale in [1.0, 2.0, 3.0]) {
        await _pump(tester, history((v) => chosen = v, 1, const Locale('pl')),
            locale: const Locale('pl'), textScale: scale, semantics: true);
        final tree = semanticsTree(tester);
        final segments = [
          for (final label in [
            _pl.historyData,
            _pl.historyCharging,
            _pl.historyEnergy
          ])
            tree.firstWhere((n) => n.label.startsWith(label))
        ];
        expect(segments.map((n) => n.selected), [false, true, false],
            reason: 'scale $scale');
        for (final s in segments) {
          expect(s.tappable, isTrue);
          expect(s.rect.height, greaterThanOrEqualTo(44), reason: '$s');
          expect(s.rect.width, greaterThanOrEqualTo(44), reason: '$s');
        }
        await expectAccessibleTargets(tester, screen: 'WbSegmented @$scale');
      }
      await tester.tap(find.text(_pl.historyEnergy));
      expect(chosen, 2);
    });
  });

  group('ChipRow', () {
    testWidgets(
        'wraps: every chip is on screen at 3.0, none hides in a scroller',
        (tester) async {
      var picked = '';
      for (final locale in const [Locale('en'), Locale('pl')]) {
        final l = locale.languageCode == 'pl' ? _pl : _en;
        await _pump(
            tester,
            ChipRow<String>(
              items: [
                l.periodLast7Days,
                l.periodThisMonth,
                l.periodLastMonth,
                l.periodThisYear,
                l.periodAllTime
              ],
              selected: l.periodThisMonth,
              label: (s) => s,
              onSelected: (s) => picked = s,
            ),
            locale: locale,
            textScale: 3.0,
            semantics: true);
        expect(find.byType(ChoiceChip), findsNWidgets(5));
        for (final chip
            in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
          final rect = tester.getRect(find.byWidget(chip));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(_phone.width),
              reason: '$locale');
        }
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(textProblems(tester), isEmpty, reason: '$locale');
        expectNoFlutterErrors(tester, screen: 'ChipRow $locale');
        final tree = semanticsTree(tester);
        expect(tree.where((n) => n.selected).map((n) => n.label),
            [l.periodThisMonth]);
        await expectAccessibleTargets(tester, screen: 'ChipRow $locale');
      }
      await tester.tap(find.text(_pl.periodAllTime));
      expect(picked, _pl.periodAllTime);
    });
  });

  group('WbCard', () {
    testWidgets('with a label: one node, children hidden, tap on the node',
        (tester) async {
      var taps = 0;
      await _pump(
          tester,
          WbCard(
              onTap: () => taps++,
              semanticLabel: 'Statistics',
              child: const Row(children: [
                Icon(Icons.insights_rounded),
                Text('Stat'),
                Icon(Icons.chevron_right)
              ])),
          semantics: true);
      final nodes = semanticsTree(tester).where((n) => n.tappable).toList();
      expect(nodes, hasLength(1));
      expect(nodes.single.label, 'Statistics');
      expect(nodes.single.button, isTrue);
      expect(nodesContaining(semanticsTree(tester), 'Stat '), isEmpty);
      await tester.tap(find.text('Stat'));
      expect(taps, 1);
    });

    testWidgets(
        'without a label it adds nothing (account and setup rely on it)',
        (tester) async {
      await _pump(tester, const WbCard(child: Text('hello')), semantics: true);
      expect(
          semanticsTree(tester).where((n) => n.label == 'hello'), hasLength(1));
    });
  });

  group('states', () {
    testWidgets('EmptyState is announced (live region), icon hidden',
        (tester) async {
      await _pump(
          tester, EmptyState(title: _en.noDataYet, body: _en.noDataBody),
          semantics: true);
      final node =
          oneNodeWith(semanticsTree(tester), [_en.noDataYet, _en.noDataBody]);
      expect(node.liveRegion, isTrue);
    });

    testWidgets(
        'ScrollableEmptyState scrolls when the text is taller than the area',
        (tester) async {
      await _pump(
          tester,
          SizedBox(
              height: 300,
              child: ScrollableEmptyState(
                  title: _en.noSessionsYet, body: _en.noDataBody)),
          textScale: 3.0);
      expectNoFlutterErrors(tester, screen: 'ScrollableEmptyState @3.0');
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();
      expect(find.text(_en.noDataBody), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'ScrollableEmptyState scrolled');
    });

    testWidgets('WbProgress has a label', (tester) async {
      await pumpScreen(tester, const WbProgress(),
          scaffold: true, semantics: true, andSettle: false);
      await tester.pump();
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);
      await pumpScreen(tester, const WbProgress(),
          scaffold: true,
          semantics: true,
          andSettle: false,
          locale: const Locale('pl'));
      await tester.pump();
      expect(
          nodesContaining(semanticsTree(tester), _pl.a11yLoading), isNotEmpty);
    });
  });

  group('DailyBarChart', () {
    List<ChartPoint> week() => [
          for (var i = 0; i < 7; i++)
            ChartPoint(DateTime(2026, 10, 7 + i), [100.0 * (i + 1), 50]),
        ];
    List<ChartPoint> month() => [
          for (var i = 0; i < 30; i++)
            ChartPoint(DateTime(2026, 9, 14 + i), [30.0 + (i % 7) * 10]),
        ];

    Widget chart(List<ChartPoint> points, {bool estimated = false}) =>
        DailyBarChart(
          points: points,
          colors: const [Colors.purple, Colors.green],
          formatValue: (v) => '${v.round()} MB',
          title: 'Data Usage',
          period: 'Last 7 Days',
          estimated: estimated,
        );

    testWidgets('summary: what, period, total, highest and lowest day',
        (tester) async {
      await _pump(tester, chart(week(), estimated: true), semantics: true);
      final images = semanticsTree(tester).where((n) => n.image).toList();
      expect(images, hasLength(1));
      expect(
          images.single.label,
          'Data Usage, Last 7 Days: total 3150 MB, highest 750 MB on '
          'Tue, Oct 13, lowest 150 MB on Wed, Oct 7. ${_en.estimated}.');
    });

    testWidgets('an empty period says so', (tester) async {
      await _pump(
          tester,
          chart([
            for (var i = 0; i < 7; i++)
              ChartPoint(DateTime(2026, 10, 7 + i), [0, 0])
          ]),
          semantics: true);
      expect(semanticsTree(tester).singleWhere((n) => n.image).label,
          _en.a11yChartEmpty('Data Usage', 'Last 7 Days'));
    });

    testWidgets('the Polish summary', (tester) async {
      await _pump(tester, chart(week()),
          semantics: true, locale: const Locale('pl'));
      final label = semanticsTree(tester).singleWhere((n) => n.image).label;
      expect(label, contains('łącznie'));
      expect(label, contains('najwięcej'));
      expect(label, contains('najmniej'));
    });

    testWidgets('axis labels never overlap, at any text size, week or month',
        (tester) async {
      for (final points in [week(), month()]) {
        for (final scale in kTextScales) {
          await _pump(tester, chart(points), textScale: scale, scroll: true);
          await settle(tester);
          final labels = tester
              .widgetList<Text>(find.descendant(
                  of: find.byType(DailyBarChart), matching: find.byType(Text)))
              .map((w) => find.byWidget(w))
              .map(tester.getRect)
              .toList()
            ..sort((a, b) => a.left.compareTo(b.left));
          expect(labels, isNotEmpty, reason: '${points.length} bars @$scale');
          for (var i = 1; i < labels.length; i++) {
            expect(labels[i].left, greaterThanOrEqualTo(labels[i - 1].right),
                reason:
                    '${points.length} bars @$scale: ${labels[i - 1]} touches ${labels[i]}');
          }
          expect(textProblems(tester), isEmpty);
          expectNoFlutterErrors(tester,
              screen: 'chart ${points.length} bars @$scale');
        }
      }
    });
  });

  group('theme contrast (WCAG AA 4.5:1 for text, 3:1 for graphics)', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);
    final lightGrounds = {
      'page': WbColors.lightBg,
      'card': WbColors.lightSurface,
      'accent wash':
          over(WbColors.byte.withValues(alpha: 0.16), WbColors.lightSurface),
      'bolt wash':
          over(WbColors.bolt.withValues(alpha: 0.16), WbColors.lightSurface),
    };
    final darkGrounds = {
      'page': WbColors.darkBg,
      'card': WbColors.darkSurface,
      'accent wash':
          over(WbColors.byte.withValues(alpha: 0.16), WbColors.darkSurface),
      'bolt wash':
          over(WbColors.bolt.withValues(alpha: 0.16), WbColors.darkSurface),
    };

    test('muted text', () {
      lightGrounds.forEach((name, bg) => expect(
          ratio(WbColors.lightMuted, bg), greaterThanOrEqualTo(4.5),
          reason: 'light $name'));
      darkGrounds.forEach((name, bg) => expect(
          ratio(WbColors.darkMuted, bg), greaterThanOrEqualTo(4.5),
          reason: 'dark $name'));
    });

    test('error text', () {
      lightGrounds.forEach((name, bg) => expect(
          ratio(WbColors.lightError, bg), greaterThanOrEqualTo(4.5),
          reason: 'light $name'));
      darkGrounds.forEach((name, bg) => expect(
          ratio(WbColors.darkError, bg), greaterThanOrEqualTo(4.5),
          reason: 'dark $name'));
      expect(wbTheme(Brightness.light).colorScheme.error, WbColors.lightError);
      expect(wbTheme(Brightness.dark).colorScheme.error, WbColors.darkError);
    });

    test('accent-coloured text (links)', () {
      lightGrounds.forEach((name, bg) => expect(
          ratio(WbColors.lightAccentText, bg), greaterThanOrEqualTo(4.5),
          reason: 'light $name'));
      darkGrounds.forEach((name, bg) => expect(
          ratio(WbColors.byte, bg), greaterThanOrEqualTo(4.5),
          reason: 'dark $name'));
    });

    testWidgets('series colours are at least 3:1 against their card',
        (tester) async {
      for (final (brightness, card) in [
        (Brightness.light, WbColors.lightSurface),
        (Brightness.dark, WbColors.darkSurface),
      ]) {
        await _pump(tester, const SizedBox(), brightness: brightness);
        final series = WbSeries.of(tester.element(find.byType(SizedBox).first));
        for (final (name, color) in [
          ('mobile', series.mobile),
          ('wifi', series.wifi),
          ('energy', series.energy),
          ('data', series.data),
          ('cost', series.cost),
        ]) {
          expect(ratio(color, card), greaterThanOrEqualTo(3.0),
              reason: '$name in $brightness');
        }
      }
    });

    test('buttons and navigation text', () {
      final light = wbTheme(Brightness.light);
      expect(ratio(light.colorScheme.onPrimary, light.colorScheme.primary),
          greaterThanOrEqualTo(7));
      for (final b in Brightness.values) {
        final t = wbTheme(b);
        final nav = t.navigationBarTheme;
        for (final states in [
          <WidgetState>{},
          {WidgetState.selected}
        ]) {
          final style = nav.labelTextStyle!.resolve(states)!;
          expect(ratio(style.color!, nav.backgroundColor!),
              greaterThanOrEqualTo(4.5),
              reason: '$b $states');
        }
      }
    });
  });

  group('theme modes', () {
    testWidgets('system follows the phone; light and dark are forced',
        (tester) async {
      final h = await pumpApp(tester);
      Brightness shown() =>
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      final settings = h.container(tester).read(settingsProvider.notifier);

      await h.setBrightness(tester, Brightness.dark);
      expect(shown(), Brightness.dark, reason: 'system, phone dark');
      await h.setBrightness(tester, Brightness.light);
      expect(shown(), Brightness.light, reason: 'system, phone light');

      await settings.update((s) => s.copyWith(theme: AppTheme.dark));
      await settle(tester);
      expect(shown(), Brightness.dark, reason: 'forced dark, phone light');
      await settings.update((s) => s.copyWith(theme: AppTheme.light));
      await h.setBrightness(tester, Brightness.dark);
      expect(shown(), Brightness.light, reason: 'forced light, phone dark');
      expectNoFlutterErrors(tester, screen: 'theme modes');
    });
  });
}
