// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/data/auth_repositories.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/cloud_providers.dart' show accountDeletedHookProvider;
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';

/// Records the refresh token the app asks the server to revoke.
class _RecordingRepo extends MockAuthRepository {
  final signedOutWith = <String>[];

  @override
  Future<void> signOut(String refreshToken) async {
    signedOutWith.add(refreshToken);
    await super.signOut(refreshToken);
  }
}

void main() {
  ProviderContainer make({AuthRepository? repo, TokenStore? store}) =>
      ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo ?? MockAuthRepository()),
        tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
      ]);

  test('starts signed out, signs in, persists tokens securely, signs out',
      () async {
    final store = InMemoryTokenStore();
    final c = make(store: store);
    expect(await c.read(authControllerProvider.future), isA<SignedOut>());

    await c
        .read(authControllerProvider.notifier)
        .signInWithEmail('a@b.c', 'password');
    final state = c.read(authControllerProvider).value;
    expect(state, isA<SignedIn>());
    expect((await store.read())?.user.email, 'a@b.c');

    await c.read(authControllerProvider.notifier).signOut();
    expect(c.read(authControllerProvider).value, isA<SignedOut>());
    expect(await store.read(), isNull);
  });

  test('wrong password -> AuthFailure(invalidCredentials)', () async {
    final c = make();
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .signInWithEmail('a@b.c', 'nope');
    final s = c.read(authControllerProvider).value;
    expect(s, isA<AuthFailure>());
    expect((s as AuthFailure).error, AuthError.invalidCredentials);
  });

  test('expired stored session is refreshed with a rotated token', () async {
    final store = InMemoryTokenStore();
    await store.write(AuthSession(
      accessToken: 'old',
      refreshToken: 'r1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      user: const User(id: 'u', email: 'a@b.c'),
    ));
    final c = make(store: store);
    final state = await c.read(authControllerProvider.future);
    expect(state, isA<SignedIn>());
    expect((state as SignedIn).session.refreshToken, isNot('r1'));
  });

  test('default repository reports the backend as unavailable', () async {
    final c = make(repo: const UnavailableAuthRepository());
    await c.read(authControllerProvider.future);
    await c.read(authControllerProvider.notifier).signInWithApple();
    expect((c.read(authControllerProvider).value as AuthFailure).error,
        AuthError.unavailable);
  });

  group('account deletion and the local clean-up hook', () {
    ProviderContainer withHook(List<User> calls, InMemoryTokenStore store,
            {Future<void> Function(User)? hook}) =>
        ProviderContainer(overrides: [
          authRepositoryProvider.overrideWithValue(MockAuthRepository()),
          tokenStoreProvider.overrideWithValue(store),
          accountDeletedHookProvider.overrideWithValue((user) async {
            calls.add(user);
            await hook?.call(user);
          }),
        ]);

    test(
        'deleteAccount runs the hook once, with the deleted user, before the session is gone',
        () async {
      final store = InMemoryTokenStore();
      final calls = <User>[];
      AuthSession? sessionSeenByHook;
      final c = withHook(calls, store,
          hook: (_) async => sessionSeenByHook = await store.read());
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      await c
          .read(authControllerProvider.notifier)
          .signInWithEmail('a@b.c', 'password');
      final user = (c.read(authControllerProvider).value as SignedIn).user;

      expect(await c.read(authControllerProvider.notifier).deleteAccount(),
          isTrue);
      expect(calls.map((u) => u.id), [user.id]);
      expect(sessionSeenByHook, isNotNull,
          reason: 'the hook runs while the account is still identifiable');
      expect(await store.read(), isNull);
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
    });

    test('signing out never runs it: the receipts must survive a logout',
        () async {
      final store = InMemoryTokenStore();
      final calls = <User>[];
      final c = withHook(calls, store);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      final auth = c.read(authControllerProvider.notifier);
      await auth.signInWithEmail('a@b.c', 'password');
      await auth.signOut();
      await auth.signInWithEmail('a@b.c', 'password');
      await auth.signOut();
      expect(calls, isEmpty);
    });
  });

  test(
      'sign-out sends the refresh token the store holds now, not the one captured at sign-in (F-01)',
      () async {
    final repo = _RecordingRepo();
    final c = make(repo: repo);
    await c.read(authControllerProvider.future);
    await c
        .read(authControllerProvider.notifier)
        .signInWithEmail('a@b.c', 'password');
    final signedIn = (c.read(authControllerProvider).value as SignedIn).session;

    // A silent refresh rotated the token: the store has a new one, the controller state still holds the first.
    await c.read(sessionManagerProvider).adopt(AuthSession(
        accessToken: 'rotated-access',
        refreshToken: 'rotated-refresh',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        user: signedIn.user));

    await c.read(authControllerProvider.notifier).signOut();
    expect(repo.signedOutWith, ['rotated-refresh']);
  });

  group('start-up does not wait for the network (F-08)', () {
    late Duration saved;
    setUp(() {
      saved = AuthController.startupBudget;
      AuthController.startupBudget = const Duration(milliseconds: 150);
    });
    tearDown(() => AuthController.startupBudget = saved);

    Future<InMemoryTokenStore> storeWith({required bool expired}) async {
      final store = InMemoryTokenStore();
      await store.write(AuthSession(
        accessToken: 'old',
        refreshToken: 'r1',
        expiresAt: DateTime.now().add(Duration(minutes: expired ? -1 : 30)),
        user: const User(id: 'u', email: 'a@b.c'),
      ));
      return store;
    }

    test(
        'a hanging server: the app starts on the stored session within the budget, then the answer is applied',
        () async {
      final repo = _SlowRepo(delay: const Duration(milliseconds: 600));
      final c = make(repo: repo, store: await storeWith(expired: true));
      addTearDown(c.dispose);
      final started = DateTime.now();
      final first = await c.read(authControllerProvider.future);
      expect(DateTime.now().difference(started),
          lessThan(const Duration(milliseconds: 500)));
      expect(first, isA<SignedIn>());
      expect((first as SignedIn).offline, isTrue, reason: 'not confirmed yet');
      expect(first.user.email, 'a@b.c');

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final later = c.read(authControllerProvider).value;
      expect(later, isA<SignedIn>());
      expect((later as SignedIn).offline, isFalse,
          reason: 'confirmed in the background');
    });

    test(
        'a fast server: confirmed before the first screen, no provisional state',
        () async {
      final c = make(
          repo: _SlowRepo(delay: Duration.zero),
          store: await storeWith(expired: true));
      addTearDown(c.dispose);
      final state = await c.read(authControllerProvider.future);
      expect((state as SignedIn).offline, isFalse);
    });

    test('a rejected session found in the background signs the user out',
        () async {
      final repo =
          _SlowRepo(delay: const Duration(milliseconds: 400), reject: true);
      final c = make(repo: repo, store: await storeWith(expired: true));
      addTearDown(c.dispose);
      expect((await c.read(authControllerProvider.future) as SignedIn).offline,
          isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
    });

    test(
        'a sign-out during the wait is not overwritten by the late confirmation',
        () async {
      final repo = _SlowRepo(delay: const Duration(milliseconds: 500));
      final store = await storeWith(expired: true);
      final c = make(repo: repo, store: store);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      await c.read(authControllerProvider.notifier).signOut();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(c.read(authControllerProvider).value, isA<SignedOut>());
    });
  });
}

/// Every call takes [delay]; [reject] makes the refresh a definitive 401.
class _SlowRepo extends MockAuthRepository {
  _SlowRepo({required this.delay, this.reject = false});

  final Duration delay;
  final bool reject;

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    await Future<void>.delayed(delay);
    if (reject) throw const AuthException(AuthError.sessionExpired);
    return super.refresh(refreshToken);
  }

  @override
  Future<User> me(String accessToken) async {
    await Future<void>.delayed(delay);
    return super.me(accessToken);
  }
}
