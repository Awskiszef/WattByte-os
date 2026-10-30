// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import '../../../api/api_factory.dart';
import '../../../api/api_failure.dart';
import '../../../generated/api/api.dart' as api;
import '../domain/auth_models.dart';

/// [AuthRepository] on top of the generated API client.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._apis, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ApiFactory _apis;
  final DateTime Function() _clock;

  Future<T> _run<T>(Future<T> Function() call,
      {AuthError onUnauthorized = AuthError.invalidCredentials}) async {
    try {
      return await guarded(call);
    } on ApiFailure catch (f) {
      throw AuthException(switch (f.kind) {
        ApiFailureKind.network || ApiFailureKind.timeout => AuthError.network,
        ApiFailureKind.unauthorized => onUnauthorized,
        ApiFailureKind.conflict => AuthError.emailTaken,
        ApiFailureKind.badRequest => AuthError.invalidInput,
        ApiFailureKind.rateLimited => AuthError.rateLimited,
        ApiFailureKind.server => AuthError.server,
        _ => AuthError.server,
      });
    }
  }

  AuthSession _session(api.AuthResponse r) => AuthSession(
        accessToken: r.tokens.accessToken,
        refreshToken: r.tokens.refreshToken,
        expiresAt: _clock().add(Duration(seconds: r.tokens.expiresIn)),
        user: _user(r.user),
      );

  static User _user(api.UserDto u) => User(
        id: u.id,
        email: u.email,
        displayName: u.displayName,
        plan: u.plan == api.UserDtoPlanEnum.premium ? Plan.premium : Plan.free,
      );

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) =>
      _run(() async {
        final r = await api.AuthApi(_apis.anonymous()).apiV1AuthRegisterPost(
            api.RegisterRequest(email: email.trim(), password: password));
        return _session(_required(r));
      });

  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) =>
      _run(() async {
        final r = await api.AuthApi(_apis.anonymous()).apiV1AuthLoginPost(
            api.LoginRequest(email: email.trim(), password: password));
        return _session(_required(r));
      });

  @override
  Future<AuthSession> refresh(String refreshToken) => _run(() async {
        final r = await api.AuthApi(_apis.anonymous()).apiV1AuthRefreshPost(
            api.RefreshRequest(refreshToken: refreshToken));
        return _session(_required(r));
      }, onUnauthorized: AuthError.sessionExpired);

  @override
  Future<void> signOut(String refreshToken) => _run(() async {
        await api.AuthApi(_apis.anonymous()).apiV1AuthLogoutPost(
            api.RefreshRequest(refreshToken: refreshToken));
      });

  @override
  Future<User> me(String accessToken) => _run(() async {
        final u = await api.AccountApi(_apis.bearer(accessToken)).apiV1MeGet();
        if (u == null) throw const ApiFailure(ApiFailureKind.server);
        return _user(u);
      }, onUnauthorized: AuthError.sessionExpired);

  @override
  Future<void> deleteAccount(String accessToken) => _run(() async {
        await api.AccountApi(_apis.bearer(accessToken)).apiV1MeDelete();
      }, onUnauthorized: AuthError.sessionExpired);

  /// Apple and Google sign-in are not configured on the server yet.
  @override
  Future<AuthSession> signInWithApple() async =>
      throw const AuthException(AuthError.unavailable);

  @override
  Future<AuthSession> signInWithGoogle() async =>
      throw const AuthException(AuthError.unavailable);

  static api.AuthResponse _required(api.AuthResponse? r) =>
      r ?? (throw const ApiFailure(ApiFailureKind.server));
}
