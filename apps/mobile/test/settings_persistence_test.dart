import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/settings/settings.dart';

/// Persistence of every [Settings] field through [SettingsStore]: the regression
/// net for simulator bug 3 (`cloudSync` was never written, so sync silently
/// stopped after a restart) and for the whole class "a field is added to
/// `Settings` but not to `save`/`load`".
///
/// A "restart" is simulated twice: a new [SettingsStore] over the same
/// `SharedPreferences` instance, and (stronger) a brand new `SharedPreferences`
/// instance built from what the first one holds, which is what a process
/// restart reads from disk.
///
/// Legacy migration (`wb.*` keys written before the automatic setup) is covered
/// in `setup_flow_test.dart`; the cases here are the ones that file does not have.
void main() {
  Future<SharedPreferences> freshPrefs([Map<String, Object>? values]) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues(values ?? {});
    return SharedPreferences.getInstance();
  }

  /// What a process restart would find on disk.
  Map<String, Object> disk(SharedPreferences p) =>
      {for (final k in p.getKeys()) k: p.get(k)!};

  Future<SharedPreferences> restart(SharedPreferences p) => freshPrefs(disk(p));

  /// Every public field of [Settings] as plain values, for comparison.
  Map<String, Object?> describe(Settings s) => {
        'currency': s.currency,
        'currencySource': s.currencySource,
        'currencyOriginalSource': s.currencyOriginalSource,
        'countryCode': s.countryCode,
        'regionSource': s.regionSource,
        'regionDetection': s.regionDetection,
        'regionOriginalSource': s.regionOriginalSource,
        'pricePerKwh': s.pricePerKwh,
        'priceMode': s.priceMode,
        'manualPricePerKwh': s.manualPricePerKwh,
        'priceSource': s.priceSource,
        'priceOriginalSource': s.priceOriginalSource,
        'accountInSync':
            ([for (final g in s.accountInSync) g.name]..sort()).join(','),
        'autoPrice': s.autoPrice == null
            ? null
            : [
                s.autoPrice!.pricePerKwh,
                s.autoPrice!.currency,
                s.autoPrice!.countryCode,
                s.autoPrice!.period,
                s.autoPrice!.source,
                s.autoPrice!.updatedAt.millisecondsSinceEpoch,
                s.autoPrice!.stale,
              ],
        'efficiency': s.efficiency,
        'designCapacityMah': s.designCapacityMah,
        'designCapacityWh': s.designCapacityWh,
        'designCapacitySource': s.designCapacitySource,
        'deviceModel': s.deviceModel,
        'deviceModelIdentifier': s.deviceModelIdentifier,
        'nominalVoltage': s.nominalVoltage,
        'binaryUnits': s.binaryUnits,
        'notifyMobileThreshold': s.notifyMobileThreshold,
        'mobileThresholdBytes': s.mobileThresholdBytes,
        'notifyChargingDone': s.notifyChargingDone,
        'notifyWeeklyEnergy': s.notifyWeeklyEnergy,
        'notifyAboveAverage': s.notifyAboveAverage,
        'dataCollection': s.dataCollection,
        'onboarded': s.onboarded,
        'theme': s.theme,
        'cloudSync': s.cloudSync,
      };

  /// One change per field, each away from the default and valid (survives
  /// `sanitized()`), so a field that is not persisted shows up by name.
  final variants = <String, Settings Function(Settings)>{
    'currency': (s) => s.copyWith(currency: 'EUR'),
    'currencySource': (s) => s.copyWith(currencySource: SettingSource.manual),
    // An original source only exists next to an account value (`sanitized()`).
    'currencyOriginalSource': (s) => s.copyWith(
        currencySource: SettingSource.accountSynced,
        currencyOriginalSource: SettingSource.manual),
    'countryCode': (s) => s.copyWith(countryCode: 'DE'),
    'regionSource': (s) => s.copyWith(regionSource: SettingSource.manual),
    'regionDetection': (s) => s.copyWith(regionDetection: 'deviceLocale'),
    'regionOriginalSource': (s) => s.copyWith(
        regionSource: SettingSource.accountSynced,
        regionOriginalSource: SettingSource.detected),
    'pricePerKwh': (s) => s.copyWith(pricePerKwh: 0.31),
    'priceMode': (s) => s.copyWith(priceMode: ElectricityPriceMode.manual),
    'manualPricePerKwh': (s) => s.copyWith(manualPricePerKwh: 0.27),
    'priceSource': (s) => s.copyWith(priceSource: SettingSource.migratedManual),
    'priceOriginalSource': (s) => s.copyWith(
        priceSource: SettingSource.accountSynced,
        priceOriginalSource: SettingSource.migratedManual),
    'accountInSync': (s) =>
        s.copyWith(accountInSync: {SettingGroup.currency, SettingGroup.price}),
    'autoPrice': (s) => s.copyWith(
        autoPrice: AutoPrice(
            pricePerKwh: 0.36,
            currency: 'EUR',
            countryCode: 'DE',
            period: '2026-S1',
            source: 'eurostat',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1760346000000),
            stale: true)),
    'efficiency': (s) => s.copyWith(efficiency: 0.9),
    // The three design-capacity fields are one group that `sanitized()` keeps
    // coherent (a known source needs the mAh, the Wh needs the mAh, `unknown`
    // carries no numbers), so each variant is complete on its own.
    'designCapacityMah': (s) => s.copyWith(
        designCapacityMah: 4800,
        designCapacitySource: DesignCapacitySource.manual),
    'designCapacityWh': (s) => s.copyWith(
        designCapacityMah: 4800,
        designCapacityWh: 12.7,
        designCapacitySource: DesignCapacitySource.manual),
    'designCapacitySource': (s) => s.copyWith(
        designCapacityMah: 4800,
        designCapacitySource: DesignCapacitySource.backendDeviceDatabase),
    'deviceModel': (s) => s.copyWith(deviceModel: 'iPhone 15 Pro'),
    'deviceModelIdentifier': (s) =>
        s.copyWith(deviceModelIdentifier: 'iPhone16,1'),
    'nominalVoltage': (s) => s.copyWith(nominalVoltage: 3.7),
    'binaryUnits': (s) => s.copyWith(binaryUnits: true),
    'notifyMobileThreshold': (s) => s.copyWith(notifyMobileThreshold: true),
    'mobileThresholdBytes': (s) => s.copyWith(mobileThresholdBytes: 7000000000),
    'notifyChargingDone': (s) => s.copyWith(notifyChargingDone: true),
    'notifyWeeklyEnergy': (s) => s.copyWith(notifyWeeklyEnergy: true),
    'notifyAboveAverage': (s) => s.copyWith(notifyAboveAverage: true),
    'dataCollection': (s) => s.copyWith(dataCollection: false),
    'onboarded': (s) => s.copyWith(onboarded: true),
    'theme': (s) => s.copyWith(theme: AppTheme.dark),
    'cloudSync': (s) => s.copyWith(cloudSync: true),
  };

  group('every Settings field', () {
    test('the table above lists every field declared in class Settings', () {
      final source = File('lib/settings/settings.dart').readAsStringSync();
      final start = source.indexOf('class Settings {');
      final end = source.indexOf('bool get hasPrice', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final declared = RegExp(r'^\s+final\s+[\w<>?]+\s+(\w+);', multiLine: true)
          .allMatches(source.substring(start, end))
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, isNotEmpty);
      expect(variants.keys.toSet(), declared,
          reason: 'a field was added to or removed from Settings: add it to '
              '`variants` and `describe` so its persistence is tested');
      expect(describe(const Settings()).keys.toSet(), declared);
    });

    for (final name in variants.keys) {
      test('$name is written by save() and read back after a restart',
          () async {
        final change = variants[name]!;
        const base = Settings();
        final changed = change(base);
        expect(describe(changed)[name], isNot(equals(describe(base)[name])),
            reason: 'the variant must differ from the default');

        final p = await freshPrefs();
        await SettingsStore(p).save(base);
        final defaultDisk = disk(p);
        await SettingsStore(p).save(changed);
        expect(disk(p), isNot(equals(defaultDisk)),
            reason: 'saving a changed $name must change what is stored');

        // Same preferences instance, new store.
        expect(describe(SettingsStore(p).load()), describe(changed));
        // New preferences instance built from "disk".
        final reopened = await restart(p);
        expect(describe(SettingsStore(reopened).load()), describe(changed));
      });
    }

    test('all of them together survive a restart', () async {
      var all = const Settings();
      for (final change in variants.values) {
        all = change(all);
      }
      final p = await freshPrefs();
      await SettingsStore(p).save(all);
      final loaded = SettingsStore(await restart(p)).load();
      expect(describe(loaded), describe(all));
      expect(loaded.cloudSync, isTrue,
          reason: 'bug 3: cloudSync was never written to storage');
    });

    test('saving twice and reloading twice changes nothing (idempotent)',
        () async {
      var all = const Settings();
      for (final change in variants.values) {
        all = change(all);
      }
      final p = await freshPrefs();
      final store = SettingsStore(p);
      await store.save(all);
      final first = store.load();
      await store.save(first);
      final second = SettingsStore(await restart(p)).load();
      expect(describe(second), describe(all));
    });

    test('the defaults are what a fresh install gets, and they round-trip',
        () async {
      final p = await freshPrefs();
      final fresh = SettingsStore(p).load();
      expect(describe(fresh), describe(const Settings()));
      expect(fresh.cloudSync, isFalse, reason: 'local-first');
      expect(fresh.dataCollection, isTrue);
      expect(fresh.onboarded, isFalse);
      await SettingsStore(p).save(fresh);
      expect(describe(SettingsStore(await restart(p)).load()),
          describe(const Settings()));
    });

    test('clearing the automatic price removes its stored keys', () async {
      final p = await freshPrefs();
      final store = SettingsStore(p);
      await store.save(variants['autoPrice']!(const Settings()));
      expect(
          p.getKeys().where((k) => k.startsWith('wb.autoPrice.')), isNotEmpty);
      await store.save(const Settings());
      expect(p.getKeys().where((k) => k.startsWith('wb.autoPrice.')), isEmpty);
      expect(SettingsStore(await restart(p)).load().autoPrice, isNull);
    });
  });

  group('enums', () {
    test('every value of every enum round-trips by name', () async {
      for (final theme in AppTheme.values) {
        for (final source in SettingSource.values) {
          for (final mode in ElectricityPriceMode.values) {
            for (final capacity in DesignCapacitySource.values) {
              final p = await freshPrefs();
              final s = Settings(
                  theme: theme,
                  currencySource: source,
                  priceMode: mode,
                  // `unknown` carries no numbers; every other source needs one.
                  designCapacityMah:
                      capacity == DesignCapacitySource.unknown ? 0 : 4000,
                  designCapacitySource: capacity);
              await SettingsStore(p).save(s);
              final loaded = SettingsStore(await restart(p)).load();
              expect([
                loaded.theme,
                loaded.currencySource,
                loaded.priceMode,
                loaded.designCapacitySource
              ], [
                theme,
                source,
                mode,
                capacity
              ]);
            }
          }
        }
      }
    });

    test('an unknown enum name is replaced by the default, not an error',
        () async {
      final p = await freshPrefs({
        'wb.theme': 'neon',
        'wb.capacitySource': 'quantum',
        'wb.priceMode': 'free',
        'wb.currencySource': 'psychic',
      });
      final s = SettingsStore(p).load();
      expect(s.theme, AppTheme.system);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.currencySource, SettingSource.detected);
    });

    test(
        'the retired measurement sources under the CURRENT key are never a '
        'design capacity (system / estimated -> unknown, number dropped)',
        () async {
      for (final retired in ['system', 'estimated']) {
        final s = SettingsStore(await freshPrefs({
          'wb.designCapacitySource': retired,
          'wb.designCapacityMah': 4480.0,
          'wb.designCapacityWh': 17.2,
        }))
            .load();
        expect(s.designCapacitySource, DesignCapacitySource.unknown,
            reason: retired);
        expect(s.designCapacityMah, 0, reason: retired);
        expect(s.designCapacityWh, 0, reason: retired);
      }
    });

    test(
        'a stored design source of bogus text (current key) is replaced, '
        'never an error', () async {
      // No number: nothing to keep, the capacity is unknown.
      final none = SettingsStore(await freshPrefs({
        'wb.designCapacitySource': 'quantum',
      }))
          .load();
      expect(none.designCapacitySource, DesignCapacitySource.unknown);
      expect(none.designCapacityMah, 0);
      // With a number and no readable source the number is the user's own
      // (nothing else ever wrote this key), so it is kept as manual: the same
      // rule as for the legacy keys. It is never promoted to a catalog value.
      final typed = SettingsStore(await freshPrefs({
        'wb.designCapacitySource': 'quantum',
        'wb.designCapacityMah': 4000.0,
        'wb.designCapacityWh': 15.4,
      }))
          .load();
      expect(typed.designCapacitySource, DesignCapacitySource.manual);
      expect(typed.designCapacityMah, 4000);
      expect(typed.designCapacityWh, 15.4);
      // A source that is not a string is ignored like any damaged preference.
      final wrongType = SettingsStore(await freshPrefs({
        'wb.designCapacitySource': 7,
        'wb.designCapacityMah': 4000.0,
      }))
          .load();
      expect(wrongType.designCapacitySource, DesignCapacitySource.manual);
      expect(wrongType.designCapacityMah, 4000);
    });
  });

  group('notification and privacy switches are independent', () {
    test('each switch persists alone and flips nothing else', () async {
      final switches = <String, Settings Function(Settings)>{
        'notifyMobileThreshold': (s) => s.copyWith(notifyMobileThreshold: true),
        'notifyChargingDone': (s) => s.copyWith(notifyChargingDone: true),
        'notifyWeeklyEnergy': (s) => s.copyWith(notifyWeeklyEnergy: true),
        'notifyAboveAverage': (s) => s.copyWith(notifyAboveAverage: true),
        'cloudSync': (s) => s.copyWith(cloudSync: true),
        'binaryUnits': (s) => s.copyWith(binaryUnits: true),
        'dataCollection': (s) => s.copyWith(dataCollection: false),
      };
      for (final e in switches.entries) {
        final p = await freshPrefs();
        await SettingsStore(p).save(e.value(const Settings()));
        final loaded = describe(SettingsStore(await restart(p)).load());
        final expected = describe(e.value(const Settings()));
        expect(loaded, expected, reason: e.key);
        final changedKeys = [
          for (final k in expected.keys)
            if (loaded[k] != describe(const Settings())[k]) k
        ];
        expect(changedKeys, [e.key],
            reason: 'only ${e.key} may differ from the defaults');
      }
    });

    test('the threshold amount persists as an exact integer', () async {
      final p = await freshPrefs();
      await SettingsStore(p)
          .save(const Settings(mobileThresholdBytes: 123456789012));
      expect(SettingsStore(await restart(p)).load().mobileThresholdBytes,
          123456789012);
    });
  });

  group('bookkeeping kept next to the settings', () {
    test('locale tag, device specification cache and sent notifications',
        () async {
      final p = await freshPrefs();
      final store = SettingsStore(p);
      expect(store.locale, isNull);
      expect(store.deviceSpecCache, isNull);
      expect(store.sentNotifications, isEmpty);
      await store.setLocale('pl_PL');
      await store.setDeviceSpecCache('{"iPhone16,1":{"mah":3274}}');
      await store.markSent('weekly:2026-W41');
      await store.markSent('mobile:2026-10-12');
      final again = SettingsStore(await restart(p));
      expect(again.locale, 'pl_PL');
      expect(again.deviceSpecCache, '{"iPhone16,1":{"mah":3274}}');
      expect(again.sentNotifications, {'weekly:2026-W41', 'mobile:2026-10-12'});
    });

    test('the sent-notification list is capped at 200 and keeps the newest',
        () async {
      final p = await freshPrefs();
      final store = SettingsStore(p);
      for (var i = 0; i < 230; i++) {
        await store.markSent('k$i');
      }
      final sent = SettingsStore(await restart(p)).sentNotifications;
      expect(sent, hasLength(200));
      expect(sent, contains('k229'));
      expect(sent, contains('k30'));
      expect(sent, isNot(contains('k29')));
    });

    test('saving settings leaves the bookkeeping alone', () async {
      final p = await freshPrefs();
      final store = SettingsStore(p);
      await store.setLocale('en');
      await store.markSent('a');
      await store.save(variants['theme']!(const Settings()));
      expect(store.locale, 'en');
      expect(store.sentNotifications, {'a'});
    });
  });

  group('corrupt values are sanitised, never fatal', () {
    test('out-of-range and non-finite numbers fall back to the defaults',
        () async {
      for (final bad in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
        -0.001,
        1e300,
      ]) {
        final p = await freshPrefs({
          'wb.pricePerKwh': bad,
          'wb.manualPricePerKwh': bad,
          'wb.efficiency': bad,
          'wb.designCapacityMah': bad,
          'wb.designCapacityWh': bad,
          'wb.designCapacitySource': 'manual',
          'wb.nominalVoltage': bad,
        });
        final s = SettingsStore(p).load();
        expect(s.pricePerKwh, 0, reason: '$bad');
        expect(s.manualPricePerKwh, 0, reason: '$bad');
        expect(s.efficiency, 0.85, reason: '$bad');
        expect(s.designCapacityMah, 0, reason: '$bad');
        expect(s.designCapacityWh, 0, reason: '$bad');
        expect(s.designCapacitySource, DesignCapacitySource.unknown,
            reason: '$bad: a source without a usable capacity is unknown');
        expect(s.nominalVoltage, 3.85, reason: '$bad');
        expect(s.energyCalc, returnsNormally,
            reason: 'the calculator must always be constructible');
      }
    });

    test('values just outside the limits are replaced, on the limits kept',
        () async {
      Future<Settings> load(Map<String, Object> v) async =>
          SettingsStore(await freshPrefs(v)).load();

      expect((await load({'wb.efficiency': 0.0})).efficiency, 0.85);
      expect((await load({'wb.efficiency': 1.0001})).efficiency, 0.85);
      expect((await load({'wb.efficiency': 1.0})).efficiency, 1.0);
      expect((await load({'wb.efficiency': 0.0001})).efficiency, 0.0001);

      expect((await load({'wb.pricePerKwh': 1000.0})).pricePerKwh, 1000);
      expect((await load({'wb.pricePerKwh': 1000.01})).pricePerKwh, 0);

      const manual = {'wb.designCapacitySource': 'manual'};
      expect(
          (await load({'wb.designCapacityMah': 30000.0, ...manual}))
              .designCapacityMah,
          30000);
      final over = await load({'wb.designCapacityMah': 30000.5, ...manual});
      expect(over.designCapacityMah, 0);
      expect(over.designCapacitySource, DesignCapacitySource.unknown);

      expect(
          (await load({
            'wb.designCapacityMah': 4000.0,
            'wb.designCapacityWh': 200.0,
            ...manual
          }))
              .designCapacityWh,
          200);
      expect(
          (await load({
            'wb.designCapacityMah': 4000.0,
            'wb.designCapacityWh': 200.01,
            ...manual
          }))
              .designCapacityWh,
          0);

      expect((await load({'wb.nominalVoltage': 2.5})).nominalVoltage, 2.5);
      expect((await load({'wb.nominalVoltage': 5.0})).nominalVoltage, 5.0);
      expect((await load({'wb.nominalVoltage': 2.4})).nominalVoltage, 3.85);
      expect((await load({'wb.nominalVoltage': 5.1})).nominalVoltage, 3.85);

      expect((await load({'wb.mobileThresholdBytes': 0})).mobileThresholdBytes,
          5000000000);
      expect((await load({'wb.mobileThresholdBytes': -7})).mobileThresholdBytes,
          5000000000);
      expect(
          (await load({'wb.mobileThresholdBytes': 1})).mobileThresholdBytes, 1);
    });

    test('malformed currency and country codes are dropped', () async {
      for (final bad in ['pln', 'PL', 'PLNN', '12', 'P N', '', 'ŻŁÓ', '€€€']) {
        final s = SettingsStore(await freshPrefs({'wb.currency': bad})).load();
        expect(s.currency, '', reason: '"$bad"');
      }
      for (final bad in ['pl', 'POL', 'P', '1', '', 'ŻŁ', '🇵🇱']) {
        final s =
            SettingsStore(await freshPrefs({'wb.countryCode': bad})).load();
        expect(s.countryCode, '', reason: '"$bad"');
      }
      final ok = SettingsStore(
              await freshPrefs({'wb.currency': 'PLN', 'wb.countryCode': 'PL'}))
          .load();
      expect([ok.currency, ok.countryCode], ['PLN', 'PL']);
    });

    test('saving an invalid Settings object stores only sanitised values',
        () async {
      final p = await freshPrefs();
      await SettingsStore(p).save(const Settings(
        currency: 'zloty',
        countryCode: 'polska',
        pricePerKwh: double.nan,
        manualPricePerKwh: -4,
        efficiency: double.infinity,
        designCapacityMah: -1,
        designCapacityWh: double.nan,
        designCapacitySource: DesignCapacitySource.manual,
        nominalVoltage: 99,
        mobileThresholdBytes: -1,
      ));
      for (final key in p.getKeys()) {
        final v = p.get(key);
        if (v is double) expect(v.isFinite, isTrue, reason: key);
      }
      expect(p.getDouble('wb.designCapacityMah'), 0);
      expect(p.getDouble('wb.designCapacityWh'), 0);
      expect(p.getString('wb.designCapacitySource'), 'unknown',
          reason: 'a source with no usable capacity is not stored as known');
      final s = SettingsStore(await restart(p)).load();
      expect(s.currency, '');
      expect(s.countryCode, '');
      expect(s.pricePerKwh, 0);
      expect(s.efficiency, 0.85);
      expect(s.nominalVoltage, 3.85);
      expect(s.mobileThresholdBytes, 5000000000);
    });

    test('sanitising twice equals sanitising once', () {
      const messy = Settings(
          currency: 'x',
          pricePerKwh: double.nan,
          efficiency: 7,
          designCapacityMah: -3,
          designCapacitySource: DesignCapacitySource.localDeviceDatabase,
          nominalVoltage: 0);
      final once = messy.sanitized();
      expect(describe(once.sanitized()), describe(once));
    });

    test('one corrupt value does not take the valid ones down with it',
        () async {
      final s = SettingsStore(await freshPrefs({
        'wb.currency': 'PLN',
        'wb.pricePerKwh': double.nan,
        'wb.designCapacityMah': 4000.0,
        'wb.designCapacitySource': 'localDeviceDatabase',
        'wb.theme': 'dark',
        'wb.cloudSync': true,
      }))
          .load();
      expect(s.currency, 'PLN');
      expect(s.pricePerKwh, 0);
      expect(s.designCapacityMah, 4000);
      expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(s.theme, AppTheme.dark);
      expect(s.cloudSync, isTrue);
    });

    test('a preference of the wrong type does not stop the app from starting',
        () async {
      for (final bad in <Map<String, Object>>[
        {'wb.pricePerKwh': 'abc'},
        {'wb.pricePerKwh': 5},
        {'wb.onboarded': 'yes'},
        {'wb.mobileThresholdBytes': 1.5},
        {'wb.currency': 5},
        {'wb.cloudSync': 1},
        {'wb.theme': 3},
        {'wb.designCapacityMah': 'abc'},
        {'wb.designCapacityMah': 4000},
        {'wb.designCapacityWh': 'abc'},
        {'wb.designCapacitySource': 3},
        {'wb.batteryCapacityMah': 'abc'},
        {'wb.batteryCapacityMah': 4000},
        {'wb.capacitySource': 3},
        {'wb.capacitySource': true, 'wb.batteryCapacityMah': 4000.0},
      ]) {
        final p = await freshPrefs({...bad, 'wb.efficiency': 0.9});
        late Settings s;
        expect(() => s = SettingsStore(p).load(), returnsNormally,
            reason: '$bad');
        expect(s.efficiency, 0.9, reason: 'the valid keys are still read');
      }
    });

    test('a corrupt stored automatic price never becomes the effective price',
        () async {
      for (final bad in <double>[double.nan, -2, 1e9]) {
        final p = await freshPrefs({
          'wb.currency': 'PLN',
          'wb.autoPrice.value': bad,
          'wb.autoPrice.currency': 'PLN',
          'wb.autoPrice.country': 'PL',
          'wb.autoPrice.period': '2026-S1',
          'wb.autoPrice.source': 'eurostat',
          'wb.autoPrice.updatedMs': 1760346000000,
        });
        final s = SettingsStore(p).load().withAutomaticPrice();
        expect(s.pricePerKwh.isFinite, isTrue, reason: '$bad');
        expect(s.energyCalc, returnsNormally, reason: '$bad');
      }
    });
  });

  group('legacy preferences (before the automatic setup): extra cases', () {
    test('only the onboarding flag: nothing is invented as manual', () async {
      final s = SettingsStore(await freshPrefs({'wb.onboarded': true})).load();
      expect(s.onboarded, isTrue);
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.currencySource, SettingSource.detected);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.pricePerKwh, 0);
      expect(s.hasPrice, isFalse);
      expect(s.hasCurrency, isFalse);
    });

    test(
        'a stored currency alone is a migrated choice; price and capacity are not',
        () async {
      final s = SettingsStore(await freshPrefs({'wb.currency': 'EUR'})).load();
      expect(s.currencySource, SettingSource.migratedManual);
      expect(s.currencySource.isConscious, isTrue);
      expect(s.currencyOriginalSource, isNull);
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
    });

    test('a stored price alone is a manual tariff and keeps its value',
        () async {
      final s =
          SettingsStore(await freshPrefs({'wb.pricePerKwh': 0.82})).load();
      expect(s.priceMode, ElectricityPriceMode.manual);
      expect(s.priceSource, SettingSource.migratedManual);
      expect(s.manualPricePerKwh, 0.82);
      expect(s.pricePerKwh, 0.82);
      expect(s.currencySource, SettingSource.detected);
    });

    test('a stored price of 0 is "no price", not a manual tariff of 0',
        () async {
      final s = SettingsStore(
              await freshPrefs({'wb.pricePerKwh': 0.0, 'wb.currency': 'PLN'}))
          .load();
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.hasPrice, isFalse);
    });

    test('a stored capacity alone is manual; a stored 0 is unknown', () async {
      final s =
          SettingsStore(await freshPrefs({'wb.batteryCapacityMah': 3500.0}))
              .load();
      expect(s.designCapacitySource, DesignCapacitySource.manual);
      expect(s.designCapacityMah, 3500);
      final zero =
          SettingsStore(await freshPrefs({'wb.batteryCapacityMah': 0.0}))
              .load();
      expect(zero.designCapacitySource, DesignCapacitySource.unknown);
    });

    test('explicit modern values win over the legacy inference', () async {
      final s = SettingsStore(await freshPrefs({
        'wb.pricePerKwh': 1.27,
        'wb.priceMode': 'automatic',
        'wb.currency': 'PLN',
        'wb.currencySource': 'automatic',
        'wb.batteryCapacityMah': 3988.0,
        'wb.capacitySource': 'localDatabase',
      }))
          .load();
      expect(s.priceMode, ElectricityPriceMode.automatic);
      expect(s.currencySource, SettingSource.detected);
      expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      expect(s.designCapacityMah, 3988);
      expect(s.manualPricePerKwh, 0,
          reason: 'the automatic price must not be taken for a manual one');
    });

    test('an unreadable mode name falls back to the legacy inference',
        () async {
      final s = SettingsStore(await freshPrefs({
        'wb.pricePerKwh': 1.2,
        'wb.priceMode': 'bogus',
        'wb.currency': 'PLN',
        'wb.currencySource': 'bogus',
        'wb.batteryCapacityMah': 4000.0,
        'wb.capacitySource': 'bogus',
      }))
          .load();
      expect(s.priceMode, ElectricityPriceMode.manual);
      expect(s.priceSource, SettingSource.migratedManual);
      expect(s.currencySource, SettingSource.migratedManual);
      expect(s.designCapacitySource, DesignCapacitySource.manual);
      expect(s.designCapacityMah, 4000);
    });

    test('the migration is persisted by the next save and stays stable',
        () async {
      final p = await freshPrefs({
        'wb.currency': 'PLN',
        'wb.pricePerKwh': 1.15,
        'wb.batteryCapacityMah': 4000.0,
        'wb.onboarded': true,
      });
      final migrated = SettingsStore(p).load();
      await SettingsStore(p).save(migrated);
      expect(p.getString('wb.priceMode'), 'manual');
      expect(p.getString('wb.priceSource'), 'migratedManual');
      expect(p.getString('wb.currencySource'), 'migratedManual');
      expect(p.getString('wb.designCapacitySource'), 'manual');
      expect(p.getDouble('wb.designCapacityMah'), 4000);
      expect(p.getDouble('wb.manualPricePerKwh'), 1.15);
      final reloaded = SettingsStore(await restart(p)).load();
      expect(describe(reloaded), describe(migrated));
      // The user switches to the automatic price and back: the tariff survives.
      final auto = reloaded.copyWith(priceMode: ElectricityPriceMode.automatic);
      expect(auto.manualPricePerKwh, 1.15);
    });
  });

  group('legacy capacity keys (before design / estimated full-charge)', () {
    // `wb.batteryCapacityMah` / `wb.batteryCapacityWh` / `wb.capacitySource`
    // could not say whether a number was nominal or measured. The old
    // `system` and `estimated` sources were charge-counter extrapolations: they
    // are NOT a design capacity and must never become one.
    const legacyKeys = [
      'wb.batteryCapacityMah',
      'wb.batteryCapacityWh',
      'wb.capacitySource',
    ];

    // (legacy source, expected design source when a number is stored,
    //  does the number survive)
    const matrix = <(String?, DesignCapacitySource, bool)>[
      ('localDatabase', DesignCapacitySource.localDeviceDatabase, true),
      ('backendDatabase', DesignCapacitySource.backendDeviceDatabase, true),
      ('manual', DesignCapacitySource.manual, true),
      ('unknown', DesignCapacitySource.unknown, false),
      ('system', DesignCapacitySource.unknown, false),
      ('estimated', DesignCapacitySource.unknown, false),
      ('bogus', DesignCapacitySource.manual, true),
      ('', DesignCapacitySource.manual, true),
      (null, DesignCapacitySource.manual, true),
    ];

    for (final (legacySource, expectedSource, keepsNumber) in matrix) {
      final label = legacySource == null ? 'absent' : "'$legacySource'";

      test('wb.capacitySource $label with a stored capacity', () async {
        final p = await freshPrefs({
          'wb.batteryCapacityMah': 3988.0,
          'wb.batteryCapacityWh': 15.3,
          if (legacySource != null) 'wb.capacitySource': legacySource,
        });
        final s = SettingsStore(p).load();
        expect(s.designCapacitySource, expectedSource);
        expect(s.designCapacityMah, keepsNumber ? 3988 : 0);
        expect(s.designCapacityWh, keepsNumber ? 15.3 : 0);
        expect(s.designCapacity.isKnown, keepsNumber);
        if (!keepsNumber) {
          expect(s.designCapacity, DesignCapacity.unknown,
              reason: 'a measurement is never a design capacity');
        }

        // The next save writes the new keys and removes the old ones, and the
        // result is stable across a restart.
        await SettingsStore(p).save(s);
        for (final key in legacyKeys) {
          expect(p.containsKey(key), isFalse, reason: key);
        }
        expect(p.getString('wb.designCapacitySource'), expectedSource.name);
        expect(p.getDouble('wb.designCapacityMah'), keepsNumber ? 3988 : 0);
        expect(p.getDouble('wb.designCapacityWh'), keepsNumber ? 15.3 : 0);
        final reloaded = SettingsStore(await restart(p)).load();
        expect(describe(reloaded), describe(s));
      });

      test('wb.capacitySource $label without a stored capacity', () async {
        final p = await freshPrefs({
          if (legacySource != null) 'wb.capacitySource': legacySource,
        });
        final s = SettingsStore(p).load();
        expect(s.designCapacity, DesignCapacity.unknown,
            reason: 'a source without a number says nothing');
        expect(s.designCapacityMah, 0);
        expect(s.designCapacityWh, 0);
        await SettingsStore(p).save(s);
        for (final key in legacyKeys) {
          expect(p.containsKey(key), isFalse, reason: key);
        }
        expect(p.getString('wb.designCapacitySource'), 'unknown');
      });
    }

    test('a legacy charge-counter measurement is stored nowhere after a save',
        () async {
      for (final source in ['system', 'estimated']) {
        final p = await freshPrefs({
          'wb.batteryCapacityMah': 3600.0,
          'wb.batteryCapacityWh': 13.9,
          'wb.capacitySource': source,
          'wb.currency': 'PLN',
        });
        final s = SettingsStore(p).load();
        await SettingsStore(p).save(s);
        for (final key in p.getKeys()) {
          final v = p.get(key);
          expect(v, isNot(3600.0), reason: '$source: $key');
          expect(v, isNot(13.9), reason: '$source: $key');
        }
        final reopened = SettingsStore(await restart(p)).load();
        expect(reopened.designCapacity, DesignCapacity.unknown);
      }
    });

    test('the current keys win over leftovers of the legacy ones', () async {
      final p = await freshPrefs({
        'wb.designCapacityMah': 4100.0,
        'wb.designCapacityWh': 15.8,
        'wb.designCapacitySource': 'backendDeviceDatabase',
        'wb.batteryCapacityMah': 9999.0,
        'wb.capacitySource': 'system',
      });
      final s = SettingsStore(p).load();
      expect(s.designCapacityMah, 4100);
      expect(s.designCapacityWh, 15.8);
      expect(
          s.designCapacitySource, DesignCapacitySource.backendDeviceDatabase);
      await SettingsStore(p).save(s);
      expect(p.containsKey('wb.batteryCapacityMah'), isFalse);
      expect(p.containsKey('wb.capacitySource'), isFalse);
    });

    test('a legacy catalog capacity out of range is dropped, not clamped',
        () async {
      for (final mah in [0.0, -5.0, double.nan, 30000.5, 1e12]) {
        final s = SettingsStore(await freshPrefs({
          'wb.batteryCapacityMah': mah,
          'wb.capacitySource': 'localDatabase',
        }))
            .load();
        expect(s.designCapacity, DesignCapacity.unknown, reason: '$mah');
        expect(s.designCapacitySource, DesignCapacitySource.unknown,
            reason: '$mah');
      }
    });

    test('converting twice is the same as converting once', () async {
      final p = await freshPrefs({
        'wb.batteryCapacityMah': 3274.0,
        'wb.batteryCapacityWh': 12.7,
        'wb.capacitySource': 'localDatabase',
      });
      final first = SettingsStore(p).load();
      await SettingsStore(p).save(first);
      final second = SettingsStore(p).load();
      await SettingsStore(p).save(second);
      expect(describe(SettingsStore(await restart(p)).load()), describe(first));
      expect(
          first.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
    });
  });

  group('design capacity: the three fields stay one coherent group', () {
    final knownSources = [
      for (final s in DesignCapacitySource.values)
        if (s != DesignCapacitySource.unknown) s
    ];

    test('every known source with a usable mAh survives sanitising', () {
      for (final source in knownSources) {
        final s = Settings(
                designCapacityMah: 4000,
                designCapacityWh: 15.4,
                designCapacitySource: source)
            .sanitized();
        expect(s.designCapacityMah, 4000, reason: source.name);
        expect(s.designCapacityWh, 15.4, reason: source.name);
        expect(s.designCapacitySource, source);
        expect(s.designCapacity.isKnown, isTrue);
      }
    });

    test('a known source without a usable mAh becomes unknown (no number)', () {
      for (final source in knownSources) {
        for (final mah in [
          0.0,
          -1.0,
          -0.001,
          double.nan,
          double.infinity,
          double.negativeInfinity,
          30000.5,
          1e300
        ]) {
          final s = Settings(
                  designCapacityMah: mah,
                  designCapacityWh: 12.7,
                  designCapacitySource: source)
              .sanitized();
          final why = '${source.name} / $mah';
          expect(s.designCapacityMah, 0, reason: why);
          expect(s.designCapacityWh, 0,
              reason: '$why: the Wh needs a valid mAh');
          expect(s.designCapacitySource, DesignCapacitySource.unknown,
              reason: why);
          expect(s.designCapacity, DesignCapacity.unknown, reason: why);
        }
      }
    });

    test('the source unknown carries no numbers', () {
      final s = const Settings(
              designCapacityMah: 4000,
              designCapacityWh: 15.4,
              designCapacitySource: DesignCapacitySource.unknown)
          .sanitized();
      expect(s.designCapacityMah, 0);
      expect(s.designCapacityWh, 0);
      expect(s.designCapacitySource, DesignCapacitySource.unknown);
      expect(s.designCapacity, DesignCapacity.unknown);
    });

    test('a bad Wh is dropped and the mAh with its source stays', () {
      for (final wh in [
        double.nan,
        double.infinity,
        -3.0,
        0.0,
        200.01,
        1e300
      ]) {
        final s = Settings(
                designCapacityMah: 4000,
                designCapacityWh: wh,
                designCapacitySource: DesignCapacitySource.manual)
            .sanitized();
        expect(s.designCapacityMah, 4000, reason: '$wh');
        expect(s.designCapacityWh, 0, reason: '$wh');
        expect(s.designCapacitySource, DesignCapacitySource.manual,
            reason: '$wh');
      }
    });

    test('the limits themselves are kept', () {
      final s = const Settings(
              designCapacityMah: 30000,
              designCapacityWh: 200,
              designCapacitySource: DesignCapacitySource.manual)
          .sanitized();
      expect([s.designCapacityMah, s.designCapacityWh], [30000, 200]);
    });

    test('sanitising is idempotent for every source and every kind of number',
        () {
      for (final source in DesignCapacitySource.values) {
        for (final mah in [0.0, 4000.0, -1.0, double.nan, 99999.0]) {
          for (final wh in [0.0, 15.4, -2.0, double.nan]) {
            final once = Settings(
                    designCapacityMah: mah,
                    designCapacityWh: wh,
                    designCapacitySource: source)
                .sanitized();
            expect(describe(once.sanitized()), describe(once),
                reason: '${source.name} / $mah / $wh');
          }
        }
      }
    });

    test('withDesignCapacity replaces the three fields together', () {
      final known = const Settings().withDesignCapacity(DesignCapacity(
          mah: 3274,
          wh: 12.7,
          source: DesignCapacitySource.localDeviceDatabase));
      expect(known.designCapacityMah, 3274);
      expect(known.designCapacityWh, 12.7);
      expect(
          known.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
      // Replacing it with a capacity without Wh clears the old Wh.
      final next = known.withDesignCapacity(DesignCapacity(
          mah: 4575, source: DesignCapacitySource.backendDeviceDatabase));
      expect(next.designCapacityMah, 4575);
      expect(next.designCapacityWh, 0);
      expect(next.designCapacitySource,
          DesignCapacitySource.backendDeviceDatabase);
      // And unknown clears everything.
      final cleared = next.withDesignCapacity(DesignCapacity.unknown);
      expect(cleared.designCapacityMah, 0);
      expect(cleared.designCapacityWh, 0);
      expect(cleared.designCapacitySource, DesignCapacitySource.unknown);
    });

    test('the settings view of the capacity is a normalised DesignCapacity',
        () {
      expect(const Settings().designCapacity, DesignCapacity.unknown);
      expect(
          const Settings(
                  designCapacityMah: 4000,
                  designCapacitySource: DesignCapacitySource.unknown)
              .designCapacity,
          DesignCapacity.unknown,
          reason: 'unknown carries no number even when one is set');
      expect(
          const Settings(
                  designCapacityMah: 4000,
                  designCapacitySource: DesignCapacitySource.manual)
              .designCapacity,
          DesignCapacity(mah: 4000, source: DesignCapacitySource.manual));
    });

    test('stored under the new keys only, for every source', () async {
      for (final source in DesignCapacitySource.values) {
        final p = await freshPrefs();
        final known = source != DesignCapacitySource.unknown;
        await SettingsStore(p).save(Settings(
            designCapacityMah: known ? 3274 : 0,
            designCapacityWh: known ? 12.7 : 0,
            designCapacitySource: source));
        expect(p.getDouble('wb.designCapacityMah'), known ? 3274 : 0);
        expect(p.getDouble('wb.designCapacityWh'), known ? 12.7 : 0);
        expect(p.getString('wb.designCapacitySource'), source.name);
        expect(
            p.getKeys().where((k) => k.contains('batteryCapacity')), isEmpty);
        expect(p.containsKey('wb.capacitySource'), isFalse);
        final reopened = SettingsStore(await restart(p)).load();
        expect(reopened.designCapacitySource, source);
        expect(reopened.designCapacityMah, known ? 3274 : 0);
        expect(reopened.designCapacityWh, known ? 12.7 : 0);
      }
    });
  });
}
