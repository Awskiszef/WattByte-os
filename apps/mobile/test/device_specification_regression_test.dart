import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import 'support/fake_system.dart';

/// One charge-counter reading as the collector would see it.
typedef _Reading = ({
  String label,
  num? chargeUah,
  num? energyNwh,
  num level,
  bool estimates,
});

/// One kind of phone the setup meets, with what its settings must end up as.
typedef _Device = ({
  String label,
  String model,
  Settings current,
  DesignCapacity expected,
});

/// Regression net for the bug this model split exists to prevent: Android
/// `BATTERY_PROPERTY_CHARGE_COUNTER` (the charge currently STORED in the battery)
/// was kept as if it were the nominal battery capacity.
///
/// The reading, however reliable, may only ever become an
/// [EstimatedFullChargeCapacity] (`charge / (level / 100)`, labelled "Estimated").
/// It must never end up in a design capacity, in any field or source, in
/// detection, in settings, in persistence or in the registration payload
/// (docs/BATTERY_CAPACITY.md). Every layer of the app that sits between the
/// collector and the disk is exercised here with the same table of readings.
///
/// The layers that sit behind this file are covered where they live:
/// `battery_capacity_test.dart` (the estimator), `sync_service_test.dart` (the
/// request itself), the collector and exporter tests, and
/// `onboarding_persistence_test.dart` (the same thing through the whole app).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalogJson =
      File('assets/device_specs/devices.json').readAsStringSync();

  /// Charge-counter readings as the collector would see them, and whether they
  /// make an estimate at all. Whatever the answer, none may become a design
  /// capacity.
  final readings = <_Reading>[
    (
      label: '3600 mAh at 100 %',
      chargeUah: 3600000,
      energyNwh: 13.9e9,
      level: 100,
      estimates: true,
    ),
    (
      label: '3420 mAh stored at 95 %',
      chargeUah: 3420000,
      energyNwh: null,
      level: 95,
      estimates: true,
    ),
    (
      label: '1800 mAh stored at 50 %',
      chargeUah: 1800000,
      energyNwh: null,
      level: 50,
      estimates: true,
    ),
    (
      label: '1440 mAh stored at 40 % (the lowest level that estimates)',
      chargeUah: 1440000,
      energyNwh: null,
      level: 40,
      estimates: true,
    ),
    (
      label: '1404 mAh stored at 39 % (too far to extrapolate)',
      chargeUah: 1404000,
      energyNwh: null,
      level: 39,
      estimates: false,
    ),
    (
      label: 'unsupported charge counter',
      chargeUah: null,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'zero charge counter',
      chargeUah: 0,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'negative charge counter',
      chargeUah: -3600000,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'battery level 0',
      chargeUah: 3600000,
      energyNwh: null,
      level: 0,
      estimates: false,
    ),
    (
      label: 'battery level unknown (-1)',
      chargeUah: 3600000,
      energyNwh: null,
      level: -1,
      estimates: false,
    ),
    (
      label: 'battery level above 100',
      chargeUah: 3600000,
      energyNwh: null,
      level: 101,
      estimates: false,
    ),
    (
      label: 'NaN charge counter',
      chargeUah: double.nan,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'infinite charge counter',
      chargeUah: double.infinity,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'negative infinite charge counter',
      chargeUah: double.negativeInfinity,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'NaN battery level',
      chargeUah: 3600000,
      energyNwh: null,
      level: double.nan,
      estimates: false,
    ),
    (
      label: 'infinite battery level',
      chargeUah: 3600000,
      energyNwh: null,
      level: double.infinity,
      estimates: false,
    ),
    (
      label: 'a counter that reports mAh instead of microampere-hours',
      chargeUah: 3600,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
    (
      label: 'an absurd counter',
      chargeUah: 9e12,
      energyNwh: null,
      level: 100,
      estimates: false,
    ),
  ];

  EstimatedFullChargeCapacity estimateOf(_Reading r) =>
      FullChargeCapacityEstimator.estimate(
          chargeUah: r.chargeUah, energyNwh: r.energyNwh, level: r.level);

  /// The three kinds of phone the setup meets.
  final devices = <_Device>[
    (
      label: 'a model no catalog knows',
      model: 'Pixel 99',
      current: const Settings(),
      expected: DesignCapacity.unknown,
    ),
    (
      label: 'a model in the local catalog',
      model: 'Pixel 8',
      current: const Settings(),
      expected: DesignCapacity(
          mah: 4575, source: DesignCapacitySource.localDeviceDatabase),
    ),
    (
      label: 'a model no catalog knows, the user typed a capacity',
      model: 'Pixel 99',
      current: const Settings().withDesignCapacity(
          DesignCapacity(mah: 4000, source: DesignCapacitySource.manual)),
      expected: DesignCapacity(mah: 4000, source: DesignCapacitySource.manual),
    ),
    (
      label: 'a catalog model, the user typed another capacity',
      model: 'Pixel 8',
      current: const Settings().withDesignCapacity(
          DesignCapacity(mah: 4000, source: DesignCapacitySource.manual)),
      expected: DesignCapacity(mah: 4000, source: DesignCapacitySource.manual),
    ),
  ];

  AutoSetup setupFor(
      String model,
      EstimatedFullChargeCapacity estimate,
      Future<void> Function(DeviceSpecification, EstimatedFullChargeCapacity)?
          registerDevice) {
    final system = fakeSystem(deviceInfo: {
      'manufacturer': 'Google',
      'model': model,
      'modelIdentifier': model,
      'regionCode': 'PL',
      'localeTag': 'en-PL',
    });
    return AutoSetup(
      region: RegionDetectionService(system: system, localeTag: () => 'en_PL'),
      device: DeviceSpecificationService(
          system: system, loadCatalog: () async => catalogJson),
      fullCharge: () async => estimate,
      registerDevice: registerDevice,
    );
  }

  Future<SharedPreferences> freshPrefs([Map<String, Object>? values]) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(values ?? {});
    return SharedPreferences.getInstance();
  }

  group('Android charge counter != design capacity', () {
    test('the design source enum has no member for a measurement', () {
      expect(DesignCapacitySource.values.map((s) => s.name).toSet(), {
        'manufacturerSpecification',
        'localDeviceDatabase',
        'backendDeviceDatabase',
        'manual',
        'unknown',
      });
      // And the estimate's own source is a different type with no overlap.
      expect(FullChargeCapacitySource.values.map((s) => s.name).toSet(),
          {'androidChargeCounter', 'unknown'});
    });

    test('the table says what it claims about each reading', () {
      for (final r in readings) {
        final e = estimateOf(r);
        expect(e.isAvailable, r.estimates, reason: r.label);
        if (r.estimates) {
          expect(e.mah, closeTo(3600, 1e-6), reason: r.label);
          expect(e.source, FullChargeCapacitySource.androidChargeCounter,
              reason: r.label);
        } else {
          expect(e, EstimatedFullChargeCapacity.unavailable, reason: r.label);
        }
      }
    });

    for (final device in devices) {
      group(device.label, () {
        for (final reading in readings) {
          test('${reading.label}: the design capacity is what it was',
              () async {
            final estimate = estimateOf(reading);
            final registered =
                <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
            final container = ProviderContainer();
            addTearDown(container.dispose);
            late Settings saved;

            // --- detection and setup ------------------------------------
            await container.read(setupControllerProvider.notifier).run(
                  setup: setupFor(device.model, estimate,
                      (spec, fc) async => registered.add((spec, fc))),
                  current: device.current,
                  save: (s) async => saved = s,
                );
            final result = container.read(setupControllerProvider).result!;

            // Detection: the model's design capacity, the reading nowhere.
            final detected = result.device!.design;
            final catalogDesign = device.model == 'Pixel 8'
                ? DesignCapacity(
                    mah: 4575, source: DesignCapacitySource.localDeviceDatabase)
                : DesignCapacity.unknown;
            expect(detected, catalogDesign);
            expect(result.fullCharge, estimate,
                reason: 'the reading is reported as an estimate, beside it');

            // Settings: the capacity the user had or the catalog's.
            expect(saved.designCapacity, device.expected);
            expect(saved.designCapacitySource, device.expected.source);
            expect(saved.designCapacityMah, device.expected.mah ?? 0);
            expect(saved.designCapacityWh, 0);

            // Registration payload: the design group is the one the app keeps
            // (the user's own figure survives detection), the estimate is its
            // own value.
            expect(registered, hasLength(1));
            expect(registered.single.$1.design, device.expected);
            expect(registered.single.$2, estimate);
            if (estimate.isAvailable) {
              expect(
                  registered.single.$1.designCapacityMah, isNot(estimate.mah));
            }

            // Persistence: nothing on disk is the reading, and the capacity
            // comes back as it was saved.
            final prefs = await freshPrefs();
            await SettingsStore(prefs).save(saved);
            final onDisk = {
              for (final k in prefs.getKeys()) k: prefs.get(k)!,
            };
            if (estimate.isAvailable && estimate.mah != device.expected.mah) {
              for (final entry in onDisk.entries) {
                expect(entry.value, isNot(estimate.mah),
                    reason: 'the estimate leaked into ${entry.key}');
                if (estimate.wh != null) {
                  expect(entry.value, isNot(estimate.wh),
                      reason: 'the estimated Wh leaked into ${entry.key}');
                }
              }
            }
            final reopened = SettingsStore(await freshPrefs(onDisk)).load();
            expect(reopened.designCapacity, device.expected);
            expect(reopened.designCapacitySource, device.expected.source);
          });
        }
      });
    }

    test(
        'a legacy install whose "capacity" was the charge counter ends up '
        'with an unknown design capacity everywhere', () async {
      // `wb.capacitySource: system` = the charge counter at a full charge. It
      // is not a design capacity; the estimate lives in the collector.
      for (final source in ['system', 'estimated']) {
        final prefs = await freshPrefs({
          'wb.batteryCapacityMah': 3600.0,
          'wb.capacitySource': source,
          'wb.onboarded': true,
        });
        final loaded = SettingsStore(prefs).load();
        expect(loaded.designCapacity, DesignCapacity.unknown, reason: source);

        // A later detection of an unknown model does not resurrect it.
        final estimate = FullChargeCapacityEstimator.estimate(
            chargeUah: 3600000, level: 100);
        final detection =
            await setupFor('Pixel 99', estimate, null).detect(loaded);
        final applied = AutoSetup.apply(loaded, detection);
        expect(applied.designCapacity, DesignCapacity.unknown, reason: source);

        await SettingsStore(prefs).save(applied);
        for (final key in prefs.getKeys()) {
          expect(prefs.get(key), isNot(3600.0), reason: '$source: $key');
        }
        expect(prefs.getString('wb.designCapacitySource'), 'unknown');
        expect(prefs.getDouble('wb.designCapacityMah'), 0);
        expect(prefs.containsKey('wb.batteryCapacityMah'), isFalse);
      }
    });

    test(
        'the calculator uses the estimate only as a fallback basis, and never '
        'writes it back as a capacity', () {
      final estimate =
          FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100);
      const unknown = Settings();
      final calc =
          unknown.energyCalc(estimatedFullChargeCapacityMah: estimate.mah!);
      expect(calc.batteryCapacityMah, 3600, reason: 'the % -> mAh fallback');
      expect(unknown.designCapacityMah, 0,
          reason: 'building a calculator changes no setting');
      expect(unknown.designCapacity, DesignCapacity.unknown);
    });
  });
}
