// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import '../support/fake_auth.dart';

// The routing rule that decides whether the account is skipped. The only input
// that may skip it is `localOnlyDev` (AppConfig.isLocalOnlyDev, true only for
// a debug build started with LOCAL_ONLY_DEV=true). A missing or broken
// API_BASE_URL is not an input here: the rule fails closed.

const _fresh = Settings();
const _done = Settings(onboarded: true);

/// What `startDestination` returns, or `null` when it throws (see the
/// `AsyncError` test below).
StartDestination? _route({
  required bool localOnlyDev,
  required AsyncValue<AuthState> auth,
  required Settings settings,
}) {
  try {
    return startDestination(
        localOnlyDev: localOnlyDev, auth: auth, settings: settings);
  } catch (_) {
    return null;
  }
}

/// Every auth state that is not a confirmed session.
final Map<String, AsyncValue<AuthState>> _notSignedIn = {
  'loading': const AsyncLoading<AuthState>(),
  'loading, earlier session': const AsyncLoading<AuthState>()
      .copyWithPrevious(AsyncData<AuthState>(SignedIn(session('earlier')))),
  'unknown': const AsyncData<AuthState>(AuthUnknown()),
  'signed out': const AsyncData<AuthState>(SignedOut()),
  for (final e in AuthError.values)
    'failure ${e.name}': AsyncData<AuthState>(AuthFailure(e)),
  'error':
      AsyncError<AuthState>(StateError('restore failed'), StackTrace.empty),
};

/// Every auth state with a session.
final Map<String, AsyncValue<AuthState>> _signedIn = {
  'signed in': AsyncData<AuthState>(SignedIn(session('a'))),
  'signed in offline':
      AsyncData<AuthState>(SignedIn(session('a'), offline: true)),
};

void main() {
  group('without LOCAL_ONLY_DEV the account is always required', () {
    test('no state but SignedIn reaches setup or dashboard', () {
      for (final entry in _notSignedIn.entries) {
        for (final settings in [_fresh, _done]) {
          final result = _route(
              localOnlyDev: false, auth: entry.value, settings: settings);
          expect(result, isNot(StartDestination.setup),
              reason: '${entry.key}, onboarded=${settings.onboarded}');
          expect(result, isNot(StartDestination.dashboard),
              reason: '${entry.key}, onboarded=${settings.onboarded}');
        }
      }
    });

    test('while the session is restored: splash, whatever the settings say',
        () {
      for (final key in ['loading', 'loading, earlier session', 'unknown']) {
        for (final settings in [_fresh, _done]) {
          expect(
              startDestination(
                  localOnlyDev: false,
                  auth: _notSignedIn[key]!,
                  settings: settings),
              StartDestination.splash,
              reason: '$key, onboarded=${settings.onboarded}');
        }
      }
    });

    test('signed out or a failed sign-in: welcome, whatever the settings say',
        () {
      final states = {
        for (final e in _notSignedIn.entries)
          if (e.key == 'signed out' || e.key.startsWith('failure'))
            e.key: e.value
      };
      expect(states, hasLength(1 + AuthError.values.length));
      for (final entry in states.entries) {
        for (final settings in [_fresh, _done]) {
          expect(
              startDestination(
                  localOnlyDev: false, auth: entry.value, settings: settings),
              StartDestination.welcome,
              reason: '${entry.key}, onboarded=${settings.onboarded}');
        }
      }
    });

    test('an error while restoring the session: welcome, never the app', () {
      // `AsyncValue.value` rethrows an error without a value: the rule must
      // not throw (StartGate would crash) and must not wait on the splash.
      final error = _notSignedIn['error']!;
      for (final settings in [_fresh, _done]) {
        expect(
            startDestination(
                localOnlyDev: false, auth: error, settings: settings),
            StartDestination.welcome,
            reason: 'onboarded=${settings.onboarded}');
      }
    });

    test('signed in: setup until it is finished, then the dashboard', () {
      for (final entry in _signedIn.entries) {
        expect(
            startDestination(
                localOnlyDev: false, auth: entry.value, settings: _fresh),
            StartDestination.setup,
            reason: entry.key);
        expect(
            startDestination(
                localOnlyDev: false, auth: entry.value, settings: _done),
            StartDestination.dashboard,
            reason: entry.key);
      }
    });

    test('a session is the only way in', () {
      final reached = <String>{};
      for (final entry in {..._notSignedIn, ..._signedIn}.entries) {
        for (final settings in [_fresh, _done]) {
          final result = _route(
              localOnlyDev: false, auth: entry.value, settings: settings);
          if (result == StartDestination.setup ||
              result == StartDestination.dashboard) {
            reached.add(entry.key);
          }
        }
      }
      expect(reached, _signedIn.keys.toSet());
    });
  });

  group('with LOCAL_ONLY_DEV the account is skipped', () {
    test(
        'setup when not onboarded, dashboard when onboarded, whatever auth says',
        () {
      for (final entry in {..._notSignedIn, ..._signedIn}.entries) {
        expect(
            startDestination(
                localOnlyDev: true, auth: entry.value, settings: _fresh),
            StartDestination.setup,
            reason: entry.key);
        expect(
            startDestination(
                localOnlyDev: true, auth: entry.value, settings: _done),
            StartDestination.dashboard,
            reason: entry.key);
      }
    });

    test('it never shows the welcome screen or the splash', () {
      for (final entry in {..._notSignedIn, ..._signedIn}.entries) {
        for (final settings in [_fresh, _done]) {
          final result = startDestination(
              localOnlyDev: true, auth: entry.value, settings: settings);
          expect(
              result, anyOf(StartDestination.setup, StartDestination.dashboard),
              reason: entry.key);
        }
      }
    });
  });

  test('the switch is the only thing that changes the account requirement', () {
    // For each state, the verdicts with and without the switch differ exactly
    // for the states without a session.
    for (final entry in {..._notSignedIn, ..._signedIn}.entries) {
      for (final settings in [_fresh, _done]) {
        final off =
            _route(localOnlyDev: false, auth: entry.value, settings: settings);
        final on =
            _route(localOnlyDev: true, auth: entry.value, settings: settings);
        final hasSession = _signedIn.containsKey(entry.key);
        expect(off == on, hasSession,
            reason: '${entry.key}, onboarded=${settings.onboarded}');
      }
    }
  });
}
