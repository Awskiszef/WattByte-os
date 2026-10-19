// Regression: the Android charge counter is NOT the design capacity.
//
// The bug these tests keep dead: `BATTERY_PROPERTY_CHARGE_COUNTER` (the charge
// currently stored in the battery, in microampere-hours) was stored as if it
// were the nominal battery capacity of the phone model. The data model now
// keeps two different facts apart (docs/BATTERY_CAPACITY.md):
//
//   * design capacity: the nominal capacity of the phone MODEL, from the local
//     catalog, the backend catalog, the user, or unknown;
//   * estimated full-charge capacity: an ESTIMATE for this particular battery,
//     the charge counter extrapolated from the battery level, with a confidence.
//
// Everything here runs the real pipeline, not one function in isolation: a
// scripted native side (FakeSystem) -> the real Collector and a real in-memory
// database -> the real AutoSetup / SetupController -> Settings -> the real
// SettingsStore (SharedPreferences) -> the energy calculation, and, in the
// widget group, the real app with its real SyncService against a fake server
// that applies the API's rules (FakeDeviceTable).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/background/refresh_service.dart' show energyCalcFor;
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/core/units.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/ui/onboarding/setup_screen.dart';
import 'package:wattbyte/ui/settings/settings_screen.dart';
import 'package:wattbyte/ui/settings/setup_editors.dart' show capacityText;
import 'package:wattbyte_system/wattbyte_system.dart' show WattByteSystem;

import 'accessibility/flow_matrix_support.dart'
    show resetAssetCache, semanticsNode;
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

final _en = AppLocalizationsEn();

/// The date of every collection pass in the pure tests.
final _now = DateTime(2026, 10, 14, 12);

/// The real bundled catalog, so these tests fail if the asset breaks.
final _catalog = File('assets/device_specs/devices.json').readAsStringSync();

/// Pixel 8 in the bundled catalog.
const _pixel8Design = 4575.0;

/// A battery that holds 3600 mAh when full: the number the charge counter
/// extrapolates to in these tests (never equal to a catalog figure on purpose).
const _full = 3600.0;

// ---------------------------------------------------------------- the phones

/// An Android phone with a working charge counter. [stored] is what the
/// counter reads: the charge currently IN the battery at [level] percent.
FakeSystem _android({
  String id = 'Pixel 8',
  String model = 'Pixel 8',
  int level = 100,
  double? stored = _full,
  int? energyNwh,
}) {
  final fake = FakeSystem(
    platform: HarnessPlatform.android,
    batteryLevel: level,
    chargeCounterMah: stored,
    deviceInfo: {
      ...FakeSystem.defaultDeviceInfo(HarnessPlatform.android),
      'modelIdentifier': id,
      'model': model,
    },
  );
  fake.energyCounterNwh = energyNwh;
  return fake;
}

/// A model that is in no catalog.
FakeSystem _unlisted({int level = 100, double? stored = _full}) => _android(
    id: 'Unlisted-1', model: 'Unlisted 1', level: level, stored: stored);

/// An iPhone: no charge counter exists on iOS.
FakeSystem _iphone({String id = 'iPhone99,9'}) => FakeSystem(
      platform: HarnessPlatform.ios,
      deviceInfo: {
        ...FakeSystem.defaultDeviceInfo(HarnessPlatform.ios),
        'modelIdentifier': id,
      },
    );

// ------------------------------------------------------------ the pipeline

class _Cache {
  String? json;
}

/// Everything one first-run setup leaves behind.
class _Run {
  _Run({
    required this.fake,
    required this.db,
    required this.collector,
    required this.result,
    required this.settings,
    required this.prefs,
    required this.registered,
    required this.cache,
  });

  final FakeSystem fake;
  final WattByteDb db;
  final Collector collector;

  /// What `AutoSetup.detect` found (the review screen's data).
  final SetupResult result;

  /// What the setup controller saved: `AutoSetup.apply(start, result)`.
  final Settings settings;

  /// The preferences after `SettingsStore.save(settings)`.
  final SharedPreferences prefs;

  /// What the setup handed to `registerDevice` (the device registration).
  final List<(DeviceSpecification, EstimatedFullChargeCapacity)> registered;

  /// The backend specification cache the detection wrote.
  final _Cache cache;

  DeviceSpecification get spec => result.device!;
  EstimatedFullChargeCapacity get estimate => result.fullCharge;

  /// The settings as the next app launch reads them.
  Settings get reloaded => SettingsStore(prefs).load();

  /// `calculateEstimatedBatteryHealth` on what the app knows.
  EstimatedBatteryHealth? get health =>
      calculateEstimatedBatteryHealth(settings.designCapacity, estimate);

  /// Every preference whose key mentions "capacity" (the design capacity keys).
  Map<String, Object?> get capacityPrefs => {
        for (final k in prefs.getKeys())
          if (k.toLowerCase().contains('capacity')) k: prefs.get(k),
      };
}

/// One real first run: collect, detect, apply, persist, register.
///
/// [start] is the settings the run starts from (a manual design capacity, an
/// old install), [backendLookup] the API's specification endpoint (null = no
/// API), [cachedSpec] what an earlier launch cached.
Future<_Run> _run(
  FakeSystem fake, {
  Settings start = const Settings(),
  Future<DeviceSpecification?> Function(String identifier)? backendLookup,
  String? cachedSpec,
  bool collect = true,
}) async {
  addTearDown(fake.dispose);
  final db = await WattByteDb.openInMemory();
  addTearDown(db.close);
  final collector = Collector(system: fake.system, db: db);
  if (collect) await collector.collect(now: _now);

  final cache = _Cache()..json = cachedSpec;
  final registered = <(DeviceSpecification, EstimatedFullChargeCapacity)>[];
  final setup = AutoSetup(
    region:
        RegionDetectionService(system: fake.system, localeTag: () => 'en_PL'),
    device: DeviceSpecificationService(
      system: fake.system,
      loadCatalog: () async => _catalog,
      backendLookup: backendLookup,
      readCache: () => cache.json,
      writeCache: (json) async => cache.json = json,
    ),
    fullCharge: collector.fullChargeCapacity,
    registerDevice: (spec, fullCharge) async =>
        registered.add((spec, fullCharge)),
  );

  final container = ProviderContainer();
  addTearDown(container.dispose);
  Settings? saved;
  await container.read(setupControllerProvider.notifier).run(
        setup: setup,
        current: start,
        save: (s) async => saved = s,
      );
  await pumpEventQueue(); // the registration is fire-and-forget

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await SettingsStore(prefs).save(saved!);
  return _Run(
    fake: fake,
    db: db,
    collector: collector,
    result: container.read(setupControllerProvider).result!,
    settings: saved!,
    prefs: prefs,
    registered: registered,
    cache: cache,
  );
}

