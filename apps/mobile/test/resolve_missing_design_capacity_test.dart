// An install can hold no design capacity although its model is in a device
// database: the old `system` / `estimated` capacity was a charge-counter
// MEASUREMENT (never a design capacity) and is dropped on load, and an offline
// first setup may have found nothing. `resolveMissingDesignCapacity` runs once
// at launch, looks the model up and fills the gap (docs/BATTERY_CAPACITY.md).
//
// The rules pinned here: it only ever FILLS A GAP (a known capacity, a manual
// one included, is never replaced), a failed or empty lookup changes nothing,
// and the capacity it finds goes up with the device registration as the DESIGN
// group while the estimate stays its own group.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/settings/setup_editors.dart';

import 'accessibility/flow_matrix_support.dart' show resetAssetCache;
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

FakeSystem _android({String id = 'Pixel 8', double? stored = 3600}) {
  return FakeSystem(
    platform: HarnessPlatform.android,
    batteryLevel: 100,
    chargeCounterMah: stored,
    deviceInfo: {
      ...FakeSystem.defaultDeviceInfo(HarnessPlatform.android),
      'modelIdentifier': id,
      'model': id,
    },
  );
}

/// What an upgraded install looks like after `SettingsStore.load()`: finished
/// setup, a stored model identifier, and NO design capacity.
Settings _gap({String id = 'Pixel 8', bool onboarded = true}) =>
    AppHarness.defaultSettings(HarnessPlatform.android).copyWith(
      designCapacityMah: 0,
      designCapacityWh: 0,
      designCapacitySource: DesignCapacitySource.unknown,
      deviceModel: id,
      deviceModelIdentifier: id,
      onboarded: onboarded,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUp(resetAssetCache);

  /// The harness on a fake Android phone whose collector has already read the
  /// charge counter once (so an estimate exists), plus the settings screen's
  /// BuildContext.
  Future<(AppHarness, FakeDeviceTable, BuildContext)> app(
    WidgetTester tester,
    FakeSystem fake,
    Settings settings,
  ) async {
    final h = await AppHarness.create(tester,
        platform: HarnessPlatform.android,
        system: fake,
        settings: settings,
        historyDays: 0);
    final table = FakeDeviceTable();
    h.backend.routes['POST /api/v1/devices'] =
        (r) => table.register(harnessUser.id, r.body!, 'device-1');
    await Collector(system: fake.system, db: h.db).collect(now: DateTime.now());
    late BuildContext context;
    await pumpScreen(
      tester,
      Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
      harness: h,
      platform: HarnessPlatform.android,
      scaffold: true,
    );
    return (h, table, context);
  }

  Settings read(AppHarness h, WidgetTester tester) =>
      h.container(tester).read(settingsProvider);

  testWidgets(
      'a model the bundled catalog knows: the gap is filled with the catalog '
      'figure and registered as the DESIGN group beside the estimate',
      (tester) async {
    final (h, table, context) = await app(tester, _android(), _gap());
    expect(read(h, tester).designCapacity.isKnown, isFalse, reason: 'the gap');

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    final s = read(h, tester);
    expect(s.designCapacityMah, 4575);
    expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    expect(s.designCapacityMah, isNot(closeTo(3600, 1)),
        reason: 'the charge counter reading is not the design capacity');

    final body = h.backend.where('POST', '/api/v1/devices').last.body!;
    expect(body['designCapacityMah'], 4575);
    expect(body['designCapacitySource'], 'localDeviceDatabase');
    expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
    expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
    final row = table.rowsOf(harnessUser.id).single;
    expect(row['designCapacityMah'], 4575.0);
    expect(row['estimatedFullChargeCapacityMah'], closeTo(3600, 0.01));
  });

  testWidgets(
      'a manual capacity is never replaced, and nothing is registered '
      '(it is a known capacity: there is no gap)', (tester) async {
    final manual = _gap().withDesignCapacity(
        DesignCapacity(mah: 5000, source: DesignCapacitySource.manual));
    final (h, _, context) = await app(tester, _android(), manual);

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    final s = read(h, tester);
    expect(s.designCapacityMah, 5000);
    expect(s.designCapacitySource, DesignCapacitySource.manual);
    expect(h.backend.where('POST', '/api/v1/devices'), isEmpty);
  });

  testWidgets('a known catalog capacity is left alone', (tester) async {
    final known = AppHarness.defaultSettings(HarnessPlatform.android);
    final (h, _, context) = await app(tester, _android(), known);

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    expect(read(h, tester).designCapacityMah, 4575);
    expect(h.backend.where('POST', '/api/v1/devices'), isEmpty);
  });

  testWidgets(
      'a model no database knows stays unknown: no number from the charge '
      'counter, no registration, nothing thrown', (tester) async {
    final fake = _android(id: 'Unlisted-1');
    final (h, _, context) = await app(tester, fake, _gap(id: 'Unlisted-1'));
    h.backend.routes['GET /api/v1/devices/specifications/Unlisted-1'] =
        (_) => FakeBackend.error(404, 'device_specification_unknown');

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    final s = read(h, tester);
    expect(s.designCapacity.isKnown, isFalse);
    expect(s.designCapacityMah, 0);
    expect(s.designCapacitySource, DesignCapacitySource.unknown);
    expect(h.backend.where('POST', '/api/v1/devices'), isEmpty);
    // The estimate exists, separately.
    final estimate =
        await h.container(tester).read(collectorProvider).fullChargeCapacity();
    expect(estimate.mah, closeTo(3600, 0.01));
  });

  testWidgets('an unreachable backend changes nothing and is not an error',
      (tester) async {
    final (h, _, context) =
        await app(tester, _android(id: 'AcmeZ9'), _gap(id: 'AcmeZ9'));
    h.backend.routes['GET /api/v1/devices/specifications/AcmeZ9'] =
        (_) => throw Exception('offline');

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    expect(read(h, tester).designCapacity.isKnown, isFalse);
    expect(h.backend.where('POST', '/api/v1/devices'), isEmpty);
  });

  testWidgets('a model only the backend catalog knows: backendDeviceDatabase',
      (tester) async {
    final (h, _, context) =
        await app(tester, _android(id: 'AcmeZ9'), _gap(id: 'AcmeZ9'));
    h.backend.routes['GET /api/v1/devices/specifications/AcmeZ9'] =
        (_) => FakeBackend.json({
              'manufacturer': 'Acme',
              'model': 'Z9',
              'modelIdentifier': 'AcmeZ9',
              'designCapacityMah': 4400,
              'designCapacityWh': 17,
              'nominalVoltage': 3.86,
              'catalogVersion': '2026.10',
            });

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    final s = read(h, tester);
    expect(s.designCapacityMah, 4400);
    expect(s.designCapacityWh, 17);
    expect(s.designCapacitySource, DesignCapacitySource.backendDeviceDatabase);
    final body = h.backend.where('POST', '/api/v1/devices').last.body!;
    expect(body['designCapacitySource'], 'backendDeviceDatabase');
  });

  testWidgets('before the first setup finished it does nothing',
      (tester) async {
    final (h, _, context) =
        await app(tester, _android(), _gap(onboarded: false));

    await resolveMissingDesignCapacity(context);
    await tester.pump();

    expect(read(h, tester).designCapacity.isKnown, isFalse);
    expect(h.backend.where('POST', '/api/v1/devices'), isEmpty);
  });
}
