import '../domain/auth_models.dart';

/// Used when no `API_BASE_URL` is configured (only reachable in the debug-only
/// `LOCAL_ONLY_DEV` mode; any other build without an address is invalid and
/// never starts): every call
/// reports [AuthError.unavailable], so the UI says cloud features are off instead
/// of pretending there is an account system.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  Never _unavailable() => throw const AuthException(AuthError.unavailable);

  @override
  Future<AuthSession> signInWithEmail(
          {required String email, required String password}) async =>
      _unavailable();

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      _unavailable();

  @override
  Future<AuthSession> signInWithApple() async => _unavailable();

  @override
  Future<AuthSession> signInWithGoogle() async => _unavailable();

  @override
  Future<AuthSession> refresh(String refreshToken) async => _unavailable();

  @override
  Future<User> me(String accessToken) async => _unavailable();

  @override
  Future<void> deleteAccount(String accessToken) async => _unavailable();

  @override
  Future<void> signOut(String refreshToken) async {}
}

/// Test double. Never wired into the app (only tests override the provider with it).
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({this.password = 'password', DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final String password;
  final DateTime Function() _clock;
  final Set<String> _revoked = {};
  int _counter = 0;

  AuthSession _session(String email) {
    _counter++;
    return AuthSession(
      accessToken: 'mock-access-$_counter',
      refreshToken: 'mock-refresh-$_counter',
      expiresAt: _clock().add(const Duration(minutes: 15)),
      user: User(
          id: 'mock-${email.hashCode}',
          email: email,
          displayName: email.split('@').first),
    );
  }

  @override
  Future<AuthSession> signInWithEmail(
      {required String email, required String password}) async {
    if (password != this.password) {
      throw const AuthException(AuthError.invalidCredentials);
    }
    return _session(email);
  }

  @override
  Future<AuthSession> signUpWithEmail(
          {required String email, required String password}) async =>
      _session(email);

  @override
  Future<AuthSession> signInWithApple() async => _session('apple@example.com');

  @override
  Future<AuthSession> signInWithGoogle() async =>
      _session('google@example.com');

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    if (_revoked.contains(refreshToken)) {
      throw const AuthException(AuthError.sessionExpired);
    }
    _revoked.add(refreshToken); // rotation: the old token is single-use
    return _session('refreshed@example.com');
  }

  @override
  Future<void> signOut(String refreshToken) async => _revoked.add(refreshToken);

  /// Set to make `me` fail, e.g. with `AuthError.network`.
  AuthError? meFailure;

  @override
  Future<User> me(String accessToken) async {
    final f = meFailure;
    if (f != null) throw AuthException(f);
    return const User(id: 'mock', email: 'mock@example.com');
  }

  bool accountDeleted = false;

  @override
  Future<void> deleteAccount(String accessToken) async => accountDeleted = true;
}