/// The one rule of this file, spelled out: whatever the charge counter read,
/// the design capacity is exactly what the catalog / the user / nobody said.
///
/// [mah] / [source] is what Settings holds (after apply and after a restart)
/// and what the registration carries; [detected] is what the detection found
/// when that differs (a manual value the detection did not replace).
void _expectDesign(
  _Run r,
  double? mah,
  DesignCapacitySource source, {
  (double?, DesignCapacitySource)? detected,
  String? reason,
}) {
  final (detectedMah, detectedSource) = detected ?? (mah, source);
  // Detection (what the review shows) and what the registration is given.
  expect(r.spec.design.source, detectedSource, reason: reason);
  expect(r.spec.design.mah, detectedMah, reason: reason);
  expect(r.spec.designCapacitySource, detectedSource);
  // The registration carries the design capacity the app KEEPS (a manual value
  // the detection did not replace), so the server never disagrees with the app.
  for (final (spec, _) in r.registered) {
    expect(spec.design.mah, mah, reason: reason);
    expect(spec.design.source, source, reason: reason);
  }
  // Settings after apply and after a restart.
  for (final s in [r.settings, r.reloaded]) {
    expect(s.designCapacityMah, mah ?? 0, reason: reason);
    expect(s.designCapacitySource, source, reason: reason);
    expect(s.designCapacity.mah, mah, reason: reason);
    expect(s.designCapacity.isKnown, mah != null, reason: reason);
  }
  // Persistence: the design keys are the new ones, and an unknown design
  // carries no numbers at all.
  expect(r.prefs.getKeys(),
      containsAll(['wb.designCapacityMah', 'wb.designCapacitySource']));
  expect(
      r.prefs.getKeys(),
      isNot(anyOf(contains('wb.batteryCapacityMah'),
          contains('wb.batteryCapacityWh'), contains('wb.capacitySource'))),
      reason: 'the ambiguous pre-split keys are gone');
  expect(r.prefs.getDouble('wb.designCapacityMah'), mah ?? 0, reason: reason);
  expect(r.prefs.getString('wb.designCapacitySource'), source.name,
      reason: reason);
}

/// The estimate the run found, spelled out.
void _expectEstimate(
  _Run r,
  double mah,
  FullChargeCapacityConfidence confidence,
) {
  expect(r.estimate.isAvailable, isTrue);
  expect(r.estimate.mah, closeTo(mah, 0.01));
  expect(r.estimate.confidence, confidence);
  expect(r.estimate.source, FullChargeCapacitySource.androidChargeCounter);
  expect(r.registered.single.$2, r.estimate,
      reason: 'the registration carries the same estimate');
}

