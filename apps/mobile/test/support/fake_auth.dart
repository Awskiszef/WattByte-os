// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:wattbyte/features/auth/domain/auth_models.dart';

AuthSession session(
  String suffix, {
  DateTime? expiresAt,
  String email = 'a@b.co',
  Plan plan = Plan.free,
}) =>
    AuthSession(
      accessToken: 'access-$suffix',
      refreshToken: 'refresh-$suffix',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
      user: User(id: 'u1', email: email, plan: plan),
    );

/// Scriptable repository: counts refresh calls, can delay and fail them.
class FakeAuthRepository implements AuthRepository {
  int refreshCalls = 0;
  Duration refreshDelay = const Duration(milliseconds: 20);
  AuthError? refreshFailure;
  int _n = 0;

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    await Future<void>.delayed(refreshDelay);
    final f = refreshFailure;
    if (f != null) throw AuthException(f);
    _n++;
    return session('r$_n');
  }

  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) async =>
      session('login');

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      session('signup');

  @override
  Future<AuthSession> signInWithApple() async =>
      throw const AuthException(AuthError.unavailable);

  @override
  Future<AuthSession> signInWithGoogle() async =>
      throw const AuthException(AuthError.unavailable);

  @override
  Future<void> signOut(String refreshToken) async {}

  AuthError? meFailure;
  int meCalls = 0;

  @override
  Future<User> me(String accessToken) async {
    meCalls++;
    final f = meFailure;
    if (f != null) throw AuthException(f);
    return const User(id: 'u1', email: 'server@b.co', plan: Plan.premium);
  }

  @override
  Future<void> deleteAccount(String accessToken) async {}
}
