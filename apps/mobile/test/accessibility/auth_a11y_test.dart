// Auth screen (create account / sign in): responsive, labelled fields, an
// announced error, reachable buttons.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/onboarding/auth_screen.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

void main() {
  for (final register in [true, false]) {
    final name = register ? 'Create account' : 'Sign in';

    testWidgets('$name fits every phone, scale, brightness and language',
        (tester) async {
      final h = await pumpScreen(tester, AuthScreen(register: register),
          signedIn: false, historyDays: 0, semantics: true);
      await sweepFlow(tester, h, screen: name);
    });

    testWidgets('$name does not throw on wide layouts', (tester) async {
      final h = await pumpScreen(tester, AuthScreen(register: register),
          signedIn: false, historyDays: 0);
      await sweepFlow(tester, h,
          screen: '$name (wide)',
          devices: kWide,
          scales: const [1.0, 2.0, 3.0],
          targets: false);
    });
  }

  testWidgets(
      'with the keyboard up at 2x on an SE the form still scrolls to '
      'its submit button', (tester) async {
    await pumpScreen(tester, const AuthScreen(register: true),
        signedIn: false, historyDays: 0, device: kIPhoneSE, textScale: 2.0);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump();
    expectNoFlutterErrors(tester, screen: 'Auth with keyboard');
    await tester.dragUntilVisible(find.widgetWithText(FilledButton, _en.signUp),
        find.byType(SingleChildScrollView), const Offset(0, -80));
    final rect = tester.getRect(find.widgetWithText(FilledButton, _en.signUp));
    expect(rect.bottom, lessThanOrEqualTo(667 - 300),
        reason: 'the button must end above the keyboard');
  });

  testWidgets('text contrast', (tester) async {
    final h = await pumpScreen(tester, const AuthScreen(register: true),
        signedIn: false, historyDays: 0);
    await expectReadableContrast(tester, h, screen: 'Create account');
  });

  testWidgets('the error text is readable (contrast)', (tester) async {
    final h = await pumpScreen(tester, const AuthScreen(register: false),
        signedIn: false, historyDays: 0);
    await tester.enterText(find.byType(TextField).first, 'tester@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, _en.signIn));
    await settle(tester);
    expect(find.text(_en.authInvalidCredentials), findsOneWidget);
    await expectReadableContrast(tester, h, screen: 'Sign in with an error');
  });

  for (final (name, l, locale) in [
    ('English', _en, const Locale('en')),
    ('Polish', _pl, const Locale('pl')),
  ]) {
    testWidgets(
        'semantics ($name): labelled fields, an obscured password, '
        'a heading and a button', (tester) async {
      await pumpScreen(tester, const AuthScreen(register: true),
          signedIn: false, historyDays: 0, semantics: true, locale: locale);

      expect(tester.getSemantics(find.text(l.authCreateTitle)),
          isSemantics(isHeader: true, label: l.authCreateTitle));
      expect(semanticsNode(tester, exactly(l.email)),
          isSemantics(isTextField: true, label: l.email));
      expect(semanticsNode(tester, exactly(l.password)),
          isSemantics(isTextField: true, isObscured: true, label: l.password));
      // The helper text is its own node, read right after the field.
      expect(semanticLabels(tester), contains(l.passwordHint));
      expect(semanticsNode(tester, exactly(l.signUp)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(semanticsNode(tester, exactly(l.haveAccount)),
          isSemantics(isButton: true, hasTapAction: true));
    });
  }

  testWidgets(
      'a failed sign-in is announced (live region) and the form is '
      'reusable', (tester) async {
    final h = await pumpScreen(tester, const AuthScreen(register: false),
        signedIn: false, historyDays: 0, semantics: true);
    await tester.enterText(find.byType(TextField).first, 'tester@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong password');
    await tester.tap(find.widgetWithText(FilledButton, _en.signIn));
    await settle(tester);

    expect(h.container(tester), isNotNull);
    final error = semanticsNode(tester, exactly(_en.authInvalidCredentials));
    expect(error, isSemantics(isLiveRegion: true));
    expect(find.widgetWithText(FilledButton, _en.signIn), findsOneWidget,
        reason: 'the submit button is back after the failure');
    expectNoFlutterErrors(tester, screen: 'Auth after a failed sign-in');
  });

  testWidgets('while it works the submit button keeps its name and says wait',
      (tester) async {
    final repository = _SlowAuthRepository();
    final h = await AppHarness.create(tester,
        signedIn: false, historyDays: 0, authRepository: repository);
    await pumpScreen(tester, const AuthScreen(register: false),
        harness: h, semantics: true);
    await tester.enterText(find.byType(TextField).first, 'tester@example.com');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.widgetWithText(FilledButton, _en.signIn));
    await tester.pump(const Duration(milliseconds: 50));

    final busy = semanticsNode(tester, exactly(_en.signIn));
    expect(busy, isSemantics(isButton: true, hint: _en.authBusy));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.release.complete();
    await settle(tester);
  });
}

/// A sign-in that takes as long as the test wants.
class _SlowAuthRepository extends HarnessAuthRepository {
  final release = Completer<void>();

  @override
  Future<AuthSession> signInWithEmail(
      {required String email, required String password}) async {
    await release.future;
    return super.signInWithEmail(email: email, password: password);
  }
}
