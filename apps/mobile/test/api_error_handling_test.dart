// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/features/ai/ai_input_builder.dart';
import 'package:wattbyte/features/ai/ai_service.dart';
import 'package:wattbyte/features/auth/data/api_auth_repository.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';

import 'support/app_harness.dart' show pumpApp, settle;
import 'support/fake_auth.dart';
import 'support/fake_backend.dart';

/// How a failed API call becomes something the app can act on, and that no
/// server text ever reaches the user:
///
///   HTTP / transport  ->  [ApiFailure] (`ApiFailure.of`, `guarded`)
///   ApiFailure        ->  [AuthError]  (`ApiAuthRepository`)  ->  localized text
///   ApiFailure        ->  [AiError]    (`AiService`)          ->  localized text
///
/// Retry and back-off (what to do next) are covered by the sync tests, not here.
/// The localized text itself is asserted in `auth_form_state_test.dart`.
void main() {
  const base = ApiConfig('http://api.test');

  group('ApiFailure.of: status and body', () {
    ApiFailure of(int status, [String? body]) =>
        ApiFailure.of(api.ApiException(status, body));

    test('every status the API uses maps to one kind', () {
      const expected = <int, ApiFailureKind>{
        400: ApiFailureKind.badRequest,
        401: ApiFailureKind.unauthorized,
        402: ApiFailureKind.other,
        403: ApiFailureKind.other,
        404: ApiFailureKind.notFound,
        405: ApiFailureKind.other,
        409: ApiFailureKind.conflict,
        410: ApiFailureKind.other,
        418: ApiFailureKind.other,
        422: ApiFailureKind.other,
        429: ApiFailureKind.rateLimited,
        500: ApiFailureKind.server,
        501: ApiFailureKind.server,
        502: ApiFailureKind.server,
        503: ApiFailureKind.server,
        504: ApiFailureKind.server,
        599: ApiFailureKind.server,
      };
      for (final e in expected.entries) {
        final f = of(e.key);
        expect(f.kind, e.value, reason: 'HTTP ${e.key}');
        expect(f.status, e.key, reason: 'the status is kept');
      }
    });

    test('a transport failure is a network failure, not a 400', () {
      // The generated client reports a socket error as ApiException(400, ...)
      // with the inner exception set; a real 400 never has one.
      for (final inner in <Exception>[
        const SocketException('Connection refused'),
        const HandshakeException('bad certificate'),
        http.ClientException('Connection closed'),
        const FormatException('deserialization'),
      ]) {
        for (final status in [400, 500]) {
          final f = ApiFailure.of(api.ApiException.withInner(
              status, 'Socket operation failed', inner, StackTrace.empty));
          expect(f.kind, ApiFailureKind.network, reason: '$inner as $status');
          expect(f.status, isNull);
        }
      }
      expect(of(400).kind, ApiFailureKind.badRequest);
    });

    test('a TimeoutException is a timeout', () {
      expect(
          ApiFailure.of(TimeoutException('slow')).kind, ApiFailureKind.timeout);
    });

    test('an ApiFailure passes through unchanged; anything else is "other"',
        () {
      const f = ApiFailure(ApiFailureKind.conflict, status: 409, code: 'x');
      expect(identical(ApiFailure.of(f), f), isTrue);
      for (final e in <Object>[
        StateError('boom'),
        const FormatException('bad'),
        ArgumentError('x'),
        'a string',
        42,
        Exception('plain'),
      ]) {
        expect(ApiFailure.of(e).kind, ApiFailureKind.other, reason: '$e');
      }
    });

    test('the {error: {code, message}} envelope is read', () {
      final f = of(409,
          '{"error":{"code":"email_taken","message":"An account with this email already exists"}}');
      expect(f.kind, ApiFailureKind.conflict);
      expect(f.code, 'email_taken');
      expect(f.message, 'An account with this email already exists');
    });

    test('an unknown code is kept as it is and changes nothing about the kind',
        () {
      final f = of(400,
          '{"error":{"code":"a_code_from_next_year","message":"whatever"}}');
      expect(f.kind, ApiFailureKind.badRequest);
      expect(f.code, 'a_code_from_next_year');
      final g = of(503, '{"error":{"code":"","message":""}}');
      expect(g.kind, ApiFailureKind.server);
      expect(g.code, '');
    });

    test('every code of the API contract is read (docs/api.md)', () {
      for (final code in [
        'validation',
        'invalid_credentials',
        'email_taken',
        'unauthorized',
        'not_found',
        'rate_limited',
        'ai_quota_exceeded',
        'ai_unavailable',
        'feature_disabled',
        'internal',
      ]) {
        expect(of(400, '{"error":{"code":"$code","message":"m"}}').code, code);
      }
    });

    test('bodies that are not the envelope give no code and no message', () {
      for (final body in <String?>[
        null,
        '',
        ' ',
        '\n',
        '<html><body><h1>502 Bad Gateway</h1></body></html>',
        '<!DOCTYPE html><title>Captive portal</title>',
        'Bad Gateway',
        '{}',
        '[]',
        'null',
        '"just a string"',
        '123',
        '{"error":"flat string"}',
        '{"error":null}',
        '{"error":[]}',
        '{"error":{}}',
        '{"error":{"code":42,"message":["x"]}}',
        '{"error":{"code":',
        '{"message":"top-level message"}',
        '\u0000\u0001',
      ]) {
        final f = of(502, body);
        expect(f.kind, ApiFailureKind.server, reason: '"$body"');
        expect(f.code, isNull, reason: '"$body"');
        expect(f.message, isNull, reason: '"$body"');
      }
    });

    test('a huge or hostile body does not hang or throw', () {
      final huge = '{"error":{"code":"c","message":"${'x' * 2000000}"}}';
      final f = of(500, huge);
      expect(f.code, 'c');
      final deep = '${'{"a":' * 3000}1${'}' * 3000}';
      expect(of(500, deep).kind, ApiFailureKind.server);
      expect(of(500, '{"error":{"code":"${'é' * 5000}"}}').code, 'é' * 5000);
    });

    test('transient failures are the ones a later try can fix', () {
      for (final k in [
        ApiFailureKind.network,
        ApiFailureKind.timeout,
        ApiFailureKind.server,
      ]) {
        expect(ApiFailure(k).isTransient, isTrue, reason: '$k');
      }
      for (final k in [
        ApiFailureKind.unauthorized,
        ApiFailureKind.badRequest,
        ApiFailureKind.notFound,
        ApiFailureKind.conflict,
        ApiFailureKind.other,
      ]) {
        expect(ApiFailure(k).isTransient, isFalse, reason: '$k');
      }
      expect(
          const ApiFailure(ApiFailureKind.rateLimited,
                  code: 'ai_quota_exceeded')
              .isTransient,
          isFalse,
          reason: 'the daily AI quota resets with the day, not with a retry');
    });

    test('toString never prints the server message', () {
      final f = of(500,
          '{"error":{"code":"internal","message":"duplicate key value violates unique constraint users_email_key"}}');
      expect(f.toString(), isNot(contains('duplicate key')));
      expect(f.toString(), isNot(contains('users_email_key')));
    });
  });

  group('guarded', () {
    test('returns the value', () async {
      expect(await guarded(() async => 7), 7);
    });

    test('turns an ApiException into an ApiFailure', () async {
      await expectLater(
          guarded<int>(() async => throw api.ApiException(404, '{}')),
          throwsA(isA<ApiFailure>()
              .having((f) => f.kind, 'kind', ApiFailureKind.notFound)));
    });

    test('a synchronous throw is mapped too', () async {
      await expectLater(
          guarded<int>(() => throw api.ApiException(409, '')),
          throwsA(isA<ApiFailure>()
              .having((f) => f.kind, 'kind', ApiFailureKind.conflict)));
    });

    test('a call that never answers ends in a timeout failure', () async {
      final started = DateTime.now();
      await expectLater(
          guarded<int>(() => Completer<int>().future,
              timeout: const Duration(milliseconds: 30)),
          throwsA(isA<ApiFailure>()
              .having((f) => f.kind, 'kind', ApiFailureKind.timeout)));
      expect(DateTime.now().difference(started).inSeconds, lessThan(5));
    });

    test('a slow answer inside the limit is delivered', () async {
      expect(
          await guarded(
              () => Future<String>.delayed(
                  const Duration(milliseconds: 10), () => 'ok'),
              timeout: const Duration(seconds: 2)),
          'ok');
    });

    test('an ApiFailure thrown by the call is not wrapped twice', () async {
      const failure = ApiFailure(ApiFailureKind.server, status: 503);
      await expectLater(
          guarded<int>(() async => throw failure), throwsA(same(failure)));
    });
  });

  group('ApiAuthRepository: every failure becomes an AuthError', () {
    late FakeBackend backend;
    late ApiAuthRepository repo;

    setUp(() {
      backend = FakeBackend();
      repo = ApiAuthRepository(ApiFactory(base, httpClient: backend.client));
    });

    /// Runs [call] against a backend answering [status] / [body].
    Future<AuthError> failureOf(
      String route,
      int status,
      Future<Object?> Function() call, [
      String? code,
    ]) async {
      backend.routes[route] = (_) => code == null
          ? http.Response('', status)
          : FakeBackend.error(status, code);
      try {
        await call();
      } on AuthException catch (e) {
        return e.error;
      }
      fail('HTTP $status did not throw');
    }

    Future<Object?> signIn() =>
        repo.signInWithEmail(email: 'a@b.co', password: 'password123');
    Future<Object?> signUp() =>
        repo.signUpWithEmail(email: 'a@b.co', password: 'password123');

    test('sign in: the whole status table', () async {
      const login = 'POST /api/v1/auth/login';
      const table = <int, AuthError>{
        400: AuthError.invalidInput,
        401: AuthError.invalidCredentials,
        403: AuthError.server,
        404: AuthError.server,
        409: AuthError.emailTaken,
        422: AuthError.server,
        429: AuthError.rateLimited,
        500: AuthError.server,
        502: AuthError.server,
        503: AuthError.server,
        504: AuthError.server,
      };
      for (final e in table.entries) {
        expect(await failureOf(login, e.key, signIn), e.value,
            reason: 'HTTP ${e.key}');
      }
    });

    test('create account: duplicate e-mail, bad input, rate limit, server',
        () async {
      const register = 'POST /api/v1/auth/register';
      expect(await failureOf(register, 409, signUp, 'email_taken'),
          AuthError.emailTaken);
      expect(await failureOf(register, 400, signUp, 'validation'),
          AuthError.invalidInput);
      expect(await failureOf(register, 429, signUp, 'rate_limited'),
          AuthError.rateLimited);
      expect(
          await failureOf(register, 500, signUp, 'internal'), AuthError.server);
      expect(await failureOf(register, 503, signUp, 'feature_disabled'),
          AuthError.server);
    });

    test('a rejected refresh, /me and delete mean "session expired"', () async {
      final session = harnessLikeSession();
      for (final (route, call) in <(String, Future<Object?> Function())>[
        ('POST /api/v1/auth/refresh', () => repo.refresh('refresh-token')),
        ('GET /api/v1/me', () => repo.me(session.accessToken)),
        ('DELETE /api/v1/me', () => repo.deleteAccount(session.accessToken)),
      ]) {
        expect(await failureOf(route, 401, call, 'unauthorized'),
            AuthError.sessionExpired,
            reason: route);
        // The other statuses behave as for sign-in.
        expect(await failureOf(route, 503, call), AuthError.server,
            reason: route);
        expect(await failureOf(route, 429, call), AuthError.rateLimited,
            reason: route);
      }
    });

    test('no connection is AuthError.network, for every operation', () async {
      backend.offline = true;
      final session = harnessLikeSession();
      for (final call in <Future<Object?> Function()>[
        signIn,
        signUp,
        () => repo.refresh('r'),
        () => repo.me(session.accessToken),
        () => repo.deleteAccount(session.accessToken),
        () => repo.signOut('r'),
      ]) {
        await expectLater(
            call(),
            throwsA(isA<AuthException>()
                .having((e) => e.error, 'error', AuthError.network)));
      }
    });

    test('an answer that is not an auth response is a server problem',
        () async {
      for (final body in ['{}', '[]', '"x"', '{"user":{},"tokens":{}}']) {
        backend.routes['POST /api/v1/auth/login'] =
            (_) => http.Response(body, 200);
        final error = await _errorOf(signIn);
        // Debug builds assert on a missing field, release builds hit a null
        // check: both are "the server answered nonsense".
        expect(error, AuthError.server, reason: body);
      }
      backend.routes['POST /api/v1/auth/login'] = (_) => http.Response('', 200);
      expect(await _errorOf(signIn), AuthError.server,
          reason: 'an empty 200 carries no session');
    });

    test('a 200 that is a proxy or captive-portal page is not a session',
        () async {
      for (final body in [
        '<html><body>Please sign in to the Wi-Fi</body></html>',
        'Bad Gateway',
      ]) {
        backend.routes['POST /api/v1/auth/login'] =
            (_) => http.Response(body, 200);
        expect(await _errorOf(signIn), AuthError.server, reason: body);
      }
    });

    test('an HTML error page (proxy) is a server problem with no leaked text',
        () async {
      backend.routes['POST /api/v1/auth/login'] = (_) => http.Response(
          '<html><body><h1>502 Bad Gateway</h1>nginx/1.25 at db-prod-3.internal</body></html>',
          502);
      final e = await _exceptionOf(signIn);
      expect(e.error, AuthError.server);
      expect(e.message, isNull);
      expect(e.toString(), isNot(contains('nginx')));
      expect(e.toString(), isNot(contains('db-prod')));
    });

    test('server and database messages never travel into the exception',
        () async {
      const leaks = [
        'duplicate key value violates unique constraint "users_email_key"',
        'connection to server at "10.0.0.5", port 5432 failed',
        'Error: SELECT * FROM users WHERE email = \$1',
        'ECONNREFUSED 127.0.0.1:5432',
        'stack trace: at Object.run (/app/dist/main.js:1:1)',
      ];
      for (final leak in leaks) {
        for (final status in [400, 401, 409, 429, 500, 503]) {
          backend.routes['POST /api/v1/auth/login'] = (_) => http.Response(
              jsonEncode({
                'error': {'code': 'internal', 'message': leak}
              }),
              status,
              headers: {'content-type': 'application/json'});
          final e = await _exceptionOf(signIn);
          expect(e.message, isNull, reason: 'HTTP $status');
          expect(e.toString(), isNot(contains(leak)));
          expect(e.toString(), isNot(contains('5432')));
          expect(e.toString(), isNot(contains('SELECT')));
        }
      }
    });

    test(
        'signing out against an unreachable server still reports a failure the '
        'controller can ignore', () async {
      backend.offline = true;
      await expectLater(repo.signOut('r'), throwsA(isA<AuthException>()));
    });

    test(
        'Apple and Google sign-in are reported as unavailable, not as errors '
        'of the server', () async {
      await expectLater(
          repo.signInWithApple(),
          throwsA(isA<AuthException>()
              .having((e) => e.error, 'error', AuthError.unavailable)));
      await expectLater(
          repo.signInWithGoogle(),
          throwsA(isA<AuthException>()
              .having((e) => e.error, 'error', AuthError.unavailable)));
      expect(backend.requests, isEmpty, reason: 'no request was made');
    });

    test('the e-mail is trimmed before it is sent, the password is not',
        () async {
      backend.routes['POST /api/v1/auth/login'] = (_) => FakeBackend.json({
            'user': {
              'id': '11111111-1111-4111-8111-111111111111',
              'email': 'a@b.co',
              'displayName': null,
              'plan': 'free',
              'createdAt': '2026-10-13T10:00:00.000Z',
            },
            'tokens': {
              'accessToken': 'a.b.c',
              'refreshToken': 'r',
              'expiresIn': 900,
              'tokenType': 'Bearer',
            },
          });
      await repo.signInWithEmail(
          email: '  a@b.co  ', password: ' keep spaces ');
      final body = backend.requests.single.body!;
      expect(body['email'], 'a@b.co');
      expect(body['password'], ' keep spaces ');
    });
  });

  group('timeouts, in fake time', () {
    // A server that accepts the connection and never answers.
    http.Client hanging() =>
        MockClient((_) => Completer<http.Response>().future);

    testWidgets('a login that never answers fails as "network" after 20 s',
        (tester) async {
      final repo = ApiAuthRepository(ApiFactory(base, httpClient: hanging()));
      final result = repo
          .signInWithEmail(email: 'a@b.co', password: 'password123')
          .then<Object?>((_) => null)
          .catchError((Object e) => e);
      await tester.pump(const Duration(seconds: 19));
      var settled = false;
      unawaited(result.then((_) => settled = true));
      await tester.pump();
      expect(settled, isFalse, reason: 'still waiting at 19 s');
      await tester.pump(const Duration(seconds: 2));
      final e = await result;
      expect(e, isA<AuthException>());
      expect((e as AuthException).error, AuthError.network);
    });

    testWidgets('an AI request gets 90 s and then reports "offline"',
        (tester) async {
      final service = AiService(
        apis: ApiFactory(base, httpClient: hanging()),
        sessions: SessionManager(
            store: InMemoryTokenStore()..write(session('old')),
            repository: FakeAuthRepository()),
      );
      final result = service
          .generate(AiKind.insight, _stats, languageCode: 'en')
          .then<Object?>((_) => null)
          .catchError((Object e) => e);
      await tester.pump(const Duration(seconds: 80));
      var settled = false;
      unawaited(result.then((_) => settled = true));
      await tester.pump();
      expect(settled, isFalse, reason: 'AI answers are slow: 80 s is fine');
      await tester.pump(const Duration(seconds: 15));
      final e = await result;
      expect(e, isA<AiException>());
      expect((e as AiException).error, AiError.offline);
    });
  });

  group('the AI card shows the app\'s own words, in the language of the app',
      () {
    setUp(rootBundle.clear);

    const leak = 'relation "ai_generations" does not exist (SQLSTATE 42P01)';

    // status, code, expected text
    final cases = <(String, int, String?, String Function(AppLocalizations))>[
      ('daily quota', 429, 'ai_quota_exceeded', (l) => l.aiQuotaExceeded),
      ('feature switched off', 503, 'feature_disabled', (l) => l.aiUnavailable),
      ('providers down', 503, 'ai_unavailable', (l) => l.aiUnavailable),
      ('server error', 500, 'internal', (l) => l.aiUnavailable),
      ('bad request', 400, 'validation', (l) => l.aiError),
      ('no connection', -1, null, (l) => l.aiOffline),
    ];

    for (final locale in [const Locale('en'), const Locale('pl')]) {
      final l = locale.languageCode == 'pl'
          ? AppLocalizationsPl()
          : AppLocalizationsEn();
      for (final (label, status, code, expected) in cases) {
        testWidgets('${locale.languageCode}: $label', (tester) async {
          final h = await pumpApp(tester, locale: locale);
          if (status == -1) {
            h.backend.offline = true;
          } else {
            h.backend.routes['POST /api/v1/ai/insight'] = (_) => http.Response(
                jsonEncode({
                  'error': {'code': code, 'message': leak}
                }),
                status,
                headers: {'content-type': 'application/json'});
          }
          await h.tapTab(tester, 2); // Insights
          final button = find.widgetWithText(FilledButton, l.aiGenerateInsight);
          expect(button, findsOneWidget);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await settle(tester);

          expect(find.text(expected(l)), findsOneWidget,
              reason: 'text comes from the ARB file ($label)');
          expect(find.textContaining('SQLSTATE'), findsNothing);
          expect(find.textContaining('ai_generations'), findsNothing);
          expect(find.textContaining('relation'), findsNothing);
        });
      }
    }
  });

  group('AiService: every failure becomes an AiError', () {
    late FakeBackend backend;
    late FakeAuthRepository auth;
    late InMemoryTokenStore store;
    late AiService service;

    setUp(() async {
      backend = FakeBackend();
      auth = FakeAuthRepository()..refreshDelay = Duration.zero;
      store = InMemoryTokenStore();
      await store.write(session('old'));
      service = AiService(
        apis: ApiFactory(base, httpClient: backend.client),
        sessions: SessionManager(store: store, repository: auth),
      );
    });

    const insight = 'POST /api/v1/ai/insight';
    const roast = 'POST /api/v1/ai/roast';

    http.Response answer() => FakeBackend.json({
          'output': {
            'title': 'Wi-Fi did the heavy lifting',
            'message': "Most of this month's data went over Wi-Fi.",
            'tone': 'friendly',
            'severity': 'info',
            'emoji': '📶',
          },
          'provider': 'google-mock',
          'model': 'mock-fast',
          'remainingToday': 2,
        });

    Future<AiError> errorOf(AiKind kind) async {
      try {
        await service.generate(kind, _stats, languageCode: 'en');
      } on AiException catch (e) {
        return e.error;
      }
      fail('no AiException');
    }

    test('a good answer is mapped field by field', () async {
      backend.routes[insight] = (_) => answer();
      final r =
          await service.generate(AiKind.insight, _stats, languageCode: 'en');
      expect(r.title, 'Wi-Fi did the heavy lifting');
      expect(r.message, "Most of this month's data went over Wi-Fi.");
      expect(r.emoji, '📶');
      expect(r.severity, 'info');
      expect(r.provider, 'google-mock');
      expect(r.model, 'mock-fast');
      expect(r.remainingToday, 2);
    });

    test('the daily quota (429 ai_quota_exceeded) is quotaExceeded', () async {
      backend.routes[insight] =
          (_) => FakeBackend.error(429, 'ai_quota_exceeded');
      expect(await errorOf(AiKind.insight), AiError.quotaExceeded);
      backend.routes[roast] =
          (_) => FakeBackend.error(429, 'ai_quota_exceeded');
      expect(await errorOf(AiKind.roast), AiError.quotaExceeded);
    });

    test('any other 429 is "unavailable", not the quota message', () async {
      backend.routes[insight] = (_) => FakeBackend.error(429, 'rate_limited');
      expect(await errorOf(AiKind.insight), AiError.unavailable);
    });

    test('503 feature_disabled and 503 ai_unavailable are "unavailable"',
        () async {
      for (final code in ['feature_disabled', 'ai_unavailable']) {
        backend.routes[insight] = (_) => FakeBackend.error(503, code);
        expect(await errorOf(AiKind.insight), AiError.unavailable,
            reason: code);
      }
    });

    test('5xx of any kind is "unavailable"', () async {
      for (final status in [500, 502, 503, 504]) {
        backend.routes[insight] = (_) => http.Response('', status);
        expect(await errorOf(AiKind.insight), AiError.unavailable,
            reason: 'HTTP $status');
      }
      backend.routes[insight] =
          (_) => http.Response('<html>502 Bad Gateway</html>', 502);
      expect(await errorOf(AiKind.insight), AiError.unavailable);
    });

    test('no connection is "offline"', () async {
      backend.offline = true;
      expect(await errorOf(AiKind.insight), AiError.offline);
      expect(await errorOf(AiKind.roast), AiError.offline);
    });

    test('400 is "invalid input" and 404 an unclassified error', () async {
      backend.routes[insight] = (_) => FakeBackend.error(400, 'validation');
      expect(await errorOf(AiKind.insight), AiError.invalidInput);
      backend.routes[insight] = (_) => FakeBackend.error(404, 'not_found');
      expect(await errorOf(AiKind.insight), AiError.other);
    });

    test('a token the server rejects twice means "not signed in"', () async {
      backend.routes[insight] = (_) => FakeBackend.error(401, 'unauthorized');
      expect(await errorOf(AiKind.insight), AiError.notSignedIn);
      expect(auth.refreshCalls, 1, reason: 'refreshed once, then gave up');
    });

    test('no stored session and a rejected refresh both mean "not signed in"',
        () async {
      await store.clear();
      final fresh = AiService(
        apis: ApiFactory(base, httpClient: backend.client),
        sessions: SessionManager(store: store, repository: auth),
      );
      await expectLater(
          fresh.generate(AiKind.insight, _stats, languageCode: 'en'),
          throwsA(isA<AiException>()
              .having((e) => e.error, 'error', AiError.notSignedIn)));
      expect(backend.requests, isEmpty, reason: 'no request without a session');

      await store.write(session('old', expiresAt: DateTime(2020)));
      auth.refreshFailure = AuthError.sessionExpired;
      final expired = AiService(
        apis: ApiFactory(base, httpClient: backend.client),
        sessions: SessionManager(store: store, repository: auth),
      );
      await expectLater(
          expired.generate(AiKind.roast, _stats, languageCode: 'en'),
          throwsA(isA<AiException>()
              .having((e) => e.error, 'error', AiError.notSignedIn)));
    });

    test(
        'an answer without a body is "unavailable", one in the wrong shape a '
        'generic error, never a crash', () async {
      backend.routes[insight] = (_) => http.Response('', 200);
      expect(await errorOf(AiKind.insight), AiError.unavailable);
      for (final body in ['{}', '[]', 'null', '<html></html>']) {
        backend.routes[insight] = (_) => http.Response(body, 200);
        expect(await errorOf(AiKind.insight), AiError.other,
            reason: '200 "$body"');
      }
    });

    test('server and database messages never reach the exception', () async {
      const leak = 'relation "ai_generations" does not exist (SQLSTATE 42P01)';
      for (final status in [400, 429, 500, 503]) {
        backend.routes[insight] = (_) => http.Response(
            jsonEncode({
              'error': {'code': 'internal', 'message': leak}
            }),
            status,
            headers: {'content-type': 'application/json'});
        try {
          await service.generate(AiKind.insight, _stats, languageCode: 'en');
          fail('HTTP $status did not throw');
        } on AiException catch (e) {
          expect(e.toString(), isNot(contains('SQLSTATE')));
          expect(e.toString(), isNot(contains('ai_generations')));
          expect(e.toString(), 'AiException(${e.error.name})');
        }
      }
    });

    test('insight and roast use their own routes, mode and language', () async {
      backend.routes[insight] = (_) => answer();
      backend.routes[roast] = (_) => answer();
      await service.generate(AiKind.insight, _stats, languageCode: 'en');
      await service.generate(AiKind.roast, _stats, languageCode: 'pl');
      final first = backend.where('POST', '/api/v1/ai/insight').single.body!;
      final second = backend.where('POST', '/api/v1/ai/roast').single.body!;
      expect(first['mode'], 'normal');
      expect(first['locale'], 'en');
      expect(second['mode'], 'roast');
      expect(second['locale'], 'pl');
    });

    test('the request carries the totals and nothing else', () async {
      backend.routes[insight] = (_) => answer();
      await service.generate(AiKind.insight, _stats, languageCode: 'en');
      final request = backend.requests.single;
      expect(request.bearer, 'access-old',
          reason: 'the token travels in the header');
      final text = jsonEncode(request.body);
      for (final secret in ['access-old', 'refresh-old', 'a@b.co', 'u1']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect((request.body!['input'] as Map).keys.toSet(), {
        'period',
        'periodType',
        'mobileDataGb',
        'wifiDataGb',
        'totalDataGb',
        'chargingSessions',
        'batteryEnergyKwh',
        'wallEnergyKwh',
        'electricityCost',
        'currency',
        'previousPeriodChangePercent',
        'wifiSharePercent',
        'averageSessionMah',
      });
      expect(request.body!.keys.toSet(), {'mode', 'locale', 'input'});
    });
  });
}

AuthSession harnessLikeSession() => session('x');

/// Runs [call] and returns the [AuthError] it throws.
Future<AuthError> _errorOf(Future<Object?> Function() call) async =>
    (await _exceptionOf(call)).error;

Future<AuthException> _exceptionOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on AuthException catch (e) {
    return e;
  }
  fail('no AuthException');
}

const _stats = AiPeriodStats(
  period: '2026-10',
  mobileDataGb: 187.4,
  wifiDataGb: 1433.8,
  totalDataGb: 1621.2,
  chargingSessions: 94,
  batteryEnergyKwh: 1.56,
  wallEnergyKwh: 1.84,
  electricityCost: 2.31,
  currency: 'PLN',
);
