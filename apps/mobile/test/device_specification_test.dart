import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import 'support/fake_system.dart';

/// The model's DESIGN capacity: catalog, backend, nothing. The Android charge
/// counter (the charge currently stored in the battery) is never consulted here
/// and never becomes a design capacity (docs/BATTERY_CAPACITY.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real bundled catalog, so the test fails if the asset breaks.
  final catalogJson =
      File('assets/device_specs/devices.json').readAsStringSync();
  Future<String> catalog() async => catalogJson;

  Map<String, Object?> info(String id,
          {String manufacturer = 'Apple', String model = 'iPhone'}) =>
      {
        'manufacturer': manufacturer,
        'model': model,
        'modelIdentifier': id,
        'regionCode': 'PL',
        'localeTag': 'en-PL',
      };

  /// What the backend's `GET /devices/specifications/iPhone19,2` answers.
  DeviceSpecification backendIphone18({
    double mah = 4100,
    double? wh,
    DesignCapacitySource source = DesignCapacitySource.backendDeviceDatabase,
  }) =>
      DeviceSpecification(
        manufacturer: 'Apple',
        model: 'iPhone 18 Pro',
        modelIdentifier: 'iPhone19,2',
        design: DesignCapacity(mah: mah, wh: wh, source: source),
      );

  group('local catalog', () {
    test(
        'known iPhone identifier -> catalog design capacity, source '
        'localDeviceDatabase', () async {
      final s = DeviceSpecificationService(
          system: fakeSystem(deviceInfo: info('iPhone16,1')),
          loadCatalog: catalog);
      final spec = await s.detect();
      expect(spec.model, 'iPhone 15 Pro');
      expect(spec.designCapacityMah, 3274);
      expect(spec.designCapacityWh, 12.7);
      expect(spec.nominalVoltage, closeTo(3.88, 0.01));
      expect(
          spec.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(spec.hasDesignCapacity, isTrue);
      expect(
          spec.design,
          DesignCapacity(
              mah: 3274,
              wh: 12.7,
              source: DesignCapacitySource.localDeviceDatabase));
    });

    test(
        'known Android model (Build.MODEL) -> catalog design capacity, '
        'prefixes cover regional codes', () async {
      final pixel = await DeviceSpecificationService(
              system: fakeSystem(
                  deviceInfo: info('Pixel 8',
                      manufacturer: 'Google', model: 'Pixel 8')),
              loadCatalog: catalog)
          .detect();
      expect(pixel.designCapacityMah, 4575);
      expect(
          pixel.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      final samsung = await DeviceSpecificationService(
              system: fakeSystem(
                  deviceInfo: info('SM-S921B',
                      manufacturer: 'samsung', model: 'SM-S921B')),
              loadCatalog: catalog)
          .detect();
      expect(samsung.model, 'Galaxy S24');
      expect(samsung.designCapacityMah, 4000);
      expect(samsung.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
    });

    test('a model the catalog knows never asks the backend', () async {
      var backendCalls = 0;
      final spec = await DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone16,1')),
        loadCatalog: catalog,
        backendLookup: (_) async {
          backendCalls++;
          return backendIphone18();
        },
      ).detect();
      expect(spec.designCapacityMah, 3274);
      expect(backendCalls, 0);
    });

    test(
        'unknown iPhone identifier -> unknown: no number, source unknown, '
        'never a typical value', () async {
      final spec = await DeviceSpecificationService(
              system: fakeSystem(deviceInfo: info('iPhone19,2')),
              loadCatalog: catalog)
          .detect();
      expect(spec.hasDesignCapacity, isFalse);
      expect(spec.designCapacityMah, isNull);
      expect(spec.designCapacityWh, isNull);
      expect(spec.designCapacitySource, DesignCapacitySource.unknown);
      expect(spec.design, DesignCapacity.unknown);
      expect(spec.modelIdentifier, 'iPhone19,2');
      expect(spec.manufacturer, 'Apple');
    });

    test('unknown Android model -> unknown too (iOS and Android behave alike)',
        () async {
      final spec = await DeviceSpecificationService(
              system: fakeSystem(
                  deviceInfo: info('Nokia 3310',
                      manufacturer: 'HMD', model: 'Nokia 3310')),
              loadCatalog: catalog)
          .detect();
      expect(spec.design, DesignCapacity.unknown);
      expect(spec.designCapacityMah, isNull);
      expect(spec.modelIdentifier, 'Nokia 3310');
    });

    test('no device identifier or no device info -> unknown, nothing thrown',
        () async {
      final noId = await DeviceSpecificationService(
              system: fakeSystem(deviceInfo: info('')), loadCatalog: catalog)
          .detect();
      expect(noId.design, DesignCapacity.unknown);
      // An old native side answers null for deviceInfo.
      final noInfo = await DeviceSpecificationService(
              system: fakeSystem(deviceInfo: null), loadCatalog: catalog)
          .detect();
      expect(noInfo.design, DesignCapacity.unknown);
      expect(noInfo.model, '');
    });

    test('the bundled catalog speaks the design-capacity vocabulary', () {
      final entries = (jsonDecode(catalogJson)['devices'] as List)
          .cast<Map<String, dynamic>>();
      expect(entries, isNotEmpty);
      for (final e in entries) {
        expect(e.containsKey('batteryCapacityMah'), isFalse,
            reason: '${e['model']} still uses the old key');
        expect(e['designCapacityMah'], isA<num>(), reason: '${e['model']}');
        expect(e['designCapacityMah'] as num, greaterThan(0),
            reason: '${e['model']}');
      }
    });

    test(
        'a catalog lookup labels the capacity with the source it was read from',
        () {
      final cat = DeviceCatalog.fromJson(catalogJson);
      expect(cat.lookup('iPhone16,1')!.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
      expect(
          cat
              .lookup('iPhone16,1',
                  source: DesignCapacitySource.backendDeviceDatabase)!
              .designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(cat.lookup('iPhone99,9'), isNull);
      expect(cat.lookup('   '), isNull);
    });
  });

  group('detect() reads no charge counter', () {
    // The Android charge counter is the charge currently in the battery. The
    // collector turns it into an ESTIMATED full-charge capacity; detect() has no
    // reading parameter and the collector's estimate reaches the setup only as
    // SetupResult.fullCharge, a separate field.
    final estimate3600 =
        FullChargeCapacityEstimator.estimate(chargeUah: 3600000, level: 100);

    AutoSetup autoSetup(FakeSystem fake) => AutoSetup(
          region: RegionDetectionService(
              system: fake.system, localeTag: () => 'en_PL'),
          device: DeviceSpecificationService(
              system: fake.system, loadCatalog: catalog),
          fullCharge: () async => estimate3600,
        );

    test('the fixture is what the next tests think it is', () {
      expect(estimate3600.mah, 3600);
      expect(estimate3600.confidence, FullChargeCapacityConfidence.high);
      expect(
          estimate3600.source, FullChargeCapacitySource.androidChargeCounter);
    });

    test(
        'a device no catalog knows STAYS unknown although the collector holds a '
        '3600 mAh / 100 % estimate', () async {
      final fake = FakeSystem(
          platform: HarnessPlatform.android,
          batteryLevel: 100,
          chargeCounterMah: 3600,
          deviceInfo:
              info('Pixel 99', manufacturer: 'Google', model: 'Pixel 99'));
      addTearDown(fake.dispose);

      final result = await autoSetup(fake).detect(const Settings());

      expect(result.device!.design, DesignCapacity.unknown);
      expect(result.device!.designCapacityMah, isNull);
      expect(result.device!.designCapacitySource, DesignCapacitySource.unknown);
      expect(result.fullCharge, estimate3600,
          reason: 'the estimate is reported, but as an estimate');
      expect(fake.callsTo('batterySnapshot'), isEmpty,
          reason: 'detection never reads the battery');

      final settings = AutoSetup.apply(const Settings(), result);
      expect(settings.designCapacityMah, 0);
      expect(settings.designCapacityWh, 0);
      expect(settings.designCapacitySource, DesignCapacitySource.unknown);
      expect(settings.designCapacity, DesignCapacity.unknown);
    });

    test(
        'a known device keeps its catalog design capacity next to a different '
        'estimate', () async {
      final fake = FakeSystem(
          platform: HarnessPlatform.android,
          batteryLevel: 100,
          chargeCounterMah: 3600,
          deviceInfo:
              info('Pixel 8', manufacturer: 'Google', model: 'Pixel 8'));
      addTearDown(fake.dispose);

      final result = await autoSetup(fake).detect(const Settings());

      expect(result.device!.designCapacityMah, 4575);
      expect(result.device!.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
      expect(result.fullCharge.mah, 3600);

      final settings = AutoSetup.apply(const Settings(), result);
      expect(settings.designCapacityMah, 4575);
      expect(settings.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
    });

    test('a failing estimate hook does not stop the detection', () async {
      final fake = FakeSystem(
          platform: HarnessPlatform.android,
          deviceInfo:
              info('Pixel 8', manufacturer: 'Google', model: 'Pixel 8'));
      addTearDown(fake.dispose);
      final result = await AutoSetup(
        region: RegionDetectionService(
            system: fake.system, localeTag: () => 'en_PL'),
        device: DeviceSpecificationService(
            system: fake.system, loadCatalog: catalog),
        fullCharge: () async => throw StateError('database closed'),
      ).detect(const Settings());
      expect(result.fullCharge, EstimatedFullChargeCapacity.unavailable);
      expect(result.device!.designCapacityMah, 4575);
    });
  });

  group('backend database', () {
    test(
        'catalog miss -> backend database, cached for the next (offline) '
        'launch', () async {
      String? cache;
      var backendCalls = 0;
      final s = DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        readCache: () => cache,
        writeCache: (json) async => cache = json,
        backendLookup: (id) async {
          backendCalls++;
          return backendIphone18();
        },
      );
      final online = await s.detect();
      expect(online.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(online.designCapacityMah, 4100);
      expect(online.model, 'iPhone 18 Pro');
      expect(jsonDecode(cache!)['modelIdentifier'], 'iPhone19,2');
      final cached = jsonDecode(cache!) as Map<String, dynamic>;
      expect(cached['designCapacityMah'], 4100);
      expect(cached['designCapacitySource'], 'backendDeviceDatabase');
      expect(cached.keys, isNot(contains('batteryCapacityMah')),
          reason: 'the cache is written in the design-capacity layout');
      expect(cached.keys, isNot(contains('source')));

      final offline = DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        readCache: () => cache,
        backendLookup: (_) async => throw Exception('offline'),
      );
      final again = await offline.detect();
      expect(again.designCapacityMah, 4100);
      expect(again.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(backendCalls, 1);
    });

    test('the backend answer is always labelled backendDeviceDatabase',
        () async {
      // Whatever the lookup says about its own provenance, the service knows
      // where the number came from.
      for (final claimed in [
        DesignCapacitySource.manual,
        DesignCapacitySource.localDeviceDatabase,
        DesignCapacitySource.manufacturerSpecification,
      ]) {
        String? cache;
        final spec = await DeviceSpecificationService(
          system: fakeSystem(deviceInfo: info('iPhone19,2')),
          loadCatalog: catalog,
          writeCache: (json) async => cache = json,
          backendLookup: (_) async => backendIphone18(source: claimed),
        ).detect();
        expect(spec.designCapacitySource,
            DesignCapacitySource.backendDeviceDatabase,
            reason: claimed.name);
        expect(jsonDecode(cache!)['designCapacitySource'],
            'backendDeviceDatabase');
      }
    });

    test('the backend Wh is kept with the mAh', () async {
      final spec = await DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        backendLookup: (_) async => backendIphone18(mah: 4000, wh: 15.4),
      ).detect();
      expect(spec.designCapacityMah, 4000);
      expect(spec.designCapacityWh, 15.4);
    });

    test(
        'backend unreachable and nothing cached -> unknown (manual entry is '
        'the last resort)', () async {
      final s = DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        backendLookup: (_) async => throw Exception('offline'),
      );
      final spec = await s.detect();
      expect(spec.designCapacitySource, DesignCapacitySource.unknown);
      expect(spec.designCapacityMah, isNull);
      // The user's manual value is then kept by Settings, outside this service
      // (automatic detection never replaces it).
      const manual = Settings(
          designCapacityMah: 4000,
          designCapacitySource: DesignCapacitySource.manual);
      expect(manual.designCapacitySource, DesignCapacitySource.manual);
      final after = AutoSetup.apply(manual, SetupResult(device: spec));
      expect(after.designCapacityMah, 4000);
      expect(after.designCapacitySource, DesignCapacitySource.manual);
    });

    test('the backend does not know the model either -> unknown', () async {
      final s = DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        backendLookup: (_) async => null,
      );
      final spec = await s.detect();
      expect(spec.design, DesignCapacity.unknown);
      expect(spec.modelIdentifier, 'iPhone19,2');
    });

    test('a backend answer without a design capacity is not trusted', () async {
      String? cache;
      final s = DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        writeCache: (json) async => cache = json,
        backendLookup: (_) async => const DeviceSpecification(
            manufacturer: 'Apple',
            model: 'iPhone 18 Pro',
            modelIdentifier: 'iPhone19,2'),
      );
      expect((await s.detect()).design, DesignCapacity.unknown);
      expect(cache, isNull, reason: 'nothing worth caching');
    });

    test('without a lookup and without a cache the backend is simply skipped',
        () async {
      final spec = await DeviceSpecificationService(
              system: fakeSystem(deviceInfo: info('iPhone19,2')),
              loadCatalog: catalog)
          .detect();
      expect(spec.design, DesignCapacity.unknown);
    });
  });

  group('the cached backend specification (readCache)', () {
    /// A cache entry as builds before the split wrote it.
    String legacyCache({String? source, Object? mah = 4100.0}) => jsonEncode({
          'manufacturer': 'Apple',
          'model': 'iPhone 18 Pro',
          'modelIdentifier': 'iPhone19,2',
          'batteryCapacityMah': mah,
          'batteryCapacityWh': null,
          'nominalVoltage': null,
          if (source != null) 'source': source,
        });

    Future<({DeviceSpecification spec, int backendCalls})> detectWith(
        String? cache,
        {bool backendKnows = false}) async {
      var calls = 0;
      final spec = await DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: catalog,
        readCache: () => cache,
        backendLookup: (_) async {
          calls++;
          return backendKnows ? backendIphone18(mah: 4200) : null;
        },
      ).detect();
      return (spec: spec, backendCalls: calls);
    }

    test(
        'legacy shape: batteryCapacityMah + source backendDatabase is accepted '
        'as backendDeviceDatabase', () async {
      final r = await detectWith(legacyCache(source: 'backendDatabase'));
      expect(r.spec.designCapacityMah, 4100);
      expect(r.spec.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(r.spec.model, 'iPhone 18 Pro');
      expect(r.backendCalls, 0, reason: 'the cache answered, offline-safe');
    });

    test(
        'legacy source system / estimated / manual / unknown / missing is '
        'ignored: a measurement or an unlabelled number is not a design '
        'capacity', () async {
      for (final source in ['system', 'estimated', 'manual', 'unknown', null]) {
        final r = await detectWith(legacyCache(source: source));
        expect(r.spec.design, DesignCapacity.unknown, reason: '$source');
        expect(r.spec.designCapacityMah, isNull, reason: '$source');
        expect(r.backendCalls, 1,
            reason: '$source: the stale entry does not answer, so ask');
      }
    });

    test('an ignored legacy entry is replaced by what the backend says',
        () async {
      final r = await detectWith(legacyCache(source: 'system', mah: 4480.0),
          backendKnows: true);
      expect(r.spec.designCapacityMah, 4200);
      expect(r.spec.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
    });

    test('new shape with a source of unknown carries no number', () async {
      final r = await detectWith(jsonEncode({
        'manufacturer': 'Apple',
        'model': 'iPhone 18 Pro',
        'modelIdentifier': 'iPhone19,2',
        'designCapacityMah': 4100.0,
        'designCapacitySource': 'unknown',
      }));
      expect(r.spec.design, DesignCapacity.unknown);
      expect(r.backendCalls, 1);
    });

    test(
        'a cached entry can never come back as manual or catalog data: only '
        'the backend writes it, so it is relabelled backendDeviceDatabase',
        () async {
      for (final claimed in [
        'manual',
        'localDeviceDatabase',
        'manufacturerSpecification',
        'backendDeviceDatabase',
      ]) {
        final r = await detectWith(jsonEncode({
          'manufacturer': 'Apple',
          'model': 'iPhone 18 Pro',
          'modelIdentifier': 'iPhone19,2',
          'designCapacityMah': 4100.0,
          'designCapacitySource': claimed,
        }));
        expect(r.spec.designCapacityMah, 4100, reason: claimed);
        expect(r.spec.designCapacitySource,
            DesignCapacitySource.backendDeviceDatabase,
            reason: claimed);
      }
    });

    test('an entry cached for another model is not used', () async {
      final r = await detectWith(jsonEncode({
        'manufacturer': 'Apple',
        'model': 'iPhone 18',
        'modelIdentifier': 'iPhone19,1',
        'designCapacityMah': 3500.0,
        'designCapacitySource': 'backendDeviceDatabase',
      }));
      expect(r.spec.design, DesignCapacity.unknown);
      expect(r.backendCalls, 1);
    });

    test('a damaged cache is ignored, never fatal', () async {
      for (final bad in [
        '',
        '{not json',
        '[]',
        '"text"',
        jsonEncode({'modelIdentifier': 5}),
        jsonEncode({
          'modelIdentifier': 'iPhone19,2',
          'designCapacityMah': 'a lot',
          'designCapacitySource': 'backendDeviceDatabase',
        }),
        jsonEncode({
          'modelIdentifier': 'iPhone19,2',
          'designCapacityMah': -4100.0,
          'designCapacitySource': 'backendDeviceDatabase',
        }),
      ]) {
        final r = await detectWith(bad);
        expect(r.spec.design, DesignCapacity.unknown, reason: bad);
      }
    });
  });

  group('a broken catalog asset', () {
    test('does not break detection', () async {
      final s = DeviceSpecificationService(
          system: fakeSystem(deviceInfo: info('iPhone16,1')),
          loadCatalog: () async => '{not json');
      final spec = await s.detect();
      expect(spec.designCapacitySource, DesignCapacitySource.unknown);
      expect(spec.designCapacityMah, isNull);
      expect(spec.modelIdentifier, 'iPhone16,1');
    });

    test('a catalog that cannot be loaded at all falls back to the backend',
        () async {
      final spec = await DeviceSpecificationService(
        system: fakeSystem(deviceInfo: info('iPhone19,2')),
        loadCatalog: () async => throw const FileSystemException('missing'),
        backendLookup: (_) async => backendIphone18(),
      ).detect();
      expect(spec.designCapacityMah, 4100);
      expect(spec.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
    });

    test(
        'a catalog still written with the old key is unusable, not read as a '
        'capacity', () async {
      final oldKeys = jsonEncode({
        'version': 'old',
        'devices': [
          {
            'manufacturer': 'Apple',
            'model': 'iPhone 15 Pro',
            'identifiers': ['iPhone16,1'],
            'batteryCapacityMah': 3274,
          }
        ],
      });
      final spec = await DeviceSpecificationService(
          system: fakeSystem(deviceInfo: info('iPhone16,1')),
          loadCatalog: () async => oldKeys).detect();
      expect(spec.design, DesignCapacity.unknown);
    });
  });

  group('DeviceSpecification JSON', () {
    test('round trips the design capacity and its source', () {
      final spec = DeviceSpecification(
        manufacturer: 'Apple',
        model: 'iPhone 15 Pro',
        modelIdentifier: 'iPhone16,1',
        nominalVoltage: 3.88,
        design: DesignCapacity(
            mah: 3274,
            wh: 12.7,
            source: DesignCapacitySource.localDeviceDatabase),
      );
      final json = spec.toJson();
      expect(json['designCapacityMah'], 3274);
      expect(json['designCapacityWh'], 12.7);
      expect(json['designCapacitySource'], 'localDeviceDatabase');
      expect(json.keys, isNot(contains('batteryCapacityMah')));
      final back = DeviceSpecification.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.design, spec.design);
      expect(back.model, 'iPhone 15 Pro');
      expect(back.modelIdentifier, 'iPhone16,1');
      expect(back.nominalVoltage, 3.88);
    });

    test('an unknown specification serialises with no number', () {
      final json = DeviceSpecification.unknown(null).toJson();
      expect(json['designCapacityMah'], isNull);
      expect(json['designCapacityWh'], isNull);
      expect(json['designCapacitySource'], 'unknown');
    });

    test('fromJson never throws and never invents a design capacity', () {
      for (final j in <Map<String, dynamic>>[
        {},
        {'designCapacitySource': 5, 'designCapacityMah': '4000'},
        {'designCapacitySource': 'bogus', 'designCapacityMah': 4000.0},
        {'designCapacitySource': 'unknown', 'designCapacityMah': 4000.0},
        {'designCapacitySource': 'manual', 'designCapacityMah': double.nan},
        {'designCapacitySource': 'manual', 'designCapacityMah': -1},
        {'designCapacitySource': 'manual', 'designCapacityMah': 99999},
        {'source': 'system', 'batteryCapacityMah': 4480.0},
        {'source': 'estimated', 'batteryCapacityMah': 4100.0},
        {'source': 'manual', 'batteryCapacityMah': 4000.0},
        {'batteryCapacityMah': 4000.0},
      ]) {
        final spec = DeviceSpecification.fromJson(j);
        expect(spec.design, DesignCapacity.unknown, reason: '$j');
      }
    });

    test('the new source key wins over leftover legacy keys', () {
      final spec = DeviceSpecification.fromJson({
        'designCapacityMah': 4100.0,
        'designCapacitySource': 'backendDeviceDatabase',
        'batteryCapacityMah': 9999.0,
        'source': 'system',
      });
      expect(spec.designCapacityMah, 4100);
      expect(spec.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
    });

    test('an entry whose Wh is implausible keeps the mAh and drops the Wh', () {
      final spec = DeviceSpecification.fromJson({
        'designCapacityMah': 4100.0,
        'designCapacityWh': -3.0,
        'designCapacitySource': 'backendDeviceDatabase',
      });
      expect(spec.designCapacityMah, 4100);
      expect(spec.designCapacityWh, isNull);
    });
  });
}
