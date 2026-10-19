import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/cloud_providers.dart' show accountDeletedHookProvider;
import 'package:wattbyte/features/auth/data/api_auth_repository.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/setup/setup_controller.dart';
import 'package:wattbyte/settings/settings.dart';

import 'support/fake_backend.dart';

/// Account deletion and what it must leave behind on the phone, on the auth side:
/// the token store, the session manager and the controller state.
///
/// The sync-side cleanup (upload receipts, the sync switch, the cached server
/// device id) is the `accountDeletedHookProvider`; it is only observed here
/// (called after a successful deletion, never after a failed one), not tested.
void main() {
  /// A repository with a server behind it: accounts exist until deleted.
  final server = _Server();
  late InMemoryTokenStore store;
  late _Repo repo;
  late List<User> hookCalls;

  setUp(() async {
    server.reset();
    repo = _Repo(server);
    store = InMemoryTokenStore();
    hookCalls = [];
    await store
        .write(server.signUp('a@b.co', expiresIn: const Duration(minutes: 15)));
  });

  /// "A launch of the app": a new container (a new SessionManager, a new
  /// controller) over the SAME token store and the same server.
  ProviderContainer launch({AuthRepository? repository}) {
    final c = ProviderContainer(overrides: [
      apiConfigProvider.overrideWithValue(const ApiConfig('http://api.test')),
      authRepositoryProvider.overrideWithValue(repository ?? repo),
      tokenStoreProvider.overrideWithValue(store),
      accountDeletedHookProvider.overrideWithValue((user) async {
        hookCalls.add(user);
      }),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<ProviderContainer> signedIn() async {
    final c = launch();
    expect(await c.read(authControllerProvider.future), isA<SignedIn>());
    return c;
  }

  group('success', () {
    test(
        'the account is deleted, the token store is emptied, the state is '
        'SignedOut', () async {
      final c = await signedIn();
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isTrue);
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
      expect(await store.read(), isNull,
          reason: 'neither the access nor the refresh token may stay behind');
      expect(server.accounts, isEmpty);
    });

    test('the server is asked once, with a valid access token of that account',
        () async {
      final stored = (await store.read())!;
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      expect(repo.deleteTokens, hasLength(1));
      expect(repo.deleteTokens.single, stored.accessToken);
      expect(server.lastDeletedTokenWasValid, isTrue,
          reason: 'not expired, not revoked, belongs to the account');
    });

    test(
        'an access token that has expired is refreshed first: the delete '
        'carries the new one', () async {
      await store.write(
          server.signUp('b@b.co', expiresIn: const Duration(seconds: -5)));
      final stale = (await store.read())!;
      final c = launch();
      await c.read(authControllerProvider.future);
      repo.deleteTokens.clear();
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isTrue);
      expect(repo.refreshCalls, greaterThanOrEqualTo(1));
      expect(repo.deleteTokens.single, isNot(stale.accessToken));
      expect(await store.read(), isNull);
    });

    test(
        'the local clean-up hook runs once, after the server said yes, for '
        'that account', () async {
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      expect(hookCalls.map((u) => u.email), ['a@b.co']);
    });

    test('a failing clean-up hook does not keep a deleted account signed in',
        () async {
      final c = ProviderContainer(overrides: [
        apiConfigProvider.overrideWithValue(const ApiConfig('http://api.test')),
        authRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(store),
        accountDeletedHookProvider
            .overrideWithValue((user) async => throw StateError('disk full')),
      ]);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isTrue);
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
      expect(await store.read(), isNull);
    });

    test('signing out afterwards is harmless and the user is routed to Welcome',
        () async {
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      await c.read(authControllerProvider.notifier).signOut();
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
      expect(
          startDestination(
              localOnlyDev: false,
              auth: c.read(authControllerProvider),
              settings: const Settings(onboarded: true)),
          StartDestination.welcome,
          reason: 'the account comes first; the onboarded flag does not '
              'bring the dashboard back');
    });
  });

  group('failure keeps everything', () {
    test('no connection: the session stays in the store, nothing is erased',
        () async {
      final before = (await store.read())!;
      final c = await signedIn();
      server.offline = true;
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isFalse);
      final after = await store.read();
      expect(after, isNotNull, reason: 'the session is kept');
      expect(after!.accessToken, before.accessToken);
      expect(after.refreshToken, before.refreshToken);
      expect(server.accounts, isNotEmpty, reason: 'the account still exists');
      expect(hookCalls, isEmpty,
          reason: 'local records are erased only after the server said yes');
    });

    test(
        'the failure is reported: false to the caller, and the state either '
        'carries the reason or stays signed in', () async {
      final c = await signedIn();
      for (final (error, label) in [
        (AuthError.network, 'no connection'),
        (AuthError.server, 'server error'),
        (AuthError.rateLimited, 'rate limited'),
      ]) {
        server.failNextDeleteWith = error;
        final ok =
            await c.read(authControllerProvider.notifier).deleteAccount();
        expect(ok, isFalse, reason: label);
        // Today the controller publishes AuthFailure(reason); the contract this
        // test pins is only that nothing says "signed out" or "deleted" (see the
        // blocked test below for what the state should be).
        final state = c.read(authControllerProvider).value;
        expect(state, anyOf(isA<AuthFailure>(), isA<SignedIn>()),
            reason: label);
        if (state is AuthFailure) expect(state.error, error, reason: label);
        expect(await store.read(), isNotNull,
            reason: '$label keeps the session');
      }
      expect(hookCalls, isEmpty);
    });

    test('the user can try again after a failure and it then succeeds',
        () async {
      final c = await signedIn();
      server.failNextDeleteWith = AuthError.network;
      expect(await c.read(authControllerProvider.notifier).deleteAccount(),
          isFalse);
      expect(await c.read(authControllerProvider.notifier).deleteAccount(),
          isTrue);
      expect(await store.read(), isNull);
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
      expect(hookCalls, hasLength(1));
    });

    test('a failed deletion followed by a restart restores the same session',
        () async {
      final c = await signedIn();
      server.failNextDeleteWith = AuthError.network;
      await c.read(authControllerProvider.notifier).deleteAccount();
      c.dispose();
      final next = launch();
      final state = await next.read(authControllerProvider.future);
      expect(state, isA<SignedIn>(),
          reason: 'nothing was deleted, so nothing was forgotten');
      expect((state as SignedIn).user.email, 'a@b.co');
    });

    test('after a failed deletion the app still treats the user as signed in',
        () async {
      // The Account screen shows "Could not delete the account" inside its
      // signed-in view, and the start gate routes every state that is not
      // SignedIn to Welcome. With `state = AuthFailure(...)` the user is thrown
      // out of the app screen by a dropped connection although the session is
      // kept. See docs/REGRESSION_TESTS.md, open issues.
      final c = await signedIn();
      server.failNextDeleteWith = AuthError.network;
      expect(await c.read(authControllerProvider.notifier).deleteAccount(),
          isFalse);
      expect(c.read(authControllerProvider).value, isA<SignedIn>());
      expect(
          startDestination(
              localOnlyDev: false,
              auth: c.read(authControllerProvider),
              settings: const Settings(onboarded: true)),
          StartDestination.dashboard);
    });
  });

  group('401 while deleting', () {
    test(
        'the mechanism: SessionManager refreshes once and retries once when '
        "the call raises the generated client's 401", () async {
      // The repository raises the generated client's own 401, which is what
      // SessionManager.authorized() reacts to (the real repository does not:
      // see the blocked test below).
      final scripted = _Repo(server, rejectFirstDeleteWith401: true);
      final c = launch(repository: scripted);
      await c.read(authControllerProvider.future);
      scripted.refreshCalls = 0;
      final first = (await store.read())!.accessToken;
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isTrue);
      expect(scripted.refreshCalls, 1, reason: 'exactly one refresh');
      expect(scripted.deleteTokens, hasLength(2), reason: 'one retry');
      expect(scripted.deleteTokens.first, first);
      expect(scripted.deleteTokens.last, isNot(first));
      expect(await store.read(), isNull);
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
    });

    test(
        'through the real repository, a delete that is always rejected '
        'neither loops nor erases the session', () async {
      final backend = FakeBackend();
      backend.routes['DELETE /api/v1/me'] =
          (_) => FakeBackend.error(401, 'unauthorized');
      backend.routes['GET /api/v1/me'] = (_) => FakeBackend.json(_userJson);
      backend.routes['POST /api/v1/auth/refresh'] = (_) => FakeBackend.json({
            'user': _userJson,
            'tokens': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'expiresIn': 900,
              'tokenType': 'Bearer',
            },
          });
      await store.write(AuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        user: const User(id: 'u1', email: 'a@b.co'),
      ));
      final real = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      final c = launch(repository: real);
      await c.read(authControllerProvider.future);
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isFalse);
      expect(backend.where('DELETE', '/api/v1/me').length, lessThanOrEqualTo(2),
          reason: 'one retry at most, never a loop');
      expect(backend.where('POST', '/api/v1/auth/refresh').length,
          lessThanOrEqualTo(1));
      expect(await store.read(), isNotNull,
          reason: 'a failed deletion erases nothing');
      expect(hookCalls, isEmpty);
    });

    test(
        'through the real repository and HTTP: a 401 on DELETE /me is '
        'refreshed once and retried', () async {
      final backend = FakeBackend();
      var deletes = 0;
      backend.routes['DELETE /api/v1/me'] = (r) {
        deletes++;
        return r.bearer == 'old-access'
            ? FakeBackend.error(401, 'unauthorized')
            : http.Response('', 204);
      };
      backend.routes['POST /api/v1/auth/refresh'] = (_) => FakeBackend.json({
            'user': _userJson,
            'tokens': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'expiresIn': 900,
              'tokenType': 'Bearer',
            },
          });
      await store.write(AuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        user: const User(id: 'u1', email: 'a@b.co'),
      ));
      backend.routes['GET /api/v1/me'] = (_) => FakeBackend.json(_userJson);
      final real = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      final c = launch(repository: real);
      await c.read(authControllerProvider.future);
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isTrue);
      expect(backend.where('POST', '/api/v1/auth/refresh'), hasLength(1));
      expect(deletes, 2);
      expect(
          backend.where('DELETE', '/api/v1/me').map((r) => r.bearer).toList(),
          ['old-access', 'new-access']);
      expect(await store.read(), isNull);
    });
  });

  group('restoring a session at launch uses the same refresh rule', () {
    test('a /me that answers 401 refreshes once and keeps the user signed in',
        () async {
      // The client's clock says the token is still good, the server disagrees
      // (clock skew, early expiry): that is a refresh, not a sign-out.
      final backend = FakeBackend();
      backend.routes['GET /api/v1/me'] = (r) => r.bearer == 'old-access'
          ? FakeBackend.error(401, 'unauthorized')
          : FakeBackend.json(_userJson);
      backend.routes['POST /api/v1/auth/refresh'] = (_) => FakeBackend.json({
            'user': _userJson,
            'tokens': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'expiresIn': 900,
              'tokenType': 'Bearer',
            },
          });
      await store.write(AuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        user: const User(id: 'u1', email: 'a@b.co'),
      ));
      final real = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      final c = launch(repository: real);
      final state = await c.read(authControllerProvider.future);
      expect(state, isA<SignedIn>());
      expect(backend.where('POST', '/api/v1/auth/refresh'), hasLength(1));
      expect((await store.read())!.refreshToken, 'new-refresh');
    });

    test(
        'offline with an expired token keeps the session (simulator fix 12) '
        'and restores it once the network is back', () async {
      await store.write(
          server.signUp('b@b.co', expiresIn: const Duration(seconds: -30)));
      final saved = (await store.read())!;
      server.offline = true;
      final c = launch();
      final state = await c.read(authControllerProvider.future);
      expect(state, isA<SignedIn>(),
          reason: 'no connection is not a reason to sign the user out');
      expect((state as SignedIn).offline, isTrue);
      expect(state.user.email, 'b@b.co');
      final kept = await store.read();
      expect(kept, isNotNull);
      expect(kept!.refreshToken, saved.refreshToken,
          reason: 'the refresh token is still the one the server knows');
      c.dispose();

      server.offline = false;
      final back = launch();
      final restored = await back.read(authControllerProvider.future);
      expect(restored, isA<SignedIn>());
      expect((restored as SignedIn).offline, isFalse);
      expect((await store.read())!.refreshToken, isNot(saved.refreshToken),
          reason: 'back online the token was rotated, once');
    });

    test('a server error while restoring also keeps the session', () async {
      final backend = FakeBackend();
      backend.routes['GET /api/v1/me'] =
          (_) => FakeBackend.error(503, 'feature_disabled');
      await store.write(AuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        user: const User(id: 'u1', email: 'a@b.co'),
      ));
      final real = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      final c = launch(repository: real);
      final state = await c.read(authControllerProvider.future);
      expect(state, isA<SignedIn>());
      expect((state as SignedIn).offline, isTrue);
      expect(await store.read(), isNotNull);
    });

    test('a refresh the server rejects ends the session and clears the store',
        () async {
      final backend = FakeBackend();
      backend.routes['GET /api/v1/me'] =
          (_) => FakeBackend.error(401, 'unauthorized');
      backend.routes['POST /api/v1/auth/refresh'] =
          (_) => FakeBackend.error(401, 'invalid_refresh_token');
      await store.write(AuthSession(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        user: const User(id: 'u1', email: 'a@b.co'),
      ));
      final real = ApiAuthRepository(ApiFactory(
          const ApiConfig('http://api.test'),
          httpClient: backend.client));
      final c = launch(repository: real);
      expect(await c.read(authControllerProvider.future), isA<SignedOut>());
      expect(await store.read(), isNull);
    });
  });

  group('after the deletion nothing restores the old session', () {
    test('a restart over the same stores starts signed out', () async {
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      c.dispose();
      final next = launch();
      expect(await next.read(authControllerProvider.future), isA<SignedOut>());
      expect(await store.read(), isNull);
    });

    test('the old refresh token is dead: even a leftover copy cannot sign in',
        () async {
      // A crash between "server deleted the account" and "token store cleared"
      // leaves the old session on disk; the server no longer knows it.
      final old = (await store.read())!;
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      c.dispose();
      await store.write(old); // the leftover
      final next = launch();
      final state = await next.read(authControllerProvider.future);
      expect(state, isA<SignedOut>(),
          reason: 'refresh / me are rejected: the session is dropped');
      expect(await store.read(), isNull,
          reason: 'and the stale copy is erased, not kept');
    });

    test('an expired leftover is also dropped (refresh is rejected)', () async {
      final old = AuthSession(
        accessToken: 'ghost-access',
        refreshToken: 'ghost-refresh',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        user: const User(id: 'gone', email: 'gone@b.co'),
      );
      await store.write(old);
      final c = launch();
      expect(await c.read(authControllerProvider.future), isA<SignedOut>());
      expect(await store.read(), isNull);
    });

    test('deleting while signed out does nothing and does not crash', () async {
      await store.clear();
      final c = launch();
      expect(await c.read(authControllerProvider.future), isA<SignedOut>());
      final ok = await c.read(authControllerProvider.notifier).deleteAccount();
      expect(ok, isFalse);
      expect(repo.deleteTokens, isEmpty,
          reason: 'no request without a session');
    });

    test('another account on the same phone is not affected', () async {
      final other = server.signUp('other@b.co');
      final c = await signedIn();
      await c.read(authControllerProvider.notifier).deleteAccount();
      expect(server.accounts.keys, ['other@b.co']);
      // The other account's token still works on the server.
      expect(server.tokenIsValid(other.accessToken), isTrue);
    });
  });
}

