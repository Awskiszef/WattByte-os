import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/setup/device_specification.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte/sync/daily_aggregate.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/sync_service.dart';

import 'support/fake_backend.dart';
import 'sync_support.dart';

/// The upload path of `SyncService` for ONE account, against a scripted API.
/// Ownership across accounts: test/sync_ownership_test.dart. Schedule and loops:
/// test/sync_frequency_test.dart. Failure table: test/retry_policy_test.dart.
void main() {
  late SyncRig rig;

  setUp(() async => rig = await SyncRig.create());
  tearDown(() => rig.close());

  Future<void> enableHistory() => rig.sync.enable(SyncScope.history);

  test(
      'an account that did not enable sync uploads NOTHING, whatever is queued',
      () async {
    await rig.queueDays(['2026-10-11', '2026-10-12']);
    for (final run in [rig.sync.syncNow, rig.sync.syncIfDue]) {
      final o = await run();
      expect(o.status, SyncStatus.idle);
      expect(o.skip, SyncSkip.notEnabled);
    }
    expect(rig.backend.requests, isEmpty,
        reason: 'no device registration and no upload without the opt-in');
    expect(await rig.receiptsOf('user-a'), isEmpty);
  });

  test('uploads queued days, registers the device once, writes receipts',
      () async {
    await rig.queueDays(['2026-10-11', '2026-10-12']);
    await enableHistory();
    final o = await rig.sync.syncNow();
    expect(o.status, SyncStatus.synced);
    expect(o.uploaded, 2);

    final reg = rig.backend.where('POST', '/api/v1/devices');
    expect(reg, hasLength(1));
    expect(reg.single.body!.keys.toSet(), {
      'installationId',
      'platform',
      'model',
      'modelIdentifier',
      ...FakeBackend.batteryKeys,
    });
    expect(reg.single.body!['model'], isNull,
        reason:
            'the sync path sends no model; no hardware id or fingerprint ever');
    expect(reg.single.body!['modelIdentifier'], isNull);
    for (final key in FakeBackend.batteryKeys) {
      expect(reg.single.body![key], isNull,
          reason: '$key: the sync path knows no battery facts; null keeps '
              'what the setup registered');
    }
    expect(reg.single.body!['platform'], 'android');
    expect((reg.single.body!['installationId'] as String).length, 32);

    final up = rig.backend.where('POST', '/api/v1/usage/sync').single;
    expect(up.bearer, 'access-user-a');
    expect(up.body!['installationId'], reg.single.body!['installationId']);
    expect((up.body!['days'] as List).map((d) => d['date']),
        ['2026-10-11', '2026-10-12']);

    final receipts = await rig.receiptsOf('user-a');
    expect(receipts.map((r) => r.day), ['2026-10-11', '2026-10-12']);
    expect(receipts.every((r) => r.fingerprint.length == 64), isTrue);

    // Second pass: nothing due, no new request, no new device registration.
    rig.backend.requests.clear();
    final again = await rig.sync.syncNow();
    expect(again.status, SyncStatus.idle);
    expect(again.skip, SyncSkip.nothingDue);
    expect(rig.backend.requests, isEmpty);
  });

  test('a changed day uploads again, an unchanged one never does', () async {
    await rig.queueDays(['2026-10-11', '2026-10-12']);
    await enableHistory();
    await rig.sync.syncNow();
    rig.backend.requests.clear();

    // Re-queueing the identical aggregate changes nothing.
    await rig.queue(agg('2026-10-12'));
    expect((await rig.sync.syncNow()).skip, SyncSkip.nothingDue);
    expect(rig.backend.requests, isEmpty);

    // A different aggregate for one day: exactly that day goes up, replacing it.
    await rig.queue(agg('2026-10-12', mobile: 999));
    final o = await rig.sync.syncNow();
    expect(o.uploaded, 1);
    final sent = rig.backend.where('POST', '/api/v1/usage/sync').single;
    final days = sent.body!['days'] as List;
    expect(days.single['date'], '2026-10-12');
    expect(days.single['mobileBytes'], 999);
    expect(rig.cloud.rowsByUser['user-a']!['2026-10-12']!['mobileBytes'], 999);
    expect(rig.cloud.rowsByUser['user-a'], hasLength(2),
        reason: 'one row per day, replaced not duplicated');
  });

  test('the fingerprint is stable: it only changes with the payload', () {
    final a = agg('2026-10-12');
    expect(a.fingerprint, agg('2026-10-12').fingerprint);
    expect(a.fingerprint, isNot(agg('2026-10-12', mobile: 101).fingerprint));
    expect(a.fingerprint, isNot(agg('2026-10-13').fingerprint));
    // survives the JSON round trip through SQLite
    final roundTripped = DailyAggregate.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    expect(roundTripped.fingerprint, a.fingerprint);
    expect(roundTripped, a);
  });

  group('registerDevice: design capacity and estimated full charge', () {
    /// A phone model with the given design capacity.
    DeviceSpecification model(DesignCapacity design) => DeviceSpecification(
          manufacturer: 'Apple',
          model: 'iPhone 15 Pro',
          modelIdentifier: 'iPhone16,1',
          design: design,
        );

    /// The body of the one device registration the rig's backend recorded.
    Map<String, dynamic> sent() =>
        rig.backend.where('POST', '/api/v1/devices').single.body!;

    /// The estimate of a reading that holds [percent] of a [fullMah] battery
    /// (the Android charge counter is the charge STORED at that level).
    EstimatedFullChargeCapacity reading(int percent,
            {double fullMah = 3600, double? fullWh}) =>
        FullChargeCapacityEstimator.estimate(
          chargeUah: fullMah * percent * 10,
          energyNwh: fullWh == null ? null : fullWh * percent * 1e7,
          level: percent,
          measuredAt: rig.now,
        );

    void expectNoRetiredKeys(Map<String, dynamic> body) {
      for (final key in FakeBackend.retiredBatteryKeys) {
        expect(body.containsKey(key), isFalse,
            reason: '$key is gone from the API: it could not say whether a '
                'number was nominal or measured');
      }
    }

    void expectNoEstimate(Map<String, dynamic> body) {
      for (final key in FakeBackend.estimateKeys) {
        expect(body[key], isNull,
            reason: '$key: no estimate means null (never source "unknown", '
                'which would erase the estimate the server stores)');
      }
    }

    for (final source in [
      DesignCapacitySource.localDeviceDatabase,
      DesignCapacitySource.backendDeviceDatabase,
      DesignCapacitySource.manual,
    ]) {
      test('a ${source.name} design capacity is sent as the design group',
          () async {
        await rig.sync.registerDevice(
            model(DesignCapacity(mah: 3274, wh: 12.7, source: source)));
        final body = sent();
        expect(body['model'], 'iPhone 15 Pro');
        expect(body['modelIdentifier'], 'iPhone16,1');
        expect(body['platform'], 'android');
        expect(body['designCapacityMah'], 3274);
        expect(body['designCapacityWh'], 12.7);
        expect(body['designCapacitySource'], source.name);
        expectNoEstimate(body);
        expectNoRetiredKeys(body);
        // The server stored exactly that and nothing as an estimate.
        final stored = rig.cloud.deviceTable.rowsOf('user-a').single;
        expect(stored['designCapacityMah'], 3274);
        expect(stored['designCapacitySource'], source.name);
        expect(stored['estimatedFullChargeCapacityMah'], isNull);
      });
    }

    test('a design capacity without Wh sends null Wh, not 0', () async {
      await rig.sync.registerDevice(model(DesignCapacity(
          mah: 4575, source: DesignCapacitySource.localDeviceDatabase)));
      final body = sent();
      expect(body['designCapacityMah'], 4575);
      expect(body['designCapacityWh'], isNull);
      expect(body['designCapacitySource'], 'localDeviceDatabase');
    });

    test('an unknown design is sent as source unknown with NULL numbers',
        () async {
      await rig.sync.registerDevice(const DeviceSpecification(
          manufacturer: 'Acme', model: 'Z1', modelIdentifier: 'Z1-model'));
      final body = sent();
      expect(body['designCapacitySource'], 'unknown');
      expect(body['designCapacityMah'], isNull);
      expect(body['designCapacityWh'], isNull);
      expect(body['modelIdentifier'], 'Z1-model',
          reason: 'the model is still registered');
      expectNoEstimate(body);
      expectNoRetiredKeys(body);
      expect(
          rig.cloud.deviceTable.rowsOf('user-a').single['designCapacitySource'],
          'unknown');
    });

    test('a design that could not be normalised is unknown, never a number',
        () async {
      // The constructor turns unusable input into DesignCapacity.unknown, so
      // nothing but a catalog or manual figure can reach the payload.
      for (final design in [
        DesignCapacity(mah: 0, source: DesignCapacitySource.manual),
        DesignCapacity(mah: -4000, source: DesignCapacitySource.manual),
        DesignCapacity(mah: double.nan, source: DesignCapacitySource.manual),
        DesignCapacity(
            mah: double.infinity,
            source: DesignCapacitySource.localDeviceDatabase),
        DesignCapacity(mah: 31000, source: DesignCapacitySource.manual),
        DesignCapacity(mah: 4000, source: DesignCapacitySource.unknown),
      ]) {
        rig.backend.requests.clear();
        await rig.sync.registerDevice(model(design));
        final body = sent();
        expect(body['designCapacitySource'], 'unknown', reason: '$design');
        expect(body['designCapacityMah'], isNull, reason: '$design');
        expect(body['designCapacityWh'], isNull, reason: '$design');
      }
    });

    for (final (level, confidence) in [
      (100, 'high'),
      (95, 'high'),
      (80, 'medium'),
      (50, 'low'),
    ]) {
      test(
          'an estimate from a reading at $level % is sent as the estimate '
          'group with confidence $confidence', () async {
        await rig.sync.registerDevice(
            model(DesignCapacity(
                mah: 4000, wh: 15.4, source: DesignCapacitySource.manual)),
            fullCharge: reading(level, fullWh: 13.86));
        final body = sent();
        expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
        expect(body['estimatedFullChargeCapacityWh'], closeTo(13.86, 1e-9));
        expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
        expect(body['fullChargeCapacityConfidence'], confidence);
        // The design group next to it is untouched by the estimate.
        expect(body['designCapacityMah'], 4000);
        expect(body['designCapacityWh'], 15.4);
        expect(body['designCapacitySource'], 'manual');
        expectNoRetiredKeys(body);
        final stored = rig.cloud.deviceTable.rowsOf('user-a').single;
        expect(stored['fullChargeCapacityConfidence'], confidence);
        expect(stored['designCapacityMah'], 4000);
      });
    }

    test('an estimate without Wh (no valid energy counter) sends null Wh',
        () async {
      await rig.sync.registerDevice(
          model(DesignCapacity(
              mah: 4000, source: DesignCapacitySource.localDeviceDatabase)),
          fullCharge: reading(100));
      final body = sent();
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
      expect(body['estimatedFullChargeCapacityWh'], isNull);
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'high');
    });

    test('NO estimate: all four estimate fields are null, source included',
        () async {
      for (final fullCharge in <EstimatedFullChargeCapacity?>[
        null,
        EstimatedFullChargeCapacity.unavailable,
        // Whatever was assembled by hand: without a finite positive mAh, a
        // known source and a confidence there is no estimate to send.
        const EstimatedFullChargeCapacity(
            mah: 3600,
            source: FullChargeCapacitySource.unknown,
            confidence: FullChargeCapacityConfidence.high),
        const EstimatedFullChargeCapacity(
            mah: 3600, source: FullChargeCapacitySource.androidChargeCounter),
        const EstimatedFullChargeCapacity(
            mah: double.nan,
            source: FullChargeCapacitySource.androidChargeCounter,
            confidence: FullChargeCapacityConfidence.high),
        const EstimatedFullChargeCapacity(
            mah: double.infinity,
            source: FullChargeCapacitySource.androidChargeCounter,
            confidence: FullChargeCapacityConfidence.high),
        const EstimatedFullChargeCapacity(
            mah: -3600,
            source: FullChargeCapacitySource.androidChargeCounter,
            confidence: FullChargeCapacityConfidence.high),
        // A reading the estimator refuses: unsupported, zero, negative,
        // NaN / Infinity counter; level 0, too low, NaN.
        FullChargeCapacityEstimator.estimate(chargeUah: null, level: 100),
        FullChargeCapacityEstimator.estimate(chargeUah: 0, level: 100),
        FullChargeCapacityEstimator.estimate(chargeUah: -1, level: 100),
        FullChargeCapacityEstimator.estimate(chargeUah: double.nan, level: 100),
        FullChargeCapacityEstimator.estimate(
            chargeUah: double.infinity, level: 100),
        FullChargeCapacityEstimator.estimate(chargeUah: 1800000, level: 0),
        FullChargeCapacityEstimator.estimate(chargeUah: 1000000, level: 30),
        FullChargeCapacityEstimator.estimate(
            chargeUah: 1800000, level: double.nan),
      ]) {
        rig.backend.requests.clear();
        await rig.sync.registerDevice(
            model(DesignCapacity(
                mah: 4000, source: DesignCapacitySource.localDeviceDatabase)),
            fullCharge: fullCharge);
        final body = sent();
        expectNoEstimate(body);
        expect(body['fullChargeCapacitySource'], isNull,
            reason: '$fullCharge: never "unknown", which erases the estimate');
        expect(body['designCapacityMah'], 4000,
            reason: 'the design group is sent either way');
      }
    });

    test('NaN and Infinity never reach the wire, whatever the field', () async {
      // jsonEncode refuses both, so a leak would make the request throw.
      await rig.sync.registerDevice(
          model(DesignCapacity(
              mah: 4000,
              wh: double.nan,
              source: DesignCapacitySource.localDeviceDatabase)),
          fullCharge: FullChargeCapacityEstimator.estimate(
              chargeUah: 3600000, energyNwh: double.infinity, level: 100));
      final body = sent();
      expect(body['designCapacityWh'], isNull,
          reason: 'a Wh that is not a number is dropped, the mAh stays');
      expect(body['designCapacityMah'], 4000);
      expect(body['estimatedFullChargeCapacityWh'], isNull);
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
    });

    test('every design source reaches the wire under its own name', () async {
      for (final source in DesignCapacitySource.values
          .where((s) => s != DesignCapacitySource.unknown)) {
        final r = await SyncRig.create();
        addTearDown(r.close);
        await r.signIn('user-a');
        await r.sync
            .registerDevice(model(DesignCapacity(mah: 4000, source: source)));
        final body = r.backend.where('POST', '/api/v1/devices').single.body!;
        expect(body['designCapacitySource'], source.name, reason: source.name);
        expect(body['designCapacityMah'], 4000, reason: source.name);
      }
    });

    test(
        'an implausible estimate Wh is left out; the registration still goes '
        'out with the mAh', () async {
      for (final wh in [double.nan, double.infinity, -3.0, 0.0, 5000.0]) {
        final r = await SyncRig.create();
        addTearDown(r.close);
        await r.signIn('user-a');
        await r.sync.registerDevice(
            model(DesignCapacity(
                mah: 4000, source: DesignCapacitySource.localDeviceDatabase)),
            fullCharge: EstimatedFullChargeCapacity(
                mah: 3600,
                wh: wh,
                source: FullChargeCapacitySource.androidChargeCounter,
                confidence: FullChargeCapacityConfidence.high,
                level: 100));
        final body = r.backend.where('POST', '/api/v1/devices').single.body!;
        expect(body['estimatedFullChargeCapacityWh'], isNull, reason: '$wh');
        expect(body['estimatedFullChargeCapacityMah'], 3600, reason: '$wh');
        expect(body['fullChargeCapacityConfidence'], 'high', reason: '$wh');
      }
    });

    test(
        'an estimate NEVER shows up in a design field and a design capacity '
        'never in an estimate field (raw JSON body)', () async {
      // Distinct numbers everywhere, so any crossing is visible.
      const designMah = 4000.0;
      const designWh = 15.4;
      final estimate = reading(100, fullMah: 3411, fullWh: 13.1);
      expect(estimate.mah, closeTo(3411, 1e-6));
      await rig.sync.registerDevice(
          model(DesignCapacity(
              mah: designMah,
              wh: designWh,
              source: DesignCapacitySource.localDeviceDatabase)),
          fullCharge: estimate);
      final body = sent();
      for (final key in FakeBackend.designKeys) {
        final v = body[key];
        expect(v, isNot(closeTo(estimate.mah!, 1e-6)), reason: key);
        expect(v, isNot(closeTo(estimate.wh!, 1e-6)), reason: key);
      }
      for (final key in FakeBackend.estimateKeys) {
        final v = body[key];
        expect(v, isNot(designMah), reason: key);
        expect(v, isNot(designWh), reason: key);
      }
      expect(body['designCapacityMah'], designMah);
      expect(body['designCapacityWh'], designWh);
      expect(body['estimatedFullChargeCapacityMah'], closeTo(3411, 1e-6));
      expect(body['estimatedFullChargeCapacityWh'], closeTo(13.1, 1e-9));
      // The design source says where a catalog or the user got the figure
      // from; a charge counter is not among the values it can take.
      expect(body['designCapacitySource'], isNot(contains('hargeCounter')));
      expect(body['designCapacitySource'], isNot(contains('estimate')));
    });

    test(
        'Android charge counter != design capacity: a reliable reading on a '
        'model no catalog knows stays an estimate, the design stays unknown',
        () async {
      // 100 % full, 4321 mAh stored: the best reading there is.
      final estimate = FullChargeCapacityEstimator.estimate(
          chargeUah: 4321000, level: 100, measuredAt: rig.now);
      expect(estimate.confidence, FullChargeCapacityConfidence.high);
      expect(estimate.mah, 4321);
      await rig.sync.registerDevice(
          const DeviceSpecification(
              manufacturer: 'Acme', model: 'Z1', modelIdentifier: 'Z1-model'),
          fullCharge: estimate);
      final body = sent();
      expect(body['designCapacityMah'], isNull);
      expect(body['designCapacityWh'], isNull);
      expect(body['designCapacitySource'], 'unknown');
      expect(body['estimatedFullChargeCapacityMah'], 4321);
      expect(body['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(body['fullChargeCapacityConfidence'], 'high');
      // 4321 occurs exactly once on the wire, in the estimate field.
      final holders = [
        for (final e in body.entries)
          if (e.value == 4321) e.key
      ];
      expect(holders, ['estimatedFullChargeCapacityMah']);
      final stored = rig.cloud.deviceTable.rowsOf('user-a').single;
      expect(stored['designCapacityMah'], isNull);
      expect(stored['designCapacitySource'], 'unknown');
      expect(stored['estimatedFullChargeCapacityMah'], 4321);
    });

    test(
        'the server keeps the estimate of an earlier registration when a '
        'later one has none (null source, never "unknown")', () async {
      final design = model(DesignCapacity(
          mah: 4000, source: DesignCapacitySource.localDeviceDatabase));
      await rig.sync.registerDevice(design, fullCharge: reading(100));
      await rig.sync.registerDevice(design); // no estimate this time
      final stored = rig.cloud.deviceTable.rowsOf('user-a').single;
      expect(stored['fullChargeCapacitySource'], 'androidChargeCounter');
      expect(stored['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
      expect(stored['fullChargeCapacityConfidence'], 'high');
      expect(stored['designCapacityMah'], 4000);
    });

    test(
        'a later registration with a new design replaces the design group '
        'as a whole and leaves the estimate alone', () async {
      await rig.sync.registerDevice(
          model(DesignCapacity(
              mah: 4000, wh: 15.4, source: DesignCapacitySource.manual)),
          fullCharge: reading(100));
      await rig.sync.registerDevice(model(DesignCapacity(
          mah: 4200, source: DesignCapacitySource.localDeviceDatabase)));
      final stored = rig.cloud.deviceTable.rowsOf('user-a').single;
      expect(stored['designCapacityMah'], 4200);
      expect(stored['designCapacityWh'], isNull,
          reason: 'a group is replaced with its nulls, no stale Wh survives');
      expect(stored['designCapacitySource'], 'localDeviceDatabase');
      expect(stored['estimatedFullChargeCapacityMah'], closeTo(3600, 1e-6));
    });

    test('the registration of a device is stored once, whatever follows',
        () async {
      await rig.sync.registerDevice(
          model(DesignCapacity(
              mah: 3274,
              wh: 12.7,
              source: DesignCapacitySource.localDeviceDatabase)),
          fullCharge: reading(100));
      // The later sync re-uses the stored server id instead of registering again.
      await rig.queueDays(['2026-10-11']);
      await enableHistory();
      await rig.sync.syncNow();
      expect(rig.backend.where('POST', '/api/v1/devices'), hasLength(1));
    });
  });

  test('installation id is random, generated once and stable', () async {
    final a = await rig.sync.installationId();
    expect(await rig.sync.installationId(), a);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
    final other = await SyncRig.create();
    addTearDown(other.close);
    expect(await other.sync.installationId(), isNot(a));
  });

  test('registerDevice is a no-op when nobody is signed in', () async {
    await rig.signOut();
    await rig.sync.registerDevice(
        DeviceSpecification(
            manufacturer: 'x',
            model: 'y',
            design:
                DesignCapacity(mah: 1000, source: DesignCapacitySource.manual)),
        fullCharge: FullChargeCapacityEstimator.estimate(
            chargeUah: 3600000, level: 100));
    expect(rig.backend.requests, isEmpty);
  });

  test('signed out: authRequired, no request', () async {
    await rig.signOut();
    expect((await rig.sync.syncNow()).status, SyncStatus.authRequired);
    expect((await rig.sync.syncIfDue()).status, SyncStatus.authRequired);
    expect(rig.backend.requests, isEmpty);
  });

  test('enable needs a signed-in account and an explicit scope', () async {
    await rig.signOut();
    await expectLater(
        rig.sync.enable(SyncScope.history), throwsA(isA<AuthException>()));
    await rig.signIn('user-a');
    final st = await rig.sync.enable(SyncScope.fromNow);
    expect(st.enabled, isTrue);
    expect(st.scope, SyncScope.fromNow);
    expect(st.enabledOn, '2026-10-13');
  });

  test(
      'a server that ignores a date does not get a receipt, nor an endless loop',
      () async {
    await rig.queueDays(['2026-10-11', '2026-10-12']);
    await enableHistory();
    rig.backend.routes['POST /api/v1/usage/sync'] = (r) => FakeBackend.json({
          'accepted': 1,
          'dates': ['2026-10-11'],
        });
    final o = await rig.sync.syncNow();
    expect(o.uploaded, 1);
    expect(o.failed, 1);
    expect((await rig.receiptsOf('user-a')).map((r) => r.day), ['2026-10-11']);
    final key = await rig.keyOf('user-a');
    expect((await rig.db.rejections(key))['2026-10-12']!.error, 'not_accepted');
    rig.backend.requests.clear();
    expect((await rig.sync.syncNow()).skip, SyncSkip.nothingDue,
        reason: 'the same payload is not sent again');
    expect(rig.backend.requests, isEmpty);
  });

  test('days that break the contract are never sent', () async {
    await rig.queue(agg('2026-10-11', wh: 1e9));
    await rig.queue(agg('2026-10-12', cost: -1));
    await rig.queue(agg('2026-10-13', mobile: 20000000000000));
    expect(agg('2026-10-12', wh: double.nan).isWithinContract, isFalse);
    expect(agg('2026-10-12', wh: double.infinity).isWithinContract, isFalse);
    await enableHistory();
    final o = await rig.sync.syncNow();
    expect(o.status, SyncStatus.rejected);
    expect(o.failed, 3);
    expect(rig.backend.where('POST', '/api/v1/usage/sync'), isEmpty);
    final key = await rig.keyOf('user-a');
    expect((await rig.db.rejections(key)).values.map((r) => r.error).toSet(),
        {'invalid_local'});
    // Not retried on the next run either.
    expect((await rig.sync.syncNow()).skip, SyncSkip.nothingDue);
  });

  test('a long history goes up in bounded batches of at most 92 days',
      () async {
    final dates = [
      for (var i = 0; i < 200; i++)
        DateTime(2026, 3, 27)
            .add(Duration(days: i))
            .toIso8601String()
            .substring(0, 10)
    ];
    await rig.queueDays(dates);
    await enableHistory();
    final o = await rig.sync.syncNow();
    expect(o.status, SyncStatus.synced);
    expect(o.uploaded, 200);
    final sizes = rig.backend
        .where('POST', '/api/v1/usage/sync')
        .map((r) => (r.body!['days'] as List).length)
        .toList();
    expect(sizes, [92, 92, 16]);
    expect(sizes.every((n) => n <= 92), isTrue);
  });

  test('a run sends at most maxBatchesPerRun requests; the rest waits',
      () async {
    final dates = [
      for (var i = 0; i < 300; i++)
        DateTime(2025, 12, 1)
            .add(Duration(days: i))
            .toIso8601String()
            .substring(0, 10)
    ];
    await rig.queueDays(dates);
    await enableHistory();
    final limited = SyncService(
        db: rig.db,
        apis: rig.sync.apis,
        sessions: rig.sessions,
        platform: 'android',
        clock: () => rig.now,
        maxBatchesPerRun: 2);
    final o = await limited.syncNow();
    expect(o.uploaded, 184);
    expect(rig.backend.where('POST', '/api/v1/usage/sync'), hasLength(2));
    final rest = await limited.syncNow();
    expect(rest.uploaded, 116);
  });

  test('disabling while a long history is going up stops after the batch',
      () async {
    final dates = [
      for (var i = 0; i < 200; i++)
        DateTime(2026, 3, 27)
            .add(Duration(days: i))
            .toIso8601String()
            .substring(0, 10)
    ];
    await rig.queueDays(dates);
    await enableHistory();
    var calls = 0;
    rig.backend.routes['POST /api/v1/usage/sync'] = (r) {
      calls++;
      final days = (r.body!['days'] as List).cast<Map<String, dynamic>>();
      if (calls == 1) rig.sync.disable(); // the user flips the switch mid-run
      return FakeBackend.json({
        'accepted': days.length,
        'dates': days.map((d) => d['date']).toList()
      });
    };
    await rig.sync.syncNow();
    expect(calls, 1, reason: 'the second batch must not be sent');
    expect((await rig.sync.accountState())!.enabled, isFalse,
        reason: 'the finishing upload must not undo the switch');
    expect(await rig.db.receiptCount(await rig.keyOf('user-a')), 92);
  });

  test('concurrent syncNow calls share one run (single flight)', () async {
    await rig.queueDays(['2026-10-12']);
    await enableHistory();
    final results = await Future.wait([
      rig.sync.syncNow(),
      rig.sync.syncNow(),
      rig.sync.syncNow(),
    ]);
    expect(rig.backend.where('POST', '/api/v1/usage/sync'), hasLength(1));
    expect(results.map((o) => o.uploaded), [1, 1, 1]);
  });

  test('an automatic run during another run does not queue up behind it',
      () async {
    await rig.queueDays(['2026-10-12']);
    await enableHistory();
    final manual = rig.sync.syncNow();
    final auto = await rig.sync.syncIfDue();
    expect(auto.skip, SyncSkip.inProgress);
    expect((await manual).status, SyncStatus.synced);
  });

  test('the migration list creates the ledger tables (schema v5)', () {
    expect(WattByteDb.schemaVersion, 5);
    expect(WattByteDb.migrations[5]!.join(' '), contains('sync_receipts'));
    expect(WattByteDb.migrations[5]!.join(' '), contains('sync_rejections'));
    expect(WattByteDb.migrations[3]!.single, contains('next_retry_ms'));
  });
}
