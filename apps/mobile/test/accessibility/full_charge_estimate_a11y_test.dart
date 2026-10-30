// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Settings > Device with an ESTIMATED full-charge capacity: the read-only row
// "Estimated full charge capacity" ("~3,600 mAh", "Estimated from the battery
// charge counter. Confidence: high") sits beside the design capacity and must
// fit and be readable at every text scale, on every phone, in both themes and
// both languages, and for a screen reader (no "tilde").
//
// The estimate is not a setting: it is the collector's reading, seeded here into
// the meta table exactly as the collector writes it (seedFullChargeEstimate).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/settings/settings_screen.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// One way the two capacities can look next to each other.
class _Case {
  const _Case(
    this.name, {
    this.knownDesign = true,
    this.mah = 3600,
    this.level = 100,
    this.confidence = FullChargeCapacityConfidence.high,
  });

  final String name;

  /// The Pixel 8 catalog figure (4575 mAh), or an unknown design capacity.
  final bool knownDesign;

  /// The estimate: a battery that holds [mah] when full, read at [level] %.
  final double mah;
  final int level;
  final FullChargeCapacityConfidence confidence;

  Settings get settings {
    final s = AppHarness.defaultSettings(HarnessPlatform.android);
    return knownDesign ? s : s.withDesignCapacity(DesignCapacity.unknown);
  }
}

const _cases = <_Case>[
  _Case('known design capacity, high confidence'),
  _Case('known design capacity, low confidence (counter at 50 %)',
      level: 50, confidence: FullChargeCapacityConfidence.low),
  _Case('unknown design capacity, medium confidence (counter at 80 %)',
      knownDesign: false,
      level: 80,
      confidence: FullChargeCapacityConfidence.medium),
  _Case('the widest plausible estimate (29 999 mAh)', mah: 29999),
];

/// A signed-in Android harness whose collector already holds the estimate of
/// [c]; the Settings screen is mounted on it.
Future<AppHarness> _pump(
  WidgetTester tester,
  _Case c, {
  bool semantics = true,
  Locale locale = const Locale('en'),
}) async {
  final h = await AppHarness.create(tester,
      platform: HarnessPlatform.android,
      settings: c.settings,
      historyDays: 0,
      locale: locale);
  final estimate =
      await seedFullChargeEstimate(h.db, mah: c.mah, level: c.level);
  expect(estimate.confidence, c.confidence,
      reason: 'the case describes the estimate it seeds');
  return pumpScreen(tester, const SettingsScreen(),
      harness: h,
      platform: HarnessPlatform.android,
      scaffold: true,
      locale: locale,
      semantics: semantics);
}

/// Brings [finder] fully on screen (the list builds rows beyond the viewport).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

