// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import 'support/fake_auth.dart';
import 'support/fake_system.dart';

void main() {
  group('start destination', () {
    const fresh = Settings();
    const done = Settings(onboarded: true);

    test(
        'unauthenticated -> auth required (welcome), whatever the settings say',
        () {
      for (final s in [fresh, done]) {
        expect(
            startDestination(
                localOnlyDev: false,
                auth: const AsyncData(SignedOut()),
                settings: s),
            StartDestination.welcome);
        expect(
            startDestination(
                localOnlyDev: false,
                auth:
                    const AsyncData(AuthFailure(AuthError.invalidCredentials)),
                settings: s),
            StartDestination.welcome);
      }
    });

    test('authenticated + setup incomplete -> device setup', () {
      expect(
          startDestination(
              localOnlyDev: false,
              auth: AsyncData(SignedIn(session('a'))),
              settings: fresh),
          StartDestination.setup);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: AsyncData(SignedIn(session('a'), offline: true)),
              settings: fresh),
          StartDestination.setup,
          reason: 'an offline-restored session still counts as signed in');
    });

    test('authenticated + setup complete -> dashboard', () {
      expect(
          startDestination(
              localOnlyDev: false,
              auth: AsyncData(SignedIn(session('a'))),
              settings: done),
          StartDestination.dashboard);
    });

    test(
        'session being restored -> splash; only LOCAL_ONLY_DEV skips the account',
        () {
      expect(
          startDestination(
              localOnlyDev: false, auth: const AsyncLoading(), settings: done),
          StartDestination.splash);
      expect(
          startDestination(
              localOnlyDev: true,
              auth: const AsyncData(SignedOut()),
              settings: fresh),
          StartDestination.setup);
      expect(
          startDestination(
              localOnlyDev: true,
              auth: const AsyncData(SignedOut()),
              settings: done),
          StartDestination.dashboard);
    });
  });

  group('AutoSetup.apply', () {
    const region = DetectedRegion(
        countryCode: 'PL',
        currencyCode: 'PLN',
        source: RegionDetectionSource.deviceRegion,
        confidence: 0.9);
    final device = DeviceSpecification(
        manufacturer: 'Apple',
        model: 'iPhone 15 Pro',
        modelIdentifier: 'iPhone16,1',
        nominalVoltage: 3.88,
        design: DesignCapacity(
            mah: 3274,
            wh: 12.7,
            source: DesignCapacitySource.localDeviceDatabase));
    final price = AutoPrice(
        pricePerKwh: 1.2724,
        currency: 'PLN',
        countryCode: 'PL',
        period: '2026-S1',
        source: 'eurostat',
        updatedAt: DateTime(2026, 10, 13));

    test('fresh install: everything detected lands in settings', () {
      final s = AutoSetup.apply(const Settings(),
          SetupResult(region: region, device: device, price: price));
      expect(s.countryCode, 'PL');
      expect(s.regionSource, SettingSource.detected);
      expect(s.regionDetection, 'deviceRegion');
      expect(s.currency, 'PLN');
      expect(s.currencySource, SettingSource.detected);
      expect(s.deviceModel, 'iPhone 15 Pro');
      expect(s.designCapacityMah, 3274);
      expect(s.designCapacityWh, 12.7);
      expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(s.nominalVoltage, 3.88);
      expect(s.pricePerKwh, 1.2724);
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.priceIsAverage, isTrue);
    });

    test('manual values from an existing install are never overwritten', () {
      const existing = Settings(
        currency: 'EUR',
        currencySource: SettingSource.manual,
        countryCode: 'DE',
        regionSource: SettingSource.manual,
        pricePerKwh: 0.3,
        manualPricePerKwh: 0.3,
        priceMode: ElectricityPriceMode.manual,
        designCapacityMah: 5000,
        designCapacitySource: DesignCapacitySource.manual,
      );
      final s = AutoSetup.apply(
          existing, SetupResult(region: region, device: device, price: price));
      expect(s.currency, 'EUR');
      expect(s.countryCode, 'DE');
      expect(s.pricePerKwh, 0.3);
      expect(s.designCapacityMah, 5000);
      expect(s.designCapacitySource, DesignCapacitySource.manual);
      expect(s.deviceModel, 'iPhone 15 Pro',
          reason: 'the model name is still recorded');
      expect(s.autoPrice!.pricePerKwh, 1.2724,
          reason: 'kept for "use automatic"');
    });

    test('unknown device and unavailable price stay unknown (no fake values)',
        () {
      final s = AutoSetup.apply(
          const Settings(),
          const SetupResult(
              region: region,
              device: DeviceSpecification(
                  manufacturer: 'Apple',
                  model: 'iPhone',
                  modelIdentifier: 'iPhone19,2'),
              priceUnavailable: true));
      expect(s.designCapacityMah, 0);
      expect(s.designCapacityWh, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.hasPrice, isFalse);
      expect(s.currency, 'PLN');
    });

    test('settings stored on the account (another phone) rank above detection',
        () {
      final acc = api.UserSettingsDto(
        countryCode: 'DE',
        countryCodeSource: api.UserSettingsDtoCountryCodeSourceEnum.detected,
        currencyCode: 'EUR',
        currencyCodeSource: api.UserSettingsDtoCurrencyCodeSourceEnum.manual,
        electricityPriceMode:
            api.UserSettingsDtoElectricityPriceModeEnum.manual,
        manualElectricityPrice: 0.4,
        electricityPriceSource:
            api.UserSettingsDtoElectricityPriceSourceEnum.manual,
        updatedAt: DateTime(2026, 10, 1),
      );
      final s = AutoSetup.apply(
          const Settings(),
          SetupResult(
              region: region,
              device: device,
              price: price,
              accountSettings: acc));
      expect(s.countryCode, 'DE');
      expect(s.currency, 'EUR');
      // It came from the account: not a choice made on this phone.
      expect(s.currencySource, SettingSource.accountSynced);
      expect(s.currencyOriginalSource, SettingSource.manual);
      expect(s.regionSource, SettingSource.accountSynced);
      expect(s.regionOriginalSource, SettingSource.detected);
      expect(s.priceSource, SettingSource.accountSynced);
      expect(s.priceOriginalSource, SettingSource.manual);
      expect(s.priceMode, ElectricityPriceMode.manual);
      expect(s.pricePerKwh, 0.4);
    });
  });

  group('design capacity in the automatic setup', () {
    // The setup writes the model's DESIGN capacity into the settings. The
    // collector's ESTIMATED full-charge capacity travels in SetupResult.fullCharge
    // and is never written into the design-capacity fields.
    final local = DeviceSpecification(
        manufacturer: 'Google',
        model: 'Pixel 8',
        modelIdentifier: 'Pixel 8',
        design: DesignCapacity(
            mah: 4575, source: DesignCapacitySource.localDeviceDatabase));
    final backend = DeviceSpecification(
        manufacturer: 'Apple',
        model: 'iPhone 18 Pro',
        modelIdentifier: 'iPhone19,2',
        design: DesignCapacity(
            mah: 4100,
            wh: 15.8,
            source: DesignCapacitySource.backendDeviceDatabase));
    const unknown = DeviceSpecification(
        manufacturer: 'Apple', model: 'iPhone', modelIdentifier: 'iPhone19,3');
    final estimate =
        FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100);

    Settings known(DeviceSpecification d) =>
        const Settings().withDesignCapacity(d.design).copyWith(
            deviceModel: d.model, deviceModelIdentifier: d.modelIdentifier);

    final manual = const Settings().withDesignCapacity(DesignCapacity(
        mah: 4000, wh: 15.4, source: DesignCapacitySource.manual));

    test('a catalog capacity from the local database', () {
      final s = AutoSetup.apply(const Settings(), SetupResult(device: local));
      expect(s.designCapacityMah, 4575);
      expect(s.designCapacityWh, 0, reason: 'the catalog gives no Wh: unknown');
      expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(s.designCapacity, local.design);
    });

    test('a capacity from the backend database keeps that source and its Wh',
        () {
      final s = AutoSetup.apply(const Settings(), SetupResult(device: backend));
      expect(s.designCapacityMah, 4100);
      expect(s.designCapacityWh, 15.8);
      expect(
          s.designCapacitySource, DesignCapacitySource.backendDeviceDatabase);
      expect(s.deviceModel, 'iPhone 18 Pro');
      expect(s.deviceModelIdentifier, 'iPhone19,2');
      expect(s.nominalVoltage, const Settings().nominalVoltage,
          reason: 'the backend sent no voltage: the default stays');
    });

    test('an unknown model leaves the capacity unknown, never a typical value',
        () {
      final s =
          AutoSetup.apply(const Settings(), const SetupResult(device: unknown));
      expect(s.designCapacityMah, 0);
      expect(s.designCapacityWh, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.designCapacity.isKnown, isFalse);
      expect(s.deviceModelIdentifier, 'iPhone19,3',
          reason: 'the model is still recorded');
    });

    test(
        'a manual design capacity survives automatic detection, whatever it '
        'finds ("Detect again" is the editor path and is not covered here)',
        () {
      for (final d in [local, backend, unknown, null]) {
        final s = AutoSetup.apply(
            manual, SetupResult(device: d, fullCharge: estimate));
        expect(s.designCapacityMah, 4000, reason: '$d');
        expect(s.designCapacityWh, 15.4, reason: '$d');
        expect(s.designCapacitySource, DesignCapacitySource.manual,
            reason: '$d');
      }
    });

    test(
        'a known non-manual capacity is kept when a later detection fails or '
        'finds nothing', () {
      for (final start in [known(local), known(backend)]) {
        for (final result in [
          const SetupResult(device: unknown),
          const SetupResult(),
          SetupResult(device: unknown, fullCharge: estimate),
        ]) {
          final s = AutoSetup.apply(start, result);
          expect(s.designCapacity, start.designCapacity,
              reason: start.designCapacitySource.name);
          expect(s.designCapacityMah, isNot(0));
        }
      }
    });

    test(
        'a later detection that does find a capacity replaces a non-manual one',
        () {
      // Catalog corrections and newer backend entries reach the phone.
      final s = AutoSetup.apply(known(local), SetupResult(device: backend));
      expect(s.designCapacityMah, 4100);
      expect(
          s.designCapacitySource, DesignCapacitySource.backendDeviceDatabase);
      final again = AutoSetup.apply(s, SetupResult(device: local));
      expect(again.designCapacityMah, 4575);
      expect(again.designCapacityWh, 0,
          reason: 'the Wh of the replaced entry does not linger');
      expect(
          again.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    });

    test(
        'the estimate in SetupResult.fullCharge never changes the design '
        'capacity', () {
      final estimates = {
        '3600 mAh at 100 %': FullChargeCapacityEstimator.estimate(
            chargeUah: 3600000, level: 100),
        '3420 mAh at 95 %':
            FullChargeCapacityEstimator.estimate(chargeUah: 3249000, level: 95),
        '1800 mAh at 50 % (low confidence)':
            FullChargeCapacityEstimator.estimate(chargeUah: 900000, level: 50),
        'unsupported counter': FullChargeCapacityEstimator.estimate(level: 100),
        'negative counter': FullChargeCapacityEstimator.estimate(
            chargeUah: -3600000, level: 100),
        'level 0':
            FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 0),
        'NaN counter': FullChargeCapacityEstimator.estimate(
            chargeUah: double.nan, level: 100),
        'infinite counter': FullChargeCapacityEstimator.estimate(
            chargeUah: double.infinity, level: 100),
        'NaN level': FullChargeCapacityEstimator.estimate(
            chargeUah: 3600000, level: double.nan),
        'nothing': EstimatedFullChargeCapacity.unavailable,
      };
      final starts = {
        'fresh install': const Settings(),
        'known (local)': known(local),
        'manual': manual,
      };
      for (final entry in estimates.entries) {
        for (final device in [unknown, local, backend, null]) {
          for (final start in starts.entries) {
            final without =
                AutoSetup.apply(start.value, SetupResult(device: device));
            final withEstimate = AutoSetup.apply(start.value,
                SetupResult(device: device, fullCharge: entry.value));
            final why = '${entry.key}, ${start.key}, $device';
            expect(withEstimate.designCapacity, without.designCapacity,
                reason: why);
            expect(withEstimate.designCapacityMah, without.designCapacityMah,
                reason: why);
            expect(withEstimate.designCapacityWh, without.designCapacityWh,
                reason: why);
            expect(
                withEstimate.designCapacitySource, without.designCapacitySource,
                reason: why);
          }
        }
      }
    });

    test(
        'a reading of 3600 mAh next to an unknown model is not a capacity '
        'anywhere in the resulting settings', () {
      final s = AutoSetup.apply(
          const Settings(), SetupResult(device: unknown, fullCharge: estimate));
      expect(s.designCapacityMah, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.energyCalc().canEstimateFromPercent, isFalse,
          reason: 'with no estimate handed to the calculator it has no basis');
    });

    test('a result without an estimate says so', () {
      expect(const SetupResult().fullCharge,
          EstimatedFullChargeCapacity.unavailable);
      expect(const SetupResult().fullCharge.isAvailable, isFalse);
    });
  });

  group('SetupController.run registers the model and the estimate separately',
      () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final catalogJson =
        File('assets/device_specs/devices.json').readAsStringSync();

    final estimate =
        FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100);

    AutoSetup setupFor(
      String modelIdentifier, {
      Future<EstimatedFullChargeCapacity> Function()? fullCharge,
      Future<void> Function(DeviceSpecification, EstimatedFullChargeCapacity)?
          registerDevice,
    }) {
      final system = fakeSystem(deviceInfo: {
        'manufacturer': 'Google',
        'model': modelIdentifier,
        'modelIdentifier': modelIdentifier,
        'regionCode': 'PL',
        'localeTag': 'en-PL',
      });
      return AutoSetup(
        region:
            RegionDetectionService(system: system, localeTag: () => 'en_PL'),
        device: DeviceSpecificationService(
            system: system, loadCatalog: () async => catalogJson),
        fullCharge: fullCharge,
        registerDevice: registerDevice,
      );
    }

    Future<({Settings saved, SetupState state})> run(AutoSetup setup,
        {Settings current = const Settings()}) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      late Settings saved;
      await container
          .read(setupControllerProvider.notifier)
          .run(setup: setup, current: current, save: (s) async => saved = s);
      return (saved: saved, state: container.read(setupControllerProvider));
    }

    test(
        'an unknown Android model: the registration gets an UNKNOWN design '
        'capacity and the estimate beside it', () async {
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      final r = await run(setupFor('Pixel 99',
          fullCharge: () async => estimate,
          registerDevice: (spec, fc) async => calls.add((spec, fc))));
      expect(calls, hasLength(1));
      final (spec, fullCharge) = calls.single;
      expect(spec.modelIdentifier, 'Pixel 99');
      expect(spec.design, DesignCapacity.unknown);
      expect(spec.designCapacityMah, isNull);
      expect(fullCharge, estimate);
      expect(r.saved.designCapacityMah, 0);
      expect(r.saved.designCapacitySource, DesignCapacitySource.unknown);
      expect(r.state.phase, SetupPhase.review);
      expect(r.state.result!.fullCharge, estimate);
      expect(r.state.result!.device!.design, DesignCapacity.unknown);
    });

    test('a catalog model: the catalog capacity and the estimate differ',
        () async {
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      final r = await run(setupFor('Pixel 8',
          fullCharge: () async => estimate,
          registerDevice: (spec, fc) async => calls.add((spec, fc))));
      final (spec, fullCharge) = calls.single;
      expect(spec.designCapacityMah, 4575);
      expect(
          spec.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(fullCharge.mah, 3600);
      expect(r.saved.designCapacityMah, 4575);
      expect(r.saved.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
    });

    test('with no estimate hook the registration gets "unavailable"', () async {
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      await run(setupFor('Pixel 8',
          registerDevice: (spec, fc) async => calls.add((spec, fc))));
      expect(calls.single.$2, EstimatedFullChargeCapacity.unavailable);
    });

    test('a failing registration is not a failed setup', () async {
      final r = await run(setupFor('Pixel 8',
          registerDevice: (spec, fc) async => throw StateError('offline')));
      expect(r.state.phase, SetupPhase.review);
      expect(r.saved.designCapacityMah, 4575);
    });

    test('a failing estimate hook is not a failed setup either', () async {
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      final r = await run(setupFor('Pixel 8',
          fullCharge: () async => throw StateError('database closed'),
          registerDevice: (spec, fc) async => calls.add((spec, fc))));
      expect(r.state.phase, SetupPhase.review);
      expect(calls.single.$2, EstimatedFullChargeCapacity.unavailable);
      expect(r.saved.designCapacityMah, 4575);
    });

    test('a manual design capacity is saved unchanged by the whole run',
        () async {
      final manual = const Settings().withDesignCapacity(
          DesignCapacity(mah: 4000, source: DesignCapacitySource.manual));
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      final r = await run(
          setupFor('Pixel 8',
              fullCharge: () async => estimate,
              registerDevice: (spec, fc) async => calls.add((spec, fc))),
          current: manual);
      expect(r.saved.designCapacityMah, 4000);
      expect(r.saved.designCapacitySource, DesignCapacitySource.manual);
      expect(calls, hasLength(1));
      expect(calls.single.$1.designCapacityMah, 4000,
          reason:
              'the server record agrees with the app, not with the catalog');
      expect(calls.single.$1.designCapacitySource, DesignCapacitySource.manual);
    });

    test(
        'a manual capacity on a model no catalog knows is registered as '
        'manual, never as unknown (which would erase it on the server)',
        () async {
      final manual = const Settings().withDesignCapacity(
          DesignCapacity(mah: 5000, source: DesignCapacitySource.manual));
      final calls = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
      final r = await run(
          setupFor('Pixel 99',
              fullCharge: () async => estimate,
              registerDevice: (spec, fc) async => calls.add((spec, fc))),
          current: manual);
      expect(r.saved.designCapacityMah, 5000);
      expect(calls.single.$1.designCapacityMah, 5000);
      expect(calls.single.$1.designCapacitySource, DesignCapacitySource.manual);
      expect(calls.single.$2.mah, 3600, reason: 'the estimate stays separate');
    });
  });

  group('legacy preferences migration', () {
    test('values typed in the old onboarding become migratedManual and survive',
        () async {
      SharedPreferences.setMockInitialValues({
        'wb.currency': 'PLN',
        'wb.pricePerKwh': 1.15,
        'wb.batteryCapacityMah': 4000.0,
        'wb.onboarded': true,
      });
      final store = SettingsStore(await SharedPreferences.getInstance());
      final s = store.load();
      expect(s.currencySource, SettingSource.migratedManual);
      expect(s.priceSource, SettingSource.migratedManual);
      expect(s.priceMode, ElectricityPriceMode.manual);
      expect(s.manualPricePerKwh, 1.15);
      expect(s.pricePerKwh, 1.15);
      expect(s.designCapacitySource, DesignCapacitySource.manual,
          reason: 'a capacity typed before sources existed was the user\'s');
      expect(s.designCapacityMah, 4000);
      expect(s.onboarded, isTrue);
      // Detection afterwards changes nothing the user chose.
      final after = AutoSetup.apply(
          s,
          const SetupResult(
              region: DetectedRegion(
                  countryCode: 'DE',
                  currencyCode: 'EUR',
                  source: RegionDetectionSource.deviceLocale,
                  confidence: 0.7)));
      expect(after.currency, 'PLN');
      expect(after.pricePerKwh, 1.15);
      expect(after.countryCode, 'DE',
          reason: 'the region itself was never set');
    });

    test('a fresh install has nothing manual', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsStore(await SharedPreferences.getInstance()).load();
      expect(s.currencySource, SettingSource.detected);
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.designCapacityMah, 0);
      expect(s.currency, '');
      expect(s.onboarded, isFalse);
    });
  });
}
