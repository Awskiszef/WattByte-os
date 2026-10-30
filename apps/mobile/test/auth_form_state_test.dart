// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/features/auth/data/api_auth_repository.dart';
import 'package:wattbyte/features/auth/data/auth_repositories.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/account_screen.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/onboarding/auth_screen.dart';

import 'support/app_harness.dart';

/// The e-mail / password form (`AuthForm`, inside `AuthScreen` and the signed-out
/// `AccountScreen`) through the real widgets, theme and l10n. Simulator bug 8:
/// the form kept a stale "Wrong email or password" after switching to
/// registration and kept the e-mail after sign-in.
///
/// The backend is the REAL `ApiAuthRepository` over a scripted HTTP fake, so a
/// status code travels the same road as in the app, and the "leaks" below prove
/// that no server text ever reaches the screen.
void main() {
  final en = AppLocalizationsEn();
  final pl = AppLocalizationsPl();

  const email = 'ola@example.com';
  const password = 'correct horse battery';

  final userJson = {
    'id': '11111111-1111-4111-8111-111111111111',
    'email': email,
    'displayName': null,
    'plan': 'free',
    'createdAt': '2026-10-13T10:00:00.000Z',
  };
  http.Response session() => FakeBackend.json({
        'user': userJson,
        'tokens': {
          'accessToken': 'a.b.c',
          'refreshToken': 'r',
          'expiresIn': 900,
          'tokenType': 'Bearer',
        },
      });

  late FakeBackend backend;

  /// A harness whose auth repository is the real one over [backend].
  Future<AppHarness> harness(WidgetTester tester,
      {Locale locale = const Locale('en')}) async {
    backend = FakeBackend();
    final repo = ApiAuthRepository(ApiFactory(
        const ApiConfig('http://api.test'),
        httpClient: backend.client));
    return AppHarness.create(tester,
        signedIn: false,
        onboarded: true,
        authRepository: repo,
        locale: locale,
        historyDays: 0);
  }

  Future<AppHarness> pumpAuth(WidgetTester tester,
      {bool register = false, Locale locale = const Locale('en')}) async {
    final h = await harness(tester, locale: locale);
    await pumpScreen(tester, AuthScreen(register: register),
        harness: h, locale: locale);
    return h;
  }

  Finder emailField(AppLocalizations l) =>
      find.widgetWithText(TextField, l.email);
  Finder passwordField(AppLocalizations l) =>
      find.widgetWithText(TextField, l.password);
  Finder submit(String label) => find.widgetWithText(FilledButton, label);

  String textOf(WidgetTester tester, Finder f) =>
      tester.widget<TextField>(f).controller!.text;

  Future<void> fill(WidgetTester tester, AppLocalizations l,
      {String mail = email, String pass = password}) async {
    await tester.enterText(emailField(l), mail);
    await tester.enterText(passwordField(l), pass);
    await tester.pump();
  }

  Future<void> send(WidgetTester tester, String label) async {
    await tester.tap(submit(label));
    await settle(tester);
  }

  group('a fresh form', () {
    testWidgets('is empty, shows no error and can be submitted',
        (tester) async {
      await pumpAuth(tester);
      expect(textOf(tester, emailField(en)), isEmpty);
      expect(textOf(tester, passwordField(en)), isEmpty);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(
          tester.widget<FilledButton>(submit(en.signIn)).onPressed, isNotNull);
      expectNoFlutterErrors(tester, screen: 'Sign in');
    });

    testWidgets('an empty submit sends nothing and complains about nothing',
        (tester) async {
      await pumpAuth(tester);
      await send(tester, en.signIn);
      expect(backend.requests, isEmpty);
      await tester.enterText(emailField(en), email); // password still empty
      await send(tester, en.signIn);
      expect(backend.requests, isEmpty);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('the e-mail is sent trimmed and in lower case', (tester) async {
      await pumpAuth(tester);
      backend.routes['POST /api/v1/auth/login'] = (_) => session();
      await fill(tester, en, mail: '  Ola@Example.COM ');
      await send(tester, en.signIn);
      expect(backend.requests.single.body!['email'], 'ola@example.com');
      expect(backend.requests.single.body!['password'], password);
    });
  });

  group('errors, in English and in Polish', () {
    // A server that says things the user must never see.
    const leaks = {
      'invalid_credentials':
          'password_hash mismatch for user id 4711 in table users',
      'email_taken':
          'duplicate key value violates unique constraint "users_email_key"',
      'validation': 'body/email must match format "email" at /api/v1/auth',
      'rate_limited':
          'Rate limit exceeded, retry in 41s (bucket auth:10.0.0.7)',
      'internal': 'connection to server at "10.0.0.5", port 5432 failed',
    };

    // route, status, code, expected message in each language
    final cases =
        <(String, String, int, String?, String Function(AppLocalizations))>[
      (
        'wrong password',
        'login',
        401,
        'invalid_credentials',
        (l) => l.authInvalidCredentials
      ),
      ('invalid input', 'login', 400, 'validation', (l) => l.authInvalidInput),
      ('rate limited', 'login', 429, 'rate_limited', (l) => l.authRateLimited),
      ('server error', 'login', 500, 'internal', (l) => l.authServerError),
      ('bad gateway page', 'login', 502, null, (l) => l.authServerError),
      ('network', 'login', -1, null, (l) => l.authNetworkError),
      ('e-mail taken', 'register', 409, 'email_taken', (l) => l.authEmailTaken),
      (
        'invalid input (register)',
        'register',
        400,
        'validation',
        (l) => l.authInvalidInput
      ),
    ];

    for (final locale in [const Locale('en'), const Locale('pl')]) {
      final l = locale.languageCode == 'pl' ? pl : en;
      for (final c in cases) {
        final (label, route, status, code, expected) = c;
        testWidgets('${locale.languageCode}: $label', (tester) async {
          final h = await pumpAuth(tester,
              register: route == 'register', locale: locale);
          final path = '/api/v1/auth/$route';
          if (status == -1) {
            backend.offline = true;
          } else {
            backend.routes['POST $path'] = (_) => code == null
                ? http.Response('<html>502 Bad Gateway nginx</html>', status)
                : http.Response(
                    jsonEncode({
                      'error': {'code': code, 'message': leaks[code]}
                    }),
                    status,
                    headers: {'content-type': 'application/json'});
          }
          await fill(tester, l);
          await send(tester, route == 'register' ? l.signUp : l.signIn);

          expect(find.text(expected(l)), findsOneWidget,
              reason: 'the message comes from the ARB file ($label)');
          for (final leak in leaks.values) {
            expect(find.textContaining(leak.substring(0, 18)), findsNothing,
                reason: 'the server\'s own words never reach the screen');
          }
          expect(find.textContaining('nginx'), findsNothing);
          expect(find.textContaining('5432'), findsNothing);
          // The form is usable again.
          expect(
              tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
              isNotNull);
          expect(await h.tokenStore.read(), isNull,
              reason: 'a failure stores no session');
          expectNoFlutterErrors(tester, screen: 'Sign in error ($label)');
        });
      }
    }

    testWidgets('each language has its own text for the same failure',
        (tester) async {
      // Guards the test above: the two expected strings must differ, or the
      // loop would pass with the wrong language on screen.
      for (final c in cases) {
        expect(c.$5(en), isNot(c.$5(pl)), reason: c.$1);
      }
    });
  });

  group('switching between sign in and create account', () {
    testWidgets('clears the password and the stale error', (tester) async {
      await pumpAuth(tester);
      backend.routes['POST /api/v1/auth/login'] =
          (_) => FakeBackend.error(401, 'invalid_credentials');
      await fill(tester, en);
      await send(tester, en.signIn);
      expect(find.text(en.authInvalidCredentials), findsOneWidget);

      // Switch to registration.
      await tester.tap(find.widgetWithText(TextButton, en.noAccount));
      await settle(tester);
      expect(find.text(en.authInvalidCredentials), findsNothing,
          reason:
              'bug 8: "Wrong email or password" stayed on the register form');
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(textOf(tester, passwordField(en)), isEmpty,
          reason: 'a password typed for one form is not carried to the other');
      expect(submit(en.signUp), findsOneWidget);
      expect(find.text(en.authCreateTitle), findsOneWidget);

      // ... and back again: still clean.
      await fill(tester, en, pass: 'another password');
      await tester.tap(find.widgetWithText(TextButton, en.haveAccount));
      await settle(tester);
      expect(textOf(tester, passwordField(en)), isEmpty);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      expect(submit(en.signIn), findsOneWidget);
      expectNoFlutterErrors(tester, screen: 'Auth form after switching');
    });

    testWidgets('a new failure after switching shows its own message',
        (tester) async {
      await pumpAuth(tester);
      backend.routes['POST /api/v1/auth/login'] =
          (_) => FakeBackend.error(401, 'invalid_credentials');
      backend.routes['POST /api/v1/auth/register'] =
          (_) => FakeBackend.error(409, 'email_taken');
      await fill(tester, en);
      await send(tester, en.signIn);
      expect(find.text(en.authInvalidCredentials), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, en.noAccount));
      await settle(tester);
      await fill(tester, en);
      await send(tester, en.signUp);
      expect(find.text(en.authEmailTaken), findsOneWidget);
      expect(find.text(en.authInvalidCredentials), findsNothing,
          reason: 'only the latest failure is shown');
    });

    testWidgets(
        'an error that appears for one form disappears on the switch '
        'and does not come back when switching again', (tester) async {
      await pumpAuth(tester, register: true);
      backend.routes['POST /api/v1/auth/register'] =
          (_) => FakeBackend.error(409, 'email_taken');
      await fill(tester, en);
      await send(tester, en.signUp);
      expect(find.text(en.authEmailTaken), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(TextButton).first);
        await settle(tester);
        expect(find.text(en.authEmailTaken), findsNothing, reason: 'switch $i');
      }
    });

    testWidgets('the Polish form behaves the same', (tester) async {
      await pumpAuth(tester, locale: const Locale('pl'));
      backend.routes['POST /api/v1/auth/login'] =
          (_) => FakeBackend.error(401, 'invalid_credentials');
      await fill(tester, pl);
      await send(tester, pl.signIn);
      expect(find.text(pl.authInvalidCredentials), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, pl.noAccount));
      await settle(tester);
      expect(find.text(pl.authInvalidCredentials), findsNothing);
      expect(textOf(tester, passwordField(pl)), isEmpty);
    });
  });

  group('after a successful sign in or sign up', () {
    testWidgets('sign in: both fields are cleared', (tester) async {
      final h = await pumpAuth(tester);
      backend.routes['POST /api/v1/auth/login'] = (_) => session();
      await fill(tester, en);
      await send(tester, en.signIn);
      // (In the app the start gate now replaces this screen; here it stays, so
      // the form can be inspected.)
      expect(h.container(tester).read(authControllerProvider).value,
          isA<SignedIn>());
      expect(textOf(tester, emailField(en)), isEmpty,
          reason: 'bug 8: the e-mail stayed in the form after sign-in');
      expect(textOf(tester, passwordField(en)), isEmpty);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('sign up: both fields are cleared', (tester) async {
      final h = await pumpAuth(tester, register: true);
      backend.routes['POST /api/v1/auth/register'] = (_) => http.Response(
          session().body, 201,
          headers: {'content-type': 'application/json'});
      await fill(tester, en);
      await send(tester, en.signUp);
      expect(h.container(tester).read(authControllerProvider).value,
          isA<SignedIn>());
      expect(textOf(tester, emailField(en)), isEmpty);
      expect(textOf(tester, passwordField(en)), isEmpty);
    });

    testWidgets('the session is stored, and the password is never kept',
        (tester) async {
      final h = await pumpAuth(tester);
      backend.routes['POST /api/v1/auth/login'] = (_) => session();
      await fill(tester, en);
      await send(tester, en.signIn);
      final stored = await h.tokenStore.read();
      expect(stored, isNotNull);
      expect(stored!.user.email, email);
      expect(
          h.prefs
              .getKeys()
              .where((k) => h.prefs.get(k).toString().contains(password)),
          isEmpty,
          reason: 'the password is in no preference');
    });
  });

  group('while a request is running', () {
    /// The form over a server that answers only when the test says so.
    Future<_GatedClient> pumpGated(WidgetTester tester,
        {bool semantics = false}) async {
      final client = _GatedClient();
      final repo = ApiAuthRepository(
          ApiFactory(const ApiConfig('http://api.test'), httpClient: client));
      final h = await AppHarness.create(tester,
          signedIn: false,
          onboarded: true,
          authRepository: repo,
          historyDays: 0);
      await pumpScreen(tester, const AuthScreen(register: false),
          harness: h, semantics: semantics);
      return client;
    }

    testWidgets('the fields and both buttons are disabled, then enabled again',
        (tester) async {
      final client = await pumpGated(tester);
      await fill(tester, en);
      await tester.tap(submit(en.signIn));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
          reason: 'a second tap cannot send a second request');
      expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
      expect(tester.widget<TextField>(emailField(en)).enabled, isFalse);
      expect(tester.widget<TextField>(passwordField(en)).enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      client.answer(401, '{"error":{"code":"invalid_credentials"}}');
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
          tester.widget<FilledButton>(submit(en.signIn)).onPressed, isNotNull);
      expect(tester.widget<TextField>(emailField(en)).enabled, isTrue);
      expect(find.text(en.authInvalidCredentials), findsOneWidget);
    });

    testWidgets('the busy button keeps its name for a screen reader',
        (tester) async {
      final client = await pumpGated(tester, semantics: true);
      await fill(tester, en);
      await tester.tap(submit(en.signIn));
      await tester.pump(const Duration(milliseconds: 100));
      expect(semanticsWithLabel(tester, en.signIn), isNotEmpty,
          reason: 'the spinner replaces the text, not the name');
      client.answer(401, '{}');
      await settle(tester);
    });

    testWidgets(
        'submitting again from the keyboard while busy sends nothing '
        'more', (tester) async {
      final client = await pumpGated(tester);
      await fill(tester, en);
      await tester.tap(submit(en.signIn));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 50));
      expect(client.requests, 1);
      client.answer(401, '{}');
      await settle(tester);
    });
  });

  group('the Account screen', () {
    testWidgets(
        'shows the same form when signed out, and starts empty after '
        'a sign-out', (tester) async {
      backend = FakeBackend();
      final repo = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      backend.routes['GET /api/v1/me'] = (_) => FakeBackend.json(userJson);
      final h = await AppHarness.create(tester,
          signedIn: true, authRepository: repo, historyDays: 0);
      await pumpScreen(tester, const AccountScreen(), harness: h);
      expect(find.text(en.signOut), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, en.signOut));
      await settle(tester);
      expect(emailField(en), findsOneWidget);
      expect(textOf(tester, emailField(en)), isEmpty);
      expect(textOf(tester, passwordField(en)), isEmpty);

      // The same switching rules as on the start screens.
      backend.routes['POST /api/v1/auth/login'] =
          (_) => FakeBackend.error(401, 'invalid_credentials');
      await fill(tester, en);
      await send(tester, en.signIn);
      expect(find.text(en.authInvalidCredentials), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, en.noAccount));
      await settle(tester);
      expect(find.text(en.authInvalidCredentials), findsNothing);
      expect(textOf(tester, passwordField(en)), isEmpty);
    });

    testWidgets(
        'a successful sign-in from the Account screen leaves the form '
        'empty for the next sign-out', (tester) async {
      backend = FakeBackend();
      final repo = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      backend.routes['POST /api/v1/auth/login'] = (_) => session();
      backend.routes['GET /api/v1/me'] = (_) => FakeBackend.json(userJson);
      final h = await AppHarness.create(tester,
          signedIn: false, authRepository: repo, historyDays: 0);
      await pumpScreen(tester, const AccountScreen(), harness: h);
      await fill(tester, en);
      await send(tester, en.signIn);
      expect(find.text(en.signOut), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, en.signOut));
      await settle(tester);
      expect(textOf(tester, emailField(en)), isEmpty);
      expect(textOf(tester, passwordField(en)), isEmpty);
    });

    testWidgets('a build without a server shows no form at all',
        (tester) async {
      final h = await AppHarness.create(tester,
          signedIn: false,
          apiConfigured: false,
          authRepository: const UnavailableAuthRepository(),
          historyDays: 0);
      await pumpScreen(tester, const AccountScreen(), harness: h);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.accountUnavailableTitle), findsOneWidget);
    });
  });
}

/// An HTTP client whose answer is held back until the test gives it.
class _GatedClient extends http.BaseClient {
  final Completer<http.Response> _gate = Completer();
  int requests = 0;

  void answer(int status, String body) =>
      _gate.complete(http.Response(body, status,
          headers: {'content-type': 'application/json'}));

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    final r = await _gate.future;
    return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode,
        headers: r.headers, request: request);
  }
}