String _plain(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  setUp(resetAssetCache);

  for (final c in _cases) {
    testWidgets(
        'Settings fits every phone, scale, theme and language: '
        '${c.name}', (tester) async {
      final h = await _pump(tester, c);
      // Not a vacuous pass: the estimate row is really there.
      await _scrollTo(tester, find.text(_en.estimatedFullChargeCapacity));
      expect(find.text(_en.estimatedFullChargeCapacity), findsOneWidget);
      await sweepFlow(tester, h,
          screen: 'Settings (estimate: ${c.name})', scroll: true);
    });
  }

  testWidgets('does not throw on wide layouts', (tester) async {
    final h = await _pump(tester, _cases.first, semantics: false);
    await sweepFlow(tester, h,
        screen: 'Settings (estimate, wide)',
        devices: kWide,
        scales: const [1.0, 2.0, 3.0],
        scroll: true,
        targets: false);
  });

  testWidgets('without an estimate the row is simply not there',
      (tester) async {
    final h = await AppHarness.create(tester,
        platform: HarnessPlatform.android, historyDays: 0);
    await pumpScreen(tester, const SettingsScreen(),
        harness: h,
        platform: HarnessPlatform.android,
        scaffold: true,
        semantics: true);
    await _scrollTo(tester, find.text(_en.detectAgain));
    expect(find.text(_en.estimatedFullChargeCapacity), findsNothing);
    expect(find.textContaining('~'), findsNothing);
    expect(find.text(_en.batteryCapacity), findsOneWidget);
  });

  // ------------------------------------------------------------ semantics

  testWidgets(
      'the estimate is marked with a tilde on screen and read without it',
      (tester) async {
    await _pump(tester, _cases.first);
    await _scrollTo(tester, find.text(_en.estimatedFullChargeCapacity));

    expect(find.text('~3,600 mAh'), findsOneWidget,
        reason: 'the estimate is marked on screen with units.approx');
    final estimate =
        semanticsNode(tester, RegExp('^${_en.estimatedFullChargeCapacity}, '));
    expect(estimate.label, contains('3,600 mAh'));
    expect(estimate.label, isNot(contains('~')),
        reason: 'VoiceOver would read "tilde"');
    expect(estimate.label,
        contains(_en.estimatedFullChargeCapacityBody(_en.confidenceHigh)));
    expect(estimate, isSemantics(hasTapAction: false, isButton: false),
        reason: 'read-only: the estimate is information, not an editor');

    // Beside it, the DESIGN capacity of the model: a different number, an
    // editable button, with its own source line.
    final design = semanticsNode(tester, RegExp('^${_en.batteryCapacity}, '));
    expect(design.label, contains('4,575 mAh'));
    expect(design.label, isNot(contains('3,600')));
    expect(design.label, contains(_en.detectedFromSpecs));
    expect(design, isSemantics(isButton: true, hasTapAction: true));
  });

  testWidgets('the Polish row reads naturally, with the confidence in Polish',
      (tester) async {
    final h = await _pump(tester, _cases.first, locale: const Locale('pl'));
    await h.setLocale(tester, const Locale('pl'));
    await _scrollTo(tester, find.text(_pl.estimatedFullChargeCapacity));

    final estimate =
        semanticsNode(tester, RegExp('^${_pl.estimatedFullChargeCapacity}, '));
    expect(
        estimate.label, contains(_plain(const Units(locale: 'pl').mah(3600))));
    expect(estimate.label, isNot(contains('~')));
    expect(estimate.label,
        contains(_pl.estimatedFullChargeCapacityBody(_pl.confidenceHigh)));
    expect(find.text(_en.estimatedFullChargeCapacity), findsNothing,
        reason: 'not the English title in a Polish UI');
  });

  testWidgets('every confidence is spoken in words, never as "none"',
      (tester) async {
    for (final c in [_cases[0], _cases[2], _cases[1]]) {
      await _pump(tester, c);
      await _scrollTo(tester, find.text(_en.estimatedFullChargeCapacity));
      final word = switch (c.confidence) {
        FullChargeCapacityConfidence.high => _en.confidenceHigh,
        FullChargeCapacityConfidence.medium => _en.confidenceMedium,
        FullChargeCapacityConfidence.low => _en.confidenceLow,
        FullChargeCapacityConfidence.none => fail('not an available estimate'),
      };
      final estimate = semanticsNode(
          tester, RegExp('^${_en.estimatedFullChargeCapacity}, '));
      expect(
          estimate.label, contains(_en.estimatedFullChargeCapacityBody(word)),
          reason: c.name);
      expect(estimate.label, isNot(contains(_en.unknownValue)));
    }
  });

  testWidgets(
      'an unknown design capacity and an estimate: "Battery capacity '
      'unavailable" is the design row, the estimate row stands apart',
      (tester) async {
    await _pump(tester, _cases[2]);
    await _scrollTo(tester, find.text(_en.estimatedFullChargeCapacity));
    final design = semanticsNode(tester, RegExp('^${_en.batteryCapacity}, '));
    expect(design.label, contains(_en.capacityUnavailable));
    expect(design.label, isNot(contains('mAh')),
        reason: 'no number invented for the model, estimate or not');
    final estimate =
        semanticsNode(tester, RegExp('^${_en.estimatedFullChargeCapacity}, '));
    expect(estimate.label, contains('3,600 mAh'));
  });

  testWidgets(
      'text contrast of the estimate row and the design capacity row, light '
      'and dark, English and Polish', (tester) async {
    // Only these two rows are judged, with the estimate centred on the screen
    // (a row cut by the screen edge is sampled half blank). The whole-list
    // check (`expectReadableContrast`) is not used here: a notification switch
    // row ("Weekly energy summary") fails it at some scroll offsets whether or
    // not the estimate row exists, which this test is not about.
    final h = await _pump(tester, _cases.first, semantics: false);
    final failures = <String>[];
    for (final b in Brightness.values) {
      for (final locale in kLocales) {
        final l = locale.languageCode == 'pl' ? _pl : _en;
        await h.configure(tester,
            textScale: 1.0,
            device: kIPhone17Pro,
            brightness: b,
            locale: locale);
        final title = find.text(l.estimatedFullChargeCapacity);
        await _scrollTo(tester, title);
        await Scrollable.ensureVisible(tester.element(title), alignment: 0.5);
        await tester.pump();
        try {
          await expectAccessibleTargets(tester,
              screen: 'Settings (estimate)',
              android: false,
              ios: false,
              labeled: false,
              contrast: true);
        } on TestFailure catch (e) {
          final message = _plain(e.message ?? '');
          for (final row in [
            l.estimatedFullChargeCapacity,
            l.batteryCapacity
          ]) {
            if (message.contains(row)) {
              failures
                  .add('${b.name} ${locale.languageCode}: "$row"\n$message');
            }
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n\n'));
  });
}
