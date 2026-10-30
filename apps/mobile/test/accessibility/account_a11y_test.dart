// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Account: signed out (form), signed in (sync section, destructive action) and
// the "cloud features are off" build, at every text scale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/data/auth_repositories.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/account_screen.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

void main() {
  final states = <String, ({bool signedIn, bool api})>{
    'signed in': (signedIn: true, api: true),
    'signed out': (signedIn: false, api: true),
    'cloud off': (signedIn: false, api: false),
  };
  for (final e in states.entries) {
    testWidgets('${e.key} fits every phone, scale, brightness and language',
        (tester) async {
      final h = await pumpScreen(tester, const AccountScreen(),
          signedIn: e.value.signedIn,
          apiConfigured: e.value.api,
          semantics: true);
      await sweepFlow(tester, h, screen: 'Account (${e.key})', scroll: true);
    });

    testWidgets('${e.key} does not throw on wide layouts', (tester) async {
      final h = await pumpScreen(tester, const AccountScreen(),
          signedIn: e.value.signedIn, apiConfigured: e.value.api);
      await sweepFlow(tester, h,
          screen: 'Account (${e.key}, wide)',
          devices: kWide,
          scales: const [1.0, 2.0, 3.0],
          scroll: true,
          targets: false);
    });
  }

  testWidgets('text contrast (signed in, signed out)', (tester) async {
    final h = await pumpScreen(tester, const AccountScreen());
    await expectReadableContrast(tester, h, screen: 'Account (signed in)');
    final out =
        await pumpScreen(tester, const AccountScreen(), signedIn: false);
    await expectReadableContrast(tester, out, screen: 'Account (signed out)');
  });

  testWidgets(
      'a very long email address wraps at "@" and "." and is never '
      'cut', (tester) async {
    const email =
        'a.very.long.name.indeed@subdomain.long-company-name.example.com';
    const user = User(id: 'u', email: email);
    final h = await AppHarness.create(tester,
        authRepository: HarnessAuthRepository(user: user));
    await pumpScreen(tester, const AccountScreen(),
        harness: h, semantics: true);
    await sweepFlow(tester, h,
        screen: 'Account (long email)',
        scroll: true,
        brightnesses: [Brightness.light]);
    // A screen reader gets the address as it is, without the invisible breaks.
    expect(semanticsNode(tester, RegExp('^${RegExp.escape(email)}\n')),
        isSemantics());
  });

  for (final (name, l, locale) in [
    ('English', _en, const Locale('en')),
    ('Polish', _pl, const Locale('pl')),
  ]) {
    testWidgets(
        'semantics signed in ($name): named buttons, the destructive '
        'one identifiable, a switch with its state', (tester) async {
      await pumpScreen(tester, const AccountScreen(),
          semantics: true, locale: locale);
      expect(
          semanticsNode(tester, RegExp('^tester@example\\.com\n')),
          isSemantics(
              label: 'tester@example.com\n${l.accountPlan}: ${l.planFree}'));
      expect(semanticsNode(tester, exactly(l.signOut)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(semanticsNode(tester, RegExp('^${l.cloudSyncTitle}\\n')),
          isSemantics(hasToggledState: true, isToggled: false));
      expect(semanticsCount(tester, RegExp('^${l.cloudSyncTitle}\\n')), 1,
          reason: 'the switch name is not doubled');
      final delete = semanticsNode(tester, exactly(l.deleteAccount));
      expect(delete, isSemantics(isButton: true, hasTapAction: true));
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget,
          reason: 'the destructive action is not identified by colour alone');
      expect(tester.getSemantics(find.text(l.account)),
          isSemantics(isHeader: true));
    });

    testWidgets(
        'semantics signed out ($name): labelled fields, heading and '
        'mode switch', (tester) async {
      await pumpScreen(tester, const AccountScreen(),
          signedIn: false, semantics: true, locale: locale);
      expect(tester.getSemantics(find.text(l.signIn).first),
          isSemantics(isHeader: true));
      expect(semanticsNode(tester, exactly(l.email)),
          isSemantics(isTextField: true));
      expect(semanticsNode(tester, exactly(l.password)),
          isSemantics(isTextField: true, isObscured: true));
      expect(semanticsNode(tester, exactly(l.noAccount)),
          isSemantics(isButton: true, hasTapAction: true));
    });
  }

  testWidgets('cloud off: the explanation is a heading with its text',
      (tester) async {
    await pumpScreen(tester, const AccountScreen(),
        signedIn: false, apiConfigured: false, semantics: true);
    expect(tester.getSemantics(find.text(_en.accountUnavailableTitle)),
        isSemantics(isHeader: true, label: _en.accountUnavailableTitle));
    expect(semanticLabels(tester), contains(_en.accountUnavailableBody));
  });

  for (final scale in [1.0, 2.0, 3.0]) {
    for (final locale in kLocales) {
      final l = locale.languageCode == 'pl' ? _pl : _en;
      testWidgets(
          'delete dialog at ${scale}x (${locale.languageCode}) on an '
          'SE scrolls, names the action and keeps both buttons',
          (tester) async {
        await pumpScreen(tester, const AccountScreen(),
            semantics: true,
            device: kIPhoneSE,
            textScale: scale,
            locale: locale);
        await tester.ensureVisible(find.text(l.deleteAccount));
        await tester.pump();
        await tester.tap(find.text(l.deleteAccount));
        await settle(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoFlutterErrors(tester, screen: 'Delete dialog');
        expectNoBrokenText(tester, screen: 'Delete dialog');
        expect(
            tester.getSemantics(find
                .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.text(l.deleteAccount))
                .first),
            isSemantics(isHeader: true));
        await tester.ensureVisible(find.text(l.cancel));
        expect(find.text(l.cancel).hitTestable(), findsOneWidget);
        await expectAccessibleTargets(tester, screen: 'Delete dialog');
        await tester.tap(find.text(l.cancel));
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }

  testWidgets('confirming the deletion deletes the account', (tester) async {
    final h = await pumpScreen(tester, const AccountScreen(), semantics: true);
    await tester.ensureVisible(find.text(_en.deleteAccount));
    await tester.pump();
    await tester.tap(find.text(_en.deleteAccount));
    await settle(tester);
    // The dialog's red action carries the same name as the button behind it.
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, _en.deleteAccount)));
    await settle(tester);
    expect((h.authRepository as MockAuthRepository).accountDeleted, isTrue);
  });

  testWidgets('a failed sign-in on the Account screen is announced',
      (tester) async {
    await pumpScreen(tester, const AccountScreen(),
        signedIn: false, semantics: true);
    await tester.enterText(find.byType(TextField).first, 'tester@example.com');
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.widgetWithText(FilledButton, _en.signIn));
    await settle(tester);
    expect(semanticsNode(tester, exactly(_en.authInvalidCredentials)),
        isSemantics(isLiveRegion: true));
  });
}