/// No number the charge counter produced (or any estimate) sits in a design
/// capacity preference, a specification cache or a registration's design.
void _expectNoEstimateInDesignStorage(_Run r, Iterable<double> estimates) {
  for (final k in r.capacityPrefs.keys) {
    final v = r.prefs.get(k);
    for (final e in estimates) {
      expect(v, isNot(closeTo(e, 0.5)),
          reason: '$k holds $v, which is the estimate $e');
    }
  }
  for (final (spec, _) in r.registered) {
    for (final e in estimates) {
      expect(spec.design.mah, isNot(closeTo(e, 0.5)));
      expect(spec.design.wh, isNot(closeTo(e, 0.5)));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUp(resetAssetCache);

  // ===========================================================================
  group('Android charge counter != design capacity', () {
    test(
        'unknown model, counter 3600 mAh at 100 %: the design capacity is 0 / '
        'unknown, the estimate is 3600 mAh with high confidence', () async {
      final r = await _run(_unlisted());

      _expectDesign(r, null, DesignCapacitySource.unknown,
          reason: 'the charge counter is not a design capacity');
      expect(r.spec.hasDesignCapacity, isFalse);
      expect(r.settings.designCapacity, DesignCapacity.unknown);
      expect(r.settings.designCapacityWh, 0);
      expect(r.spec.modelIdentifier, 'Unlisted-1');

      _expectEstimate(r, 3600, FullChargeCapacityConfidence.high);
      expect(r.estimate.level, 100);
      expect(r.health, isNull, reason: 'no design capacity, no health');

      _expectNoEstimateInDesignStorage(r, [3600, 3.6, 3600000]);
      expect(r.capacityPrefs, {
        'wb.designCapacityMah': 0.0,
        'wb.designCapacityWh': 0.0,
        'wb.designCapacitySource': 'unknown',
      });
      expect(r.prefs.getKeys().map(r.prefs.get), isNot(contains(3600.0)),
          reason: 'no preference of any kind holds the counter reading');
    });

    test(
        'known model (Pixel 8, catalog 4575 mAh), counter 3600 mAh at 100 %: '
        'design 4575 from the local catalog, the estimate stays 3600',
        () async {
      final r = await _run(_android());

      // Two different numbers, two different sources.
      _expectDesign(r, _pixel8Design, DesignCapacitySource.localDeviceDatabase);
      _expectEstimate(r, 3600, FullChargeCapacityConfidence.high);
      expect(r.settings.designCapacityMah, isNot(closeTo(r.estimate.mah!, 1)));
      expect(r.spec.model, 'Pixel 8');

      // 3600 / 4575 = 78.69 %.
      final health = r.health;
      expect(health, isNotNull);
      expect(health!.percent, closeTo(3600 / 4575 * 100, 1e-9));
      expect(health.percent, closeTo(78.7, 0.05));
      expect(health.confidence, FullChargeCapacityConfidence.high);

      _expectNoEstimateInDesignStorage(r, [3600]);
      expect(r.prefs.getDouble('wb.designCapacityMah'), 4575.0);
      expect(r.prefs.getKeys().map(r.prefs.get), isNot(contains(3600.0)));
    });

    test('the counter never reaches the design capacity at any battery level',
        () async {
      // (level, confidence of the estimate, or null = no estimate at all)
      const levels = <(int, FullChargeCapacityConfidence?)>[
        (100, FullChargeCapacityConfidence.high),
        (95, FullChargeCapacityConfidence.high),
        (94, FullChargeCapacityConfidence.medium),
        (75, FullChargeCapacityConfidence.medium),
        (50, FullChargeCapacityConfidence.low),
        (40, FullChargeCapacityConfidence.low),
        (39, null),
        (20, null),
        (1, null),
      ];
      for (final (level, confidence) in levels) {
        final stored = _full * level / 100;
        for (final known in [false, true]) {
          final fake = known
              ? _android(level: level, stored: stored)
              : _unlisted(level: level, stored: stored);
          final r = await _run(fake);
          final why = '${known ? 'Pixel 8' : 'unlisted model'} at $level %';

          if (known) {
            _expectDesign(
                r, _pixel8Design, DesignCapacitySource.localDeviceDatabase,
                reason: why);
          } else {
            _expectDesign(r, null, DesignCapacitySource.unknown, reason: why);
          }
          if (confidence == null) {
            expect(r.estimate, EstimatedFullChargeCapacity.unavailable,
                reason: why);
            expect(r.registered.single.$2.isAvailable, isFalse, reason: why);
            expect(r.health, isNull, reason: why);
          } else {
            _expectEstimate(r, 3600, confidence);
            _expectNoEstimateInDesignStorage(r, [3600]);
          }
          // A health needs a known design AND a medium/high estimate.
          final reliable = confidence == FullChargeCapacityConfidence.high ||
              confidence == FullChargeCapacityConfidence.medium;
          expect(r.health != null, known && reliable, reason: why);
        }
      }
    });

    test(
        'even a counter that equals a catalog figure (4575 mAh) is no design '
        'capacity: only the source tells them apart', () async {
      final unknown = await _run(_unlisted(stored: 4575));
      _expectDesign(unknown, null, DesignCapacitySource.unknown);
      expect(unknown.estimate.mah, closeTo(4575, 0.01));

      final known = await _run(_android(stored: 4575));
      _expectDesign(known, 4575, DesignCapacitySource.localDeviceDatabase);
      expect(
          known.estimate.source, FullChargeCapacitySource.androidChargeCounter,
          reason: 'same number, different fact');
      expect(known.health!.percent, closeTo(100, 1e-9));
    });

    test('the types make the mix-up impossible: no measurement source exists',
        () {
      expect(DesignCapacitySource.values.map((s) => s.name), [
        'manufacturerSpecification',
        'localDeviceDatabase',
        'backendDeviceDatabase',
        'manual',
        'unknown',
      ]);
      for (final s in DesignCapacitySource.values) {
        final n = s.name.toLowerCase();
        expect(
            n,
            isNot(anyOf(
                contains('counter'),
                contains('system'),
                contains('measure'),
                contains('estimate'),
                contains('android'))));
      }
      expect(FullChargeCapacitySource.values.map((s) => s.name),
          ['androidChargeCounter', 'unknown']);
      final spec = DeviceSpecification(
          manufacturer: 'x',
          model: 'y',
          design: DesignCapacity(
              mah: 3600, source: DesignCapacitySource.localDeviceDatabase));
      expect(spec.toJson().keys,
          isNot(contains('estimatedFullChargeCapacityMah')));
      expect(spec.toJson()['designCapacitySource'], 'localDeviceDatabase');
    });

    test('the specification cache and the registration never carry the counter',
        () async {
      final r = await _run(_unlisted(), backendLookup: (id) async => null);
      expect(r.cache.json, isNull, reason: 'nothing known, nothing cached');
      final (spec, fullCharge) = r.registered.single;
      expect(spec.toJson()['designCapacityMah'], isNull);
      expect(spec.toJson()['designCapacitySource'], 'unknown');
      expect(fullCharge.mah, closeTo(3600, 0.01));
    });
  });

  // ===========================================================================
  group('where a design capacity comes from', () {
    test('local catalog: known models, source localDeviceDatabase', () async {
      final pixel = await _run(_android(stored: null));
      _expectDesign(
          pixel, _pixel8Design, DesignCapacitySource.localDeviceDatabase);
      expect(pixel.estimate, EstimatedFullChargeCapacity.unavailable);

      final iphone = await _run(_iphone(id: 'iPhone18,1'));
      _expectDesign(iphone, 3988, DesignCapacitySource.localDeviceDatabase);
      expect(iphone.spec.model, 'iPhone 17 Pro');
    });

    test(
        'backend catalog fallback: a model the bundled catalog lacks gets the '
        'API\'s figure, source backendDeviceDatabase; the estimate is separate',
        () async {
      final asked = <String>[];
      final r = await _run(_unlisted(), backendLookup: (id) async {
        asked.add(id);
        return DeviceSpecification(
          manufacturer: 'Acme',
          model: 'Acme One',
          modelIdentifier: id,
          design: DesignCapacity(
              mah: 4000, source: DesignCapacitySource.backendDeviceDatabase),
        );
      });
      expect(asked, ['Unlisted-1']);

      _expectDesign(r, 4000, DesignCapacitySource.backendDeviceDatabase);
      expect(r.spec.model, 'Acme One');
      _expectEstimate(r, 3600, FullChargeCapacityConfidence.high);
      // design 4000 + estimated 3600 = 90 %.
      expect(r.health!.percent, closeTo(90, 1e-9));
      expect(r.cache.json, contains('4000'),
          reason: 'the specification is cached for offline launches');
      expect(r.cache.json, isNot(contains('3600')));
      _expectNoEstimateInDesignStorage(r, [3600]);
    });

    test(
        'backend catalog, offline on the next launch: the cached figure stands',
        () async {
      final first = await _run(_unlisted(),
          backendLookup: (id) async => DeviceSpecification(
                manufacturer: 'Acme',
                model: 'Acme One',
                modelIdentifier: id,
                design: DesignCapacity(
                    mah: 4000,
                    source: DesignCapacitySource.backendDeviceDatabase),
              ));
      final offline = await _run(_unlisted(),
          cachedSpec: first.cache.json,
          backendLookup: (id) async => throw const SocketException('offline'));
      _expectDesign(offline, 4000, DesignCapacitySource.backendDeviceDatabase);
      _expectEstimate(offline, 3600, FullChargeCapacityConfidence.high);
    });

    test(
        'unknown device: stays unknown with no number, on Android with a '
        'counter and without one, API or not', () async {
      for (final backend in <Future<DeviceSpecification?> Function(String)?>[
        null,
        (id) async => null,
        (id) async => throw const SocketException('offline'),
      ]) {
        for (final stored in <double?>[3600, null]) {
          final r =
              await _run(_unlisted(stored: stored), backendLookup: backend);
          _expectDesign(r, null, DesignCapacitySource.unknown,
              reason: 'counter $stored');
          expect(r.estimate.isAvailable, stored != null);
          expect(r.settings.designCapacity.isKnown, isFalse);
          expect(r.health, isNull);
        }
      }
    });

    test('manual design capacity: automatic detection never replaces it',
        () async {
      final manual = const Settings().withDesignCapacity(
          DesignCapacity(mah: 5000, source: DesignCapacitySource.manual));

      // A model the catalog knows: the user's figure still wins.
      final known = await _run(_android(), start: manual);
      _expectDesign(known, 5000, DesignCapacitySource.manual,
          detected: (_pixel8Design, DesignCapacitySource.localDeviceDatabase));
      _expectEstimate(known, 3600, FullChargeCapacityConfidence.high);
      expect(known.health!.percent, closeTo(72, 1e-9),
          reason: '3600 / 5000: the manual figure is a design capacity');

      // A model no catalog knows: the manual figure stays too, and the
      // estimate is still a separate 3600.
      final unlisted = await _run(_unlisted(), start: manual);
      _expectDesign(unlisted, 5000, DesignCapacitySource.manual,
          detected: (null, DesignCapacitySource.unknown));
      _expectEstimate(unlisted, 3600, FullChargeCapacityConfidence.high);
      expect(unlisted.settings.designCapacityMah,
          isNot(closeTo(unlisted.estimate.mah!, 1)));
    });

    test('an unknown detection never downgrades a known design capacity',
        () async {
      final known = const Settings().withDesignCapacity(DesignCapacity(
          mah: 4575, source: DesignCapacitySource.localDeviceDatabase));
      final r = await _run(_unlisted(), start: known);
      expect(r.spec.hasDesignCapacity, isFalse);
      expect(r.settings.designCapacityMah, 4575,
          reason: 'a failed lookup must not wipe what is known');
      expect(r.settings.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
    });
  });

  // ===========================================================================
  group('readings that must never become any capacity', () {
    test('unsupported counter (null): nothing estimated, nothing registered',
        () async {
      for (final known in [false, true]) {
        final r = await _run(
            known ? _android(stored: null) : _unlisted(stored: null));
        expect(r.fake.capabilities['chargeCounter'], isFalse);
        expect(r.estimate, EstimatedFullChargeCapacity.unavailable);
        expect(r.registered.single.$2, EstimatedFullChargeCapacity.unavailable);
        if (known) {
          _expectDesign(
              r, _pixel8Design, DesignCapacitySource.localDeviceDatabase);
        } else {
          _expectDesign(r, null, DesignCapacitySource.unknown);
        }
        expect(r.health, isNull);
      }
    });

    for (final (name, stored) in [
      ('zero', 0.0),
      ('negative', -3600.0),
      ('negative and tiny', -0.002),
    ]) {
      test('$name counter: no estimate, the design capacity is untouched',
          () async {
        for (final known in [false, true]) {
          final r = await _run(
              known ? _android(stored: stored) : _unlisted(stored: stored));
          expect(r.estimate, EstimatedFullChargeCapacity.unavailable);
          expect(await r.collector.fullChargeCapacity(),
              EstimatedFullChargeCapacity.unavailable);
          if (known) {
            _expectDesign(
                r, _pixel8Design, DesignCapacitySource.localDeviceDatabase);
          } else {
            _expectDesign(r, null, DesignCapacitySource.unknown);
          }
          expect(r.capacityPrefs.values.whereType<num>(),
              everyElement(greaterThanOrEqualTo(0)),
              reason: 'no negative number reaches a design capacity key');
        }
      });
    }

    test('battery level 0 and -1 (unknown): no division by zero, no estimate',
        () async {
      for (final level in [0, -1]) {
        for (final stored in [3600.0, 120.0, 0.0]) {
          final r = await _run(_unlisted(level: level, stored: stored));
          expect(r.estimate, EstimatedFullChargeCapacity.unavailable,
              reason: 'level $level, counter $stored');
          _expectDesign(r, null, DesignCapacitySource.unknown);
          expect(r.health, isNull);
        }
      }
    });

    test('a counter reporting mAh instead of uAh is rejected, not promoted',
        () async {
      final r = await _run(_unlisted(stored: 3.6)); // 3 600 "uAh"
      expect(r.estimate, EstimatedFullChargeCapacity.unavailable);
      _expectDesign(r, null, DesignCapacitySource.unknown);
    });

    test('NaN and Infinity never become a capacity of either kind', () async {
      // The estimator: any non-finite input is "no estimate".
      for (final (charge, level) in [
        (double.nan, 100.0),
        (double.infinity, 100.0),
        (double.negativeInfinity, 100.0),
        (3600000.0, double.nan),
        (3600000.0, double.infinity),
        (3600000.0, double.negativeInfinity),
        (double.nan, double.nan),
      ]) {
        final e = FullChargeCapacityEstimator.estimate(
            chargeUah: charge, level: level);
        expect(e, EstimatedFullChargeCapacity.unavailable,
            reason: 'charge $charge at $level');
        expect(e.toMeta(), isEmpty);
        expect(FullChargeCapacityEstimator.prefer(null, e, now: _now),
            EstimatedFullChargeCapacity.unavailable);
      }
      // A non-finite energy counter loses the Wh and keeps the mAh.
      final noWh = FullChargeCapacityEstimator.estimate(
          chargeUah: 3600000, energyNwh: double.nan, level: 100);
      expect(noWh.mah, closeTo(3600, 0.01));
      expect(noWh.wh, isNull);

      // The design capacity: normalised to unknown, wherever it comes from.
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1.0,
        0.0,
        30001.0,
      ]) {
        final d = DesignCapacity(
            mah: bad, source: DesignCapacitySource.localDeviceDatabase);
        expect(d, DesignCapacity.unknown, reason: 'design $bad');
        expect(d.isKnown, isFalse);
        final s = Settings(
          designCapacityMah: bad,
          designCapacityWh: bad,
          designCapacitySource: DesignCapacitySource.manual,
        ).sanitized();
        expect(s.designCapacityMah, 0, reason: 'settings $bad');
        expect(s.designCapacityWh, 0);
        expect(s.designCapacitySource, DesignCapacitySource.unknown);
      }

      // A corrupt preference file.
      SharedPreferences.setMockInitialValues({
        'wb.designCapacityMah': double.nan,
        'wb.designCapacityWh': double.infinity,
        'wb.designCapacitySource': 'manual',
      });
      final corrupt =
          SettingsStore(await SharedPreferences.getInstance()).load();
      expect(corrupt.designCapacity, DesignCapacity.unknown);
      expect(corrupt.designCapacityMah, 0);

      // A corrupt estimate in the collector's meta table.
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      for (final text in ['NaN', 'Infinity', '-Infinity']) {
        await db.setMeta('calibrated_capacity_mah', text);
        await db.setMeta('calibrated_capacity_level', '100');
        final c = Collector(system: WattByteSystem(), db: db);
        final e = await c.fullChargeCapacity();
        expect(e, EstimatedFullChargeCapacity.unavailable, reason: text);
        // ... and the energy calculation neither throws nor uses it.
        final calc = await energyCalcFor(const Settings(), c);
        expect(calc.batteryCapacityMah, 0, reason: text);
      }

      // The health: NaN in, no result out.
      expect(
          calculateEstimatedBatteryHealth(
              DesignCapacity(
                  mah: 4000, source: DesignCapacitySource.localDeviceDatabase),
              const EstimatedFullChargeCapacity(
                  mah: double.nan,
                  source: FullChargeCapacitySource.androidChargeCounter,
                  confidence: FullChargeCapacityConfidence.high)),
          isNull);
    });
  });

  // ===========================================================================
  group('the energy calculation', () {
    // 20 % -> 100 %, no counters: the "% -> mAh" path that needs a capacity.
    final session = ChargingSession(
      start: DateTime(2026, 10, 14, 0, 20),
      end: DateTime(2026, 10, 14, 6, 50),
      startLevel: 20,
      endLevel: 100,
    );

    test('uses the design capacity when it is known, even with an estimate',
        () async {
      final r = await _run(_android());
      final calc = await energyCalcFor(r.settings, r.collector);
      expect(calc.batteryCapacityMah, 4575);
      expect(calc.canEstimateFromPercent, isTrue);
      final e = calc.session(session);
      expect(e.mah, closeTo(4575 * 0.8, 1e-9),
          reason: '80 % of the DESIGN capacity, not of the 3600 estimate');
      expect(e.mahEstimated, isTrue);
    });

    test('uses the estimate only as a fallback, when no design capacity exists',
        () async {
      final r = await _run(_unlisted());
      expect(r.settings.designCapacityMah, 0);
      final calc = await energyCalcFor(r.settings, r.collector);
      expect(calc.batteryCapacityMah, closeTo(3600, 0.01));
      expect(calc.canEstimateFromPercent, isTrue);
      final e = calc.session(session);
      expect(e.mah, closeTo(3600 * 0.8, 0.01));
      expect(e.mahEstimated, isTrue, reason: 'still an estimate');
      expect(r.settings.designCapacityMah, 0,
          reason: 'the fallback does not write a design capacity');
    });

    test('a low confidence estimate also stands in, but never beats a design',
        () async {
      final unlisted = await _run(_unlisted(level: 50, stored: 1800));
      expect(unlisted.estimate.confidence, FullChargeCapacityConfidence.low);
      expect(
          (await energyCalcFor(unlisted.settings, unlisted.collector))
              .batteryCapacityMah,
          closeTo(3600, 0.01));

      final known = await _run(_android(level: 50, stored: 1800));
      expect(
          (await energyCalcFor(known.settings, known.collector))
              .batteryCapacityMah,
          4575);
    });

    test('with neither, nothing is invented: capacity 0, no % -> mAh path',
        () async {
      final ios = await _run(_iphone());
      final calc = await energyCalcFor(ios.settings, ios.collector);
      expect(calc.batteryCapacityMah, 0);
      expect(calc.canEstimateFromPercent, isFalse);
      expect(calc.session(session).mah, 0);

      expect(const Settings().energyCalc().batteryCapacityMah, 0,
          reason: 'no design, no estimate passed: 0, not a typical value');
      expect(
          const Settings()
              .energyCalc(estimatedFullChargeCapacityMah: 3600)
              .batteryCapacityMah,
          3600);
    });

    test('measured counters still beat any capacity', () async {
      final r = await _run(_android());
      final calc = await energyCalcFor(r.settings, r.collector);
      final measured = ChargingSession(
        start: session.start,
        end: session.end,
        startLevel: 20,
        endLevel: 100,
        chargeDeltaUah: 2880000,
        energyDeltaNwh: 11088000000,
        avgVoltageMv: 3850,
      );
      final e = calc.session(measured);
      expect(e.mah, closeTo(2880, 1e-9));
      expect(e.mahEstimated, isFalse);
    });
  });

  // ===========================================================================
  group('iOS has no charge counter', () {
    test(
        'unknown identifier: design unknown, no estimate, nothing registered '
        'as an estimate, no health', () async {
      final r = await _run(_iphone());
      _expectDesign(r, null, DesignCapacitySource.unknown);
      expect(r.fake.capabilities['chargeCounter'], isFalse);
      expect(r.estimate, EstimatedFullChargeCapacity.unavailable);
      expect(r.registered.single.$2.isAvailable, isFalse);
      expect(r.health, isNull);
      expect(await r.db.metaKeys('calibrated_capacity_'), isEmpty);
    });

    test('known identifier: the catalog design capacity, still no estimate',
        () async {
      final r = await _run(_iphone(id: 'iPhone18,1'));
      _expectDesign(r, 3988, DesignCapacitySource.localDeviceDatabase);
      expect(r.estimate, EstimatedFullChargeCapacity.unavailable);
      expect(r.health, isNull);
    });

    testWidgets(
        'the capacity text of an unknown model is "Battery capacity '
        'unavailable", in both languages, with no number', (tester) async {
      Future<String> text(Locale locale, Settings s) async {
        late String out;
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) {
            out = capacityText(context, s, Units(locale: locale.languageCode));
            return const SizedBox();
          }),
        ));
        return out;
      }

      expect(await text(const Locale('en'), const Settings()),
          'Battery capacity unavailable');
      expect(await text(const Locale('pl'), const Settings()),
          'Pojemność baterii niedostępna');
      // A known one is the catalog number, exactly.
      expect(
          await text(
              const Locale('en'),
              const Settings().withDesignCapacity(DesignCapacity(
                  mah: 3988,
                  source: DesignCapacitySource.localDeviceDatabase))),
          '3,988 mAh');
    });
  });

  // ===========================================================================
  group('persistence and installs from before the split', () {
    Future<(Settings, Collector)> upgrade(
      Map<String, Object> prefsBefore, {
      Map<String, String> metaBefore = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefsBefore);
      final prefs = await SharedPreferences.getInstance();
      final db = await WattByteDb.openInMemory();
      addTearDown(db.close);
      for (final e in metaBefore.entries) {
        await db.setMeta(e.key, e.value);
      }
      final store = SettingsStore(prefs);
      final loaded = store.load();
      await store.save(loaded); // the first save removes the old keys
      expect(
          prefs.getKeys(),
          isNot(anyOf(
              contains('wb.batteryCapacityMah'),
              contains('wb.batteryCapacityWh'),
              contains('wb.capacitySource'))));
      return (store.load(), Collector(system: WattByteSystem(), db: db));
    }

    for (final source in ['system', 'estimated']) {
      test(
          'an old install whose "capacity" was a measurement ($source, 3600 mAh) '
          'becomes UNKNOWN design capacity; the reading lives on as the estimate',
          () async {
        final (settings, collector) = await upgrade(
          {'wb.batteryCapacityMah': 3600.0, 'wb.capacitySource': source},
          metaBefore: {
            'calibrated_capacity_mah': '3600',
            'calibrated_capacity_level': '100',
          },
        );
        expect(settings.designCapacityMah, 0);
        expect(settings.designCapacitySource, DesignCapacitySource.unknown);
        expect(settings.designCapacity, DesignCapacity.unknown);

        final estimate = await collector.fullChargeCapacity();
        expect(estimate.isAvailable, isTrue);
        expect(estimate.mah, 3600);
        expect(estimate.confidence, FullChargeCapacityConfidence.high);
        expect(
            calculateEstimatedBatteryHealth(settings.designCapacity, estimate),
            isNull);
      });
    }

    test(
        'an old install with a catalog or typed capacity keeps it, with the '
        'new source names', () async {
      final (local, _) = await upgrade({
        'wb.batteryCapacityMah': 4575.0,
        'wb.capacitySource': 'localDatabase',
      });
      expect(local.designCapacityMah, 4575);
      expect(
          local.designCapacitySource, DesignCapacitySource.localDeviceDatabase);

      final (backend, _) = await upgrade({
        'wb.batteryCapacityMah': 4000.0,
        'wb.capacitySource': 'backendDatabase',
      });
      expect(backend.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);

      final (manual, _) = await upgrade({
        'wb.batteryCapacityMah': 5000.0,
        'wb.capacitySource': 'manual',
      });
      expect(manual.designCapacityMah, 5000);
      expect(manual.designCapacitySource, DesignCapacitySource.manual);
    });

    test(
        'a pre-split estimate (only mAh + level in the meta table) is an estimate',
        () async {
      final (settings, collector) = await upgrade({}, metaBefore: {
        'calibrated_capacity_mah': '3500',
        'calibrated_capacity_level': '80',
      });
      expect(settings.designCapacity, DesignCapacity.unknown);
      final e = await collector.fullChargeCapacity();
      expect(e.mah, 3500);
      expect(e.confidence, FullChargeCapacityConfidence.medium);
      expect(e.source, FullChargeCapacitySource.androidChargeCounter);
    });

    test('save and load round-trip every design source', () async {
      for (final source in DesignCapacitySource.values) {
        final design = source == DesignCapacitySource.unknown
            ? DesignCapacity.unknown
            : DesignCapacity(mah: 4575, wh: 17.6, source: source);
        SharedPreferences.setMockInitialValues({});
        final store = SettingsStore(await SharedPreferences.getInstance());
        await store.save(const Settings().withDesignCapacity(design));
        expect(store.load().designCapacity, design, reason: source.name);
      }
    });
  });

  // ===========================================================================
  group('through the real app (setup screen, Settings, device registration)',
      () {
    /// Android or iOS harness whose `POST /api/v1/devices` answers like the real
    /// API (every rule of `POST /devices` enforced, battery groups stored
    /// atomically). The collector has already run once on the fake phone.
    Future<(AppHarness, FakeDeviceTable)> app(
      WidgetTester tester,
      FakeSystem fake, {
      Settings? settings,
      bool onboarded = false,
      bool collect = true,
    }) async {
      final h = await AppHarness.create(tester,
          platform: fake.platform,
          system: fake,
          settings: settings,
          onboarded: onboarded,
          historyDays: 0);
      final table = FakeDeviceTable();
      h.backend.routes['POST /api/v1/devices'] =
          (r) => table.register(harnessUser.id, r.body!, 'device-1');
      if (collect) {
        await Collector(system: fake.system, db: h.db)
            .collect(now: DateTime.now());
      }
      return (h, table);
    }

    Future<void> runSetup(WidgetTester tester, AppHarness h) async {
      await pumpScreen(tester, const SetupScreen(),
          harness: h, platform: h.platform, semantics: true);
      await settle(tester);
      expect(find.text(_en.setupReviewTitle), findsOneWidget,
          reason: 'the review screen is up');
    }

    /// The design capacity keys of a request body or a stored row.
    Map<String, Object?> designOf(Map<String, dynamic> m) =>
        {for (final k in FakeBackend.designKeys) k: m[k]};

    Map<String, Object?> estimateOf(Map<String, dynamic> m) =>
        {for (final k in FakeBackend.estimateKeys) k: m[k]};

    void expectBodyHasNoCounterInDesign(Map<String, dynamic> body) {
      for (final k in FakeBackend.retiredBatteryKeys) {
        expect(body.containsKey(k), isFalse, reason: 'retired key $k sent');
      }
      for (final k in ['designCapacityMah', 'designCapacityWh']) {
        final v = body[k];
        if (v != null) expect(v, isNot(closeTo(3600, 0.5)), reason: k);
      }
    }

    testWidgets(
        'unknown Android model: the registration says design unknown (no '
        'numbers) and an estimated 3600 mAh, high confidence', (tester) async {
      final (h, table) = await app(tester, _unlisted());
      await runSetup(tester, h);

      final posts = h.backend.where('POST', '/api/v1/devices');
      expect(posts, isNotEmpty);
      for (final p in posts) {
        expectBodyHasNoCounterInDesign(p.body!);
      }
      final body = posts.last.body!;
      expect(designOf(body), {
        'designCapacityMah': null,
        'designCapacityWh': null,
        'designCapacitySource': 'unknown',
      });
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
      expect(body['estimatedFullChargeCapacityWh'], isNull);
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'high');
      expect(body['modelIdentifier'], 'Unlisted-1');

      // What the server stored (the API's rules applied): two groups.
      final row = table.rowsOf(harnessUser.id).single;
      expect(designOf(row), {
        'designCapacityMah': null,
        'designCapacityWh': null,
        'designCapacitySource': 'unknown',
      });
      expect(row['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
      expect(row['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(row['fullChargeCapacityConfidence'], 'high');

      // The app's own state and the screen.
      final s = h.container(tester).read(settingsProvider);
      expect(s.designCapacityMah, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      final battery = semanticsNode(tester, RegExp('^${_en.setupBattery}, '));
      expect(battery.label,
          contains('${_en.warningLabel}: ${_en.capacityUnavailable}'));
      expect(battery.label, isNot(contains('3,600')));
      expect(find.textContaining('3,600'), findsNothing,
          reason: 'the review never shows the estimate as the capacity');
    });

    testWidgets(
        'known Android model: the registration carries the catalog design '
        'capacity AND the estimate, as two groups with two sources',
        (tester) async {
      final (h, table) = await app(tester, _android());
      await runSetup(tester, h);

      final body = h.backend.where('POST', '/api/v1/devices').last.body!;
      expectBodyHasNoCounterInDesign(body);
      expect(designOf(body), {
        'designCapacityMah': 4575.0,
        'designCapacityWh': null,
        'designCapacitySource': 'localDeviceDatabase',
      });
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'high');

      final row = table.rowsOf(harnessUser.id).single;
      expect(row['designCapacityMah'], 4575.0);
      expect(row['designCapacitySource'], 'localDeviceDatabase');
      expect(row['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));

      final battery = semanticsNode(tester, RegExp('^${_en.setupBattery}, '));
      expect(battery.label, contains('4,575 mAh'));
      expect(battery.label, contains(_en.detectedFromSpecs));
      expect(battery.label, isNot(contains('3,600')));
      expect(find.textContaining('3,600'), findsNothing);
    });

    testWidgets(
        'no counter on this Android phone: the estimate group is all null, '
        'never "source unknown"', (tester) async {
      final (h, table) = await app(tester, _android(stored: null));
      await runSetup(tester, h);

      final body = h.backend.where('POST', '/api/v1/devices').last.body!;
      expect(
          estimateOf(body),
          {
            'estimatedFullChargeCapacityMah': null,
            'estimatedFullChargeCapacityWh': null,
            'fullChargeCapacitySource': null,
            'fullChargeCapacityConfidence': null,
          },
          reason: 'a null source keeps whatever the server stores; "unknown" '
              'would erase it');
      expect(body['designCapacitySource'], 'localDeviceDatabase');
      expect(table.rowsOf(harnessUser.id), hasLength(1));
    });

    testWidgets(
        'a registration without an estimate keeps the estimate the server '
        'already stores', (tester) async {
      final (h, table) = await app(tester, _android());
      await runSetup(tester, h);
      expect(
          table.rowsOf(harnessUser.id).single['estimatedFullChargeCapacityMah'],
          closeTo(3600, 0.01));

      // The local reading is gone ("Reset statistics" wipes the meta table);
      // the user taps "Detect again" in Settings: the design capacity goes up
      // again, the estimate group is left out.
      await h.db.resetAll();
      await pumpScreen(tester, const SettingsScreen(),
          harness: h, platform: h.platform, scaffold: true, semantics: true);
      await tester.scrollUntilVisible(find.text(_en.detectAgain), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(_en.detectAgain));
      await tester.pump();
      final before = h.backend.where('POST', '/api/v1/devices').length;
      await tester.tap(find.text(_en.detectAgain));
      await settle(tester);

      final posts = h.backend.where('POST', '/api/v1/devices');
      expect(posts.length, greaterThan(before), reason: 'registered again');
      final last = posts.last.body!;
      expect(estimateOf(last).values, everyElement(isNull),
          reason: 'null source: nothing to replace, and never "unknown"');
      expect(last['designCapacitySource'], 'localDeviceDatabase');
      final row = table.rowsOf(harnessUser.id).single;
      expect(row['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01),
          reason: 'kept by the server');
      expect(row['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(row['fullChargeCapacityConfidence'], 'high');
      expect(row['designCapacityMah'], 4575.0);
    });

    testWidgets(
        'iOS, unknown identifier: "Battery capacity unavailable", an unknown '
        'design capacity registered with no numbers, no estimate',
        (tester) async {
      final (h, table) = await app(tester, _iphone());
      await runSetup(tester, h);

      final body = h.backend.where('POST', '/api/v1/devices').last.body!;
      expect(body['platform'], 'ios');
      expect(designOf(body), {
        'designCapacityMah': null,
        'designCapacityWh': null,
        'designCapacitySource': 'unknown',
      });
      expect(estimateOf(body).values, everyElement(isNull));
      expect(table.rowsOf(harnessUser.id).single['designCapacitySource'],
          'unknown');

      expect(find.text(_en.capacityUnavailable), findsOneWidget);
      expect(_en.capacityUnavailable, 'Battery capacity unavailable');
      final battery = semanticsNode(tester, RegExp('^${_en.setupBattery}, '));
      expect(battery.label,
          contains('${_en.warningLabel}: Battery capacity unavailable'));
      expect(battery.label, contains(_en.capacityUnavailableBody));
      expect(battery.label, isNot(contains('mAh')));
      expect(battery.label, endsWith(_en.enterManually));
      expect(h.container(tester).read(settingsProvider).designCapacityMah, 0);
    });

    testWidgets(
        'Settings > Device shows the design capacity and, separately, the '
        'estimated full charge capacity with its confidence', (tester) async {
      final (h, _) =
          await app(tester, _android(), onboarded: true, collect: false);
      await seedFullChargeEstimate(h.db, mah: 3600, level: 100);
      await pumpScreen(tester, const SettingsScreen(),
          harness: h, platform: h.platform, scaffold: true, semantics: true);

      await tester.scrollUntilVisible(
          find.text(_en.estimatedFullChargeCapacity), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(_en.estimatedFullChargeCapacity));
      await tester.pump();

      final design = semanticsNode(tester, RegExp('^${_en.batteryCapacity}, '));
      expect(design.label, contains('4,575 mAh'));
      expect(design.label, contains(_en.detectedFromSpecs));
      expect(design.label, isNot(contains('3,600')));

      expect(find.text('~3,600 mAh'), findsOneWidget,
          reason: 'the estimate is marked on screen with a tilde');
      final estimate = semanticsNode(
          tester, RegExp('^${_en.estimatedFullChargeCapacity}, '));
      expect(estimate.label, contains('3,600 mAh'));
      expect(estimate.label, isNot(contains('~')),
          reason: 'a screen reader would say "tilde"');
      expect(estimate.label,
          contains(_en.estimatedFullChargeCapacityBody(_en.confidenceHigh)));
      expect(estimate.label, isNot(contains('4,575')));
    });

    testWidgets(
        '"Detect again" on an unlisted model with an estimate leaves the design '
        'capacity unknown (it replaces a manual one only by catalog data)',
        (tester) async {
      final fake = _unlisted();
      final manual = AppHarness.defaultSettings(HarnessPlatform.android)
          .withDesignCapacity(
              DesignCapacity(mah: 5000, source: DesignCapacitySource.manual));
      final (h, table) =
          await app(tester, fake, settings: manual, onboarded: true);
      await pumpScreen(tester, const SettingsScreen(),
          harness: h, platform: h.platform, scaffold: true, semantics: true);
      expect(
          h.container(tester).read(settingsProvider).designCapacityMah, 5000);

      await tester.scrollUntilVisible(find.text(_en.detectAgain), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(_en.detectAgain));
      await tester.pump();
      await tester.tap(find.text(_en.detectAgain));
      await settle(tester);

      // An explicit "Detect again" replaces the manual figure, with what the
      // catalogs know: nothing. It does NOT put the 3600 mAh estimate there.
      final s = h.container(tester).read(settingsProvider);
      expect(s.designCapacityMah, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      final body = h.backend.where('POST', '/api/v1/devices').last.body!;
      expect(body['designCapacitySource'], 'unknown');
      expect(body['designCapacityMah'], isNull);
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
      expect(designOf(table.rowsOf(harnessUser.id).single),
          containsPair('designCapacitySource', 'unknown'));
    });

    testWidgets(
        'the app\'s energy calculation reads the estimate only when the design '
        'capacity is unknown', (tester) async {
      final (h, _) =
          await app(tester, _android(), onboarded: true, collect: false);
      await seedFullChargeEstimate(h.db, mah: 3600, level: 100);
      await pumpScreen(tester, const SettingsScreen(),
          harness: h, platform: h.platform, scaffold: true);
      final container = h.container(tester);
      await container.read(fullChargeCapacityProvider.future);

      expect(container.read(energyCalcProvider).batteryCapacityMah, 4575,
          reason: 'known design capacity wins');

      await container
          .read(settingsProvider.notifier)
          .update((s) => s.withDesignCapacity(DesignCapacity.unknown));
      await settle(tester);
      expect(container.read(energyCalcProvider).batteryCapacityMah,
          closeTo(3600, 0.01),
          reason: 'estimate as the fallback');
      expect(container.read(settingsProvider).designCapacityMah, 0);
    });
  });
}
