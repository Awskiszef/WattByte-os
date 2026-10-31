// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';

import 'support/fake_auth.dart';

/// The session as it sits in the Keychain / Keystore (`SecureTokenStore`), with
/// `FlutterSecureStorage`'s own in-memory test double underneath: what is
/// written, what is read back, and what a damaged record does to the app start.
///
/// A record that cannot be read must never stop the app from starting: an
/// exception from `read()` escapes `AuthController.build`, leaves the auth state
/// in error and the start gate on the splash screen for good.
void main() {
  final expires = DateTime.utc(2026, 10, 13, 12, 30, 45);

  AuthSession session({
    String? displayName = 'Ala',
    Plan plan = Plan.premium,
    DateTime? expiresAt,
  }) =>
      AuthSession(
        accessToken: 'access.jwt.value',
        refreshToken: 'cmVmcmVzaC10b2tlbi12YWx1ZQ',
        expiresAt: expiresAt ?? expires,
        user: User(
            id: '11111111-1111-4111-8111-111111111111',
            email: 'ala@example.com',
            displayName: displayName,
            plan: plan),
      );

  const keys = {
    'wb.auth.access',
    'wb.auth.refresh',
    'wb.auth.expires',
    'wb.auth.user.id',
    'wb.auth.user.email',
    'wb.auth.user.name',
    'wb.auth.user.plan',
  };

  /// A complete, valid record as plain strings.
  Map<String, String> record() => {
        'wb.auth.access': 'access.jwt.value',
        'wb.auth.refresh': 'cmVmcmVzaC10b2tlbi12YWx1ZQ',
        'wb.auth.expires': expires.toIso8601String(),
        'wb.auth.user.id': 'user-1',
        'wb.auth.user.email': 'ala@example.com',
        'wb.auth.user.name': 'Ala',
        'wb.auth.user.plan': 'free',
      };

  SecureTokenStore storeOver(Map<String, String> values) {
    FlutterSecureStorage.setMockInitialValues(values);
    return SecureTokenStore();
  }

  Future<Map<String, String>> raw() => const FlutterSecureStorage().readAll();

  group('round trip', () {
    test('a written session is read back as it was', () async {
      final store = storeOver({});
      await store.write(session());
      final back = (await store.read())!;
      expect(back.accessToken, 'access.jwt.value');
      expect(back.refreshToken, 'cmVmcmVzaC10b2tlbi12YWx1ZQ');
      expect(back.expiresAt.isAtSameMomentAs(expires), isTrue);
      expect(back.user.id, '11111111-1111-4111-8111-111111111111');
      expect(back.user.email, 'ala@example.com');
      expect(back.user.displayName, 'Ala');
      expect(back.user.plan, Plan.premium);
    });

    test('a user without a display name stays without one (null, not "")',
        () async {
      final store = storeOver({});
      await store.write(session(displayName: null));
      expect((await store.read())!.user.displayName, isNull);
    });

    test('both plans survive', () async {
      for (final plan in Plan.values) {
        final store = storeOver({});
        await store.write(session(plan: plan));
        expect((await store.read())!.user.plan, plan);
      }
    });

    test('the expiry is stored in UTC whatever zone the session carries',
        () async {
      final store = storeOver({});
      await store.write(session(expiresAt: DateTime(2026, 3, 29, 3, 30)));
      final stored = (await raw())['wb.auth.expires']!;
      expect(stored, endsWith('Z'));
      expect((await store.read())!.expiresAt, DateTime.parse(stored));
    });

    test('a second write replaces the whole first one', () async {
      final store = storeOver({});
      await store.write(session());
      await store.write(AuthSession(
        accessToken: 'second-access',
        refreshToken: 'second-refresh',
        expiresAt: expires.add(const Duration(days: 1)),
        user: const User(id: 'u2', email: 'other@example.com'),
      ));
      final back = (await store.read())!;
      expect(back.accessToken, 'second-access');
      expect(back.user.email, 'other@example.com');
      expect(back.user.displayName, isNull,
          reason: 'the first user\'s name must not leak into the second');
      expect(back.user.plan, Plan.free);
      expect((await raw()).values, isNot(contains('ala@example.com')));
    });

    test('only the documented keys are written, nothing else', () async {
      final store = storeOver({});
      await store.write(session());
      expect((await raw()).keys.toSet(), keys);
    });
  });

  group('nothing stored, or not everything', () {
    test('an empty store has no session', () async {
      expect(await storeOver({}).read(), isNull);
    });

    test('each required value missing means no session, never a half one',
        () async {
      for (final key in [
        'wb.auth.access',
        'wb.auth.refresh',
        'wb.auth.expires',
        'wb.auth.user.id',
        'wb.auth.user.email',
      ]) {
        final values = record()..remove(key);
        expect(await storeOver(values).read(), isNull, reason: key);
      }
    });

    test('the display name and the plan are optional', () async {
      final values = record()
        ..remove('wb.auth.user.name')
        ..remove('wb.auth.user.plan');
      final back = (await storeOver(values).read())!;
      expect(back.user.displayName, isNull);
      expect(back.user.plan, Plan.free);
    });

    test('clear removes every key', () async {
      final store = storeOver({});
      await store.write(session());
      await store.clear();
      expect(await raw(), isEmpty);
      expect(await store.read(), isNull);
    });

    test('clearing an empty store is harmless', () async {
      final store = storeOver({});
      await store.clear();
      expect(await store.read(), isNull);
    });
  });

  group('a damaged record never throws', () {
    test('an unknown plan name is "free": the server decides, not the phone',
        () async {
      for (final plan in ['gold', 'PREMIUM', '', '0', 'null']) {
        final values = record()..['wb.auth.user.plan'] = plan;
        final back = await storeOver(values).read();
        expect(back, isNotNull, reason: '"$plan"');
        expect(back!.user.plan, Plan.free, reason: '"$plan"');
      }
    });

    test('an unreadable expiry makes the session expired, so it is refreshed',
        () async {
      for (final bad in ['garbage', '', 'yesterday', '12345', 'null']) {
        final values = record()..['wb.auth.expires'] = bad;
        final back = await storeOver(values).read();
        expect(back, isNotNull, reason: '"$bad"');
        expect(back!.isExpired(DateTime.now()), isTrue, reason: '"$bad"');
        expect(back.refreshToken, 'cmVmcmVzaC10b2tlbi12YWx1ZQ',
            reason: 'the refresh token is what recovers the session');
      }
    });

    test('a record with an empty token is no session at all', () async {
      for (final key in ['wb.auth.access', 'wb.auth.refresh']) {
        final values = record()..[key] = '';
        expect(await storeOver(values).read(), isNull, reason: key);
      }
    });
  });

  group('the app starts whatever the stored record looks like', () {
    ProviderContainer launch(SecureTokenStore store, FakeAuthRepository repo) {
      final c = ProviderContainer(overrides: [
        apiConfigProvider.overrideWithValue(const ApiConfig('http://api.test')),
        authRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('a damaged expiry is refreshed and the user stays signed in',
        () async {
      final store = storeOver(record()..['wb.auth.expires'] = 'garbage');
      final repo = FakeAuthRepository()..refreshDelay = Duration.zero;
      final c = launch(store, repo);
      final state = await c.read(authControllerProvider.future);
      expect(state, isA<SignedIn>());
      expect(repo.refreshCalls, 1);
      expect((await store.read())!.refreshToken, 'refresh-r1');
    });

    test('an unknown plan does not stop the start; the server answers it',
        () async {
      final store = storeOver(record()..['wb.auth.user.plan'] = 'gold');
      final c = launch(store, FakeAuthRepository());
      final state = await c.read(authControllerProvider.future);
      expect(state, isA<SignedIn>());
    });

    test('an incomplete record starts signed out', () async {
      final store = storeOver(record()..remove('wb.auth.refresh'));
      final c = launch(store, FakeAuthRepository());
      expect(await c.read(authControllerProvider.future), isA<SignedOut>());
    });
  });
}