const _userJson = {
  'id': '11111111-1111-4111-8111-111111111111',
  'email': 'a@b.co',
  'displayName': null,
  'plan': 'free',
  'createdAt': '2026-10-13T10:00:00.000Z',
};

/// What the server knows: accounts with live access and refresh tokens.
class _Server {
  final Map<String, _Account> accounts = {};
  bool offline = false;
  AuthError? failNextDeleteWith;
  bool lastDeletedTokenWasValid = false;
  int _n = 0;

  void reset() {
    accounts.clear();
    offline = false;
    failNextDeleteWith = null;
    lastDeletedTokenWasValid = false;
    _n = 0;
  }

  AuthSession signUp(String email,
      {Duration expiresIn = const Duration(minutes: 15)}) {
    final id = 'user-${accounts.length + 1}';
    final account = _Account(id, email);
    accounts[email] = account;
    return _issue(account, expiresIn);
  }

  AuthSession _issue(_Account a, Duration expiresIn) {
    _n++;
    final access = 'access-$_n';
    final refresh = 'refresh-$_n';
    a.accessTokens.add(access);
    a.refreshTokens.add(refresh);
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(expiresIn),
      user: User(id: a.id, email: a.email),
    );
  }

  _Account? byAccess(String token) {
    for (final a in accounts.values) {
      if (a.accessTokens.contains(token)) return a;
    }
    return null;
  }

  bool tokenIsValid(String token) => byAccess(token) != null;

  AuthSession refresh(String refreshToken) {
    for (final a in accounts.values) {
      if (a.refreshTokens.remove(refreshToken)) {
        return _issue(a, const Duration(minutes: 15));
      }
    }
    throw const AuthException(AuthError.sessionExpired);
  }
}

