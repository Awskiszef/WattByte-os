import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/generated/api/api.dart';

import 'support/fake_auth.dart';

void main() {
  late InMemoryTokenStore store;
  late FakeAuthRepository repo;
  late SessionManager manager;
  var signedOut = 0;

  final expired = DateTime.now().subtract(const Duration(minutes: 1));

  setUp(() async {
    store = InMemoryTokenStore();
    repo = FakeAuthRepository();
    signedOut = 0;
    manager = SessionManager(store: store, repository: repo)
      ..onSignedOut = () => signedOut++;
  });

  test('5 concurrent callers with an expired token cause exactly 1 refresh',
      () async {
    await store.write(session('old', expiresAt: expired));
    final results =
        await Future.wait(List.generate(5, (_) => manager.validSession()));
    expect(repo.refreshCalls, 1);
    expect(manager.refreshCalls, 1);
    expect(results.map((s) => s.accessToken).toSet(), {'access-r1'});
    expect((await store.read())?.refreshToken, 'refresh-r1');
  });

  test('5 requests that all get 401 share one refresh and all succeed on retry',
      () async {
    await store.write(session('old'));
    var calls = 0;
    final results = await Future.wait(List.generate(5, (_) {
      return manager.authorized((token) async {
        calls++;
        if (token == 'access-old') throw ApiException(401, '{}');
        return token;
      });
    }));
    expect(repo.refreshCalls, 1);
    expect(results.toSet(), {'access-r1'});
    expect(calls, 10); // each request ran twice: 401, then the retry
  });

  test('a second 401 after the retry is surfaced, not looped', () async {
    await store.write(session('old'));
    var calls = 0;
    await expectLater(
      manager.authorized((token) async {
        calls++;
        throw ApiException(401, '{}');
      }),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 2);
    expect(repo.refreshCalls, 1);
  });

  test('other failures are not retried and do not refresh', () async {
    await store.write(session('old'));
    for (final code in [400, 404, 429, 500]) {
      await expectLater(
        manager.authorized((_) async => throw ApiException(code, '{}')),
        throwsA(isA<ApiException>()),
      );
    }
    expect(repo.refreshCalls, 0);
  });

  test(
      'a rejected refresh ends the session once: store cleared, callback fired',
      () async {
    await store.write(session('old', expiresAt: expired));
    repo.refreshFailure = AuthError.sessionExpired;
    final futures = List.generate(
        3,
        (_) => expectLater(
            manager.validSession(),
            throwsA(isA<AuthException>()
                .having((e) => e.error, 'error', AuthError.sessionExpired))));
    await Future.wait(futures);
    expect(repo.refreshCalls, 1);
    expect(signedOut, 1);
    expect(await store.read(), isNull);
  });

  test('offline during refresh keeps the session and does not sign out',
      () async {
    await store.write(session('old', expiresAt: expired));
    repo.refreshFailure = AuthError.network;
    await expectLater(
        manager.validSession(),
        throwsA(isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.network)));
    expect(signedOut, 0);
    expect(await store.read(), isNotNull);
    // Back online: the next call refreshes normally.
    repo.refreshFailure = null;
    expect((await manager.validSession()).accessToken, 'access-r1');
  });

  test(
      'if another isolate already rotated the token, its session is adopted instead of signing out',
      () async {
    final stale = session('old', expiresAt: expired);
    await store.write(stale);
    await manager.current(); // cache the stale one
    // The background isolate refreshes first and stores the new session...
    await store.write(session('rotated'));
    // ...so our refresh with the old token is rejected by the server.
    repo.refreshFailure = AuthError.sessionExpired;
    final s = await manager.validSession();
    expect(s.refreshToken, 'refresh-rotated');
    expect(signedOut, 0);
  });

  test('without a session every call reports sessionExpired', () async {
    await expectLater(manager.validSession(), throwsA(isA<AuthException>()));
  });

  test('ApiFailure tells transport failures from real 400s', () {
    expect(
        ApiFailure.of(ApiException.withInner(400, 'Socket operation failed',
                Exception('x'), StackTrace.empty))
            .kind,
        ApiFailureKind.network);
    final real = ApiFailure.of(
        ApiException(400, '{"error":{"code":"validation","message":"bad"}}'));
    expect(real.kind, ApiFailureKind.badRequest);
    expect(real.code, 'validation');
    expect(
        ApiFailure.of(ApiException(
                429, '{"error":{"code":"ai_quota_exceeded","message":"x"}}'))
            .code,
        'ai_quota_exceeded');
    expect(ApiFailure.of(ApiException(503, '')).isTransient, isTrue);
    expect(ApiFailure.of(ApiException(400, '')).isTransient, isFalse);
  });

  group('401 handling is bounded', () {
    test('after the second 401 the call fails: exactly 2 requests, 1 refresh',
        () async {
      await store.write(session('old'));
      var requests = 0;
      await expectLater(
        manager.authorized((token) async {
          requests++;
          throw ApiException(401, '{}');
        }),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 2);
      expect(repo.refreshCalls, 1);
    });

    test(
        'consecutive 401s never grow into a loop: N calls cost 2N requests, N refreshes',
        () async {
      await store.write(session('old'));
      var requests = 0;
      for (var n = 1; n <= 10; n++) {
        await expectLater(
          manager.authorized((token) async {
            requests++;
            throw ApiException(401, '{}');
          }),
          throwsA(isA<ApiException>()),
        );
        expect(requests, 2 * n);
        expect(repo.refreshCalls, n);
      }
    });

    test(
        'once the refresh is rejected the session ends and NO further request is made',
        () async {
      await store.write(session('old'));
      repo.refreshFailure = AuthError.sessionExpired;
      var requests = 0;
      Future<String> call() => manager.authorized((token) async {
            requests++;
            throw ApiException(401, '{}');
          });
      await expectLater(call(), throwsA(isA<AuthException>()));
      expect(requests, 1, reason: 'the retry never happens without a session');
      expect(signedOut, 1);
      for (var i = 0; i < 20; i++) {
        await expectLater(call(), throwsA(isA<AuthException>()));
      }
      expect(requests, 1, reason: 'signed out: not a single further request');
      expect(repo.refreshCalls, 1);
      expect(await store.read(), isNull);
    });

    test(
        'an AuthException(sessionExpired) from the call is a 401: one refresh, one retry',
        () async {
      await store.write(session('old'));
      var requests = 0;
      final result = await manager.authorized((token) async {
        requests++;
        if (token == 'access-old') {
          throw const AuthException(AuthError.sessionExpired);
        }
        return token;
      });
      expect(result, 'access-r1');
      expect(requests, 2);
      expect(repo.refreshCalls, 1);
      // ...and a second one is surfaced, never looped
      await expectLater(manager.authorized((token) async {
        requests++;
        throw const AuthException(AuthError.sessionExpired);
      }), throwsA(isA<AuthException>()));
      expect(requests, 4);
    });

    test(
        'a refresh that fails because the network is down keeps the session and retries nothing',
        () async {
      await store.write(session('old'));
      repo.refreshFailure = AuthError.network;
      var requests = 0;
      await expectLater(manager.authorized((token) async {
        requests++;
        throw ApiException(401, '{}');
      }),
          throwsA(isA<AuthException>()
              .having((e) => e.error, 'error', AuthError.network)));
      expect(requests, 1);
      expect(signedOut, 0);
      expect(await store.read(), isNotNull);
    });
  });

  group('accounts', () {
    AuthSession of(String id) => AuthSession(
          accessToken: 'access-$id',
          refreshToken: 'refresh-$id',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          user: User(id: id, email: '$id@example.test'),
        );

    test(
        'accountEpoch changes on sign-out and on a different user, not on a token refresh',
        () async {
      final e0 = manager.accountEpoch;
      await manager.adopt(of('a'));
      final e1 = manager.accountEpoch;
      expect(e1, isNot(e0), reason: 'first sign-in');
      await manager.adopt(of('a'));
      expect(manager.accountEpoch, e1, reason: 'same user, new tokens');
      await manager.clear();
      final e2 = manager.accountEpoch;
      expect(e2, isNot(e1), reason: 'sign-out');
      await manager.adopt(of('a'));
      expect(manager.accountEpoch, isNot(e2), reason: 'sign-in after sign-out');
      final e3 = manager.accountEpoch;
      await manager.adopt(of('b'));
      expect(manager.accountEpoch, isNot(e3), reason: 'another user');
    });

    test('a refresh does not change the epoch', () async {
      await store.write(session('old', expiresAt: expired));
      await manager.current();
      final before = manager.accountEpoch;
      await manager.validSession();
      expect(manager.accountEpoch, before);
    });

    test(
        'a call pinned to user A is refused, without a request, when B is signed in',
        () async {
      await manager.adopt(of('a'));
      await manager.adopt(of('b'));
      var requests = 0;
      await expectLater(
          manager.authorized((t) async {
            requests++;
            return t;
          }, userId: 'a'),
          throwsA(isA<WrongAccountException>()));
      expect(requests, 0);
      expect(await manager.authorized((t) async => t, userId: 'b'), 'access-b');
    });

    test('the pin is checked again after the refresh of a 401', () async {
      await manager.adopt(of('a'));
      var calls = 0;
      await expectLater(
          manager.authorized((t) async {
            calls++;
            // the account changes while the first request is on the wire
            await manager.adopt(of('b'));
            throw ApiException(401, '{}');
          }, userId: 'a'),
          throwsA(isA<WrongAccountException>()));
      expect(calls, 1, reason: 'the retry must not go out with B\'s token');
    });
  });

  group('a refresh that outlives its session', () {
    AuthSession of(String id) => AuthSession(
          accessToken: 'access-$id',
          refreshToken: 'refresh-$id',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          user: User(id: id, email: '$id@example.test'),
        );

    test(
        'signing out while the refresh is on the wire does not sign the user back in',
        () async {
      await manager.adopt(of('a'));
      repo.refreshDelay = const Duration(milliseconds: 40);
      final refreshing = manager.refresh(of('a'));
      await manager.clear(); // the user taps "Sign out"
      await expectLater(refreshing, throwsA(isA<AuthException>()));
      expect(await manager.current(), isNull);
      expect(await store.read(), isNull,
          reason: 'the old tokens were not written back');
    });

    test('another account signing in meanwhile keeps its own session',
        () async {
      await manager.adopt(of('a'));
      repo.refreshDelay = const Duration(milliseconds: 40);
      final refreshing = manager.refresh(of('a'));
      await manager.clear();
      await manager.adopt(of('b'));
      await expectLater(refreshing, throwsA(isA<AuthException>()));
      expect((await manager.current())!.user.id, 'b');
      expect((await store.read())!.user.id, 'b');
      expect(signedOut, 0);
    });

    test('a REJECTED refresh of the old session does not sign the new one out',
        () async {
      await manager.adopt(of('a'));
      repo.refreshDelay = const Duration(milliseconds: 40);
      repo.refreshFailure = AuthError.sessionExpired;
      final refreshing = manager.refresh(of('a'));
      await manager.clear();
      await manager.adopt(of('b'));
      await expectLater(refreshing, throwsA(isA<AuthException>()));
      expect((await manager.current())!.user.id, 'b');
      expect((await store.read())!.user.id, 'b');
      expect(signedOut, 0, reason: 'no "signed out" event for B');
    });
  });
}
