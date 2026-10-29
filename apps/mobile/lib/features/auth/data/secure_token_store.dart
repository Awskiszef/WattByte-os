import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/error_log.dart';
import '../domain/auth_models.dart';

/// Keychain (iOS) / Keystore-backed EncryptedSharedPreferences (Android).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility:
                      KeychainAccessibility.first_unlock_this_device),
            );

  final FlutterSecureStorage _storage;

  static const _access = 'wb.auth.access';
  static const _refresh = 'wb.auth.refresh';
  static const _expires = 'wb.auth.expires';
  static const _userId = 'wb.auth.user.id';
  static const _email = 'wb.auth.user.email';
  static const _name = 'wb.auth.user.name';
  static const _plan = 'wb.auth.user.plan';

  /// The stored session, or null when there is none or it is incomplete.
  ///
  /// A damaged record must never stop the app from starting (an exception from
  /// here would leave the auth state in error and the start gate on the splash
  /// screen for good), and it must never grant anything:
  ///
  /// * an unreadable expiry makes the session EXPIRED, so the refresh token (the
  ///   part that matters) is used at once and the server decides;
  /// * an unknown plan name is [Plan.free] (the plan is only ever what the
  ///   server last said, and `GET /me` confirms it at launch);
  /// * a missing or empty token, id or e-mail means no session.
  @override
  Future<AuthSession?> read() async {
    final values = await _storage.readAll();
    String? present(String key) {
      final v = values[key];
      return v == null || v.isEmpty ? null : v;
    }

    final access = present(_access);
    final refresh = present(_refresh);
    final expires = values[_expires];
    final id = present(_userId);
    final email = present(_email);
    if (access == null ||
        refresh == null ||
        expires == null ||
        id == null ||
        email == null) {
      return null;
    }
    var expiresAt = DateTime.tryParse(expires);
    if (expiresAt == null) {
      // Never print the value: it is the one field of this record that is not
      // a secret, but a damaged record is not to be trusted to stay that way.
      reportError(const FormatException('stored session expiry is unreadable'),
          StackTrace.current, 'token store');
      expiresAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      user: User(
        id: id,
        email: email,
        // `write` stores "" for "no display name".
        displayName: present(_name),
        plan: Plan.values.asNameMap()[values[_plan]] ?? Plan.free,
      ),
    );
  }

  /// One key after the other, the refresh token FIRST. The record is seven items and a write can be cut short (the
  /// app is killed): in that order the worst case is a new refresh token with an old, already expired access token,
  /// which the next start simply refreshes. The reverse (a consumed refresh token next to a fresh access token) would
  /// be a session that only the server's retry window can still save.
  @override
  Future<void> write(AuthSession s) async {
    await _storage.write(key: _refresh, value: s.refreshToken);
    await _storage.write(key: _access, value: s.accessToken);
    await _storage.write(
        key: _expires, value: s.expiresAt.toUtc().toIso8601String());
    await _storage.write(key: _userId, value: s.user.id);
    await _storage.write(key: _email, value: s.user.email);
    await _storage.write(key: _name, value: s.user.displayName ?? '');
    await _storage.write(key: _plan, value: s.user.plan.name);
  }

  @override
  Future<void> clear() => Future.wait([
        for (final k in [
          _access,
          _refresh,
          _expires,
          _userId,
          _email,
          _name,
          _plan
        ])
          _storage.delete(key: k),
      ]);
}

/// Test double; keeps everything in memory.
class InMemoryTokenStore implements TokenStore {
  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