class _Account {
  _Account(this.id, this.email);

  final String id;
  final String email;
  final Set<String> accessTokens = {};
  final Set<String> refreshTokens = {};
}

/// An [AuthRepository] in front of [_Server]; records what it was asked.
class _Repo implements AuthRepository {
  _Repo(this.server, {this.rejectFirstDeleteWith401 = false});

  final _Server server;
  final bool rejectFirstDeleteWith401;
  final List<String> deleteTokens = [];
  int refreshCalls = 0;
  int signOutCalls = 0;

  void _online() {
    if (server.offline) throw const AuthException(AuthError.network);
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    _online();
    deleteTokens.add(accessToken);
    final scripted = server.failNextDeleteWith;
    if (scripted != null) {
      server.failNextDeleteWith = null;
      throw AuthException(scripted);
    }
    if (rejectFirstDeleteWith401 && deleteTokens.length == 1) {
      throw api.ApiException(401, '{"error":{"code":"unauthorized"}}');
    }
    final account = server.byAccess(accessToken);
    if (account == null) throw const AuthException(AuthError.sessionExpired);
    server.lastDeletedTokenWasValid = true;
    server.accounts.remove(account.email);
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    _online();
    refreshCalls++;
    return server.refresh(refreshToken);
  }

  @override
  Future<User> me(String accessToken) async {
    _online();
    final a = server.byAccess(accessToken);
    if (a == null) throw const AuthException(AuthError.sessionExpired);
    return User(id: a.id, email: a.email);
  }

  @override
  Future<void> signOut(String refreshToken) async {
    signOutCalls++;
  }

  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      throw UnimplementedError();

  @override
  Future<AuthSession> signInWithApple() async => throw UnimplementedError();

  @override
  Future<AuthSession> signInWithGoogle() async => throw UnimplementedError();
}
