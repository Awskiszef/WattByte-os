import 'dart:async';

import '../core/error_log.dart';
import '../features/auth/domain/auth_models.dart';
import 'api_failure.dart';

/// Internal: a refresh answered for a session that was replaced meanwhile.
class _Superseded implements Exception {
  const _Superseded();
}

/// The signed-in account is not the one a request was prepared for.
class WrongAccountException implements Exception {
  const WrongAccountException();

  @override
  String toString() => 'WrongAccountException';
}

/// Owns the signed-in session for every API call.
///
/// * One refresh at a time: when five requests get `401` together, exactly one
///   refresh call is made and the other four wait for its result (single flight).
///   The server rotates refresh tokens, so a second concurrent refresh would be
///   rejected and could end the session.
/// * Another isolate (background task) may have rotated the token meanwhile: before
///   giving up, the stored session is re-read and used if it is newer.
/// * Tokens live only in the [TokenStore] (Keychain/Keystore) and in memory.
/// * A `401` is answered by exactly ONE refresh and ONE retry of the request
///   ([authorized]); a second `401` is surfaced, never looped.
/// * [accountEpoch] changes whenever the signed-in account changes or the session
///   ends, so long-running work (an upload) can tell that its result belongs to a
///   previous session and must be dropped.
class SessionManager {
  SessionManager({
    required TokenStore store,
    required AuthRepository repository,
    DateTime Function()? clock,
    this.expirySkew = const Duration(seconds: 30),
  })  : _store = store,
        _repo = repository,
        _clock = clock ?? DateTime.now;

  final TokenStore _store;
  final AuthRepository _repo;
  final DateTime Function() _clock;

  /// A token that expires within this window is refreshed first.
  final Duration expirySkew;

  /// Called after the session ended for good (refresh rejected, sign-out).
  void Function()? onSignedOut;

  AuthSession? _session;
  Future<AuthSession>? _refreshing;
  // What the running refresh is FOR: the refresh token it uses and the account epoch it started in. A caller of another
  // session (the account changed meanwhile) must not be handed this refresh's result or its failure.
  String? _refreshingToken;
  int _refreshingEpoch = -1;
  int _epoch = 0;

  /// Bumped (synchronously) by [clear] and by [adopt] of a different user. Capture it
  /// before an `await`, compare afterwards: a difference means the account changed
  /// in between and whatever just arrived is about the previous one.
  int get accountEpoch => _epoch;

  /// Number of refresh requests actually sent (diagnostics and tests).
  int refreshCalls = 0;

  /// The active session: the one in memory, else the stored one.
  ///
  /// A read that was in flight while the session was cleared or replaced must not bring the old session back
  /// (F-16): the epoch tells whether anything changed meanwhile. A store that cannot be read (Keychain locked,
  /// Keystore error) is "no session" for this call, never an exception: the form must still be usable.
  Future<AuthSession?> current() async {
    final cached = _session;
    if (cached != null) return cached;
    final epoch = _epoch;
    final read = await _readStore();
    if (_epoch != epoch) return _session;
    return _session ??= read;
  }

  Future<AuthSession?> _readStore() async {
    try {
      return await _store.read();
    } catch (e, st) {
      reportError(e, st, 'token store read');
      return null;
    }
  }

  /// Makes [session] the active one (after sign-in) and persists it.
  ///
  /// A store that cannot be written does not fail the sign-in (an endless spinner): the session works in memory
  /// for this run, and the failure is recorded (F-10).
  Future<void> adopt(AuthSession session) async {
    if (_session?.user.id != session.user.id) _epoch++;
    _session = session;
    try {
      await _store.write(session);
    } catch (e, st) {
      reportError(e, st, 'token store write');
    }
  }

  /// Forgets the session locally. Never throws: a Keychain that refuses to delete must not make sign-out impossible.
  Future<void> clear() async {
    _epoch++;
    _session = null;
    try {
      await _store.clear();
    } catch (e, st) {
      reportError(e, st, 'token store clear');
    }
  }

  /// The stored session with a usable access token, refreshing it if needed.
  /// Throws [AuthException] (`sessionExpired`) when signed out.
  Future<AuthSession> validSession() async {
    final s = await current();
    if (s == null) throw const AuthException(AuthError.sessionExpired);
    if (s.isExpired(_clock().add(expirySkew))) return refresh(s);
    return s;
  }

  /// Refreshes [used] unless a refresh of the same session is already running (single flight per refresh token).
  Future<AuthSession> refresh(AuthSession used) {
    final running = _refreshing;
    if (running != null &&
        _refreshingToken == used.refreshToken &&
        _refreshingEpoch == _epoch) {
      return running;
    }
    late final Future<AuthSession> flight;
    flight = _refreshOnce(used).whenComplete(() {
      if (identical(_refreshing, flight)) {
        _refreshing = null;
        _refreshingToken = null;
      }
    });
    _refreshing = flight;
    _refreshingToken = used.refreshToken;
    _refreshingEpoch = _epoch;
    return flight;
  }

  Future<AuthSession> _refreshOnce(AuthSession used) async {
    refreshCalls++;
    final epoch = _epoch;
    try {
      final fresh = await _repo.refresh(used.refreshToken);
      // The user signed out, or another account signed in, while the request was on
      // the wire: this answer belongs to a session nobody uses any more. Adopting it
      // would sign the old account back in over the new one.
      if (_epoch != epoch) throw const _Superseded();
      await adopt(fresh);
      return fresh;
    } on _Superseded {
      throw const AuthException(AuthError.sessionExpired);
    } on AuthException catch (e) {
      // Only "this session is no longer valid" (a 401) ends the sign-in. A 400, a 409 or anything else the server or a proxy
      // answers is not a verdict on the refresh token: the tokens stay and the call can be tried again.
      if (e.error != AuthError.sessionExpired) rethrow;
      // A rejection of an old session must not end the one that replaced it.
      if (_epoch != epoch) {
        throw const AuthException(AuthError.sessionExpired);
      }
      final stored = await _readStore();
      if (stored != null &&
          stored.refreshToken != used.refreshToken &&
          !stored.isExpired(_clock())) {
        _session = stored; // another isolate rotated it first
        return stored;
      }
      await clear();
      onSignedOut?.call();
      throw const AuthException(AuthError.sessionExpired);
    }
  }

  /// Runs [call] with a valid access token; on `401` refreshes once and retries once.
  ///
  /// At most two calls and one refresh per invocation, whatever the server answers:
  /// the retry's outcome (a second `401` included) is returned or thrown as is.
  /// A `401` is an [ApiFailure] of kind `unauthorized`, or the [AuthException]
  /// (`sessionExpired`) that the auth repository makes of one.
  ///
  /// [userId] pins the call to one account: when the signed-in user is not [userId]
  /// (the account changed since the caller decided to act for it) nothing is sent
  /// and [WrongAccountException] is thrown, so a request prepared for account A can
  /// never carry account B's token.
  Future<T> authorized<T>(Future<T> Function(String accessToken) call,
      {String? userId}) async {
    var session = await validSession();
    _expect(session, userId);
    try {
      return await call(session.accessToken);
    } catch (e) {
      if (!_isUnauthorized(e)) rethrow;
      session = await refresh(session);
      _expect(session, userId);
      return call(session.accessToken);
    }
  }

  static void _expect(AuthSession session, String? userId) {
    if (userId != null && session.user.id != userId) {
      throw const WrongAccountException();
    }
  }

  static bool _isUnauthorized(Object e) =>
      (e is AuthException && e.error == AuthError.sessionExpired) ||
      ApiFailure.of(e).kind == ApiFailureKind.unauthorized;
}
