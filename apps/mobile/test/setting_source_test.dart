import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/account_settings.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte/setup/setup_controller.dart';

import 'support/fake_account_settings.dart';
import 'support/fake_backend.dart';
import 'support/phone_rig.dart';

/// Where a setting came from (`docs/SETTING_SOURCES.md`): detected, chosen on
/// this phone, synced from the account (with the account's origin kept), or a
/// choice carried over from an older version.
///
/// The model and the priorities are tested as plain values first; then two and
/// three PHONES (own preferences, own SQLite, the real providers) talk to one
/// fake account server that follows the rules of the real API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the model', () {
    test('four sources; only a choice of the user is conscious', () {
      expect(SettingSource.values.map((s) => s.name), [
        'detected',
        'manual',
        'accountSynced',
        'migratedManual',
      ]);
      expect([
        for (final s in SettingSource.values)
          if (s.isConscious) s
      ], [
        SettingSource.manual,
        SettingSource.migratedManual
      ]);
    });

    test(
        'the name of the first version of the model is still read; the API only knows three origins',
        () {
      expect(SettingSource.tryParse('automatic'), SettingSource.detected);
      expect(SettingSource.tryParse('manual'), SettingSource.manual);
      expect(SettingSource.tryParse('psychic'), isNull);
      expect(SettingSource.tryParse(null), isNull);
      // accountSynced is how a value reaches a device, never how the account got it.
      expect(SettingSource.tryParseOriginal('accountSynced'), isNull);
      expect(SettingSource.tryParseOriginal('migratedManual'),
          SettingSource.migratedManual);
    });

    test('a value from the account is accountSynced and keeps its origin', () {
      final s = const Settings()
          .withAccountCurrency('EUR', original: SettingSource.manual);
      expect(s.currencySource, SettingSource.accountSynced);
      expect(s.currencyOriginalSource, SettingSource.manual);
      expect(s.accountInSync, {SettingGroup.currency});
      expect(s.isCustom(SettingGroup.currency), isTrue,
          reason: 'the user chose it, on another phone');
      // An origin the account does not say stays unknown, never guessed.
      final unknown = const Settings().withAccountCurrency('EUR');
      expect(unknown.currencyOriginalSource, isNull);
      expect(unknown.isCustom(SettingGroup.currency), isFalse);
    });

    test(
        'a local choice is manual with no original, and not on the account yet',
        () {
      final s = const Settings()
          .withAccountCurrency('PLN', original: SettingSource.detected)
          .withManualCurrency('eur');
      expect(s.currency, 'EUR');
      expect(s.currencySource, SettingSource.manual);
      expect(s.currencyOriginalSource, isNull);
      expect(s.accountInSync, isEmpty);
    });

    test(
        'a manual value is never turned into accountSynced, and an account '
        'value never into manual, by the way they are stored', () {
      final synced = const Settings()
          .withAccountRegion('PL', original: SettingSource.manual)
          .withAccountPrice(
              mode: ElectricityPriceMode.manual,
              manualPrice: 0.95,
              original: SettingSource.manual);
      expect(synced.regionSource, SettingSource.accountSynced);
      expect(synced.priceSource, SettingSource.accountSynced);
      expect(synced.sanitized().regionSource, SettingSource.accountSynced);
      expect(synced.sanitized().priceSource, SettingSource.accountSynced);
    });

    test('sanitized keeps the original only next to an account value', () {
      // An original with a local source, or an original that is accountSynced
      // itself, can only come from a damaged store.
      final local = const Settings(
        currencySource: SettingSource.manual,
        currencyOriginalSource: SettingSource.manual,
        regionSource: SettingSource.detected,
        regionOriginalSource: SettingSource.manual,
      ).sanitized();
      expect(local.currencyOriginalSource, isNull);
      expect(local.regionOriginalSource, isNull);
      final circular = const Settings(
        priceSource: SettingSource.accountSynced,
        priceOriginalSource: SettingSource.accountSynced,
      ).sanitized();
      expect(circular.priceOriginalSource, isNull);
      final fine = const Settings(
        currencySource: SettingSource.accountSynced,
        currencyOriginalSource: SettingSource.migratedManual,
      ).sanitized();
      expect(fine.currencyOriginalSource, SettingSource.migratedManual);
    });

    test('a manual tariff and the automatic price mode are different decisions',
        () {
      final manual = const Settings(currency: 'PLN').withManualPrice(0.95);
      expect(manual.priceMode, ElectricityPriceMode.manual);
      expect(manual.priceSource, SettingSource.manual);
      expect(manual.pricePerKwh, 0.95);
      final back = manual.withAutomaticPrice();
      expect(back.priceMode, ElectricityPriceMode.automatic);
      expect(back.manualPricePerKwh, 0.95,
          reason: 'the tariff is kept for the way back');
      expect(back.priceSource, SettingSource.manual,
          reason: 'the user chose the average');
    });
  });

  group('the priorities (mergeAccountSettings)', () {
    api.UserSettingsDto account({
      String? country,
      String? countrySource,
      String? currency,
      String? currencySource,
      String mode = 'automatic',
      double? price,
      String? priceSource,
    }) =>
        api.UserSettingsDto.fromJson({
          'countryCode': country,
          'countryCodeSource': countrySource,
          'currencyCode': currency,
          'currencyCodeSource': currencySource,
          'electricityPriceMode': mode,
          'manualElectricityPrice': price,
          'electricityPriceSource': priceSource,
          'updatedAt': '2026-10-14T10:00:00.000Z',
        })!;

    test('an unreachable account changes nothing, not even a source', () {
      final s = const Settings()
          .withAccountCurrency('EUR', original: SettingSource.manual)
          .withAccountRegion('DE', original: SettingSource.detected);
      final merged = mergeAccountSettings(s, null);
      expect(identical(merged, s), isTrue);
    });

    test('1. an own choice the account has not acknowledged beats the account',
        () {
      final s = const Settings().withManualCurrency('GBP');
      final merged = mergeAccountSettings(
          s, account(currency: 'EUR', currencySource: 'manual'));
      expect(merged.currency, 'GBP');
      expect(merged.currencySource, SettingSource.manual);
    });

    test('1. the same for a choice migrated from an older version', () {
      const s = Settings(
          currency: 'PLN', currencySource: SettingSource.migratedManual);
      final merged = mergeAccountSettings(
          s, account(currency: 'EUR', currencySource: 'detected'));
      expect(merged.currency, 'PLN');
      expect(merged.currencySource, SettingSource.migratedManual);
    });

    test(
        '2. the account beats a fresh detection, and the value is accountSynced, '
        'not manual, whatever its origin was', () {
      for (final origin in ['detected', 'manual', 'migratedManual', null]) {
        final merged = mergeAccountSettings(
            const Settings(currency: 'USD'),
            account(
                country: 'DE',
                countrySource: origin,
                currency: 'EUR',
                currencySource: origin));
        expect(merged.currency, 'EUR', reason: '$origin');
        expect(merged.currencySource, SettingSource.accountSynced,
            reason: '$origin');
        expect(merged.currencyOriginalSource, SettingSource.tryParse(origin),
            reason: '$origin');
        expect(merged.regionSource, SettingSource.accountSynced);
        expect(merged.regionOriginalSource, SettingSource.tryParse(origin));
      }
    });

    test(
        '2. a choice the account HAS acknowledged gives way to a newer word of '
        'the account (another device changed it since)', () {
      final acked = const Settings().withManualCurrency('PLN').markInSyncFrom(
          const Settings().withManualCurrency('PLN'), {SettingGroup.currency});
      final merged = mergeAccountSettings(
          acked, account(currency: 'EUR', currencySource: 'manual'));
      expect(merged.currency, 'EUR');
      expect(merged.currencySource, SettingSource.accountSynced);
      expect(merged.currencyOriginalSource, SettingSource.manual);
    });

    test('an account without a currency does not clear the one of this phone',
        () {
      final merged = mergeAccountSettings(
          const Settings().withManualCurrency('GBP'), account(country: 'PL'));
      expect(merged.currency, 'GBP');
      expect(merged.regionSource, SettingSource.accountSynced);
    });

    test('a fresh account holds no price decision: the price stays as it is',
        () {
      const s = Settings(currency: 'PLN');
      final merged = mergeAccountSettings(s, account());
      expect(merged.priceSource, SettingSource.detected);
      expect(merged.priceMode, ElectricityPriceMode.automatic);
    });

    test(
        'a manual tariff of the account is kept as the tariff, accountSynced '
        'with origin manual', () {
      final merged = mergeAccountSettings(
          const Settings(currency: 'PLN'),
          account(
              currency: 'PLN',
              mode: 'manual',
              price: 0.95,
              priceSource: 'manual'));
      expect(merged.priceMode, ElectricityPriceMode.manual);
      expect(merged.manualPricePerKwh, 0.95);
      expect(merged.pricePerKwh, 0.95);
      expect(merged.priceSource, SettingSource.accountSynced);
      expect(merged.priceOriginalSource, SettingSource.manual);
    });

    test(
        'automatic mode of the account stays automatic: its kept tariff does '
        'not become a permanent manual override', () {
      final auto = AutoPrice(
          pricePerKwh: 1.27,
          currency: 'PLN',
          countryCode: 'PL',
          period: '2026-S1',
          source: 'eurostat',
          updatedAt: DateTime(2026, 10, 13));
      final merged = mergeAccountSettings(
          Settings(currency: 'PLN', autoPrice: auto).withAutoPrice(auto),
          account(
              currency: 'PLN',
              mode: 'automatic',
              price: 0.95,
              priceSource: 'manual'));
      expect(merged.priceMode, ElectricityPriceMode.automatic);
      expect(merged.pricePerKwh, 1.27,
          reason: 'the household average of THIS phone applies');
      expect(merged.manualPricePerKwh, 0.95, reason: 'kept for the way back');
      expect(merged.priceSource, SettingSource.accountSynced);
      // The average is refreshed by ElectricityPriceService: it changes the
      // number and nothing about where the decision came from.
      final refreshed = merged.withAutoPrice(AutoPrice(
          pricePerKwh: 1.31,
          currency: 'PLN',
          countryCode: 'PL',
          period: '2026-S2',
          source: 'eurostat',
          updatedAt: DateTime(2026, 10, 14)));
      expect(refreshed.pricePerKwh, 1.31);
      expect(refreshed.priceMode, ElectricityPriceMode.automatic);
      expect(refreshed.priceSource, SettingSource.accountSynced);
      expect(refreshed.priceOriginalSource, SettingSource.manual);
    });

    test('the account switching a phone back to automatic is followed', () {
      final manual = const Settings(currency: 'PLN').withAccountPrice(
          mode: ElectricityPriceMode.manual,
          manualPrice: 0.95,
          original: SettingSource.manual);
      final merged = mergeAccountSettings(
          manual,
          account(
              currency: 'PLN',
              mode: 'automatic',
              price: 0.95,
              priceSource: 'manual'));
      expect(merged.priceMode, ElectricityPriceMode.automatic);
    });

    test('what is uploaded: only the own decisions, never an account value',
        () {
      expect(groupsToPush(const Settings()), isEmpty,
          reason: 'nothing known, nothing decided');
      final detected = const Settings()
          .withDetectedRegion('PL', detection: 'deviceRegion')
          .withDetectedCurrency('PLN');
      expect(
          groupsToPush(detected), {SettingGroup.region, SettingGroup.currency},
          reason: 'detections go up too; an untouched price decides nothing');
      expect(
          groupsToPush(const Settings().withAccountCurrency('EUR')), isEmpty);
      expect(groupsToPush(const Settings().withManualPrice(0.95)),
          {SettingGroup.price});
      expect(
          groupsToPush(const Settings().withManualPrice(0.95).markInSyncFrom(
              const Settings().withManualPrice(0.95), {SettingGroup.price})),
          isEmpty,
          reason: 'already acknowledged');
    });

    test('a group edited while its upload was on the way is not acknowledged',
        () {
      final uploaded = const Settings().withManualCurrency('EUR');
      final edited = uploaded.withManualCurrency('GBP');
      expect(
          edited
              .markInSyncFrom(uploaded, {SettingGroup.currency}).accountInSync,
          isEmpty);
      expect(
          uploaded
              .markInSyncFrom(uploaded, {SettingGroup.currency}).accountInSync,
          {SettingGroup.currency});
    });
  });

  group('AutoSetup.apply: the four priorities', () {
    const region = DetectedRegion(
        countryCode: 'PL',
        currencyCode: 'PLN',
        source: RegionDetectionSource.deviceRegion,
        confidence: 0.9);
    api.UserSettingsDto account(Map<String, Object?> json) =>
        api.UserSettingsDto.fromJson({
          'countryCode': null,
          'countryCodeSource': null,
          'currencyCode': null,
          'currencyCodeSource': null,
          'electricityPriceMode': 'automatic',
          'manualElectricityPrice': null,
          'electricityPriceSource': null,
          'updatedAt': '2026-10-14T10:00:00.000Z',
          ...json,
        })!;

    test('4. nothing at all: what the phone has stays', () {
      final s = AutoSetup.apply(
          const Settings(currency: 'USD', countryCode: 'US'),
          const SetupResult());
      expect(s.currency, 'USD');
      expect(s.countryCode, 'US');
    });

    test('3. detection fills what nobody decided', () {
      final s =
          AutoSetup.apply(const Settings(), const SetupResult(region: region));
      expect(s.countryCode, 'PL');
      expect(s.regionSource, SettingSource.detected);
      expect(s.regionDetection, 'deviceRegion');
      expect(s.currency, 'PLN');
      expect(s.currencySource, SettingSource.detected);
      expect(s.priceSource, SettingSource.detected);
    });

    test(
        '2. the account outranks detection: PLN/accountSynced, original detected',
        () {
      final s = AutoSetup.apply(
          const Settings(),
          SetupResult(
              region: const DetectedRegion(
                  countryCode: 'DE',
                  currencyCode: 'EUR',
                  source: RegionDetectionSource.deviceRegion,
                  confidence: 0.9),
              accountSettings: account({
                'countryCode': 'PL',
                'countryCodeSource': 'detected',
                'currencyCode': 'PLN',
                'currencyCodeSource': 'detected',
              })));
      expect(s.countryCode, 'PL');
      expect(s.currency, 'PLN');
      expect(s.currencySource, SettingSource.accountSynced);
      expect(s.currencyOriginalSource, SettingSource.detected);
    });

    test(
        '2. an account country without a currency: the currency is that of the '
        'ACCOUNT country, not the one this phone detected', () {
      final s = AutoSetup.apply(
          const Settings(),
          SetupResult(
              region: region, // PL / PLN detected here
              accountSettings: account({'countryCode': 'DE'})));
      expect(s.countryCode, 'DE');
      expect(s.currency, 'EUR');
      expect(s.currencySource, SettingSource.detected);
    });

    test('1. an own manual currency beats both the account and detection', () {
      final s = AutoSetup.apply(
          const Settings().withManualCurrency('GBP'),
          SetupResult(
              region: region,
              accountSettings: account({
                'currencyCode': 'EUR',
                'currencyCodeSource': 'manual',
              })));
      expect(s.currency, 'GBP');
      expect(s.currencySource, SettingSource.manual);
    });

    test('offline: the account value on the phone and its source are kept', () {
      final local = const Settings()
          .withAccountCurrency('EUR', original: SettingSource.manual);
      final s = AutoSetup.apply(local, const SetupResult(region: region));
      expect(s.currency, 'EUR', reason: 'detection never replaces it');
      expect(s.currencySource, SettingSource.accountSynced);
      expect(s.currencyOriginalSource, SettingSource.manual);
    });

    test('detecting the same region again is not a new decision to upload', () {
      final first =
          AutoSetup.apply(const Settings(), const SetupResult(region: region));
      final acked = first
          .markInSyncFrom(first, {SettingGroup.region, SettingGroup.currency});
      final again = AutoSetup.apply(acked, const SetupResult(region: region));
      expect(again.accountInSync, acked.accountInSync);
    });
  });

  group('two phones, one account', () {
    late FakeBackend backend;
    late FakeAccountSettings server;

    setUp(() {
      backend = FakeBackend();
      server = FakeAccountSettings(backend);
    });

    test(
        'Device A detects PLN -> backend -> Device B gets PLN / accountSynced, '
        'whatever B itself would have detected', () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.runSetup();
      expect(a.settings.currency, 'PLN');
      expect(a.settings.currencySource, SettingSource.detected);
      expect(server.of('user-a'), containsPair('currencyCode', 'PLN'));
      expect(
          server.of('user-a'), containsPair('currencyCodeSource', 'detected'));
      expect(
          server.of('user-a'), containsPair('countryCodeSource', 'detected'));

      // B is a German phone: left alone it would detect EUR.
      final b = await Phone.create('B', backend,
          regionCode: 'DE', localeTag: 'de-DE');
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.countryCode, 'PL');
      expect(b.settings.currency, 'PLN');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, SettingSource.detected);
      expect(b.settings.regionSource, SettingSource.accountSynced);
      // B uploaded nothing of its own: the account's values were not echoed back as B's.
      expect(server.puts, hasLength(1));
    });

    test(
        'Device A manually selects EUR -> backend -> Device B gets EUR / '
        'accountSynced / original manual; A stays manual', () async {
      final a = await Phone.create('A', backend);
      final b = await Phone.create('B', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.currency, 'PLN');

      await a.edit((s) => s.withManualCurrency('EUR'));
      expect(a.settings.currencySource, SettingSource.manual);
      expect(a.settings.currencyOriginalSource, isNull);
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'));
      expect(server.of('user-a'), containsPair('currencyCodeSource', 'manual'));
      expect(server.puts.last, containsPair('currencyCodeSource', 'manual'));

      await b.reconcile();
      expect(b.settings.currency, 'EUR');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, SettingSource.manual);
      expect(b.settings.isCustom(SettingGroup.currency), isTrue);

      // A reconciles too: its own manual value is not turned into accountSynced
      // by being read back from the account.
      await a.reconcile();
      expect(a.settings.currency, 'EUR');
      expect(a.settings.currencySource, SettingSource.manual);
    });

    test(
        'a phone that has itself chosen by hand follows a LATER change from the '
        'other phone, and the two do not overwrite each other in turns',
        () async {
      final a = await Phone.create('A', backend);
      final b = await Phone.create('B', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await b.signIn('user-a');
      await b.runSetup();
      await b.edit((s) => s.withManualCurrency('GBP')); // acknowledged
      await a.reconcile();
      expect(a.settings.currency, 'GBP');

      await a.edit((s) => s.withManualCurrency('EUR')); // newer, from A
      await b.reconcile();
      expect(b.settings.currency, 'EUR', reason: 'B follows the newer word');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      await a.reconcile();
      await b.reconcile();
      expect(a.settings.currency, 'EUR');
      expect(b.settings.currency, 'EUR');
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'));
    });

    test(
        'a manual tariff of 0.95 on A -> B preserves it as accountSynced / '
        'original manual', () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await a.edit((s) => s.withManualPrice(0.95));
      expect(
          server.of('user-a'), containsPair('electricityPriceMode', 'manual'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.95));
      expect(server.of('user-a'),
          containsPair('electricityPriceSource', 'manual'));

      final b = await Phone.create('B', backend);
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.priceMode, ElectricityPriceMode.manual);
      expect(b.settings.manualPricePerKwh, 0.95);
      expect(b.settings.pricePerKwh, 0.95);
      expect(b.settings.priceSource, SettingSource.accountSynced);
      expect(b.settings.priceOriginalSource, SettingSource.manual);
      // And it is still B's tariff after B edits something else: the tariff is
      // not echoed back as a decision of B.
      await b.edit((s) => s.withManualCurrency('PLN'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.95));
      expect(server.of('user-a'),
          containsPair('electricityPriceSource', 'manual'));
    });

    test('automatic price mode on A -> B stays automatic', () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.runSetup();
      // The account keeps an old tariff, but the user has switched to automatic.
      await a.edit((s) => s.withManualPrice(0.95));
      await a.edit((s) => s.withAutomaticPrice());
      expect(server.of('user-a'),
          containsPair('electricityPriceMode', 'automatic'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.95));
      expect(server.of('user-a'),
          containsPair('electricityPriceSource', 'manual'));

      final b = await Phone.create('B', backend);
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.priceMode, ElectricityPriceMode.automatic,
          reason: 'the kept tariff is not a manual override');
      expect(b.settings.manualPricePerKwh, 0.95);
      expect(b.settings.priceSource, SettingSource.accountSynced);
      expect(b.settings.priceOriginalSource, SettingSource.manual);
    });

    test('switching a phone to automatic reaches the other phone', () async {
      final a = await Phone.create('A', backend);
      final b = await Phone.create('B', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await a.edit((s) => s.withManualPrice(0.95));
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.priceMode, ElectricityPriceMode.manual);

      await a.edit((s) => s.withAutomaticPrice());
      await b.reconcile();
      expect(b.settings.priceMode, ElectricityPriceMode.automatic);
      expect(b.settings.priceSource, SettingSource.accountSynced);
    });

    test(
        'a stale phone never undoes a newer change: it uploads what it decided '
        'and echoes the rest of the account', () async {
      final a = await Phone.create('A', backend);
      final b = await Phone.create('B', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await b.signIn('user-a');
      await b.runSetup();
      await a.edit((s) => s.withManualCurrency('EUR'));
      // B has not heard of EUR yet and makes a decision about the price.
      await b.edit((s) => s.withManualPrice(0.5));
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'),
          reason: 'B\'s PLN was an account value: it is not sent back');
      expect(server.of('user-a'), containsPair('currencyCodeSource', 'manual'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.5));
    });

    test('device-bound values never travel through the account settings',
        () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.edit((s) => s.withDesignCapacity(
          DesignCapacity(mah: 3274, source: DesignCapacitySource.manual)));
      await a.runSetup();
      await a.edit((s) => s.withManualCurrency('EUR'));
      for (final body in server.puts) {
        expect(
            body.keys.toSet(),
            {
              'countryCode',
              'countryCodeSource',
              'currencyCode',
              'currencyCodeSource',
              'electricityPriceMode',
              'manualElectricityPrice',
              'electricityPriceSource',
            },
            reason: 'no battery capacity, model or measurement');
      }
      final b = await Phone.create('B', backend, modelIdentifier: 'Pixel 99');
      await b.signIn('user-a');
      await b.runSetup();
      expect(
          b.settings.designCapacitySource, isNot(DesignCapacitySource.manual),
          reason: 'A\'s typed capacity did not become B\'s manual capacity');
      expect(b.settings.designCapacityMah, isNot(3274));
    });

    test('offline: the last value stays, its source is unchanged', () async {
      final a = await Phone.create('A', backend);
      final b = await Phone.create('B', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await a.edit((s) => s.withManualCurrency('EUR'));
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.currencySource, SettingSource.accountSynced);

      b.offline = true;
      await b.reconcile();
      await b.restart();
      expect(b.settings.currency, 'EUR');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, SettingSource.manual);
      // A setup run with no connection does not turn it into a detection either.
      await b.runSetup(expectUpload: false);
      expect(b.settings.currency, 'EUR');
      expect(b.settings.currencySource, SettingSource.accountSynced);

      // The network is back: the normal synchronisation follows the account.
      b.offline = false;
      await a.edit((s) => s.withManualCurrency('GBP'));
      await b.reconcile();
      expect(b.settings.currency, 'GBP');
      expect(b.settings.currencySource, SettingSource.accountSynced);
    });

    test(
        'a choice made offline stays a choice, and goes up when the network '
        'is back', () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.runSetup();
      a.offline = true;
      await a.edit((s) => s.withManualCurrency('EUR'));
      expect(a.settings.currencySource, SettingSource.manual);
      expect(a.settings.accountInSync, isNot(contains(SettingGroup.currency)));
      expect(server.of('user-a'), containsPair('currencyCode', 'PLN'));

      a.offline = false;
      await a.reconcile();
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'));
      expect(server.of('user-a'), containsPair('currencyCodeSource', 'manual'));
      expect(a.settings.currencySource, SettingSource.manual);
      expect(a.settings.accountInSync, contains(SettingGroup.currency));
    });

    test('a manual currency survives a restart of the app', () async {
      final a = await Phone.create('A', backend);
      await a.signIn('user-a');
      await a.runSetup();
      await a.edit((s) => s.withManualCurrency('EUR'));
      await a.restart();
      expect(a.settings.currency, 'EUR');
      expect(a.settings.currencySource, SettingSource.manual);
      expect(a.settings.onboarded, isTrue);
      // ... and so does an account value, with its original.
      final b = await Phone.create('B', backend);
      await b.signIn('user-a');
      await b.runSetup();
      await b.restart();
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, SettingSource.manual);
      expect(SettingsStore(b.prefs).load().currencySource,
          SettingSource.accountSynced);
    });

    test('the same phone, another install: the account loads its settings',
        () async {
      final first = await Phone.create('install 1', backend);
      await first.signIn('user-a');
      await first.runSetup();
      await first.edit((s) => s.withManualCurrency('EUR'));
      await first.edit((s) => s.withManualPrice(0.95));

      // A new install: empty preferences, empty database, same user.
      final second = await Phone.create('install 2', backend);
      await second.signIn('user-a');
      expect(second.settings.currency, isEmpty,
          reason: 'nothing is known before the setup');
      await second.runSetup();
      expect(second.settings.currency, 'EUR');
      expect(second.settings.currencySource, SettingSource.accountSynced);
      expect(second.settings.currencyOriginalSource, SettingSource.manual);
      expect(second.settings.priceSource, SettingSource.accountSynced);
      expect(second.settings.manualPricePerKwh, 0.95);
    });

    test(
        'an account whose values were saved by an older client: origin unknown',
        () async {
      server.seedLegacy('user-a',
          country: 'PL', currency: 'PLN', mode: 'manual', price: 0.8);
      final b = await Phone.create('B', backend);
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.currency, 'PLN');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, isNull, reason: 'not guessed');
      expect(b.settings.priceMode, ElectricityPriceMode.manual);
      expect(b.settings.priceSource, SettingSource.accountSynced);
      expect(b.settings.isCustom(SettingGroup.currency), isFalse);
    });
  });

  group('account switching on one phone', () {
    late FakeBackend backend;
    late FakeAccountSettings server;

    setUp(() {
      backend = FakeBackend();
      server = FakeAccountSettings(backend);
    });

    test(
        'User A logs in -> settings A; logout; User B logs in -> settings B; '
        'nothing of A reaches B', () async {
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('EUR'));
      await phone.edit((s) => s.withManualPrice(0.95));
      expect(phone.settings.currencySource, SettingSource.manual);

      await phone.signOut();
      await phone.signIn('user-b');
      // B starts from nothing: none of A's choices, none of A's sources.
      expect(phone.settings.currency, isEmpty);
      expect(phone.settings.currencySource, SettingSource.detected);
      expect(phone.settings.priceMode, ElectricityPriceMode.automatic);
      expect(phone.settings.manualPricePerKwh, 0);
      expect(phone.settings.priceSource, SettingSource.detected);
      expect(phone.settings.accountInSync, isEmpty);
      expect(phone.settings.onboarded, isFalse,
          reason: 'B goes through the setup, which loads B\'s account');
      expect(phone.settings.countryCode, isEmpty);

      await phone.runSetup();
      // B's own account is empty: B gets what the phone detects, as detected.
      expect(phone.settings.currency, 'PLN');
      expect(phone.settings.currencySource, SettingSource.detected);
      expect(phone.settings.priceMode, ElectricityPriceMode.automatic);
      expect(phone.settings.manualPricePerKwh, 0);
      // The server: B never received an A value, A kept its own.
      expect(server.of('user-b'), containsPair('currencyCode', 'PLN'));
      expect(
          server.of('user-b'), containsPair('currencyCodeSource', 'detected'));
      expect(server.of('user-b'), containsPair('manualElectricityPrice', null));
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.95));
    });

    test('B\'s own account settings are loaded for B, as accountSynced',
        () async {
      final bPhone = await Phone.create('other', backend);
      await bPhone.signIn('user-b');
      await bPhone.runSetup();
      await bPhone.edit((s) => s.withManualCurrency('GBP'));

      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('EUR'));
      await phone.signOut();
      await phone.signIn('user-b');
      await phone.runSetup();
      expect(phone.settings.currency, 'GBP');
      expect(phone.settings.currencySource, SettingSource.accountSynced);
      expect(phone.settings.currencyOriginalSource, SettingSource.manual);
    });

    test(
        'A comes back and finds A\'s settings exactly as they were, B\'s do not follow',
        () async {
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('EUR'));
      await phone.edit((s) => s.withManualPrice(0.95));
      final before = phone.settings;

      await phone.signOut();
      await phone.signIn('user-b');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('GBP'));

      await phone.signOut();
      await phone.signIn('user-a');
      expect(phone.settings.onboarded, isTrue,
          reason: 'A does not go through the setup again');
      expect(phone.settings.currency, 'EUR');
      expect(phone.settings.currencySource, before.currencySource);
      expect(phone.settings.priceMode, ElectricityPriceMode.manual);
      expect(phone.settings.manualPricePerKwh, 0.95);
      expect(phone.settings.priceSource, before.priceSource);
      expect(phone.settings.accountInSync, before.accountInSync);
    });

    test('an accountSynced value of A is not a manual value of B', () async {
      final other = await Phone.create('other', backend);
      await other.signIn('user-a');
      await other.runSetup();
      await other.edit((s) => s.withManualCurrency('EUR'));

      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      expect(phone.settings.currencySource, SettingSource.accountSynced);
      await phone.signOut();
      await phone.signIn('user-b');
      await phone.runSetup();
      expect(phone.settings.currency, 'PLN', reason: 'detected for B');
      expect(phone.settings.currencySource, SettingSource.detected);
      expect(phone.settings.currencyOriginalSource, isNull);
      expect(server.of('user-b'), containsPair('currencyCode', 'PLN'));
    });

    test(
        'device-bound values stay with the phone across accounts '
        '(the phone is still the same phone)', () async {
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      final model = phone.settings.deviceModelIdentifier;
      await phone.edit((s) => s.copyWith(efficiency: 0.9));
      await phone.signOut();
      await phone.signIn('user-b');
      expect(phone.settings.deviceModelIdentifier, model);
      expect(phone.settings.efficiency, 0.9);
    });

    test('the start gate waits for the account\'s own settings', () {
      final auth = AsyncData<AuthState>(SignedIn(AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime(2030),
          user: const User(id: 'user-b', email: 'b@example.test'))));
      const previousUser = Settings(onboarded: true);
      expect(
          startDestination(
              localOnlyDev: false,
              auth: auth,
              settings: previousUser,
              settingsBound: false),
          StartDestination.splash,
          reason: 'what is on the phone may be the previous user\'s');
      expect(
          startDestination(
              localOnlyDev: false, auth: auth, settings: previousUser),
          StartDestination.dashboard);
    });

    test('deleting the account erases its settings from the phone', () async {
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.edit((s) => s.withManualCurrency('EUR'));
      await phone.edit((s) => s.withManualPrice(0.95));
      final user =
          (phone.c.read(authControllerProvider).value as SignedIn).user;
      await phone.c.read(accountDeletedHookProvider)(user);
      expect(phone.settings.currency, isEmpty);
      expect(phone.settings.manualPricePerKwh, 0);
      expect(phone.settings.onboarded, isFalse);
      await phone.signOut();
      await phone.signIn('user-b');
      expect(phone.settings.currency, isEmpty);
      expect(phone.settings.currencySource, SettingSource.detected);
    });
  });

  group('legacy preferences (the old onboarding)', () {
    test('conscious values are kept as migratedManual and survive the setup',
        () async {
      final backend = FakeBackend();
      final server = FakeAccountSettings(backend);
      final phone = await Phone.create('old phone', backend, storedPrefs: {
        // What the old onboarding wrote: no sources, no region.
        'wb.currency': 'EUR',
        'wb.pricePerKwh': 0.82,
        'wb.batteryCapacityMah': 4000.0,
        'wb.onboarded': true,
      });
      // The first account to sign in on the phone adopts what is on it.
      await phone.signIn('user-a');
      expect(phone.settings.currency, 'EUR');
      expect(phone.settings.currencySource, SettingSource.migratedManual);
      expect(phone.settings.priceSource, SettingSource.migratedManual);
      expect(phone.settings.priceMode, ElectricityPriceMode.manual);
      expect(phone.settings.manualPricePerKwh, 0.82);
      expect(phone.settings.onboarded, isTrue);
      expect(phone.settings.designCapacitySource, DesignCapacitySource.manual);

      // The shell reconciles at start: the old choices go up as such.
      await phone.reconcile();
      expect(server.of('user-a'), containsPair('currencyCode', 'EUR'));
      expect(server.of('user-a'),
          containsPair('currencyCodeSource', 'migratedManual'));
      expect(server.of('user-a'), containsPair('manualElectricityPrice', 0.82));
      expect(server.of('user-a'),
          containsPair('electricityPriceSource', 'migratedManual'));
      expect(phone.settings.currencySource, SettingSource.migratedManual,
          reason: 'being uploaded does not change what it is');

      // Another phone of the same user gets them with the original.
      final b = await Phone.create('B', backend);
      await b.signIn('user-a');
      await b.runSetup();
      expect(b.settings.currency, 'EUR');
      expect(b.settings.currencySource, SettingSource.accountSynced);
      expect(b.settings.currencyOriginalSource, SettingSource.migratedManual);
      expect(b.settings.priceOriginalSource, SettingSource.migratedManual);
    });

    test('the old phone\'s answers do not reach a SECOND account', () async {
      final backend = FakeBackend();
      FakeAccountSettings(backend);
      final phone = await Phone.create('old phone', backend, storedPrefs: {
        'wb.currency': 'EUR',
        'wb.pricePerKwh': 0.82,
        'wb.onboarded': true,
      });
      await phone.signIn('user-a');
      await phone.signOut();
      await phone.signIn('user-b');
      expect(phone.settings.currency, isEmpty);
      expect(phone.settings.currencySource, SettingSource.detected);
      expect(phone.settings.manualPricePerKwh, 0);
      expect(phone.settings.onboarded, isFalse);
    });

    test(
        'a fresh phone has nothing to migrate: no value is invented as a choice',
        () async {
      final backend = FakeBackend();
      FakeAccountSettings(backend);
      final phone = await Phone.create('new phone', backend);
      await phone.signIn('user-a');
      expect(phone.settings.currencySource, SettingSource.detected);
      expect(phone.settings.priceSource, SettingSource.detected);
      expect(phone.settings.regionSource, SettingSource.detected);
      expect(phone.settings.accountInSync, isEmpty);
      expect(groupsToPush(phone.settings), isEmpty);
    });
  });

  group('the preferences of an account are stored under a one-way key', () {
    test('neither the user id nor the e-mail is written into them', () async {
      final backend = FakeBackend();
      FakeAccountSettings(backend);
      final phone = await Phone.create('phone', backend);
      await phone.signIn('user-a');
      await phone.runSetup();
      await phone.signOut();
      await phone.signIn('user-b');
      final keys = phone.prefs.getKeys();
      expect(keys.where((k) => k.startsWith('wb.acct.')), isNotEmpty,
          reason: 'user-a\'s settings are put away');
      for (final k in keys) {
        expect(k, isNot(contains('user-a')));
        expect(k, isNot(contains('user-b')));
        expect('${phone.prefs.get(k)}', isNot(contains('user-a')));
        expect('${phone.prefs.get(k)}', isNot(contains('@example.test')));
      }
      final owner = phone.store.accountOwner!;
      expect(owner, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });
}
