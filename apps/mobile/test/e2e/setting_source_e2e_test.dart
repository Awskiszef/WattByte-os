@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/features/auth/domain/auth_models.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/generated/api/api.dart' as api;
import 'package:wattbyte/settings/settings.dart';

import '../support/phone_rig.dart';

/// Where a setting came from, across PHONES and ACCOUNTS, against a RUNNING API
/// on PostgreSQL (`docs/SETTING_SOURCES.md`).
///
/// Skipped unless WATTBYTE_E2E_API_URL is set (see test/e2e/api_e2e_test.dart); run
/// the API with AI_MOCK=1 and a high AUTH_RATE_LIMIT_PER_MIN:
///
///   WATTBYTE_E2E_API_URL=http://127.0.0.1:18080 flutter test test/e2e/setting_source_e2e_test.dart
///
/// Every phone is real except its platform: the providers (auth, the settings
/// binding to the signed-in account, setup, account sync), the generated client,
/// the HTTP stack, the API and PostgreSQL. Each phone has its own preferences and
/// SQLite, so a value can only travel through the account.
void main() {
  // The fake native side of a phone needs the test binding; the network must
  // stay real (the binding would answer every request with 400).
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final url = Platform.environment['WATTBYTE_E2E_API_URL'];
  final skip = url == null ? 'set WATTBYTE_E2E_API_URL to run' : null;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  var counter = 0;
  String email(String what) =>
      'e2e-src-$what-$stamp-${counter++}@test.wattbyte';

  Future<Phone> phone(String name,
          {String region = 'PL',
          String locale = 'en-PL',
          Map<String, Object> prefs = const {}}) =>
      Phone.create(name, null,
          apiUrl: url,
          regionCode: region,
          localeTag: locale,
          storedPrefs: prefs);

  /// What the SERVER holds for the account [p] is signed in as.
  Future<api.UserSettingsDto> account(Phone p) async =>
      (await p.c.read(accountSettingsSyncProvider)!.pull())!;

  test(
      'Device A detects PLN -> API -> PostgreSQL -> Device B (a German phone) '
      'gets PLN / accountSynced / original detected', () async {
    final user = email('detect');
    final a = await phone('A');
    await a.signUp(user);
    await a.runSetup();
    expect(a.settings.currency, 'PLN');
    expect(a.settings.currencySource, SettingSource.detected);
    expect(a.settings.priceSource, SettingSource.detected);

    final stored = await account(a);
    expect(stored.countryCode, 'PL');
    expect(stored.countryCodeSource,
        api.UserSettingsDtoCountryCodeSourceEnum.detected);
    expect(stored.currencyCode, 'PLN');
    expect(stored.currencyCodeSource,
        api.UserSettingsDtoCurrencyCodeSourceEnum.detected);
    expect(stored.electricityPriceSource, isNull,
        reason: 'nobody decided anything about the price');

    final b = await phone('B', region: 'DE', locale: 'de-DE');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.countryCode, 'PL');
    expect(b.settings.currency, 'PLN');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, SettingSource.detected);
    expect(b.settings.regionSource, SettingSource.accountSynced);
    // The same after a restart of B.
    await b.restart();
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, SettingSource.detected);
  }, skip: skip);

  test(
      'Device A manually selects EUR -> API -> Device B gets EUR / accountSynced '
      '/ original manual, and A stays manual', () async {
    final user = email('manual');
    final a = await phone('A');
    await a.signUp(user);
    await a.runSetup();
    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.currency, 'PLN');

    await a.edit((s) => s.withManualCurrency('EUR'));
    final stored = await account(a);
    expect(stored.currencyCode, 'EUR');
    expect(stored.currencyCodeSource,
        api.UserSettingsDtoCurrencyCodeSourceEnum.manual);
    expect(stored.countryCodeSource,
        api.UserSettingsDtoCountryCodeSourceEnum.detected,
        reason: 'the country was not touched');

    await b.reconcile();
    expect(b.settings.currency, 'EUR');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, SettingSource.manual);
    await a.reconcile();
    expect(a.settings.currencySource, SettingSource.manual);
    expect(a.settings.currencyOriginalSource, isNull);

    // B starts again: still synced, still EUR.
    await b.restart();
    expect(b.settings.currency, 'EUR');
    expect(b.settings.currencySource, SettingSource.accountSynced);
  }, skip: skip);

  test(
      'a manual tariff of 0.95 PLN/kWh on A is preserved on B as manual tariff, '
      'accountSynced / original manual', () async {
    final user = email('tariff');
    final a = await phone('A');
    await a.signUp(user);
    await a.runSetup();
    await a.edit((s) => s.withManualPrice(0.95));
    final stored = await account(a);
    expect(stored.electricityPriceMode,
        api.UserSettingsDtoElectricityPriceModeEnum.manual);
    expect(stored.manualElectricityPrice, 0.95);
    expect(stored.electricityPriceSource,
        api.UserSettingsDtoElectricityPriceSourceEnum.manual);

    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.priceMode, ElectricityPriceMode.manual);
    expect(b.settings.manualPricePerKwh, 0.95);
    expect(b.settings.pricePerKwh, 0.95);
    expect(b.settings.priceSource, SettingSource.accountSynced);
    expect(b.settings.priceOriginalSource, SettingSource.manual);
    // The tariff survives the setup's own price lookup on B.
    expect(b.settings.pricePerKwh, 0.95);
  }, skip: skip);

  test(
      'automatic price mode on A: B stays automatic, the household average is '
      'still refreshed by ElectricityPriceService and never becomes a manual override',
      () async {
    final user = email('auto');
    final a = await phone('A');
    await a.signUp(user);
    await a.runSetup();
    await a.edit((s) => s.withManualPrice(0.95));
    await a.edit((s) => s.withAutomaticPrice());
    final stored = await account(a);
    expect(stored.electricityPriceMode,
        api.UserSettingsDtoElectricityPriceModeEnum.automatic);
    expect(stored.manualElectricityPrice, 0.95,
        reason: 'kept for the way back');

    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.priceMode, ElectricityPriceMode.automatic);
    expect(b.settings.manualPricePerKwh, 0.95);
    expect(b.settings.priceSource, SettingSource.accountSynced);
    expect(b.settings.priceOriginalSource, SettingSource.manual);
    // The average of the real API (Eurostat), when it could be reached.
    final auto = b.settings.autoPrice;
    if (auto != null) {
      expect(b.settings.pricePerKwh, auto.pricePerKwh,
          reason: 'the effective price is the average of this phone, not 0.95');
      expect(b.settings.pricePerKwh, isNot(0.95));
    } else {
      stderr.writeln('note: the household price source was unreachable; '
          'the average itself is covered by api_e2e_test.dart');
    }
    // A later refresh of the average changes the number and nothing else.
    final refreshed = b.settings.withAutoPrice(AutoPrice(
        pricePerKwh: 2.5,
        currency: b.settings.currency,
        countryCode: 'PL',
        period: '2026-S2',
        source: 'eurostat',
        updatedAt: DateTime.now()));
    expect(refreshed.priceMode, ElectricityPriceMode.automatic);
    expect(refreshed.priceSource, SettingSource.accountSynced);
    expect(refreshed.pricePerKwh, 2.5);
  }, skip: skip);

  test(
      'User A logs in -> settings A; logout; User B logs in -> settings B; '
      'nothing of A reaches B (manual currency, manual tariff, accountSynced state)',
      () async {
    final userA = email('leak-a');
    final userB = email('leak-b');
    // B exists with an account of its own, with settings of its own.
    final bOther =
        await phone('B on another phone', region: 'GB', locale: 'en-GB');
    await bOther.signUp(userB);
    await bOther.runSetup();
    expect(bOther.settings.currency, 'GBP');

    // A's phone: A chooses by hand and has a synced value, too.
    final a2 = await phone('A on another phone');
    await a2.signUp(userA);
    await a2.runSetup();
    await a2.edit((s) => s.withManualCurrency('EUR'));

    final phoneA = await phone('shared phone');
    await phoneA.signIn(userA);
    await phoneA.runSetup();
    expect(phoneA.settings.currencySource, SettingSource.accountSynced,
        reason: 'A\'s EUR came from A\'s account');
    await phoneA.edit((s) => s.withManualPrice(0.95));
    final ownerKeyA = phoneA.store.accountOwner;

    await phoneA.signOut();
    await phoneA.signIn(userB);
    expect(phoneA.store.accountOwner, isNot(ownerKeyA));
    // Right after B signs in, before B's setup: nothing of A is in B's settings.
    expect(phoneA.settings.currency, isEmpty);
    expect(phoneA.settings.currencySource, SettingSource.detected);
    expect(phoneA.settings.priceMode, ElectricityPriceMode.automatic);
    expect(phoneA.settings.manualPricePerKwh, 0);
    expect(phoneA.settings.priceSource, SettingSource.detected);
    expect(phoneA.settings.accountInSync, isEmpty);
    expect(phoneA.settings.onboarded, isFalse);

    await phoneA.runSetup();
    // B's own account answers: GBP, detected on B's other phone.
    expect(phoneA.settings.currency, 'GBP');
    expect(phoneA.settings.currencySource, SettingSource.accountSynced);
    expect(phoneA.settings.currencyOriginalSource, SettingSource.detected);
    expect(phoneA.settings.priceMode, ElectricityPriceMode.automatic);
    expect(phoneA.settings.manualPricePerKwh, 0);

    // The servers: neither account was touched by the other.
    final storedB = await account(phoneA);
    expect(storedB.currencyCode, 'GBP');
    expect(storedB.manualElectricityPrice, isNull);
    expect(storedB.electricityPriceMode,
        api.UserSettingsDtoElectricityPriceModeEnum.automatic);
    final storedA = await account(a2);
    expect(storedA.currencyCode, 'EUR');
    expect(storedA.manualElectricityPrice, 0.95);

    // A comes back to the shared phone: its own settings, no setup again.
    await phoneA.signOut();
    await phoneA.signIn(userA);
    expect(phoneA.store.accountOwner, ownerKeyA);
    expect(phoneA.settings.onboarded, isTrue);
    expect(phoneA.settings.currency, 'EUR');
    expect(phoneA.settings.currencySource, SettingSource.accountSynced);
    expect(phoneA.settings.manualPricePerKwh, 0.95);
    expect(phoneA.settings.priceMode, ElectricityPriceMode.manual);
  }, skip: skip);

  test(
      'offline: the cached account setting stays and its source does not change; '
      'when the network is back the normal synchronisation runs', () async {
    final user = email('offline');
    final a = await phone('A');
    await a.signUp(user);
    await a.runSetup();
    await a.edit((s) => s.withManualCurrency('EUR'));
    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.currencySource, SettingSource.accountSynced);

    b.offline = true;
    await b.reconcile();
    await b.restart();
    expect(b.settings.currency, 'EUR');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, SettingSource.manual);

    // A changes it meanwhile; B's own choice is made offline.
    await a.edit((s) => s.withManualCurrency('GBP'));
    await b.edit((s) => s.withManualPrice(0.5));
    expect(b.settings.priceSource, SettingSource.manual);
    expect(b.settings.accountInSync, isNot(contains(SettingGroup.price)));

    b.offline = false;
    await b.reconcile();
    expect(b.settings.currency, 'GBP', reason: 'the account is the newer word');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.priceMode, ElectricityPriceMode.manual);
    expect(b.settings.priceSource, SettingSource.manual,
        reason: 'B\'s own choice went up and stayed B\'s');
    final stored = await account(b);
    expect(stored.currencyCode, 'GBP', reason: 'B did not undo A\'s change');
    expect(stored.manualElectricityPrice, 0.5);
    expect(stored.electricityPriceSource,
        api.UserSettingsDtoElectricityPriceSourceEnum.manual);
  }, skip: skip);

  test(
      'legacy migration: the old onboarding\'s answers are kept as migratedManual, '
      'go up as such, and reach the other phone with that original', () async {
    final user = email('legacy');
    final old = await phone('old install', prefs: {
      'wb.currency': 'EUR',
      'wb.pricePerKwh': 0.82,
      'wb.batteryCapacityMah': 4000.0,
      'wb.onboarded': true,
    });
    await old.signUp(user);
    expect(old.settings.currency, 'EUR');
    expect(old.settings.currencySource, SettingSource.migratedManual);
    expect(old.settings.priceSource, SettingSource.migratedManual);
    expect(old.settings.onboarded, isTrue, reason: 'no new setup for them');
    await old.reconcile();
    final stored = await account(old);
    expect(stored.currencyCode, 'EUR');
    expect(stored.currencyCodeSource,
        api.UserSettingsDtoCurrencyCodeSourceEnum.migratedManual);
    expect(stored.manualElectricityPrice, 0.82);
    expect(stored.electricityPriceSource,
        api.UserSettingsDtoElectricityPriceSourceEnum.migratedManual);
    expect(old.settings.currencySource, SettingSource.migratedManual);

    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.currency, 'EUR');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, SettingSource.migratedManual);
    expect(b.settings.priceOriginalSource, SettingSource.migratedManual);
    expect(b.settings.manualPricePerKwh, 0.82);
  }, skip: skip);

  test(
      'compatibility: an older client that sends no origins leaves them unknown; '
      'the phone still takes the value as accountSynced, with no original',
      () async {
    final user = email('oldclient');
    final seed = await phone('seed');
    await seed.signUp(user);
    final token = (await seed.tokens.read())!.accessToken;
    // What the previous build of the app sent: four fields, no origins.
    final res = await http.put(Uri.parse('$url/api/v1/me/settings'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json'
        },
        body: jsonEncode({
          'countryCode': 'PL',
          'currencyCode': 'PLN',
          'electricityPriceMode': 'manual',
          'manualElectricityPrice': 0.8,
        }));
    expect(res.statusCode, 200, reason: res.body);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    expect(json['currencyCodeSource'], isNull);
    expect(json['countryCodeSource'], isNull);
    expect(json['electricityPriceSource'], isNull);

    final b = await phone('B');
    await b.signIn(user);
    await b.runSetup();
    expect(b.settings.currency, 'PLN');
    expect(b.settings.currencySource, SettingSource.accountSynced);
    expect(b.settings.currencyOriginalSource, isNull);
    expect(b.settings.priceMode, ElectricityPriceMode.manual);
    expect(b.settings.manualPricePerKwh, 0.8);
    expect(b.settings.priceSource, SettingSource.accountSynced);

    // The API refuses to store "accountSynced" as an origin.
    final bad = await http.put(Uri.parse('$url/api/v1/me/settings'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json'
        },
        body: jsonEncode(
            {'currencyCode': 'EUR', 'currencyCodeSource': 'accountSynced'}));
    expect(bad.statusCode, 400);
  }, skip: skip);

  test('the account of the phone is the account that signed in', () async {
    final a = await phone('A');
    await a.signUp(email('who'));
    final user = (a.c.read(authControllerProvider).value as SignedIn).user;
    expect(a.userId, user.id);
    expect(a.store.accountOwner, matches(RegExp(r'^[0-9a-f]{32}$')));
  }, skip: skip);
}
