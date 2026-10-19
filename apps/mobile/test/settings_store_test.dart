import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/settings/settings.dart';

void main() {
  test(
      'every setting survives a restart (save, then load from the same storage)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final all = Settings(
      currency: 'EUR',
      currencySource: SettingSource.manual,
      countryCode: 'DE',
      regionSource: SettingSource.manual,
      pricePerKwh: 0.31,
      priceMode: ElectricityPriceMode.manual,
      manualPricePerKwh: 0.31,
      autoPrice: AutoPrice(
          pricePerKwh: 0.36,
          currency: 'EUR',
          countryCode: 'DE',
          period: '2026-S1',
          source: 'eurostat',
          updatedAt: DateTime(2026, 10, 13, 9),
          stale: true),
      designCapacityWh: 12.7,
      designCapacitySource: DesignCapacitySource.localDeviceDatabase,
      deviceModel: 'iPhone 15 Pro',
      deviceModelIdentifier: 'iPhone16,1',
      efficiency: 0.9,
      designCapacityMah: 4800,
      nominalVoltage: 3.7,
      binaryUnits: true,
      notifyMobileThreshold: true,
      mobileThresholdBytes: 7000000000,
      notifyChargingDone: true,
      notifyWeeklyEnergy: true,
      notifyAboveAverage: true,
      dataCollection: false,
      onboarded: true,
      theme: AppTheme.dark,
      cloudSync: true,
    );
    await SettingsStore(prefs).save(all);

    // A new store over the same storage is what the next app launch sees.
    final loaded = SettingsStore(prefs).load();
    expect(loaded.currency, 'EUR');
    expect(loaded.currencySource, SettingSource.manual);
    expect(loaded.countryCode, 'DE');
    expect(loaded.regionSource, SettingSource.manual);
    expect(loaded.pricePerKwh, 0.31);
    expect(loaded.priceMode, ElectricityPriceMode.manual);
    expect(loaded.manualPricePerKwh, 0.31);
    expect(loaded.autoPrice!.pricePerKwh, 0.36);
    expect(loaded.autoPrice!.period, '2026-S1');
    expect(loaded.autoPrice!.updatedAt, DateTime(2026, 10, 13, 9));
    expect(loaded.autoPrice!.stale, isTrue);
    expect(loaded.designCapacityWh, 12.7);
    expect(
        loaded.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    expect(loaded.deviceModel, 'iPhone 15 Pro');
    expect(loaded.deviceModelIdentifier, 'iPhone16,1');
    expect(loaded.efficiency, 0.9);
    expect(loaded.designCapacityMah, 4800);
    expect(loaded.nominalVoltage, 3.7);
    expect(loaded.binaryUnits, isTrue);
    expect(loaded.notifyMobileThreshold, isTrue);
    expect(loaded.mobileThresholdBytes, 7000000000);
    expect(loaded.notifyChargingDone, isTrue);
    expect(loaded.notifyWeeklyEnergy, isTrue);
    expect(loaded.notifyAboveAverage, isTrue);
    expect(loaded.dataCollection, isFalse);
    expect(loaded.onboarded, isTrue);
    expect(loaded.theme, AppTheme.dark);
    expect(loaded.cloudSync, isTrue,
        reason: 'was never written to storage before the fix');
  });

  group('the design capacity keys', () {
    Future<SharedPreferences> prefsWith(Map<String, Object> v) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(v);
      return SharedPreferences.getInstance();
    }

    test('save() writes wb.designCapacity* and none of the old keys', () async {
      final prefs = await prefsWith({
        // A build from before the split left these behind.
        'wb.batteryCapacityMah': 3988.0,
        'wb.batteryCapacityWh': 15.3,
        'wb.capacitySource': 'system',
      });
      await SettingsStore(prefs).save(const Settings(
          designCapacityMah: 3274,
          designCapacityWh: 12.7,
          designCapacitySource: DesignCapacitySource.localDeviceDatabase));
      expect(prefs.getDouble('wb.designCapacityMah'), 3274);
      expect(prefs.getDouble('wb.designCapacityWh'), 12.7);
      expect(prefs.getString('wb.designCapacitySource'), 'localDeviceDatabase');
      expect(prefs.containsKey('wb.batteryCapacityMah'), isFalse);
      expect(prefs.containsKey('wb.batteryCapacityWh'), isFalse);
      expect(prefs.containsKey('wb.capacitySource'), isFalse);
      final loaded = SettingsStore(prefs).load();
      expect(loaded.designCapacityMah, 3274);
      expect(loaded.designCapacitySource,
          DesignCapacitySource.localDeviceDatabase);
    });

    test('every source is stored under its own name and read back', () async {
      for (final source in DesignCapacitySource.values) {
        final prefs = await prefsWith({});
        final known = source != DesignCapacitySource.unknown;
        await SettingsStore(prefs).save(Settings(
            designCapacityMah: known ? 4000 : 0, designCapacitySource: source));
        expect(prefs.getString('wb.designCapacitySource'), source.name);
        expect(SettingsStore(prefs).load().designCapacitySource, source);
      }
    });

    test('a legacy charge-counter reading is not loaded as a design capacity',
        () async {
      for (final source in ['system', 'estimated']) {
        final prefs = await prefsWith({
          'wb.batteryCapacityMah': 4480.0,
          'wb.capacitySource': source,
        });
        final loaded = SettingsStore(prefs).load();
        expect(loaded.designCapacityMah, 0, reason: source);
        expect(loaded.designCapacitySource, DesignCapacitySource.unknown,
            reason: source);
        expect(loaded.designCapacity, DesignCapacity.unknown, reason: source);
        // Without a design capacity the calculator has no basis at all.
        expect(loaded.energyCalc().canEstimateFromPercent, isFalse,
            reason: source);
      }
    });

    test('the legacy catalog sources are renamed, their numbers kept',
        () async {
      final local = SettingsStore(await prefsWith({
        'wb.batteryCapacityMah': 3274.0,
        'wb.batteryCapacityWh': 12.7,
        'wb.capacitySource': 'localDatabase',
      }))
          .load();
      expect(
          local.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect([local.designCapacityMah, local.designCapacityWh], [3274, 12.7]);
      final backend = SettingsStore(await prefsWith({
        'wb.batteryCapacityMah': 4100.0,
        'wb.capacitySource': 'backendDatabase',
      }))
          .load();
      expect(backend.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      expect(backend.designCapacityMah, 4100);
    });
  });

  test('cloud sync is off by default (local-first)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(SettingsStore(prefs).load().cloudSync, isFalse);
  });

  group('the cloud-sync switch is a view; the consent lives in the ledger', () {
    test(
        'the value of wb.cloudSync at construction is kept as the legacy consent',
        () async {
      SharedPreferences.setMockInitialValues({'wb.cloudSync': true});
      final prefs = await SharedPreferences.getInstance();
      final store = SettingsStore(prefs);
      expect(store.legacyCloudSync, isTrue);
      // A later save writes a view over the key; the legacy value read at start stays.
      await store.save(const Settings(cloudSync: false));
      expect(store.legacyCloudSync, isTrue);
      expect(SettingsStore(prefs).legacyCloudSync, isFalse,
          reason: 'a store created afterwards sees what was written');
    });

    test('never stored: null, and the view is off', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SettingsStore(prefs);
      expect(store.legacyCloudSync, isNull);
      expect(store.load().cloudSync, isFalse);
    });

    test('a damaged value reads as off, not on', () async {
      SharedPreferences.setMockInitialValues({'wb.cloudSync': 'yes'});
      final prefs = await SharedPreferences.getInstance();
      final store = SettingsStore(prefs);
      expect(store.load().cloudSync, isFalse);
    });
  });

  group('damaged preferences never stop the app from starting', () {
    Future<SharedPreferences> prefsWith(Map<String, Object> v) async {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(v);
      return SharedPreferences.getInstance();
    }

    test('a value of the wrong type is ignored, the valid ones are still read',
        () async {
      for (final bad in <Map<String, Object>>[
        {'wb.pricePerKwh': 'abc'},
        {'wb.pricePerKwh': 5},
        {'wb.onboarded': 'yes'},
        {'wb.mobileThresholdBytes': 1.5},
        {'wb.currency': 5},
        {'wb.cloudSync': 1},
        {'wb.theme': 3},
        {'wb.sentNotifications': 'x'},
        {'wb.designCapacityMah': 'abc'},
        {'wb.designCapacitySource': 4},
        {'wb.batteryCapacityMah': 'abc', 'wb.capacitySource': 4},
      ]) {
        final p = await prefsWith({...bad, 'wb.efficiency': 0.9});
        late SettingsStore store;
        late Settings s;
        expect(() {
          store = SettingsStore(p);
          s = store.load();
          store.sentNotifications;
        }, returnsNormally, reason: '$bad');
        expect(s.efficiency, 0.9, reason: '$bad');
        expect(store.legacyCloudSync, isNull, reason: 'not a bool: absent');
      }
    });

    test('a stored automatic price that is not a plausible number is dropped',
        () async {
      for (final bad in <double>[double.nan, -2, 0, 1e9, double.infinity]) {
        final p = await prefsWith({
          'wb.currency': 'PLN',
          'wb.autoPrice.value': bad,
          'wb.autoPrice.currency': 'PLN',
          'wb.autoPrice.country': 'PL',
          'wb.autoPrice.period': '2026-S1',
          'wb.autoPrice.source': 'eurostat',
          'wb.autoPrice.updatedMs': 1760346000000,
        });
        final s = SettingsStore(p).load();
        expect(s.autoPrice, isNull, reason: '$bad');
        final effective = s.withAutomaticPrice();
        expect(effective.pricePerKwh, 0, reason: '$bad');
        expect(effective.energyCalc, returnsNormally);
      }
    });

    test('a plausible automatic price is kept', () async {
      final p = await prefsWith({
        'wb.currency': 'PLN',
        'wb.autoPrice.value': 1.15,
        'wb.autoPrice.currency': 'PLN',
        'wb.autoPrice.updatedMs': 1760346000000,
      });
      expect(SettingsStore(p).load().autoPrice!.pricePerKwh, 1.15);
    });
  });
}
