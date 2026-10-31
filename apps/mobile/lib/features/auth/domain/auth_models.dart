// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Account models. No backend exists yet; these define the contract the
/// Flutter side will program against once `apps/api` is live.
library;

enum Plan { free, premium }

class User {
  const User({
    required this.id,
    required this.email,
    this.displayName,
    this.plan = Plan.free,
  });

  final String id;
  final String email;
  final String? displayName;

  /// Always as last confirmed by the backend; never decided client-side.
  final Plan plan;
}

/// Tokens of a signed-in user. Persisted only through [TokenStore]
/// (Keychain / Keystore), never in SharedPreferences.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final User user;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

/// What the UI reacts to.
///
/// [AuthUnknown] = initializing (stored session not restored yet),
/// [SignedIn] = authenticated, [SignedOut] = unauthenticated.
sealed class AuthState {
  const AuthState();
}

/// Session not restored yet (app start).
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class SignedOut extends AuthState {
  const SignedOut();
}

class SignedIn extends AuthState {
  const SignedIn(this.session, {this.offline = false});

  final AuthSession session;

  /// The stored session could not be confirmed with the server (no connection).
  final bool offline;
  User get user => session.user;
}

class AuthFailure extends AuthState {
  const AuthFailure(this.error);

  final AuthError error;
}

enum AuthError {
  /// No backend configured in this build.
  unavailable,
  invalidCredentials,
  network,
  sessionExpired,
  cancelled,
  emailTaken,
  invalidInput,
  rateLimited,
  server,
}

class AuthException implements Exception {
  const AuthException(this.error, [this.message]);

  final AuthError error;
  final String? message;

  @override
  String toString() =>
      'AuthException(${error.name}${message == null ? '' : ': $message'})';
}

/// Backend contract. Implementations must not cache tokens themselves.
abstract interface class AuthRepository {
  Future<AuthSession> signInWithEmail(
      {required String email, required String password});
  Future<AuthSession> signUpWithEmail(
      {required String email, required String password});
  Future<AuthSession> signInWithApple();
  Future<AuthSession> signInWithGoogle();

  /// The signed-in user as the server sees it (also proves the access token is valid).
  Future<User> me(String accessToken);

  /// Permanently deletes the account and every cloud record (GDPR erasure).
  Future<void> deleteAccount(String accessToken);

  /// Exchanges a refresh token for a new session (rotating refresh tokens).
  Future<AuthSession> refresh(String refreshToken);

  /// Revokes the refresh token server-side.
  Future<void> signOut(String refreshToken);
}

/// Secure persistence of the session (see `SecureTokenStore`).
abstract interface class TokenStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}
