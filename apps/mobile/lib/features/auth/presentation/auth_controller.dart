import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/api_config.dart';
import '../../../api/api_factory.dart';
import '../../../api/session_manager.dart';
import '../../../cloud_providers.dart' show accountDeletedHookProvider;
import '../../../config/app_build.dart' show appBuildProvider;
import '../../../config/config_providers.dart' show appConfigProvider;
import '../../../core/error_log.dart';
import '../data/api_auth_repository.dart';
import '../data/auth_repositories.dart';
import '../data/secure_token_store.dart';
import '../domain/auth_models.dart';

/// The build's validated API address: always the one in [appConfigProvider], so
/// the configuration is decided in one place. Tests may override it directly.
final apiConfigProvider =
    Provider<ApiConfig>((ref) => ref.watch(appConfigProvider).api);

final apiFactoryProvider = Provider<ApiFactory>((ref) {
  final factory = ApiFactory(ref.watch(apiConfigProvider),
      appBuild: ref.watch(appBuildProvider));
  ref.onDispose(factory.close);
  return factory;
});

/// The real backend when `API_BASE_URL` is set, otherwise "not available" (which
/// can only be reached in the debug-only `LOCAL_ONLY_DEV` mode: an invalid
/// configuration never starts the app, see `main()`).
/// Tests override this with `MockAuthRepository`.
final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    ref.watch(apiConfigProvider).isConfigured
        ? ApiAuthRepository(ref.watch(apiFactoryProvider))
        : const UnavailableAuthRepository());

final tokenStoreProvider = Provider<TokenStore>((_) => SecureTokenStore());

final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    store: ref.watch(tokenStoreProvider),
    repository: ref.watch(authRepositoryProvider),
  );
  manager.onSignedOut =
      () => ref.read(authControllerProvider.notifier).sessionEnded();
  return manager;
});

/// Restores the session at start-up (initializing -> authenticated | unauthenticated),
/// then drives register / sign-in / sign-out / account deletion.
class AuthController extends AsyncNotifier<AuthState> {
  SessionManager get _sessions => ref.read(sessionManagerProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async {
    if (!ref.read(apiConfigProvider).isConfigured &&
        _repo is UnavailableAuthRepository) {
      // No backend (LOCAL_ONLY_DEV mode): nothing to restore, and the UI must not show a login form.
      return const SignedOut();
    }
    final stored = await _sessions.current();
    if (stored == null) return const SignedOut();
    // The app opens on what is stored. Confirming the session (a refresh, then GET /me, each up to 20 s) used to be the gate
    // in front of the first screen, with all the local statistics behind it (F-08). Within the budget the answer is used;
    // after it the app starts as "not confirmed yet" and the result is applied when it arrives.
    final check = _confirm(stored);
    try {
      return await check.timeout(startupBudget);
    } on TimeoutException {
      final provisional = SignedIn(stored, offline: true);
      unawaited(check.then<void>((confirmed) {
        // Only if nothing happened meanwhile (a sign-in, a sign-out, an ended session): the state is still ours.
        if (identical(state.valueOrNull, provisional)) {
          state = AsyncData(confirmed);
        }
      }, onError: (Object e, StackTrace st) {
        reportError(e, st, 'session confirmation');
      }));
      return provisional;
    }
  }

  /// How long the first screen may wait for the stored session to be confirmed with the server.
  static Duration startupBudget = const Duration(seconds: 4);

  /// Refreshes when expired, then proves the stored session with GET /me.
  Future<AuthState> _confirm(AuthSession stored) async {
    try {
      final session = await _sessions.validSession();
      final user = await _sessions.authorized((t) => _repo.me(t));
      final confirmed = AuthSession(
        accessToken:
            (await _sessions.current())?.accessToken ?? session.accessToken,
        refreshToken:
            (await _sessions.current())?.refreshToken ?? session.refreshToken,
        expiresAt: (await _sessions.current())?.expiresAt ?? session.expiresAt,
        user: user,
      );
      await _sessions.adopt(confirmed);
      return SignedIn(confirmed);
    } on AuthException catch (e) {
      if (e.error == AuthError.network ||
          e.error == AuthError.server ||
          e.error == AuthError.rateLimited) {
        return SignedIn(stored, offline: true); // keep going offline
      }
      await _sessions.clear();
      return const SignedOut();
    } on Exception {
      return SignedIn(stored, offline: true);
    }
  }

  /// The session manager lost the session (refresh rejected).
  void sessionEnded() => state = const AsyncData(SignedOut());

  Future<void> signInWithEmail(String email, String password) =>
      _run(() => _repo.signInWithEmail(email: email, password: password));

  Future<void> signUpWithEmail(String email, String password) =>
      _run(() => _repo.signUpWithEmail(email: email, password: password));

  Future<void> signInWithApple() => _run(() => _repo.signInWithApple());

  Future<void> signInWithGoogle() => _run(() => _repo.signInWithGoogle());

  Future<void> signOut() async {
    final current = state.value;
    if (current is SignedIn) {
      // The token the store holds NOW: the one captured at sign-in is stale after the first silent refresh (F-01).
      // The server revokes the whole device, so even a stale one would work, but the current one is the right one.
      final token = (await _sessions.current())?.refreshToken ??
          current.session.refreshToken;
      try {
        await _repo.signOut(token);
      } on AuthException {
        // Local sign-out still proceeds; the server token expires on its own.
      }
    }
    await _sessions.clear();
    state = const AsyncData(SignedOut());
  }

  /// Deletes the account on the server, then erases what this phone remembers about
  /// it (upload receipts, the sync switch, the cached server device id: see
  /// `accountDeletedHookProvider`; local statistics stay), then forgets the session.
  /// Returns false (and keeps the session and all local records) when the server
  /// could not be reached.
  Future<bool> deleteAccount() async {
    final user = (await _sessions.current())?.user;
    try {
      await _sessions.authorized((t) => _repo.deleteAccount(t));
    } on AuthException {
      // The server could not be reached (or refused): the account still exists and the user is still signed
      // in. Reporting the failure through `state` would route a signed-in user to Welcome; the caller shows
      // the message. An ended session (refresh rejected) already reached `sessionEnded()` through the manager.
      return false;
    }
    if (user != null) {
      try {
        await ref.read(accountDeletedHookProvider)(user);
      } catch (e, st) {
        // The account is gone on the server: the session must end regardless. A
        // failed local cleanup is recorded, not allowed to keep a dead session alive.
        reportError(e, st, 'account deletion cleanup');
      }
    }
    await _sessions.clear();
    state = const AsyncData(SignedOut());
    return true;
  }

  Future<void> _run(Future<AuthSession> Function() action) async {
    state = const AsyncLoading();
    try {
      final session = await action();
      await _sessions.adopt(session);
      state = AsyncData(SignedIn(session));
    } on AuthException catch (e) {
      state = AsyncData(AuthFailure(e.error));
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
