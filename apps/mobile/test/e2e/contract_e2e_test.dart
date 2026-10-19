@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/generated/api/api.dart' as api;

/// The optional-null contract end to end: the REAL generated client sends every unset optional
/// field as an explicit JSON `null` (see `generated_client_contract_test.dart`), and a RUNNING API on
/// PostgreSQL must accept it. This is the regression for the bug where such requests answered 400.
///
/// Skipped unless WATTBYTE_E2E_API_URL is set:
///
///   WATTBYTE_E2E_API_URL=http://127.0.0.1:18147 flutter test test/e2e/contract_e2e_test.dart
///
/// Start the API with AI_MOCK=1 and AI_FREE_DAILY_LIMIT=4 (this test makes exactly four AI calls).
/// `GET /me/export` is limited to 6 requests per minute per IP (`CLOUD_EXPORT_RATE_LIMIT_PER_MIN`); one run
/// makes 5, so wait a minute before running it again against the same server (or restart the server).
///
/// Battery capacity (`docs/BATTERY_CAPACITY.md`) is two groups on the device record, each stored
/// atomically: the design capacity of the model and the estimated full-charge capacity of the
/// battery. The 'devices and usage' group registers the one device the later tests (export, cloud
/// data) count on; 'battery capacity groups' exercises the server rules on an account of its own.
///
/// The config route (`GET /config`) and the cloud-data routes (`DELETE /me/cloud-data`,
/// `GET /me/export`) are called through the generated API classes (`ConfigApi`, `AccountApi`); only
/// the CSV export, which is not JSON, is read from the plain HTTP response those classes also give.
void main() {
  final url = Platform.environment['WATTBYTE_E2E_API_URL'];
  final skip = url == null ? 'set WATTBYTE_E2E_API_URL to run' : null;

  final email =
      'contract-${DateTime.now().microsecondsSinceEpoch}@test.wattbyte';
  const password = 'correct horse battery';
  const installationId = 'install-contract-e2e-0001';
  late ApiFactory apis;
  late api.AuthResponse session;

  setUpAll(() => apis = ApiFactory(ApiConfig(url ?? 'http://unused')));

  api.ApiClient bearer() => apis.bearer(session.tokens.accessToken);

  group('auth', () {
    test('register without a display name: displayName goes out as null',
        () async {
      final res = await api.AuthApi(apis.anonymous()).apiV1AuthRegisterPost(
          api.RegisterRequest(email: email, password: password));
      expect(res, isNotNull);
      expect(res!.user.email, email);
      expect(res.user.displayName, isNull);
      expect(res.user.plan, api.UserDtoPlanEnum.free);
      session = res;
    }, skip: skip);

    test('register with a display name keeps it', () async {
      final named = await api.AuthApi(apis.anonymous()).apiV1AuthRegisterPost(
          api.RegisterRequest(
              email: 'named-$email', password: password, displayName: 'Ala'));
      expect(named!.user.displayName, 'Ala');
    }, skip: skip);

    test('login and refresh through the generated client', () async {
      final auth = api.AuthApi(apis.anonymous());
      final login = await auth.apiV1AuthLoginPost(
          api.LoginRequest(email: email, password: password));
      expect(login!.user.id, session.user.id);
      final next = await auth.apiV1AuthRefreshPost(
          api.RefreshRequest(refreshToken: login.tokens.refreshToken));
      expect(next!.tokens.refreshToken, isNot(login.tokens.refreshToken));
      session = next;
    }, skip: skip);
  });

  group('account', () {
    test('PATCH /me: null clears the display name, a value sets it', () async {
      final account = api.AccountApi(bearer());
      expect(
          (await account.apiV1MePatch(api.UpdateMeRequest(displayName: null)))!
              .displayName,
          isNull);
      expect(
          (await account.apiV1MePatch(api.UpdateMeRequest(displayName: 'Ala')))!
              .displayName,
          'Ala');
      expect(
          (await account.apiV1MePatch(api.UpdateMeRequest(displayName: null)))!
              .displayName,
          isNull);
    }, skip: skip);

    test('PUT /me/settings: an empty request (every field null) is accepted',
        () async {
      final account = api.AccountApi(bearer());
      final s =
          await account.apiV1MeSettingsPut(api.UpdateUserSettingsRequest());
      expect(s, isNotNull);
      expect(s!.countryCode, isNull);
      expect(s.currencyCode, isNull);
      expect(s.electricityPriceMode,
          api.UserSettingsDtoElectricityPriceModeEnum.automatic,
          reason: 'a null mode means "not given", never a mode of its own');
      expect(s.manualElectricityPrice, isNull);
    }, skip: skip);

    test('PUT /me/settings: some fields set, the rest null', () async {
      final account = api.AccountApi(bearer());
      final partial = await account.apiV1MeSettingsPut(
          api.UpdateUserSettingsRequest(
              countryCode: 'PL', currencyCode: 'PLN'));
      expect(partial!.countryCode, 'PL');
      expect(partial.currencyCode, 'PLN');
      expect(partial.electricityPriceMode,
          api.UserSettingsDtoElectricityPriceModeEnum.automatic);

      final manual =
          await account.apiV1MeSettingsPut(api.UpdateUserSettingsRequest(
        countryCode: 'PL',
        currencyCode: 'PLN',
        electricityPriceMode:
            api.UpdateUserSettingsRequestElectricityPriceModeEnum.manual,
        manualElectricityPrice: 0.95,
      ));
      expect(manual!.electricityPriceMode,
          api.UserSettingsDtoElectricityPriceModeEnum.manual);
      expect(manual.manualElectricityPrice, 0.95);

      // Manual mode without a price is the documented 400, not a crash and not silently accepted.
      await expectLater(
          account.apiV1MeSettingsPut(api.UpdateUserSettingsRequest(
              electricityPriceMode: api
                  .UpdateUserSettingsRequestElectricityPriceModeEnum.manual)),
          throwsA(
              isA<api.ApiException>().having((e) => e.code, 'status', 400)));
      final after = await account.apiV1MeSettingsGet();
      expect(after!.manualElectricityPrice, 0.95);
      expect(after.electricityPriceMode,
          api.UserSettingsDtoElectricityPriceModeEnum.manual);
    }, skip: skip);
  });

  group('devices and usage', () {
    test(
        'register a device with every optional field null, then fill both '
        'battery groups, then null again', () async {
      final devices = api.DevicesApi(bearer());
      final bare = await devices.apiV1DevicesPost(api.DeviceRegisterRequest(
          installationId: installationId,
          platform: api.DeviceRegisterRequestPlatformEnum.ios));
      expect(bare!.installationId, installationId);
      expect(bare.model, isNull);
      expect(bare.designCapacityMah, isNull);
      expect(bare.designCapacityWh, isNull);
      expect(bare.designCapacitySource, isNull);
      expect(bare.estimatedFullChargeCapacityMah, isNull);
      expect(bare.estimatedFullChargeCapacityWh, isNull);
      expect(bare.fullChargeCapacitySource, isNull);
      expect(bare.fullChargeCapacityConfidence, isNull);

      final full = await devices.apiV1DevicesPost(api.DeviceRegisterRequest(
        installationId: installationId,
        platform: api.DeviceRegisterRequestPlatformEnum.ios,
        model: 'iPhone 15 Pro',
        modelIdentifier: 'iPhone16,1',
        designCapacityMah: 3274,
        designCapacityWh: 12.7,
        designCapacitySource: api
            .DeviceRegisterRequestDesignCapacitySourceEnum.localDeviceDatabase,
        estimatedFullChargeCapacityMah: 3101.5,
        estimatedFullChargeCapacityWh: 11.9,
        fullChargeCapacitySource: api
            .DeviceRegisterRequestFullChargeCapacitySourceEnum
            .androidChargeCounter,
        fullChargeCapacityConfidence:
            api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.medium,
      ));
      expect(full!.id, bare.id, reason: 'idempotent per installation');
      expect(full.designCapacityMah, 3274);
      expect(full.designCapacityWh, 12.7);
      expect(full.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase);
      expect(full.estimatedFullChargeCapacityMah, 3101.5);
      expect(full.estimatedFullChargeCapacityWh, 11.9);
      expect(full.fullChargeCapacitySource,
          api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
      expect(full.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.medium);

      // A sync-time registration carries nulls and must not erase the setup data
      // of EITHER group (a null source keeps the stored group).
      final again = await devices.apiV1DevicesPost(api.DeviceRegisterRequest(
          installationId: installationId,
          platform: api.DeviceRegisterRequestPlatformEnum.ios));
      expect(again!.modelIdentifier, 'iPhone16,1');
      expect(again.designCapacityMah, 3274);
      expect(again.designCapacityWh, 12.7);
      expect(again.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase);
      expect(again.estimatedFullChargeCapacityMah, 3101.5);
      expect(again.estimatedFullChargeCapacityWh, 11.9);
      expect(again.fullChargeCapacitySource,
          api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
      expect(again.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.medium);
    }, skip: skip);

    test('sync days whose optional flags are left at the generated defaults',
        () async {
      final usage = api.UsageApi(bearer());
      final res = await usage.apiV1UsageSyncPost(api.UsageSyncRequest(
        installationId: installationId,
        days: [
          api.DailyUsageDto(
            date: '2026-10-11',
            mobileBytes: 1000,
            wifiBytes: 5000,
            chargedWh: 12.5,
            wallWh: 14.706,
            chargingSessions: 2,
            estimatedCost: 0.0169,
            currency: 'PLN',
          ),
          api.DailyUsageDto(
            date: '2026-10-12',
            mobileBytes: 2000,
            wifiBytes: 6000,
            chargedWh: 0,
            wallWh: 0,
            chargingSessions: 0,
            estimatedCost: 0,
            currency: 'PLN',
            dataEstimated: true,
            energyEstimated: false,
          ),
        ],
      ));
      expect(res!.accepted, 2);
      expect(res.dates, ['2026-10-11', '2026-10-12']);
      final daily = await usage.apiV1UsageDailyGet('2026-10-01', '2026-10-31');
      expect(daily!.days.map((d) => d.date), ['2026-10-11', '2026-10-12']);
      expect(daily.days[0].dataEstimated, isFalse);
      expect(daily.days[0].energyEstimated, isTrue);
      expect(daily.days[1].dataEstimated, isTrue);
      expect(daily.days[1].energyEstimated, isFalse);
    }, skip: skip);
  });

  group('battery capacity groups (design capacity / estimated full charge)',
      () {
    // An account of its own, so the single device of the main account (which
    // the export and cloud-data tests count) is not disturbed.
    final batteryEmail = 'battery-$email';
    late api.AuthResponse owner;

    api.ApiClient ownerClient() => apis.bearer(owner.tokens.accessToken);

    setUpAll(() async {
      if (url == null) return;
      final res = await api.AuthApi(apis.anonymous()).apiV1AuthRegisterPost(
          api.RegisterRequest(email: batteryEmail, password: password));
      owner = res!;
    });

    tearDownAll(() async {
      if (url == null) return;
      await api.AccountApi(ownerClient()).apiV1MeDelete();
    });

    Future<api.DeviceDto> register(
      String installation, {
      String? model,
      num? designMah,
      num? designWh,
      api.DeviceRegisterRequestDesignCapacitySourceEnum? designSource,
      num? estimateMah,
      num? estimateWh,
      api.DeviceRegisterRequestFullChargeCapacitySourceEnum? estimateSource,
      api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum? confidence,
    }) async =>
        (await api.DevicesApi(ownerClient())
            .apiV1DevicesPost(api.DeviceRegisterRequest(
          installationId: installation,
          platform: api.DeviceRegisterRequestPlatformEnum.android,
          model: model,
          designCapacityMah: designMah,
          designCapacityWh: designWh,
          designCapacitySource: designSource,
          estimatedFullChargeCapacityMah: estimateMah,
          estimatedFullChargeCapacityWh: estimateWh,
          fullChargeCapacitySource: estimateSource,
          fullChargeCapacityConfidence: confidence,
        )))!;

    Future<api.DeviceDto> stored(String installation) async =>
        (await api.DevicesApi(ownerClient()).apiV1DevicesGet())!
            .devices
            .singleWhere((d) => d.installationId == installation);

    const android = api
        .DeviceRegisterRequestFullChargeCapacitySourceEnum.androidChargeCounter;
    const manual = api.DeviceRegisterRequestDesignCapacitySourceEnum.manual;
    const local =
        api.DeviceRegisterRequestDesignCapacitySourceEnum.localDeviceDatabase;
    const unknownDesign =
        api.DeviceRegisterRequestDesignCapacitySourceEnum.unknown;
    const high = api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.high;
    const low = api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.low;

    test(
        'the design sources the other tests do not use are accepted with a '
        'capacity', () async {
      // local and manual are exercised below; these two have no other user.
      for (final (i, source) in [
        api.DeviceRegisterRequestDesignCapacitySourceEnum
            .manufacturerSpecification,
        api.DeviceRegisterRequestDesignCapacitySourceEnum.backendDeviceDatabase,
      ].indexed) {
        final d = await register('battery-source-$i-aaaa',
            designMah: 4000 + i, designSource: source);
        expect(d.designCapacityMah, 4000 + i, reason: source.name);
        expect(d.designCapacitySource.toString(), source.name);
        expect(d.estimatedFullChargeCapacityMah, isNull);
      }
    }, skip: skip);

    test(
        'Android charge counter != design capacity: an estimate registered '
        'without a design capacity leaves the design unknown', () async {
      final d = await register('battery-estimate-only-1',
          designSource: unknownDesign,
          estimateMah: 4321,
          estimateSource: android,
          confidence: high);
      expect(d.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.unknown);
      expect(d.designCapacityMah, isNull);
      expect(d.designCapacityWh, isNull);
      expect(d.estimatedFullChargeCapacityMah, 4321);
      expect(d.fullChargeCapacitySource,
          api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
      expect(d.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.high);
      // Only the estimate, with NO design source at all: nothing is stored as a
      // design capacity either (the group is simply not touched).
      final onlyEstimate = await register('battery-estimate-only-2',
          estimateMah: 4321, estimateSource: android, confidence: high);
      expect(onlyEstimate.designCapacityMah, isNull);
      expect(onlyEstimate.designCapacitySource, isNull);
      expect(onlyEstimate.estimatedFullChargeCapacityMah, 4321);
      final read = await stored('battery-estimate-only-2');
      expect(read.designCapacityMah, isNull);
      expect(read.designCapacitySource, isNull);
    }, skip: skip);

    test('each group is stored atomically: a given source replaces the group',
        () async {
      const id = 'battery-atomic-0001';
      final first = await register(id,
          model: 'Pixel 8',
          designMah: 4575,
          designWh: 17.6,
          designSource: local,
          estimateMah: 3600,
          estimateWh: 13.9,
          estimateSource: android,
          confidence: high);
      expect(first.designCapacityWh, 17.6);
      expect(first.estimatedFullChargeCapacityWh, 13.9);

      // A new design WITHOUT Wh: the old Wh must not survive next to it, and
      // the estimate (null source) is left alone.
      final newDesign =
          await register(id, designMah: 4100, designSource: manual);
      expect(newDesign.designCapacityMah, 4100);
      expect(newDesign.designCapacityWh, isNull,
          reason: 'the group is replaced with its nulls');
      expect(newDesign.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.manual);
      expect(newDesign.estimatedFullChargeCapacityMah, 3600);
      expect(newDesign.estimatedFullChargeCapacityWh, 13.9);
      expect(newDesign.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.high);
      expect(newDesign.model, 'Pixel 8', reason: 'a null model keeps the old');

      // A new estimate WITHOUT Wh and with another confidence replaces that
      // group as a whole; the design is left alone.
      final newEstimate = await register(id,
          estimateMah: 3000, estimateSource: android, confidence: low);
      expect(newEstimate.estimatedFullChargeCapacityMah, 3000);
      expect(newEstimate.estimatedFullChargeCapacityWh, isNull);
      expect(newEstimate.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.low);
      expect(newEstimate.designCapacityMah, 4100);
      expect(newEstimate.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.manual);

      // Every field null (what the sync path sends) changes nothing.
      await register(id);
      final kept = await stored(id);
      expect(kept.designCapacityMah, 4100);
      expect(kept.estimatedFullChargeCapacityMah, 3000);
      expect(kept.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.low);

      // Design source "unknown" (no numbers) clears the design group only.
      final cleared = await register(id, designSource: unknownDesign);
      expect(cleared.designCapacityMah, isNull);
      expect(cleared.designCapacityWh, isNull);
      expect(cleared.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.unknown);
      expect(cleared.estimatedFullChargeCapacityMah, 3000);
    }, skip: skip);

    test(
        'an estimate source "unknown" erases the stored estimate: this is why '
        'the app sends nulls, not "unknown", when it has no estimate',
        () async {
      const id = 'battery-erase-0001';
      await register(id,
          designMah: 4000,
          designSource: manual,
          estimateMah: 3600,
          estimateSource: android,
          confidence: high);
      final erased = await register(id,
          estimateSource:
              api.DeviceRegisterRequestFullChargeCapacitySourceEnum.unknown);
      expect(erased.estimatedFullChargeCapacityMah, isNull);
      expect(erased.fullChargeCapacityConfidence, isNull);
      expect(erased.fullChargeCapacitySource,
          api.DeviceDtoFullChargeCapacitySourceEnum.unknown);
      expect(erased.designCapacityMah, 4000, reason: 'the design is untouched');
    }, skip: skip);

    /// One request per rule of `validateBatteryCapacityGroups` and per range of
    /// the request schema; the full matrix is `apps/api/tests/battery-capacity*`.
    /// Each is HTTP 400 `validation`, which the app sees as an [ApiFailure] of
    /// kind badRequest. (Kept short on purpose: the API rate-limits a client
    /// to RATE_LIMIT_PER_MIN requests, and all e2e files share one.)
    final refused = <String, api.DeviceRegisterRequest>{
      'a design capacity without a source': _device(designMah: 4000),
      'a design capacity with source unknown':
          _device(designMah: 4000, designSource: unknownDesign),
      'a design source without a capacity': _device(designSource: manual),
      'design Wh without mAh': _device(designWh: 12, designSource: manual),
      'an estimate without a source':
          _device(estimateMah: 3600, confidence: high),
      'an estimate without a confidence':
          _device(estimateMah: 3600, estimateSource: android),
      'a confidence without an estimate':
          _device(estimateSource: android, confidence: high),
      'estimate Wh without mAh':
          _device(estimateWh: 13, estimateSource: android, confidence: high),
      'an estimate with source unknown': _device(
          estimateMah: 3600,
          confidence: high,
          estimateSource:
              api.DeviceRegisterRequestFullChargeCapacitySourceEnum.unknown),
      'design mAh above 30000': _device(designMah: 30001, designSource: manual),
      'a negative design capacity':
          _device(designMah: -4000, designSource: manual),
      'estimate mAh below 0.1':
          _device(estimateMah: 0.05, estimateSource: android, confidence: high),
    };

    test('refused: each broken group is a 400 validation failure', () async {
      for (final entry in refused.entries) {
        await expectLater(
            guarded(() =>
                api.DevicesApi(ownerClient()).apiV1DevicesPost(entry.value)),
            throwsA(isA<ApiFailure>()
                .having((f) => f.kind, 'kind', ApiFailureKind.badRequest)
                .having((f) => f.status, 'status', 400)
                .having((f) => f.code, 'code', 'validation')),
            reason: entry.key);
      }
    }, skip: skip);

    test('a refused registration stores nothing, not even the model', () async {
      const id = 'battery-refused-0001';
      final before = await register(id,
          model: 'Kept', designMah: 4000, designSource: manual);
      await expectLater(
          guarded(() => api.DevicesApi(ownerClient()).apiV1DevicesPost(_device(
              installation: id,
              model: 'Changed',
              designMah: 5000,
              designSource: unknownDesign))),
          throwsA(
              isA<ApiFailure>().having((f) => f.code, 'code', 'validation')));
      final after = await stored(id);
      expect(after.model, 'Kept');
      expect(after.designCapacityMah, 4000);
      expect(after.designCapacitySource, before.designCapacitySource);
    }, skip: skip);

    test(
        'a build that still sends the retired names stores no design capacity '
        'and answers without them', () async {
      final res = await http.post(Uri.parse('$url/api/v1/devices'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer ${owner.tokens.accessToken}',
          },
          body: jsonEncode({
            'installationId': 'battery-legacy-0001',
            'platform': 'android',
            'batteryCapacityMah': 4000,
            'batteryCapacityWh': 15.4,
            'batterySpecificationSource': 'system',
          }));
      if (res.statusCode == 400) return; // refused outright: also fine
      expect(res.statusCode, 201);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final key in [
        'batteryCapacityMah',
        'batteryCapacityWh',
        'batterySpecificationSource',
      ]) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      expect(body['designCapacityMah'], isNull,
          reason: 'a number without provenance is never promoted to a design');
      expect(body['designCapacitySource'], isNull);
      expect(body['estimatedFullChargeCapacityMah'], isNull);
    }, skip: skip);

    test('the device list carries all seven battery keys on every device',
        () async {
      final res =
          await api.DevicesApi(ownerClient()).apiV1DevicesGetWithHttpInfo();
      expect(res.statusCode, 200);
      final devices =
          (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['devices'] as List;
      expect(devices, isNotEmpty);
      for (final d in devices.cast<Map<String, dynamic>>()) {
        for (final key in [
          'designCapacityMah',
          'designCapacityWh',
          'designCapacitySource',
          'estimatedFullChargeCapacityMah',
          'estimatedFullChargeCapacityWh',
          'fullChargeCapacitySource',
          'fullChargeCapacityConfidence',
        ]) {
          expect(d.containsKey(key), isTrue, reason: '$key of ${d['id']}');
        }
        expect(d.keys.where((k) => k.startsWith('battery')), isEmpty);
      }
    }, skip: skip);

    test(
        'the public catalog answers designCapacityMah (no token), and 404 for '
        'a model it does not list', () async {
      final devices = api.DevicesApi(apis.anonymous());
      final iphone =
          await devices.apiV1DevicesSpecificationsIdentifierGet('iPhone16,1');
      expect(iphone!.modelIdentifier, 'iPhone16,1');
      expect(iphone.designCapacityMah, 3274);
      expect(iphone.designCapacityWh, 12.7);
      expect(iphone.catalogVersion, isNotEmpty);
      final pixel =
          await devices.apiV1DevicesSpecificationsIdentifierGet('Pixel 8');
      expect(pixel!.designCapacityMah, 4575);
      expect(pixel.designCapacityWh, isNull,
          reason: 'null when the catalog has no Wh, never 0');

      final raw = await devices
          .apiV1DevicesSpecificationsIdentifierGetWithHttpInfo('Pixel 8');
      final json = jsonDecode(utf8.decode(raw.bodyBytes)) as Map;
      expect(json.keys, containsAll(['designCapacityMah', 'designCapacityWh']));
      expect(
          json.keys.where((k) => k.toString().startsWith('battery')), isEmpty);

      await expectLater(
          guarded(() => devices.apiV1DevicesSpecificationsIdentifierGet(
              'Acme-Does-Not-Exist-9000')),
          throwsA(isA<ApiFailure>()
              .having((f) => f.kind, 'kind', ApiFailureKind.notFound)
              .having((f) => f.code, 'code', 'device_specification_unknown')));
    }, skip: skip);
  });

  group('AI', () {
    api.AIInput input() => api.AIInput(
          period: '2026-10',
          periodType: api.AIInputPeriodTypeEnum.month,
          mobileDataGb: 187.4,
          wifiDataGb: 1433.8,
          totalDataGb: 1621.2,
          chargingSessions: 94,
          batteryEnergyKwh: 1.56,
          wallEnergyKwh: 1.84,
          electricityCost: 2.31,
          currency: 'PLN',
          // previousPeriodChangePercent, wifiSharePercent, averageSessionMah: null
        );

    test(
        'mode, locale and the optional input numbers all null: all four AI routes answer',
        () async {
      final ai = api.AiApi(bearer());
      final answers = [
        await ai.apiV1AiInsightPost(api.AIGenerateRequest(input: input())),
        await ai
            .apiV1AiWeeklySummaryPost(api.AIGenerateRequest(input: input())),
        await ai
            .apiV1AiMonthlySummaryPost(api.AIGenerateRequest(input: input())),
        await ai.apiV1AiRoastPost(api.AIGenerateRequest(input: input())),
      ];
      for (final a in answers) {
        expect(a, isNotNull);
        expect(a!.output.title, isNotEmpty);
        expect(a.output.message, isNotEmpty);
      }
      // null mode = the server default (normal), except /ai/roast which is always roast.
      expect(answers[0]!.output.tone, api.AIOutputToneEnum.normal);
      expect(answers[3]!.output.tone, api.AIOutputToneEnum.roast);
      expect(answers.map((a) => a!.remainingToday), [3, 2, 1, 0]);
    }, skip: skip);
  });

  group('config (public, no token)', () {
    test('GET /config: environment, feature flags and the AI limits', () async {
      final config = await api.ConfigApi(apis.anonymous()).apiV1ConfigGet();
      expect(config, isNotNull);
      expect(config!.environment, api.AppConfigDtoEnvironmentEnum.development);
      expect(config.features.ai, isTrue);
      expect(config.features.cloudSync, isTrue);
      expect(config.features.subscriptions, isFalse,
          reason:
              'off unless the server is started with FEATURE_SUBSCRIPTIONS=1');
      expect(config.ai.dailyLimits.free, 4,
          reason: 'the e2e server runs with AI_FREE_DAILY_LIMIT=4');
      expect(config.ai.dailyLimits.premium,
          greaterThan(config.ai.dailyLimits.free));
    }, skip: skip);

    test('the same answer with a token and without one', () async {
      final anonymous = await api.ConfigApi(apis.anonymous()).apiV1ConfigGet();
      final signedIn = await api.ConfigApi(bearer()).apiV1ConfigGet();
      expect(signedIn, anonymous,
          reason: 'nothing account-specific in the public configuration');
    }, skip: skip);
  });

  group('cloud data (through the generated AccountApi)', () {
    // The typed export of the first test, to compare the raw answer with.
    api.CloudExportDocument? exported;

    test('export: the whole account as a typed document', () async {
      final account = api.AccountApi(bearer());
      final doc = await account.apiV1MeExportGet();
      expect(doc, isNotNull);
      exported = doc;
      expect(doc!.schemaVersion, 1);
      expect(doc.account.email, email);
      expect(doc.account.id, session.user.id);
      expect(doc.devices, hasLength(1));
      expect(doc.devices.single.designCapacityMah, 3274);
      expect(doc.devices.single.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase);
      expect(doc.devices.single.estimatedFullChargeCapacityMah, 3101.5);
      expect(doc.devices.single.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.medium);
      expect(doc.devices.single.modelIdentifier, 'iPhone16,1');
      expect(doc.dailyUsage.map((d) => d.date), ['2026-10-11', '2026-10-12']);
      expect(doc.dailyUsage.first.deviceId, doc.devices.single.id);
      expect(doc.dailyUsage.first.dataEstimated, isFalse);
      expect(doc.dailyUsage.first.energyEstimated, isTrue);
      expect(doc.aiGenerations, hasLength(4));
      expect(doc.settings.countryCode, 'PL');
      expect(doc.settings.electricityPriceMode,
          api.CloudExportSettingsElectricityPriceModeEnum.manual);
      expect(doc.settings.manualElectricityPrice, 0.95);
      expect(doc.limits.maxRowsPerCollection, 10000);
      expect(doc.limits.truncated.dailyUsage, isFalse);
      expect(doc.subscriptions, isEmpty);

      // The document never carries credentials or sessions.
      final text = jsonEncode(doc.toJson());
      for (final secret in [
        password,
        session.tokens.accessToken,
        session.tokens.refreshToken,
        'scrypt'
      ]) {
        expect(text.contains(secret), isFalse);
      }
    }, skip: skip);

    test('export: attachment headers, and the CSV variant of the daily usage',
        () async {
      final account = api.AccountApi(bearer());
      final res = await account.apiV1MeExportGetWithHttpInfo();
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], startsWith('application/json'));
      expect(
          res.headers['content-disposition'],
          matches(RegExp(
              r'^attachment; filename="wattbyte-export-\d{4}-\d{2}-\d{2}\.json"$')));
      // What came over the wire is the same document the typed call decoded
      // (apart from the instant each of the two requests was answered).
      final wire = api.CloudExportDocument.fromJson(
          jsonDecode(utf8.decode(res.bodyBytes)))!;
      expect(exported, isNotNull, reason: 'the typed export test runs first');
      wire.exportedAt = exported!.exportedAt;
      expect(wire, exported);

      final csv = await account.apiV1MeExportGetWithHttpInfo(format: 'csv');
      expect(csv.statusCode, 200);
      expect(csv.headers['content-type'], 'text/csv; charset=utf-8');
      final lines = const LineSplitter().convert(utf8.decode(csv.bodyBytes));
      expect(lines.first,
          'date,deviceId,mobileBytes,wifiBytes,chargedWh,wallWh,chargingSessions,estimatedCost,currency,dataEstimated,energyEstimated');
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('2026-10-11,'));

      await expectLater(
          account.apiV1MeExportGet(format: 'xml'),
          throwsA(
              isA<api.ApiException>().having((e) => e.code, 'status', 400)));
    }, skip: skip);

    test('export without a token is refused', () async {
      await expectLater(
          api.AccountApi(apis.anonymous()).apiV1MeExportGet(),
          throwsA(
              isA<api.ApiException>().having((e) => e.code, 'status', 401)));
    }, skip: skip);

    test(
        'delete cloud data: usage and AI log go, account, settings and device stay, sync resumes',
        () async {
      final account = api.AccountApi(bearer());
      final res = await account.apiV1MeCloudDataDelete();
      expect(res, isNotNull);
      expect(res!.deleted.dailyUsage, 2);
      expect(res.deleted.chargingSummaries, 0);
      expect(res.deleted.monthlySummaries, 0);
      expect(res.deleted.aiGenerations, 4);
      expect(res.deleted.devices, 0);

      final again = await account.apiV1MeCloudDataDelete();
      expect(again!.deleted.dailyUsage, 0, reason: 'idempotent');
      expect(again.deleted.aiGenerations, 0);

      expect(
          (await api.UsageApi(bearer())
                  .apiV1UsageDailyGet('2026-10-01', '2026-10-31'))!
              .days,
          isEmpty);
      expect((await api.DevicesApi(bearer()).apiV1DevicesGet())!.devices,
          hasLength(1));
      expect((await account.apiV1MeGet())!.email, email);
      expect((await account.apiV1MeSettingsGet())!.countryCode, 'PL');

      // The kept device accepts the next sync without registering again.
      final resumed =
          await api.UsageApi(bearer()).apiV1UsageSyncPost(api.UsageSyncRequest(
        installationId: installationId,
        days: [
          api.DailyUsageDto(
              date: '2026-10-12',
              mobileBytes: 1,
              wifiBytes: 2,
              chargedWh: 0,
              wallWh: 0,
              chargingSessions: 0,
              estimatedCost: 0,
              currency: 'PLN'),
        ],
      ));
      expect(resumed!.accepted, 1);

      // ?devices=true takes the device too.
      final all = await account.apiV1MeCloudDataDelete(devices: 'true');
      expect(all!.deleted.devices, 1);
      expect(all.deleted.dailyUsage, 1);
      expect(
          (await api.DevicesApi(bearer()).apiV1DevicesGet())!.devices, isEmpty);
    }, skip: skip);

    test('delete cloud data needs a token', () async {
      await expectLater(
          api.AccountApi(apis.anonymous()).apiV1MeCloudDataDelete(),
          throwsA(
              isA<api.ApiException>().having((e) => e.code, 'status', 401)));
    }, skip: skip);

    test('delete account: every old token stops working', () async {
      final old = session.tokens.accessToken;
      await api.AccountApi(bearer()).apiV1MeDelete();
      for (final call in <Future<Object?> Function()>[
        () => api.AccountApi(apis.bearer(old)).apiV1MeCloudDataDelete(),
        () => api.AccountApi(apis.bearer(old)).apiV1MeGet(),
      ]) {
        await expectLater(
            call(),
            throwsA(
                isA<api.ApiException>().having((e) => e.code, 'status', 401)));
      }
      await expectLater(
          api.AuthApi(apis.anonymous()).apiV1AuthRefreshPost(
              api.RefreshRequest(refreshToken: session.tokens.refreshToken)),
          throwsA(
              isA<api.ApiException>().having((e) => e.code, 'status', 401)));
    }, skip: skip);
  });
}

/// A registration request built for the refused-cases table.
api.DeviceRegisterRequest _device({
  String installation = 'battery-refused-xxxx',
  String? model,
  num? designMah,
  num? designWh,
  api.DeviceRegisterRequestDesignCapacitySourceEnum? designSource,
  num? estimateMah,
  num? estimateWh,
  api.DeviceRegisterRequestFullChargeCapacitySourceEnum? estimateSource,
  api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum? confidence,
}) =>
    api.DeviceRegisterRequest(
      installationId: installation,
      platform: api.DeviceRegisterRequestPlatformEnum.android,
      model: model,
      designCapacityMah: designMah,
      designCapacityWh: designWh,
      designCapacitySource: designSource,
      estimatedFullChargeCapacityMah: estimateMah,
      estimatedFullChargeCapacityWh: estimateWh,
      fullChargeCapacitySource: estimateSource,
      fullChargeCapacityConfidence: confidence,
    );
