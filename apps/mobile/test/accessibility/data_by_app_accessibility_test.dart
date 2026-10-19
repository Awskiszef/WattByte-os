// Data by app (Android only) at every text size, phone, theme and language;
// what a screen reader says about each app; touch targets; contrast.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/data_by_app/data_by_app_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

const _mb = 1024 * 1024;

/// Apps as the native side reports them, including the awkward ones: a very
/// long single-word name, a system bucket, tethering, removed apps, a huge
/// total and an app that used no data at all.
List<Map<String, Object?>> _awkwardApps() => [
      for (final a in [
        ('Gesundheitsversicherungsanwendung', 'app', 4200, 1900),
        ('Photos and Videos Backup Service for Family', 'app', 2100, 90),
        ('', 'system', 640, 300),
        ('', 'tethering', 410, 0),
        ('', 'removed', 120, 80),
        ('', 'unknown', 33, 12),
        ('Chrome', 'app', 0, 0),
        ('X', 'app', 1, 0),
      ])
        {
          'uid': a.hashCode,
          'name': a.$1,
          'package': 'p.${a.hashCode}',
          'mobile': a.$3 * _mb,
          'wifi': a.$4 * _mb,
          'icon': null,
          'kind': a.$2,
        },
    ];

Future<AppHarness> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? apps,
  Locale locale = const Locale('en'),
  bool semantics = false,
  bool andSettle = true,
  bool tall = false,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) async {
  final system = FakeSystem(
      platform: HarnessPlatform.android, chargeCounterMah: 4575 * 0.78);
  if (apps != null) system.appRows = apps;
  final h = await AppHarness.create(tester,
      platform: HarnessPlatform.android, locale: locale, system: system);
  return pumpScreen(tester, const DataByAppScreen(),
      harness: h,
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
    testWidgets('the usual apps', (tester) async {
      final h = await _pump(tester);
      expect(find.text('YouTube'), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Data by app',
          positions: 4,
          check: () => _check(tester, 'Data by app'));
    });

    testWidgets('awkward names and buckets', (tester) async {
      final h = await _pump(tester, apps: _awkwardApps());
      expect(find.text(_en.appSystem), findsOneWidget);
      expect(find.text(_en.appTethering), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Data by app (awkward)',
          positions: 5,
          check: () => _check(tester, 'Data by app (awkward)'));
    });

    testWidgets('nothing recorded for the period', (tester) async {
      final h = await _pump(tester, apps: const []);
      expect(find.text(_en.dataByAppEmpty), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Data by app (empty)',
          check: () => _check(tester, 'Data by app (empty)'));
    });

    testWidgets('every period chip', (tester) async {
      final h = await _pump(tester);
      for (final label in [
        _en.periodToday,
        _en.periodLast30Days,
        _en.periodThisMonth,
        _en.periodLast7Days
      ]) {
        await tester.tap(find.text(label));
        await settle(tester);
        await sweepLayouts(tester, h,
            screen: 'Data by app ($label)',
            scales: const [1.0, 3.0],
            brightnesses: const [Brightness.light],
            check: () => _check(tester, 'Data by app ($label)'));
        await applyView(tester, h,
            textScale: 1.0,
            device: kIPhone17Pro,
            brightness: Brightness.light,
            locale: const Locale('en'));
      }
    });

    testWidgets('loading state fits too', (tester) async {
      final h = await _pump(tester, andSettle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Data by app (loading)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'Data by app (loading)'));
    });
  });

  group('layout: wide screens must not throw', () {
    testWidgets('usual and awkward apps', (tester) async {
      for (final apps in [null, _awkwardApps()]) {
        final h = await _pump(tester, apps: apps);
        await sweepLayouts(tester, h,
            screen: 'Data by app wide',
            devices: kWideScreens,
            scales: kWideScales,
            brightnesses: const [Brightness.light],
            positions: 3,
            check: () => _check(tester, 'Data by app wide'));
      }
    });
  });

  group('bold text (iOS "Bold Text", Android bold fonts)', () {
    testWidgets('widens every text and still fits', (tester) async {
      final h = await _pump(tester,
          apps: _awkwardApps(),
          accessibilityFeatures:
              const FakeAccessibilityFeatures(boldText: true));
      await sweepLayouts(tester, h,
          screen: 'Data by app bold',
          scales: const [1.0, 1.6, 3.0],
          brightnesses: const [Brightness.light],
          positions: 4,
          check: () => _check(tester, 'Data by app bold'));
    });
  });

  group('semantics', () {
    testWidgets('each app is ONE node: name, total, mobile, Wi-Fi',
        (tester) async {
      await _pump(tester, semantics: true, tall: true);
      const u = Units(locale: 'en');
      final tree = semanticsTree(tester);
      final youtube = oneNodeWith(tree, ['YouTube', u.bytes(2060 * _mb)]);
      expect(
          youtube.spoken,
          'YouTube, ${u.bytes(2060 * _mb)}, ${_en.mobile} ${u.bytes(1840 * _mb)}, '
          '${_en.wifi} ${u.bytes(220 * _mb)}');
      expect(youtube.spoken, isNot(contains('·')));
      expect(nodesContaining(tree, 'YouTube'), hasLength(1),
          reason: 'the name is not a node of its own as well');
    });

    testWidgets('system buckets use their translated names', (tester) async {
      await _pump(tester, apps: _awkwardApps(), semantics: true, tall: true);
      final tree = semanticsTree(tester);
      for (final name in [
        _en.appSystem,
        _en.appTethering,
        _en.appRemoved,
        _en.appOther
      ]) {
        expect(tree.where((n) => n.spoken.startsWith('$name, ')), hasLength(1),
            reason: name);
      }
      expect(nodesContaining(tree, 'Chrome'), isEmpty,
          reason: 'an app without traffic is not listed');
    });

    testWidgets('Polish', (tester) async {
      await _pump(tester,
          semantics: true, tall: true, locale: const Locale('pl'));
      final node =
          oneNodeWith(semanticsTree(tester), ['YouTube', _pl.mobile, _pl.wifi]);
      expect(node.spoken, contains(','));
    });

    testWidgets('the period chips know which is selected', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      var tree = semanticsTree(tester);
      expect(
          tree
              .where((n) => n.tappable && n.selected)
              .map((n) => n.label)
              .toList(),
          [_en.periodLast7Days]);
      await tester.tap(find.text(_en.periodToday));
      await settle(tester);
      tree = semanticsTree(tester);
      expect(
          tree
              .where((n) => n.tappable && n.selected)
              .map((n) => n.label)
              .toList(),
          [_en.periodToday]);
    });

    testWidgets('empty is announced, loading is labelled', (tester) async {
      await _pump(tester, apps: const [], semantics: true);
      final empty = oneNodeWith(semanticsTree(tester), [_en.dataByAppEmpty]);
      expect(empty.liveRegion, isTrue);

      await _pump(tester, semantics: true, andSettle: false);
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);
    });
  });

  group('touch targets (Android 48 px, iOS 44 px, labelled)', () {
    testWidgets('usual and awkward apps', (tester) async {
      for (final apps in [null, _awkwardApps()]) {
        final h = await _pump(tester, apps: apps, semantics: true);
        await sweepLayouts(tester, h,
            screen: 'Data by app targets',
            brightnesses: const [Brightness.light],
            positions: 3, check: () async {
          await expectAccessibleTargets(tester, screen: 'Data by app');
          final problems = tappableProblems(tester, semanticsTree(tester));
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    });
  });

  group('contrast (light and dark)', () {
    testWidgets('usual and awkward apps', (tester) async {
      for (final apps in [null, _awkwardApps()]) {
        final h = await _pump(tester, apps: apps, semantics: true);
        await sweepLayouts(tester, h,
            screen: 'Data by app contrast',
            scales: const [1.0, 2.0],
            devices: const [kIPhoneSE],
            positions: 3,
            settleFully: true, check: () async {
          expectTextContrast(tester, screen: 'Data by app');
          await expectAccessibleTargets(tester,
              screen: 'Data by app',
              android: false,
              ios: false,
              labeled: false,
              contrast: true);
        });
      }
    });
  });
}
