// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// An account switch cannot leak across accounts through the account-settings calls (F-13) or through a failed swap of the
// locally stored settings (F-21).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/account_settings.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import 'support/fake_account_settings.dart';
import 'support/fake_backend.dart';
import 'support/phone_rig.dart';
import 'sync_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('account settings are pinned to the account that asked (F-13)', () {
    late SyncRig rig;
    late AccountSettingsSync sync;
    setUp(() async {
      rig = await SyncRig.create();
      sync = AccountSettingsSync(apis: rig.sync.apis, sessions: rig.sessions);
    });
    tearDown(() => rig.close());

    Map<String, Object?> account(String country) => {
          'countryCode': country,
          'countryCodeSource': 'detected',
          'currencyCode': 'PLN',
          'currencyCodeSource': 'detected',
          'electricityPriceMode': 'automatic',
          'manualElectricityPrice': null,
          'electricityPriceSource': null,
        };

    test(
        'a pull pinned to account A is refused, not sent, while account B is signed in',
        () async {
      rig.backend.routes['GET /api/v1/me/settings'] =
          (r) => FakeBackend.json(account('PL'));
      await rig.sessions.adopt(sessionOf('user-b'));
      expect(await sync.pull(userId: 'user-a'), isNull);
      expect(rig.backend.where('GET', '/api/v1/me/settings'), isEmpty,
          reason: 'B\'s token must not carry a request made for A');
    });

    test(
        'an answer is never attributed to an account other than the one whose token asked',
        () async {
      rig.backend.routes['GET /api/v1/me/settings'] = (r) => FakeBackend.json(
          account(userOfToken(r.bearer) == 'user-a' ? 'PL' : 'DE'));
      final pending = sync.pull();
      await rig.sessions.adopt(sessionOf('user-b'));
      final result = await pending;
      final asked = rig.backend.where('GET', '/api/v1/me/settings');
      if (result != null) {
        expect(result.countryCode,
            userOfToken(asked.last.bearer) == 'user-a' ? 'PL' : 'DE');
      }
    });

    test('a push prepared for account A is not sent with account B\'s token',
        () async {
      var puts = <String>[];
      rig.backend.routes['GET /api/v1/me/settings'] =
          (r) => FakeBackend.json(account('PL'));
      rig.backend.routes['PUT /api/v1/me/settings'] = (r) {
        puts.add(userOfToken(r.bearer));
        return FakeBackend.json(account('PL'));
      };
      // The pull is the first await of the push; the account switches while it is on the wire.
      final first = rig.backend.routes['GET /api/v1/me/settings']!;
      rig.backend.routes['GET /api/v1/me/settings'] = (r) {
        final response = first(r);
        // The switch lands after A's request was answered and before the push's PUT is made.
        unawaited(rig.sessions.adopt(sessionOf('user-b')));
        return response;
      };
      final settings = const Settings().withManualCurrency('EUR');
      final result = await sync.push(settings);
      expect(puts.where((u) => u != 'user-a'), isEmpty,
          reason: 'B\'s token never carried A\'s settings');
      expect(result, isNull);
    });
  });

  group('a failed swap of the stored settings (F-21)', () {
    test(
        'the start gate shows a blocking error, not the previous user\'s settings',
        () {
      final auth = AsyncData<AuthState>(SignedIn(AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime(2030),
          user: const User(id: 'user-b', email: 'b@example.test'))));
      const previousUser = Settings(onboarded: true);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: auth,
              settings: previousUser,
              settingsBound: false,
              settingsBindFailed: true),
          StartDestination.settingsError);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: auth,
              settings: previousUser,
              settingsBound: false),
          StartDestination.splash,
          reason: 'still binding: the splash, as before');
    });

    test('retries succeed after a transient failure and the gate opens',
        () async {
      final backend = FakeBackend();
      FakeAccountSettings(backend);
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.signOut();

      final saved = SettingsNotifier.bindRetryDelays;
      SettingsNotifier.bindRetryDelays = const [
        Duration(milliseconds: 20),
        Duration(milliseconds: 20)
      ];
      addTearDown(() => SettingsNotifier.bindRetryDelays = saved);
      final failing = _FailsTimes(phone.prefs, 2);
      // The same phone, with a preferences layer that fails the first two swaps.
      phone.extraOverrides = [settingsStoreProvider.overrideWithValue(failing)];
      phone.rebuild();
      await phone.signIn('user-b');
      expect(failing.attempts, 3, reason: 'two failures, then the swap worked');
      expect(phone.c.read(settingsBindFailedProvider), isFalse);
      expect(phone.c.read(settingsBoundProvider), isTrue);
    });

    test(
        'a swap that keeps failing keeps the gate shut and flags it; Retry works once the failure is gone',
        () async {
      final backend = FakeBackend();
      FakeAccountSettings(backend);
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('USD'));
      await phone.signOut();

      final saved = SettingsNotifier.bindRetryDelays;
      SettingsNotifier.bindRetryDelays = const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 10)
      ];
      addTearDown(() => SettingsNotifier.bindRetryDelays = saved);
      final failing = _FailsTimes(phone.prefs, 1000);
      phone.extraOverrides = [settingsStoreProvider.overrideWithValue(failing)];
      phone.rebuild();
      phone.c.read(
          settingsProvider); // the notifier binds the account when it is first read
      await phone.c.read(authControllerProvider.future);
      await phone.c
          .read(authControllerProvider.notifier)
          .signInWithEmail('user-b', 'password');
      for (var i = 0;
          i < 200 && !phone.c.read(settingsBindFailedProvider);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(phone.c.read(settingsBindFailedProvider), isTrue);
      expect(phone.c.read(settingsBoundProvider), isFalse,
          reason: 'user A\'s USD must not be shown as user B\'s');

      failing.remaining = 0; // the failure is gone
      phone.c.read(settingsProvider.notifier).retryBind();
      for (var i = 0; i < 200 && !phone.c.read(settingsBoundProvider); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(phone.c.read(settingsBoundProvider), isTrue);
      expect(phone.c.read(settingsBindFailedProvider), isFalse);
    });
  });
}

/// A settings store whose account swap fails [remaining] times before it works.
class _FailsTimes extends SettingsStore {
  _FailsTimes(super.prefs, this.remaining);

  int remaining;
  int attempts = 0;

  @override
  Future<void> switchAccount(String key) async {
    attempts++;
    if (remaining > 0) {
      remaining--;
      throw StateError('preferences write failed');
    }
    return super.switchAccount(key);
  }
}
