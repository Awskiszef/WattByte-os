// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/setup_controller.dart';

/// Settings through the app's own provider (`settingsProvider`), across a
/// simulated process restart: a NEW `ProviderContainer` over a NEW
/// `SharedPreferences` instance that was built from what the old one had stored.
/// This is the path the real app takes, not just `SettingsStore` on its own.
void main() {
  /// What a process restart would find on disk.
  Map<String, Object> disk(SharedPreferences p) =>
      {for (final k in p.getKeys()) k: p.get(k)!};

  Future<SharedPreferences> prefsFrom(Map<String, Object> values) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  ProviderContainer launch(SharedPreferences prefs) {
    final c =
        ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  /// Ends the "process" and starts the next one.
  Future<ProviderContainer> restart(
      ProviderContainer old, SharedPreferences prefs) async {
    old.dispose();
    return launch(await prefsFrom(disk(prefs)));
  }

  test('a fresh install starts with the defaults and is not onboarded',
      () async {
    final c = launch(await prefsFrom({}));
    final s = c.read(settingsProvider);
    expect(s.onboarded, isFalse);
    expect(s.cloudSync, isFalse);
    expect(s.currency, '');
    expect(s.hasPrice, isFalse);
  });

  test(
      'every change made through the notifier is on disk when update() returns',
      () async {
    final prefs = await prefsFrom({});
    var c = launch(prefs);
    final notifier = c.read(settingsProvider.notifier);
    await notifier.update((s) => s.copyWith(cloudSync: true));
    // Not just the in-memory state: a new process sees it.
    c = await restart(c, prefs);
    expect(c.read(settingsProvider).cloudSync, isTrue,
        reason: 'bug 3: the switch was lost after a restart');
  });

  test('several updates in a row all survive, in order', () async {
    final prefs = await prefsFrom({});
    var c = launch(prefs);
    final n = c.read(settingsProvider.notifier);
    await n.update((s) => s.copyWith(theme: AppTheme.dark));
    await n.update((s) => s.withManualCurrency('eur'));
    await n.update((s) => s.withManualPrice(0.42));
    await n.update((s) => s.copyWith(binaryUnits: true));
    await n.update((s) => s.copyWith(theme: AppTheme.light));
    c = await restart(c, prefs);
    final s = c.read(settingsProvider);
    expect(s.theme, AppTheme.light, reason: 'the last write wins');
    expect(s.currency, 'EUR');
    expect(s.currencySource, SettingSource.manual);
    expect(s.priceMode, ElectricityPriceMode.manual);
    expect(s.pricePerKwh, 0.42);
    expect(s.manualPricePerKwh, 0.42);
    expect(s.binaryUnits, isTrue);
  });

  test('updates started at the same time do not overwrite each other',
      () async {
    final prefs = await prefsFrom({});
    var c = launch(prefs);
    final n = c.read(settingsProvider.notifier);
    await Future.wait([
      n.update((s) => s.copyWith(cloudSync: true)),
      n.update((s) => s.copyWith(notifyChargingDone: true)),
      n.update((s) => s.copyWith(dataCollection: false)),
    ]);
    c = await restart(c, prefs);
    final s = c.read(settingsProvider);
    expect([s.cloudSync, s.notifyChargingDone, s.dataCollection],
        [true, true, false]);
  });

  test('a value that fails validation is stored sanitised, and read as such',
      () async {
    final prefs = await prefsFrom({});
    var c = launch(prefs);
    await c
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(efficiency: 7, pricePerKwh: double.nan));
    c = await restart(c, prefs);
    final s = c.read(settingsProvider);
    expect(s.efficiency, 0.85);
    expect(s.pricePerKwh, 0);
    expect(s.energyCalc, returnsNormally);
  });

  group('the design capacity through the provider', () {
    test('every source survives a restart; unknown carries no number',
        () async {
      for (final source in DesignCapacitySource.values) {
        final prefs = await prefsFrom({});
        var c = launch(prefs);
        final known = source != DesignCapacitySource.unknown;
        await c.read(settingsProvider.notifier).update((s) => s.copyWith(
            designCapacityMah: known ? 3274 : 0,
            designCapacityWh: known ? 12.7 : 0,
            designCapacitySource: source));
        c = await restart(c, prefs);
        final s = c.read(settingsProvider);
        expect(s.designCapacitySource, source);
        expect(s.designCapacityMah, known ? 3274 : 0);
        expect(s.designCapacityWh, known ? 12.7 : 0);
        expect(s.designCapacity.isKnown, known);
      }
    });

    test('a manual capacity is still manual after a restart and later updates',
        () async {
      final prefs = await prefsFrom({});
      var c = launch(prefs);
      final n = c.read(settingsProvider.notifier);
      await n.update((s) => s.withDesignCapacity(
          DesignCapacity(mah: 4100, source: DesignCapacitySource.manual)));
      await n.update((s) => s.copyWith(theme: AppTheme.dark));
      c = await restart(c, prefs);
      final s = c.read(settingsProvider);
      expect(s.designCapacity,
          DesignCapacity(mah: 4100, source: DesignCapacitySource.manual));
    });

    test(
        'an install from before the split starts with its catalog capacity '
        'renamed and its measurement dropped', () async {
      for (final (legacy, expected) in <(String, DesignCapacitySource)>[
        ('localDatabase', DesignCapacitySource.localDeviceDatabase),
        ('backendDatabase', DesignCapacitySource.backendDeviceDatabase),
        ('manual', DesignCapacitySource.manual),
        ('system', DesignCapacitySource.unknown),
        ('estimated', DesignCapacitySource.unknown),
      ]) {
        final prefs = await prefsFrom({
          'wb.batteryCapacityMah': 3988.0,
          'wb.capacitySource': legacy,
          'wb.onboarded': true,
        });
        var c = launch(prefs);
        final first = c.read(settingsProvider);
        expect(first.designCapacitySource, expected, reason: legacy);
        expect(first.designCapacityMah,
            expected == DesignCapacitySource.unknown ? 0 : 3988,
            reason: legacy);
        expect(first.onboarded, isTrue, reason: 'the install stays onboarded');
        // The first write converts the stored keys for good.
        await c
            .read(settingsProvider.notifier)
            .update((s) => s.copyWith(theme: AppTheme.dark));
        expect(prefs.containsKey('wb.batteryCapacityMah'), isFalse);
        expect(prefs.containsKey('wb.capacitySource'), isFalse);
        expect(prefs.getString('wb.designCapacitySource'), expected.name);
        c = await restart(c, prefs);
        expect(c.read(settingsProvider).designCapacitySource, expected,
            reason: legacy);
      }
    });

    test(
        'a legacy measured capacity never feeds the calculator as a design '
        'capacity', () async {
      final c = launch(await prefsFrom({
        'wb.batteryCapacityMah': 4480.0,
        'wb.capacitySource': 'system',
      }));
      final s = c.read(settingsProvider);
      expect(s.designCapacityMah, 0);
      expect(s.energyCalc().canEstimateFromPercent, isFalse);
      expect(s.energyCalc().batteryCapacityMah, 0);
    });
  });

  group('the onboarding flag', () {
    test('is stored under wb.onboarded and defaults to false', () async {
      final prefs = await prefsFrom({});
      expect(prefs.containsKey('wb.onboarded'), isFalse);
      final c = launch(prefs);
      expect(c.read(settingsProvider).onboarded, isFalse);
      await c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(onboarded: true));
      expect(prefs.getBool('wb.onboarded'), isTrue);
    });

    test('survives a restart and later changes do not clear it', () async {
      final prefs = await prefsFrom({});
      var c = launch(prefs);
      await c
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(onboarded: true));
      c = await restart(c, prefs);
      expect(c.read(settingsProvider).onboarded, isTrue);
      final n = c.read(settingsProvider.notifier);
      await n.update((s) => s.copyWith(theme: AppTheme.dark));
      await n.update((s) => s.withManualPrice(1.1));
      await n.update((s) => s.copyWith(cloudSync: true));
      c = await restart(c, prefs);
      expect(c.read(settingsProvider).onboarded, isTrue);
    });

    test('an unfinished setup stays unfinished: values saved, flag still false',
        () async {
      // The user got through the detection (values are saved as they are
      // detected) but quit before "Get started".
      final prefs = await prefsFrom({});
      var c = launch(prefs);
      await c.read(settingsProvider.notifier).update((s) => s.copyWith(
          countryCode: 'PL',
          regionSource: SettingSource.detected,
          currency: 'PLN',
          designCapacityMah: 3988,
          designCapacitySource: DesignCapacitySource.localDeviceDatabase));
      c = await restart(c, prefs);
      final s = c.read(settingsProvider);
      expect(s.onboarded, isFalse);
      expect([s.countryCode, s.currency, s.designCapacityMah],
          ['PL', 'PLN', 3988]);
      expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      // ... so the next launch resumes at the setup, not at the dashboard.
      expect(
          startDestination(
              localOnlyDev: false,
              auth: AsyncData(SignedIn(_session())),
              settings: s),
          StartDestination.setup);
    });

    test('with the flag set a signed-in launch goes straight to the dashboard',
        () async {
      final prefs = await prefsFrom({'wb.onboarded': true});
      final c = launch(prefs);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: AsyncData(SignedIn(_session())),
              settings: c.read(settingsProvider)),
          StartDestination.dashboard);
    });

    test('with the flag set but no account the launch still starts at Welcome',
        () async {
      final prefs = await prefsFrom({'wb.onboarded': true});
      final c = launch(prefs);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: const AsyncData(SignedOut()),
              settings: c.read(settingsProvider)),
          StartDestination.welcome,
          reason: 'the account comes first, whatever the flag says');
    });
  });
}

AuthSession _session() => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      user: const User(id: 'u', email: 'a@b.co'),
    );
