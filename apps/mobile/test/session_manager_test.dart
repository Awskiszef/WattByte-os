import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/generated/api/api.dart';

import 'support/fake_auth.dart';

void main() {
  sessionStoreRobustness();

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

  test(
      'after an account switch the new account refreshes its own session; it is not handed the old account\'s in-flight refresh',
      () async {
    final perUser = _PerUserRepo();
    final m = SessionManager(store: store, repository: perUser);
    await m.adopt(_sessionOf('a', expiresAt: expired));
    final a = m.validSession().then<Object?>((s) => s,
        onError: (Object e) => e); // account A's refresh is on the wire
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await m.adopt(_sessionOf('b',
        expiresAt: expired)); // another account signs in meanwhile
    final b = await m.validSession();
    expect(b.user.id, 'b');
    expect(b.accessToken, 'fresh-b');
    expect(perUser.calls, ['refresh-a', 'refresh-b'],
        reason: 'one refresh per session, each with its own token');
    // A's answer belongs to nobody any more.
    expect(
        await a,
        isA<AuthException>()
            .having((e) => e.error, 'error', AuthError.sessionExpired));
    expect((await m.current())?.user.id, 'b');
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
      'a 400 or 409 answer to a refresh is not a verdict on the session: the tokens stay',
      () async {
    for (final failure in [
      AuthError.invalidInput,
      AuthError.emailTaken,
      AuthError.unavailable
    ]) {
      await store.write(session('old', expiresAt: expired));
      repo.refreshFailure = failure;
      await expectLater(
          manager.validSession(),
          throwsA(
              isA<AuthException>().having((e) => e.error, 'error', failure)));
      expect(signedOut, 0, reason: '$failure');
      expect(await store.read(), isNotNull, reason: '$failure');
    }
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

/// A token store whose operations can be made slow or failing, for the cases a Keychain/Keystore really produces.
class _FlakyStore implements TokenStore {
  _FlakyStore(this._inner);
  final InMemoryTokenStore _inner;
  Future<void>? readGate;
  bool failRead = false;
  bool failWrite = false;
  bool failClear = false;

  @override
  Future<AuthSession?> read() async {
    final gate = readGate;
    final value =
        await _inner.read(); // the value as it was when the read started
    if (gate != null) await gate;
    if (failRead) throw StateError('keychain locked');
    return value;
  }

  @override
  Future<void> write(AuthSession s) async {
    if (failWrite) throw StateError('keystore write failed');
    await _inner.write(s);
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('keychain delete failed');
    await _inner.clear();
  }
}

void sessionStoreRobustness() {
  group('a slow or failing token store (F-16, F-10)', () {
    late InMemoryTokenStore inner;
    late _FlakyStore store;
    late SessionManager manager;

    setUp(() {
      inner = InMemoryTokenStore();
      store = _FlakyStore(inner);
      manager = SessionManager(store: store, repository: FakeAuthRepository());
    });

    test(
        'a store read that is still in flight when the user signs out does not bring the old session back',
        () async {
      await inner.write(session('old'));
      final gate = Completer<void>();
      store.readGate = gate.future;
      final reading =
          manager.current(); // starts the read of the stored session
      await manager.clear(); // sign-out while it is in flight
      gate.complete();
      expect(await reading, isNull);
      store.readGate = null;
      expect(await manager.current(),
          isNull); // and nothing was cached from the stale read
    });

    test('a store that cannot be read is "no session", not an exception',
        () async {
      await inner.write(session('old'));
      store.failRead = true;
      expect(await manager.current(), isNull);
    });

    test(
        'a store that cannot be written does not fail the sign-in: the session works in memory',
        () async {
      store.failWrite = true;
      await manager.adopt(session('new'));
      expect((await manager.current())?.accessToken, 'access-new');
      expect((await manager.validSession()).accessToken, 'access-new');
    });

    test('a store that cannot be cleared does not block sign-out', () async {
      await manager.adopt(session('new'));
      store.failClear = true;
      await manager.clear();
      expect(manager.accountEpoch, greaterThan(0));
      store.failRead = true; // the stale record cannot be read back either
      expect(await manager.current(), isNull);
    });
  });
}

AuthSession _sessionOf(String user, {DateTime? expiresAt}) => AuthSession(
      accessToken: 'access-$user',
      refreshToken: 'refresh-$user',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
      user: User(id: user, email: '$user@example.test'),
    );

/// Answers a refresh with a session of the user the refresh token belongs to.
class _PerUserRepo extends FakeAuthRepository {
  final List<String> calls = [];

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    calls.add(refreshToken);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final user = refreshToken.replaceFirst('refresh-', '');
    return AuthSession(
      accessToken: 'fresh-$user',
      refreshToken: 'refresh2-$user',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      user: User(id: user, email: '$user@example.test'),
    );
  }
}
