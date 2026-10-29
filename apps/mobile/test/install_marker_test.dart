// A session left in the Keychain by an earlier install is not this install's (audit F-19).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/features/auth/data/install_marker.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';

AuthSession _session() => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime(2030),
      user: const User(id: 'u', email: 'old@example.test'),
    );

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  test(
      'a fresh install (no preferences) removes the session an earlier install left behind',
      () async {
    final store = InMemoryTokenStore();
    await store.write(_session());
    final prefs = await _prefs({});
    expect(await clearSessionOfPreviousInstall(prefs: prefs, tokens: store),
        isTrue);
    expect(await store.read(), isNull);
    expect(prefs.containsKey(kInstallMarkerKey), isTrue);
  });

  test(
      'an existing install that is only updated keeps its session and gets the marker',
      () async {
    final store = InMemoryTokenStore();
    await store.write(_session());
    final prefs =
        await _prefs({'wb.settingsOwner': 'abc', 'wb.onboarded': true});
    expect(await clearSessionOfPreviousInstall(prefs: prefs, tokens: store),
        isFalse);
    expect(await store.read(), isNotNull);
    expect(prefs.containsKey(kInstallMarkerKey), isTrue);
  });

  test(
      'after the marker exists nothing is ever removed again, also when the preferences are otherwise empty',
      () async {
    final store = InMemoryTokenStore();
    final prefs = await _prefs({});
    await clearSessionOfPreviousInstall(prefs: prefs, tokens: store);
    // The user signs in; the app restarts with only the marker in the preferences.
    await store.write(_session());
    expect(await clearSessionOfPreviousInstall(prefs: prefs, tokens: store),
        isFalse);
    expect(await store.read(), isNotNull);
  });

  test(
      'a fresh install with nothing in the store changes nothing but the marker',
      () async {
    final prefs = await _prefs({});
    expect(
        await clearSessionOfPreviousInstall(
            prefs: prefs, tokens: InMemoryTokenStore()),
        isFalse);
    expect(prefs.containsKey(kInstallMarkerKey), isTrue);
  });

  test('a store that throws does not stop the start', () async {
    final prefs = await _prefs({});
    expect(
        await clearSessionOfPreviousInstall(
            prefs: prefs, tokens: _ThrowingStore()),
        isFalse);
    expect(prefs.containsKey(kInstallMarkerKey), isTrue);
  });
}

class _ThrowingStore implements TokenStore {
  @override
  Future<AuthSession?> read() async => throw StateError('keychain unavailable');
  @override
  Future<void> write(AuthSession session) async {}
  @override
  Future<void> clear() async {}
}
