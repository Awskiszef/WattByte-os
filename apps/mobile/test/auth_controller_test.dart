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
}
