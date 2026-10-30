// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Welcome: responsive at every text scale on small and large phones, light and
// dark, English and Polish; no throw on wide layouts; readable by a screen reader.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/onboarding/welcome_screen.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

void main() {
  testWidgets('fits every phone, scale, brightness and language',
      (tester) async {
    final h = await pumpScreen(tester, const WelcomeScreen(),
        signedIn: false, historyDays: 0, semantics: true);
    await sweepFlow(tester, h, screen: 'Welcome');
  });

  testWidgets('does not throw on wide layouts', (tester) async {
    final h = await pumpScreen(tester, const WelcomeScreen(),
        signedIn: false, historyDays: 0);
    await sweepFlow(tester, h,
        screen: 'Welcome (wide)',
        devices: kWide,
        scales: const [1.0, 2.0, 3.0],
        targets: false);
  });

  testWidgets('text contrast', (tester) async {
    final h = await pumpScreen(tester, const WelcomeScreen(),
        signedIn: false, historyDays: 0);
    await expectReadableContrast(tester, h, screen: 'Welcome');
  });

  testWidgets('every button stays reachable by scrolling at 3x on an SE',
      (tester) async {
    await pumpScreen(tester, const WelcomeScreen(),
        signedIn: false, historyDays: 0, device: kIPhoneSE, textScale: 3.0);
    for (final label in [_en.signUp, _en.signIn]) {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
      final rect = tester.getRect(find.text(label));
      expect(rect.bottom, lessThanOrEqualTo(667));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.width, greaterThan(0));
    }
  });

  for (final (name, l, locale) in [
    ('English', _en, const Locale('en')),
    ('Polish', _pl, const Locale('pl')),
  ]) {
    testWidgets('semantics ($name): a heading, a tagline and two named buttons',
        (tester) async {
      await pumpScreen(tester, const WelcomeScreen(),
          signedIn: false, historyDays: 0, semantics: true, locale: locale);

      expect(tester.getSemantics(find.text(l.appName)),
          isSemantics(isHeader: true, label: l.appName));
      for (final label in [l.signUp, l.signIn]) {
        expect(semanticsNode(tester, exactly(label)),
            isSemantics(isButton: true, hasTapAction: true, label: label));
      }
      // The logo is decoration, not an unlabeled image.
      expect(semanticLabels(tester).where((t) => t.isEmpty), isEmpty);
      expect(semanticLabels(tester), contains(l.welcomeTagline));
    });
  }
}
