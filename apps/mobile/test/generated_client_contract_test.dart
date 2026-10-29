import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/generated/api/api.dart' as api;

/// The generated client (`lib/generated/api`, never edited by hand) against the shapes the API
/// publishes. Importing it compiles all of it; on top of that:
///
/// * every REQUEST model is built with its optional fields left unset and must serialise them as an
///   explicit JSON `null`: this is what the generator emits for an absent optional field, and the
///   reason the API's request schemas accept `null` (`apps/api/tests/contract-nulls.test.ts`);
/// * every RESPONSE model is round-tripped (`fromJson` then `toJson`) from a realistic server answer,
///   with its nullable fields both set and null;
/// * every enum survives its own `toJson` and rejects values it does not know;
/// * every generated model file is covered by one of the above (a newly generated model fails this
///   test until a case is added);
/// * the client is checked against the published OpenAPI document
///   (`packages/contracts/openapi/openapi.json`): every route has a generated method, every schema a model
///   class, every enum the same values, and the fixtures below carry exactly the properties of their schema.

/// Normalises what `toJson()` returns (which may hold model objects and enums) into plain JSON.
Object? wire(Object? model) => jsonDecode(jsonEncode(model));

Map<String, dynamic> wireMap(Object? model) =>
    wire(model) as Map<String, dynamic>;

class RequestCase {
  const RequestCase(this.file, this.model, this.json);

  /// Model file name in `lib/generated/api/model` without `.dart`.
  final String file;
  final Object model;

  /// Exactly what goes on the wire, optional fields as explicit nulls.
  final Map<String, Object?> json;
}

class ResponseCase {
  const ResponseCase(this.file, this.fromJson, this.json);

  final String file;
  final Object? Function(dynamic) fromJson;
  final Map<String, Object?> json;
}

const uuid = '11111111-1111-4111-8111-111111111111';
const at = '2026-10-13T10:00:00.000Z';

final dailyDto = api.DailyUsageDto(
  date: '2026-10-12',
  mobileBytes: 1000,
  wifiBytes: 5000,
  chargedWh: 12.5,
  wallWh: 14.706,
  chargingSessions: 2,
  estimatedCost: 0.0169,
  currency: 'PLN',
);

final aiInput = api.AIInput(
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
);

const dailyJson = <String, Object?>{
  'date': '2026-10-12',
  'mobileBytes': 1000,
  'wifiBytes': 5000,
  'chargedWh': 12.5,
  'wallWh': 14.706,
  'chargingSessions': 2,
  'estimatedCost': 0.0169,
  'currency': 'PLN',
  'dataEstimated': false,
  'energyEstimated': true,
};

const aiInputJson = <String, Object?>{
  'period': '2026-10',
  'periodType': 'month',
  'mobileDataGb': 187.4,
  'wifiDataGb': 1433.8,
  'totalDataGb': 1621.2,
  'chargingSessions': 94,
  'batteryEnergyKwh': 1.56,
  'wallEnergyKwh': 1.84,
  'electricityCost': 2.31,
  'currency': 'PLN',
  'previousPeriodChangePercent': null,
  'wifiSharePercent': null,
  'averageSessionMah': null,
};

const userJson = <String, Object?>{
  'id': uuid,
  'email': 'a@b.co',
  'displayName': 'Ala',
  'plan': 'premium',
  'createdAt': at,
};

/// A device with both battery groups: the design capacity of the model (a
/// catalog figure) and the estimated full-charge capacity of this battery.
const deviceFull = <String, Object?>{
  'id': uuid,
  'installationId': 'install-1234',
  'platform': 'ios',
  'model': 'iPhone 15 Pro',
  'modelIdentifier': 'iPhone16,1',
  'designCapacityMah': 3274,
  'designCapacityWh': 12.7,
  'designCapacitySource': 'localDeviceDatabase',
  'estimatedFullChargeCapacityMah': 3101.5,
  'estimatedFullChargeCapacityWh': 11.93,
  'fullChargeCapacitySource': 'androidChargeCounter',
  'fullChargeCapacityConfidence': 'medium',
  'createdAt': at,
  'lastSeenAt': at,
};

/// Nothing stored: every battery key is present and `null`.
const deviceBare = <String, Object?>{
  'id': uuid,
  'installationId': 'install-5678',
  'platform': 'android',
  'model': null,
  'modelIdentifier': null,
  'designCapacityMah': null,
  'designCapacityWh': null,
  'designCapacitySource': null,
  'estimatedFullChargeCapacityMah': null,
  'estimatedFullChargeCapacityWh': null,
  'fullChargeCapacitySource': null,
  'fullChargeCapacityConfidence': null,
  'createdAt': at,
  'lastSeenAt': at,
};

/// A model no catalog knows: the design is `unknown` and carries no numbers
/// (there is no "typical" capacity); the estimate group is absent.
const deviceUnknownDesign = <String, Object?>{
  'id': uuid,
  'installationId': 'install-9012',
  'platform': 'android',
  'model': 'Acme Z1',
  'modelIdentifier': 'Z1',
  'designCapacityMah': null,
  'designCapacityWh': null,
  'designCapacitySource': 'unknown',
  'estimatedFullChargeCapacityMah': null,
  'estimatedFullChargeCapacityWh': null,
  'fullChargeCapacitySource': null,
  'fullChargeCapacityConfidence': null,
  'createdAt': at,
  'lastSeenAt': at,
};

/// The Android charge counter shows up as an ESTIMATE next to an unknown
/// design capacity, never as the design capacity.
const deviceEstimateOnly = <String, Object?>{
  'id': uuid,
  'installationId': 'install-3456',
  'platform': 'android',
  'model': 'Acme Z1',
  'modelIdentifier': 'Z1',
  'designCapacityMah': null,
  'designCapacityWh': null,
  'designCapacitySource': 'unknown',
  'estimatedFullChargeCapacityMah': 4321,
  'estimatedFullChargeCapacityWh': null,
  'fullChargeCapacitySource': 'androidChargeCounter',
  'fullChargeCapacityConfidence': 'high',
  'createdAt': at,
  'lastSeenAt': at,
};

const tokenJson = <String, Object?>{
  'accessToken': 'access.jwt.value',
  'refreshToken': 'cmVmcmVzaC10b2tlbi12YWx1ZQ',
  'expiresIn': 900,
  'tokenType': 'Bearer',
};

const aiOutputJson = <String, Object?>{
  'title': 'Wi-Fi did the heavy lifting',
  'message': 'Most of this month\'s data went over Wi-Fi.',
  'tone': 'friendly',
  'severity': 'info',
  'emoji': '📶',
};

const appConfigJson = <String, Object?>{
  'environment': 'development',
  'features': {'ai': true, 'subscriptions': false, 'cloudSync': true},
  'ai': {
    'dailyLimits': {'free': 3, 'premium': 50},
  },
};

const deletedCountsJson = <String, Object?>{
  'dailyUsage': 2,
  'chargingSummaries': 0,
  'monthlySummaries': 1,
  'aiGenerations': 4,
  'devices': 0,
};

const exportSettingsJson = <String, Object?>{
  'countryCode': 'PL',
  'countryCodeSource': 'detected',
  'currencyCode': 'PLN',
  'currencyCodeSource': 'manual',
  'electricityPriceMode': 'manual',
  'manualElectricityPrice': 0.95,
  'electricityPriceSource': 'migratedManual',
  'updatedAt': at,
};

const exportSettingsEmptyJson = <String, Object?>{
  'countryCode': null,
  'countryCodeSource': null,
  'currencyCode': null,
  'currencyCodeSource': null,
  'electricityPriceMode': 'automatic',
  'manualElectricityPrice': null,
  'electricityPriceSource': null,
  'updatedAt': null,
};

const exportDailyJson = <String, Object?>{
  'deviceId': uuid,
  'date': '2026-10-12',
  'mobileBytes': 1000,
  'wifiBytes': 5000,
  'chargedWh': 12.5,
  'wallWh': 14.706,
  'chargingSessions': 2,
  'estimatedCost': 0.0169,
  'currency': 'PLN',
  'dataEstimated': false,
  'energyEstimated': true,
};

const exportChargingJson = <String, Object?>{
  'deviceId': uuid,
  'startedAt': '2026-10-12T22:30:00.000Z',
  'endedAt': '2026-10-12T23:30:00.000Z',
  'startPercent': 20,
  'endPercent': 80,
  'mah': 2400.5,
  'mahEstimated': true,
  'batteryWh': 9.24,
  'wallWh': 10.87,
  'estimatedCost': 0.0125,
  'createdAt': at,
};

const exportMonthlyJson = <String, Object?>{
  'month': '2026-10',
  'mobileBytes': 187400000000,
  'wifiBytes': 1433800000000,
  'wallWh': 1840.5,
  'chargingSessions': 94,
  'estimatedCost': 2.31,
  'currency': 'PLN',
  'computedAt': at,
};

const exportAiJson = <String, Object?>{
  'task': 'insight',
  'mode': 'normal',
  'provider': 'google-mock',
  'model': 'mock-fast',
  'inputTokens': 120,
  'outputTokens': 80,
  'estimatedCostUsd': 0.0004,
  'latencyMs': 350,
  'createdAt': at,
};

const exportSubscriptionJson = <String, Object?>{
  'store': 'app_store',
  'productId': 'pl.wattbyte.premium.monthly',
  'originalTransactionId': '1000000123456789',
  'status': 'active',
  'expiresAt': at,
  'createdAt': at,
  'updatedAt': at,
};

const exportTruncatedJson = <String, Object?>{
  'devices': false,
  'dailyUsage': true,
  'chargingSummaries': false,
  'monthlySummaries': false,
  'aiGenerations': false,
  'subscriptions': false,
};

const exportLimitsJson = <String, Object?>{
  'maxRowsPerCollection': 10000,
  'truncated': exportTruncatedJson,
};

const exportDocumentJson = <String, Object?>{
  'schemaVersion': 1,
  'exportedAt': at,
  'account': userJson,
  'settings': exportSettingsJson,
  'devices': [deviceFull, deviceBare],
  'dailyUsage': [exportDailyJson],
  'chargingSummaries': [exportChargingJson],
  'monthlySummaries': [exportMonthlyJson],
  'aiGenerations': [exportAiJson],
  'subscriptions': [exportSubscriptionJson],
  'limits': exportLimitsJson,
};

final exportDocumentEmptyJson = <String, Object?>{
  'schemaVersion': 1,
  'exportedAt': at,
  'account': userJson,
  'settings': exportSettingsEmptyJson,
  'devices': <Object?>[],
  'dailyUsage': <Object?>[],
  'chargingSummaries': <Object?>[],
  'monthlySummaries': <Object?>[],
  'aiGenerations': <Object?>[],
  'subscriptions': <Object?>[],
  'limits': {
    'maxRowsPerCollection': 10000,
    'truncated': {
      for (final k in exportTruncatedJson.keys) k: false,
    },
  },
};

final requestCases = <RequestCase>[
  RequestCase(
    'change_password_request',
    api.ChangePasswordRequest(
        currentPassword: 'password123', newPassword: 'a-brand-new-password'),
    {'currentPassword': 'password123', 'newPassword': 'a-brand-new-password'},
  ),
  RequestCase(
    'register_request',
    api.RegisterRequest(email: 'a@b.co', password: 'password123'),
    {'email': 'a@b.co', 'password': 'password123', 'displayName': null},
  ),
  RequestCase(
    'login_request',
    api.LoginRequest(email: 'a@b.co', password: 'password123'),
    {'email': 'a@b.co', 'password': 'password123'},
  ),
  RequestCase(
    'refresh_request',
    api.RefreshRequest(refreshToken: 'cmVmcmVzaC10b2tlbi12YWx1ZQ'),
    {'refreshToken': 'cmVmcmVzaC10b2tlbi12YWx1ZQ'},
  ),
  RequestCase(
    'update_me_request',
    api.UpdateMeRequest(displayName: null),
    {'displayName': null},
  ),
  RequestCase(
    'api_v1_auth_apple_post_request',
    api.ApiV1AuthApplePostRequest(idToken: 'x' * 20),
    {'idToken': 'x' * 20},
  ),
  RequestCase(
    'device_register_request',
    api.DeviceRegisterRequest(
      installationId: 'install-1234',
      platform: api.DeviceRegisterRequestPlatformEnum.ios,
    ),
    {
      'installationId': 'install-1234',
      'platform': 'ios',
      'model': null,
      'modelIdentifier': null,
      'designCapacityMah': null,
      'designCapacityWh': null,
      'designCapacitySource': null,
      'estimatedFullChargeCapacityMah': null,
      'estimatedFullChargeCapacityWh': null,
      'fullChargeCapacitySource': null,
      'fullChargeCapacityConfidence': null,
    },
  ),
  RequestCase(
    'usage_sync_request',
    api.UsageSyncRequest(installationId: 'install-1234', days: [dailyDto]),
    {
      'installationId': 'install-1234',
      'days': [dailyJson],
    },
  ),
  RequestCase('daily_usage_dto', dailyDto, dailyJson),
  RequestCase(
    'update_user_settings_request',
    api.UpdateUserSettingsRequest(),
    {
      'countryCode': null,
      'countryCodeSource': null,
      'currencyCode': null,
      'currencyCodeSource': null,
      'electricityPriceMode': null,
      'manualElectricityPrice': null,
      'electricityPriceSource': null,
    },
  ),
  RequestCase(
    'ai_generate_request',
    api.AIGenerateRequest(input: aiInput),
    {'mode': null, 'locale': null, 'input': aiInputJson},
  ),
  RequestCase('ai_input', aiInput, aiInputJson),
];

const sessionJson = <String, Object?>{
  'id': uuid,
  'createdAt': at,
  'lastUsedAt': at,
  'expiresAt': at,
  'current': true,
};

final responseCases = <ResponseCase>[
  const ResponseCase('session_dto', api.SessionDto.fromJson, sessionJson),
  const ResponseCase(
      'session_list_response', api.SessionListResponse.fromJson, {
    'sessions': [sessionJson]
  }),
  const ResponseCase('session_list_response', api.SessionListResponse.fromJson,
      {'sessions': <Object?>[]}),
  const ResponseCase('user_dto', api.UserDto.fromJson, userJson),
  const ResponseCase('token_pair', api.TokenPair.fromJson, tokenJson),
  const ResponseCase('auth_response', api.AuthResponse.fromJson,
      {'user': userJson, 'tokens': tokenJson}),
  const ResponseCase('device_dto', api.DeviceDto.fromJson, deviceFull),
  const ResponseCase('device_dto', api.DeviceDto.fromJson, deviceBare),
  const ResponseCase('device_dto', api.DeviceDto.fromJson, deviceUnknownDesign),
  const ResponseCase('device_dto', api.DeviceDto.fromJson, deviceEstimateOnly),
  const ResponseCase('device_list_response', api.DeviceListResponse.fromJson, {
    'devices': [deviceFull, deviceBare]
  }),
  const ResponseCase('device_list_response', api.DeviceListResponse.fromJson,
      {'devices': <Object?>[]}),
  const ResponseCase(
      'device_specification_dto', api.DeviceSpecificationDto.fromJson, {
    'manufacturer': 'Apple',
    'model': 'iPhone 15 Pro',
    'modelIdentifier': 'iPhone16,1',
    'designCapacityMah': 3274,
    'designCapacityWh': 12.7,
    'nominalVoltage': 3.88,
    'catalogVersion': '2026.10',
  }),
  const ResponseCase(
      'device_specification_dto', api.DeviceSpecificationDto.fromJson, {
    'manufacturer': 'Google',
    'model': 'Pixel 8',
    'modelIdentifier': 'Pixel 8',
    'designCapacityMah': 4575,
    'designCapacityWh': null,
    'nominalVoltage': null,
    'catalogVersion': '2026.10',
  }),
  const ResponseCase(
      'electricity_price_dto', api.ElectricityPriceDto.fromJson, {
    'countryCode': 'PL',
    'currency': 'PLN',
    'pricePerKwh': 1.2724,
    'period': '2026-S1',
    'source': 'eurostat',
    'includesTaxes': true,
    'includesNetworkCosts': true,
    'updatedAt': at,
    'stale': false,
  }),
  const ResponseCase(
      'electricity_price_dto', api.ElectricityPriceDto.fromJson, {
    'countryCode': 'DE',
    'currency': 'EUR',
    'pricePerKwh': 0.39,
    'period': '2026-S1',
    'source': 'fallback',
    'includesTaxes': null,
    'includesNetworkCosts': null,
    'updatedAt': at,
    'stale': true,
  }),
  const ResponseCase('error_response_error', api.ErrorResponseError.fromJson,
      {'code': 'validation', 'message': 'body/email Invalid email'}),
  const ResponseCase('error_response', api.ErrorResponse.fromJson, {
    'error': {
      'code': 'invalid_credentials',
      'message': 'Wrong email or password'
    },
  }),
  const ResponseCase('health_response', api.HealthResponse.fromJson,
      {'status': 'ok', 'version': '0.1.0', 'uptimeSec': 12}),
  const ResponseCase('ready_response', api.ReadyResponse.fromJson, {
    'status': 'degraded',
    'database': 'unavailable',
    'schema': 'behind',
    'aiProviders': ['openai', 'anthropic'],
  }),
  const ResponseCase('region_response', api.RegionResponse.fromJson,
      {'countryCode': null, 'source': 'none'}),
  const ResponseCase('region_response', api.RegionResponse.fromJson,
      {'countryCode': 'PL', 'source': 'backendCountry'}),
  const ResponseCase('daily_usage_dto', api.DailyUsageDto.fromJson, dailyJson),
  const ResponseCase('usage_daily_response', api.UsageDailyResponse.fromJson, {
    'days': [dailyJson],
  }),
  const ResponseCase('usage_sync_response', api.UsageSyncResponse.fromJson, {
    'accepted': 1,
    'dates': ['2026-10-12']
  }),
  const ResponseCase('user_settings_dto', api.UserSettingsDto.fromJson, {
    'countryCode': 'PL',
    'countryCodeSource': 'detected',
    'currencyCode': 'PLN',
    'currencyCodeSource': 'manual',
    'electricityPriceMode': 'manual',
    'manualElectricityPrice': 0.95,
    'electricityPriceSource': 'migratedManual',
    'updatedAt': at,
  }),
  const ResponseCase('user_settings_dto', api.UserSettingsDto.fromJson, {
    'countryCode': null,
    'countryCodeSource': null,
    'currencyCode': null,
    'currencyCodeSource': null,
    'electricityPriceMode': 'automatic',
    'manualElectricityPrice': null,
    'electricityPriceSource': null,
    'updatedAt': at,
  }),
  const ResponseCase(
      'app_config_dto', api.AppConfigDto.fromJson, appConfigJson),
  for (final env in ['development', 'staging', 'production'])
    ResponseCase('app_config_dto', api.AppConfigDto.fromJson, {
      ...appConfigJson,
      'environment': env,
      'features': {'ai': false, 'subscriptions': true, 'cloudSync': false},
      'ai': {
        'dailyLimits': {'free': 0, 'premium': 1000},
      },
    }),
  const ResponseCase(
      'app_config_dto_features', api.AppConfigDtoFeatures.fromJson, {
    'ai': true,
    'subscriptions': false,
    'cloudSync': true,
  }),
  const ResponseCase('app_config_dto_ai', api.AppConfigDtoAi.fromJson, {
    'dailyLimits': {'free': 3, 'premium': 50},
  }),
  const ResponseCase('app_config_dto_ai_daily_limits',
      api.AppConfigDtoAiDailyLimits.fromJson, {'free': 3, 'premium': 50}),
  const ResponseCase('cloud_data_deleted_counts',
      api.CloudDataDeletedCounts.fromJson, deletedCountsJson),
  const ResponseCase('cloud_data_delete_response',
      api.CloudDataDeleteResponse.fromJson, {'deleted': deletedCountsJson}),
  const ResponseCase(
      'cloud_data_delete_response', api.CloudDataDeleteResponse.fromJson, {
    'deleted': {
      'dailyUsage': 0,
      'chargingSummaries': 0,
      'monthlySummaries': 0,
      'aiGenerations': 0,
      'devices': 0,
    },
  }),
  const ResponseCase('cloud_export_settings', api.CloudExportSettings.fromJson,
      exportSettingsJson),
  const ResponseCase('cloud_export_settings', api.CloudExportSettings.fromJson,
      exportSettingsEmptyJson),
  const ResponseCase('cloud_export_daily_usage',
      api.CloudExportDailyUsage.fromJson, exportDailyJson),
  const ResponseCase('cloud_export_charging_summary',
      api.CloudExportChargingSummary.fromJson, exportChargingJson),
  const ResponseCase('cloud_export_monthly_summary',
      api.CloudExportMonthlySummary.fromJson, exportMonthlyJson),
  const ResponseCase('cloud_export_ai_generation',
      api.CloudExportAiGeneration.fromJson, exportAiJson),
  const ResponseCase('cloud_export_subscription',
      api.CloudExportSubscription.fromJson, exportSubscriptionJson),
  for (final (store, status) in [
    ('app_store', 'active'),
    ('play', 'grace'),
    ('app_store', 'expired'),
    ('play', 'revoked'),
  ])
    ResponseCase(
        'cloud_export_subscription', api.CloudExportSubscription.fromJson, {
      ...exportSubscriptionJson,
      'store': store,
      'status': status,
      'expiresAt': null,
    }),
  const ResponseCase('cloud_export_truncated',
      api.CloudExportTruncated.fromJson, exportTruncatedJson),
  const ResponseCase(
      'cloud_export_limits', api.CloudExportLimits.fromJson, exportLimitsJson),
  const ResponseCase('cloud_export_document', api.CloudExportDocument.fromJson,
      exportDocumentJson),
  ResponseCase('cloud_export_document', api.CloudExportDocument.fromJson,
      exportDocumentEmptyJson),
  const ResponseCase('ai_output', api.AIOutput.fromJson, aiOutputJson),
  const ResponseCase('ai_generate_response', api.AIGenerateResponse.fromJson, {
    'output': aiOutputJson,
    'provider': 'google-mock',
    'model': 'mock-fast',
    'remainingToday': 2,
  }),
];

/// Every enum of the client with its values; `values` is the generated list, the wire names come from `toJson()`.
final enumCases = <String, (List<Enum>, Object? Function(dynamic))>{
  'UserDtoPlanEnum': (api.UserDtoPlanEnum.values, api.UserDtoPlanEnum.fromJson),
  'TokenPairTokenTypeEnum': (
    api.TokenPairTokenTypeEnum.values,
    api.TokenPairTokenTypeEnum.fromJson
  ),
  'DeviceRegisterRequestPlatformEnum': (
    api.DeviceRegisterRequestPlatformEnum.values,
    api.DeviceRegisterRequestPlatformEnum.fromJson
  ),
  'DeviceRegisterRequestDesignCapacitySourceEnum': (
    api.DeviceRegisterRequestDesignCapacitySourceEnum.values,
    api.DeviceRegisterRequestDesignCapacitySourceEnum.fromJson
  ),
  'DeviceRegisterRequestFullChargeCapacitySourceEnum': (
    api.DeviceRegisterRequestFullChargeCapacitySourceEnum.values,
    api.DeviceRegisterRequestFullChargeCapacitySourceEnum.fromJson
  ),
  'DeviceRegisterRequestFullChargeCapacityConfidenceEnum': (
    api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.values,
    api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.fromJson
  ),
  'DeviceDtoPlatformEnum': (
    api.DeviceDtoPlatformEnum.values,
    api.DeviceDtoPlatformEnum.fromJson
  ),
  'DeviceDtoDesignCapacitySourceEnum': (
    api.DeviceDtoDesignCapacitySourceEnum.values,
    api.DeviceDtoDesignCapacitySourceEnum.fromJson
  ),
  'DeviceDtoFullChargeCapacitySourceEnum': (
    api.DeviceDtoFullChargeCapacitySourceEnum.values,
    api.DeviceDtoFullChargeCapacitySourceEnum.fromJson
  ),
  'DeviceDtoFullChargeCapacityConfidenceEnum': (
    api.DeviceDtoFullChargeCapacityConfidenceEnum.values,
    api.DeviceDtoFullChargeCapacityConfidenceEnum.fromJson
  ),
  'UserSettingsDtoElectricityPriceModeEnum': (
    api.UserSettingsDtoElectricityPriceModeEnum.values,
    api.UserSettingsDtoElectricityPriceModeEnum.fromJson
  ),
  'UserSettingsDtoCountryCodeSourceEnum': (
    api.UserSettingsDtoCountryCodeSourceEnum.values,
    api.UserSettingsDtoCountryCodeSourceEnum.fromJson
  ),
  'UserSettingsDtoCurrencyCodeSourceEnum': (
    api.UserSettingsDtoCurrencyCodeSourceEnum.values,
    api.UserSettingsDtoCurrencyCodeSourceEnum.fromJson
  ),
  'UserSettingsDtoElectricityPriceSourceEnum': (
    api.UserSettingsDtoElectricityPriceSourceEnum.values,
    api.UserSettingsDtoElectricityPriceSourceEnum.fromJson
  ),
  'UpdateUserSettingsRequestElectricityPriceModeEnum': (
    api.UpdateUserSettingsRequestElectricityPriceModeEnum.values,
    api.UpdateUserSettingsRequestElectricityPriceModeEnum.fromJson
  ),
  'UpdateUserSettingsRequestCountryCodeSourceEnum': (
    api.UpdateUserSettingsRequestCountryCodeSourceEnum.values,
    api.UpdateUserSettingsRequestCountryCodeSourceEnum.fromJson
  ),
  'UpdateUserSettingsRequestCurrencyCodeSourceEnum': (
    api.UpdateUserSettingsRequestCurrencyCodeSourceEnum.values,
    api.UpdateUserSettingsRequestCurrencyCodeSourceEnum.fromJson
  ),
  'UpdateUserSettingsRequestElectricityPriceSourceEnum': (
    api.UpdateUserSettingsRequestElectricityPriceSourceEnum.values,
    api.UpdateUserSettingsRequestElectricityPriceSourceEnum.fromJson
  ),
  'ElectricityPriceDtoSource_Enum': (
    api.ElectricityPriceDtoSource_Enum.values,
    api.ElectricityPriceDtoSource_Enum.fromJson
  ),
  'RegionResponseSource_Enum': (
    api.RegionResponseSource_Enum.values,
    api.RegionResponseSource_Enum.fromJson
  ),
  'HealthResponseStatusEnum': (
    api.HealthResponseStatusEnum.values,
    api.HealthResponseStatusEnum.fromJson
  ),
  'ReadyResponseStatusEnum': (
    api.ReadyResponseStatusEnum.values,
    api.ReadyResponseStatusEnum.fromJson
  ),
  'ReadyResponseDatabaseEnum': (
    api.ReadyResponseDatabaseEnum.values,
    api.ReadyResponseDatabaseEnum.fromJson
  ),
  'ReadyResponseSchemaEnum': (
    api.ReadyResponseSchemaEnum.values,
    api.ReadyResponseSchemaEnum.fromJson
  ),
  'AIInputPeriodTypeEnum': (
    api.AIInputPeriodTypeEnum.values,
    api.AIInputPeriodTypeEnum.fromJson
  ),
  'AIOutputToneEnum': (
    api.AIOutputToneEnum.values,
    api.AIOutputToneEnum.fromJson
  ),
  'AIOutputSeverityEnum': (
    api.AIOutputSeverityEnum.values,
    api.AIOutputSeverityEnum.fromJson
  ),
  'AIGenerateRequestModeEnum': (
    api.AIGenerateRequestModeEnum.values,
    api.AIGenerateRequestModeEnum.fromJson
  ),
  'AppConfigDtoEnvironmentEnum': (
    api.AppConfigDtoEnvironmentEnum.values,
    api.AppConfigDtoEnvironmentEnum.fromJson
  ),
  'CloudExportSettingsElectricityPriceModeEnum': (
    api.CloudExportSettingsElectricityPriceModeEnum.values,
    api.CloudExportSettingsElectricityPriceModeEnum.fromJson
  ),
  'CloudExportSettingsCountryCodeSourceEnum': (
    api.CloudExportSettingsCountryCodeSourceEnum.values,
    api.CloudExportSettingsCountryCodeSourceEnum.fromJson
  ),
  'CloudExportSettingsCurrencyCodeSourceEnum': (
    api.CloudExportSettingsCurrencyCodeSourceEnum.values,
    api.CloudExportSettingsCurrencyCodeSourceEnum.fromJson
  ),
  'CloudExportSettingsElectricityPriceSourceEnum': (
    api.CloudExportSettingsElectricityPriceSourceEnum.values,
    api.CloudExportSettingsElectricityPriceSourceEnum.fromJson
  ),
  'CloudExportSubscriptionStoreEnum': (
    api.CloudExportSubscriptionStoreEnum.values,
    api.CloudExportSubscriptionStoreEnum.fromJson
  ),
  'CloudExportSubscriptionStatusEnum': (
    api.CloudExportSubscriptionStatusEnum.values,
    api.CloudExportSubscriptionStatusEnum.fromJson
  ),
  'AIGenerateRequestLocaleEnum': (
    api.AIGenerateRequestLocaleEnum.values,
    api.AIGenerateRequestLocaleEnum.fromJson
  ),
};

List<String> generatedModelFiles() {
  final dir = Directory('lib/generated/api/model');
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.dart'))
      .map((n) => n.substring(0, n.length - '.dart'.length))
      .toList()
    ..sort();
}

/// The OpenAPI document the API publishes (`pnpm --filter @wattbyte/contracts openapi`), the source the
/// client is generated from.
Map<String, dynamic> loadSpec() =>
    jsonDecode(File('../../packages/contracts/openapi/openapi.json')
        .readAsStringSync()) as Map<String, dynamic>;

/// `components.schemas` of the published document.
Map<String, dynamic> schemas() =>
    (loadSpec()['components'] as Map)['schemas'] as Map<String, dynamic>;

/// `CloudExportDailyUsage` -> `cloud_export_daily_usage`, `AIInput` -> `ai_input` (the generator's file names).
String snakeCase(String name) => name
    .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();

/// The generated method name for a route: `/api/v1/me/cloud-data` + DELETE -> `apiV1MeCloudDataDelete`,
/// `/health` + GET -> `healthGet`.
String generatedMethod(String path, String method) {
  final segments = path
      .split('/')
      .where((s) => s.isNotEmpty)
      .map((s) => s.replaceAll(RegExp(r'[{}]'), ''));
  final buffer = StringBuffer();
  for (final (i, segment) in segments.indexed) {
    for (final (j, word) in segment.split(RegExp(r'[-_]')).indexed) {
      buffer.write(i == 0 && j == 0
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}');
    }
  }
  return '$buffer${method[0].toUpperCase()}${method.substring(1)}';
}

/// Every `enum: [...]` of strings anywhere in [node].
void collectEnums(Object? node, List<List<String>> out) {
  if (node is Map) {
    final values = node['enum'];
    if (values is List) {
      out.add([
        for (final v in values)
          if (v is String) v
      ]..sort());
    }
    for (final v in node.values) {
      collectEnums(v, out);
    }
  } else if (node is List) {
    for (final v in node) {
      collectEnums(v, out);
    }
  }
}

void main() {
  group('request models send their unset optional fields as explicit null', () {
    for (final c in requestCases) {
      test(c.file, () {
        expect(wire(c.model), c.json);
        // toJson() itself is what ApiClient serialises.
        expect(wire((c.model as dynamic).toJson()), c.json);
      });
    }

    test('a request with values keeps them (null only fills what is unset)',
        () {
      final register = api.RegisterRequest(
          email: 'a@b.co', password: 'password123', displayName: 'Ala');
      expect(wireMap(register)['displayName'], 'Ala');
      final device = api.DeviceRegisterRequest(
        installationId: 'install-1234',
        platform: api.DeviceRegisterRequestPlatformEnum.ios,
        model: 'iPhone 15 Pro',
        modelIdentifier: 'iPhone16,1',
        designCapacityMah: 3274,
        designCapacityWh: 12.7,
        designCapacitySource: api
            .DeviceRegisterRequestDesignCapacitySourceEnum.localDeviceDatabase,
        estimatedFullChargeCapacityMah: 3101.5,
        estimatedFullChargeCapacityWh: 11.93,
        fullChargeCapacitySource: api
            .DeviceRegisterRequestFullChargeCapacitySourceEnum
            .androidChargeCounter,
        fullChargeCapacityConfidence:
            api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.medium,
      );
      expect(wire(device), {
        'installationId': 'install-1234',
        'platform': 'ios',
        'model': 'iPhone 15 Pro',
        'modelIdentifier': 'iPhone16,1',
        'designCapacityMah': 3274,
        'designCapacityWh': 12.7,
        'designCapacitySource': 'localDeviceDatabase',
        'estimatedFullChargeCapacityMah': 3101.5,
        'estimatedFullChargeCapacityWh': 11.93,
        'fullChargeCapacitySource': 'androidChargeCounter',
        'fullChargeCapacityConfidence': 'medium',
      });
      // Only the design group set: the estimate group stays four nulls (the
      // server then keeps the stored estimate; source "unknown" would erase it).
      final designOnly = api.DeviceRegisterRequest(
        installationId: 'install-1234',
        platform: api.DeviceRegisterRequestPlatformEnum.android,
        designCapacityMah: 4575,
        designCapacitySource:
            api.DeviceRegisterRequestDesignCapacitySourceEnum.manual,
      );
      expect(
          wireMap(designOnly), containsPair('designCapacitySource', 'manual'));
      for (final k in [
        'estimatedFullChargeCapacityMah',
        'estimatedFullChargeCapacityWh',
        'fullChargeCapacitySource',
        'fullChargeCapacityConfidence',
      ]) {
        expect(wireMap(designOnly), containsPair(k, null));
      }
      final settings = api.UpdateUserSettingsRequest(
        countryCode: 'PL',
        electricityPriceMode:
            api.UpdateUserSettingsRequestElectricityPriceModeEnum.manual,
        manualElectricityPrice: 0.95,
      );
      expect(wire(settings), {
        'countryCode': 'PL',
        'countryCodeSource': null,
        'currencyCode': null,
        'currencyCodeSource': null,
        'electricityPriceMode': 'manual',
        'manualElectricityPrice': 0.95,
        'electricityPriceSource': null,
      });
      final ai = api.AIGenerateRequest(
        mode: api.AIGenerateRequestModeEnum.roast,
        locale: api.AIGenerateRequestLocaleEnum.pl,
        input: aiInput,
      );
      expect(wire(ai), containsPair('mode', 'roast'));
      expect(wire(ai), containsPair('locale', 'pl'));
    });
  });

  group('response models round-trip realistic server answers', () {
    for (final (i, c) in responseCases.indexed) {
      test('${c.file} #$i', () {
        final model = c.fromJson(c.json);
        expect(model, isNotNull, reason: 'fromJson accepted the answer');
        expect(wire(model), c.json);
        // Equal inputs give equal models. (The generator hashes a list field by identity while `==` compares
        // it deeply, so models with a list field are equal but may hash differently: not asserted for them.)
        final again = c.fromJson(c.json);
        expect(again, model);
        if (!c.json.values.any((v) => v is List)) {
          expect(again.hashCode, model.hashCode);
        }
      });
    }

    test('nullable fields stay null instead of becoming defaults', () {
      final device = api.DeviceDto.fromJson(deviceBare)!;
      expect(device.model, isNull);
      expect(device.designCapacityMah, isNull);
      expect(device.designCapacityWh, isNull);
      expect(device.designCapacitySource, isNull);
      expect(device.estimatedFullChargeCapacityMah, isNull);
      expect(device.estimatedFullChargeCapacityWh, isNull);
      expect(device.fullChargeCapacitySource, isNull);
      expect(device.fullChargeCapacityConfidence, isNull);
      final region =
          api.RegionResponse.fromJson({'countryCode': null, 'source': 'none'})!;
      expect(region.countryCode, isNull);
      expect(region.source_, api.RegionResponseSource_Enum.none);
      final settings = api.UserSettingsDto.fromJson({
        'countryCode': null,
        'countryCodeSource': null,
        'currencyCode': null,
        'currencyCodeSource': null,
        'electricityPriceMode': 'automatic',
        'manualElectricityPrice': null,
        'electricityPriceSource': null,
        'updatedAt': at,
      })!;
      expect(settings.manualElectricityPrice, isNull);
      expect(settings.countryCodeSource, isNull);
      expect(settings.currencyCodeSource, isNull);
      expect(settings.electricityPriceSource, isNull);
    });

    test('timestamps are read as the instant the server sent', () {
      final user = api.UserDto.fromJson(userJson)!;
      expect(user.createdAt.toUtc(), DateTime.utc(2026, 10, 13, 10));
    });

    test(
        'numbers keep their type: integers stay integers, decimals stay decimals',
        () {
      final device = api.DeviceDto.fromJson(deviceFull)!;
      expect(device.designCapacityMah, 3274);
      expect(device.designCapacityWh, 12.7);
      expect(device.estimatedFullChargeCapacityMah, 3101.5);
      expect(device.estimatedFullChargeCapacityWh, 11.93);
      final day = api.DailyUsageDto.fromJson(dailyJson)!;
      expect(day.mobileBytes, isA<int>());
      expect(day.chargedWh, 12.5);
    });

    test('the server defaults of a daily row apply when the flags are absent',
        () {
      final day = api.DailyUsageDto.fromJson({
        for (final e in dailyJson.entries)
          if (e.key != 'dataEstimated' && e.key != 'energyEstimated')
            e.key: e.value,
      })!;
      expect(day.dataEstimated, isFalse);
      expect(day.energyEstimated, isTrue);
    });
  });

  group('enums', () {
    for (final e in enumCases.entries) {
      test(e.key, () {
        final (values, fromJson) = e.value;
        expect(values, isNotEmpty);
        for (final v in values) {
          final wireName = (v as dynamic).toJson() as String;
          expect(fromJson(wireName), v, reason: '$wireName decodes to itself');
          expect(wire(v), wireName);
        }
        expect(fromJson('definitely-not-a-value'), isNull,
            reason: 'unknown values are not mapped onto a real one');
        expect(fromJson(null), isNull);
      });
    }

    test('every enum of the generated client is in the table above', () {
      final declared = <String>{};
      for (final f in Directory('lib/generated/api/model').listSync()) {
        if (f is! File) continue;
        for (final m in RegExp(r'^enum (\w+) \{', multiLine: true)
            .allMatches(f.readAsStringSync())) {
          declared.add(m.group(1)!);
        }
      }
      expect(enumCases.keys.toSet(), declared,
          reason: 'add the new enum to enumCases, or remove the stale one');
    });
  });

  group('the client against the published OpenAPI document', () {
    final spec = loadSpec();
    final schemas =
        (spec['components'] as Map)['schemas'] as Map<String, dynamic>;

    test('every route the API publishes has a method in the generated client',
        () {
      final apiSource = Directory('lib/generated/api/api')
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      final missing = <String>[];
      var routes = 0;
      for (final path in (spec['paths'] as Map<String, dynamic>).entries) {
        for (final method in (path.value as Map<String, dynamic>).keys) {
          if (!const {'get', 'post', 'put', 'patch', 'delete'}
              .contains(method)) {
            continue;
          }
          routes++;
          final name = generatedMethod(path.key, method);
          if (!RegExp('Future<[^\\n]*> $name\\(').hasMatch(apiSource)) {
            missing.add('${method.toUpperCase()} ${path.key} (expected $name)');
          }
        }
      }
      expect(routes, greaterThan(20), reason: 'the spec lists the routes');
      expect(missing, isEmpty,
          reason:
              'regenerate the client: pnpm openapi:generate (or the repository script)');
    });

    test('the config and cloud-data routes exist on the generated API classes',
        () {
      // Compile-time proof that the e2e test can call them without `invokeAPI`.
      final config = api.ConfigApi(api.ApiClient());
      final account = api.AccountApi(api.ApiClient());
      expect(config.apiV1ConfigGet, isNotNull);
      expect(account.apiV1MeCloudDataDelete, isNotNull);
      expect(account.apiV1MeExportGet, isNotNull);
      expect(account.apiV1MeExportGetWithHttpInfo, isNotNull);
    });

    test('every schema of the document has a generated model class', () {
      final files = generatedModelFiles().toSet();
      final missing = [
        for (final name in schemas.keys)
          if (!files.contains(snakeCase(name))) name
      ];
      expect(missing, isEmpty, reason: 'schemas without a model: regenerate');
    });

    test('every generated model is either a schema or part of one', () {
      // Inline objects (the nested parts of AppConfigDto, ...) have no schema of their own.
      final known = {for (final name in schemas.keys) snakeCase(name)};
      final orphans = [
        for (final file in generatedModelFiles())
          if (!known.contains(file) &&
              !known.any((k) => file.startsWith('${k}_')) &&
              // The generator names an inline request body after its route.
              !file.startsWith('api_v1_'))
            file
      ];
      expect(orphans, isEmpty, reason: 'models of a schema that was removed');
    });

    test('the fixtures carry exactly the properties of their schema', () {
      final bySchema = {
        for (final e in schemas.entries) snakeCase(e.key): e.value
      };
      var checked = 0;
      for (final c in [...responseCases]) {
        final schema = bySchema[c.file] as Map<String, dynamic>?;
        if (schema == null) continue; // an inline part
        checked++;
        final properties =
            (schema['properties'] as Map<String, dynamic>).keys.toSet();
        expect(c.json.keys.toSet(), properties,
            reason: '${c.file}: fixture and schema list different properties');
      }
      for (final c in requestCases) {
        final schema = bySchema[c.file] as Map<String, dynamic>?;
        if (schema == null) continue;
        checked++;
        final properties =
            (schema['properties'] as Map<String, dynamic>).keys.toSet();
        expect(c.json.keys.toSet(), properties,
            reason: '${c.file}: request fixture and schema differ');
      }
      expect(checked, greaterThan(30));
    });

    test('required properties are never null in a fixture', () {
      final bySchema = {
        for (final e in schemas.entries) snakeCase(e.key): e.value
      };
      for (final c in responseCases) {
        final schema = bySchema[c.file] as Map<String, dynamic>?;
        if (schema == null) continue;
        final required =
            ((schema['required'] as List?) ?? const []).cast<String>();
        final nullable = <String>{
          for (final e
              in (schema['properties'] as Map<String, dynamic>).entries)
            if ((e.value as Map)['nullable'] == true) e.key
        };
        for (final key in required) {
          if (nullable.contains(key)) continue;
          expect(c.json[key], isNotNull,
              reason: '${c.file}.$key is required and not nullable');
        }
      }
    });

    test('the enums of the client have exactly the values of the document', () {
      final fromSpec = <List<String>>[];
      // Only the models: query-parameter enums (`?format=csv|json`) are not classes.
      collectEnums(schemas, fromSpec);
      final specSets = {for (final v in fromSpec) v.join('|')};
      final clientSets = {
        for (final e in enumCases.values)
          ([for (final v in e.$1) (v as dynamic).toJson() as String]..sort())
              .join('|')
      };
      expect(clientSets.difference(specSets), isEmpty,
          reason: 'client enum values the API does not publish');
      expect(specSets.difference(clientSets), isEmpty,
          reason: 'API enum values the client does not know');
    });
  });

  group('numbers the server writes without a decimal point', () {
    // JSON has one number type: a double with an integral value is written as `0` or `2400`. The
    // generated code must read that as a double instead of failing on `int is not double`.
    Map<String, Object?> integral(
            Map<String, Object?> json, Set<String> keys) =>
        {
          for (final e in json.entries)
            e.key: keys.contains(e.key) ? (e.value as num).toInt() : e.value
        };

    test('daily usage, export rows and the export document', () {
      final daily = api.CloudExportDailyUsage.fromJson(integral({
        ...exportDailyJson,
        'chargedWh': 12.0,
        'wallWh': 0.0,
        'estimatedCost': 0.0
      }, {
        'chargedWh',
        'wallWh',
        'estimatedCost'
      }))!;
      expect(daily.chargedWh, 12);
      expect(daily.wallWh, 0);
      expect(daily.estimatedCost, 0);

      final charging = api.CloudExportChargingSummary.fromJson(integral({
        ...exportChargingJson,
        'mah': 2400.0,
        'batteryWh': 9.0,
        'wallWh': 11.0,
        'estimatedCost': 0.0,
      }, {
        'mah',
        'batteryWh',
        'wallWh',
        'estimatedCost'
      }))!;
      expect(charging.mah, 2400);
      expect(charging.estimatedCost, 0);

      final monthly = api.CloudExportMonthlySummary.fromJson(integral(
          {...exportMonthlyJson, 'wallWh': 1840.0, 'estimatedCost': 2.0},
          {'wallWh', 'estimatedCost'}))!;
      expect(monthly.wallWh, 1840);

      final ai = api.CloudExportAiGeneration.fromJson(integral(
          {...exportAiJson, 'estimatedCostUsd': 0.0}, {'estimatedCostUsd'}))!;
      expect(ai.estimatedCostUsd, 0);

      final settings = api.CloudExportSettings.fromJson(integral(
          {...exportSettingsJson, 'manualElectricityPrice': 1.0},
          {'manualElectricityPrice'}))!;
      expect(settings.manualElectricityPrice, 1);
    });

    test('device and user settings (existing models)', () {
      final device = api.DeviceDto.fromJson(integral({
        ...deviceFull,
        'designCapacityWh': 13.0,
        'estimatedFullChargeCapacityMah': 3100.0,
        'estimatedFullChargeCapacityWh': 12.0,
      }, {
        'designCapacityWh',
        'estimatedFullChargeCapacityMah',
        'estimatedFullChargeCapacityWh'
      }))!;
      expect(device.designCapacityWh, 13);
      expect(device.estimatedFullChargeCapacityMah, 3100);
      expect(device.estimatedFullChargeCapacityWh, 12);
      final price = api.ElectricityPriceDto.fromJson({
        'countryCode': 'PL',
        'currency': 'PLN',
        'pricePerKwh': 1,
        'period': '2026-S1',
        'source': 'eurostat',
        'includesTaxes': true,
        'includesNetworkCosts': true,
        'updatedAt': at,
        'stale': false,
      })!;
      expect(price.pricePerKwh, 1);
    });
  });

  group('the new models', () {
    test('AppConfigDto: flags and limits keep their types and meaning', () {
      final c = api.AppConfigDto.fromJson(appConfigJson)!;
      expect(c.environment, api.AppConfigDtoEnvironmentEnum.development);
      expect(c.features.ai, isTrue);
      expect(c.features.subscriptions, isFalse);
      expect(c.features.cloudSync, isTrue);
      expect(c.ai.dailyLimits.free, 3);
      expect(c.ai.dailyLimits.premium, 50);
    });

    test('AppConfigDto: an unknown environment is not mapped onto a real one',
        () {
      expect(api.AppConfigDtoEnvironmentEnum.fromJson('testing'), isNull);
      expect(api.AppConfigDtoEnvironmentEnum.fromJson('prod'), isNull);
    });

    test('CloudDataDeleteResponse: every counter is an int', () {
      final r =
          api.CloudDataDeleteResponse.fromJson({'deleted': deletedCountsJson})!;
      expect(r.deleted.dailyUsage, 2);
      expect(r.deleted.monthlySummaries, 1);
      expect(r.deleted.aiGenerations, 4);
      expect(r.deleted.devices, 0);
    });

    test('CloudExportDocument: the account, devices and rows are typed models',
        () {
      final d = api.CloudExportDocument.fromJson(exportDocumentJson)!;
      expect(d.schemaVersion, 1);
      expect(d.exportedAt.toUtc(), DateTime.utc(2026, 10, 13, 10));
      expect(d.account, isA<api.UserDto>());
      expect(d.account.email, 'a@b.co');
      expect(d.devices, hasLength(2));
      expect(d.devices.first.designCapacityMah, 3274);
      expect(d.devices.first.estimatedFullChargeCapacityMah, 3101.5);
      expect(d.devices.last.designCapacityMah, isNull);
      expect(d.devices.last.estimatedFullChargeCapacityMah, isNull);
      expect(d.dailyUsage.single.deviceId, uuid);
      expect(d.chargingSummaries.single.startPercent, 20);
      expect(d.monthlySummaries.single.mobileBytes, 187400000000);
      expect(d.aiGenerations.single.provider, 'google-mock');
      expect(d.subscriptions.single.store,
          api.CloudExportSubscriptionStoreEnum.appStore);
      expect(d.subscriptions.single.status,
          api.CloudExportSubscriptionStatusEnum.active);
      expect(d.limits.maxRowsPerCollection, 10000);
      expect(d.limits.truncated.dailyUsage, isTrue);
      expect(d.limits.truncated.devices, isFalse);
    });

    test('CloudExportDocument: an empty account has empty lists, never null',
        () {
      final d = api.CloudExportDocument.fromJson(exportDocumentEmptyJson)!;
      expect(d.devices, isEmpty);
      expect(d.dailyUsage, isEmpty);
      expect(d.chargingSummaries, isEmpty);
      expect(d.monthlySummaries, isEmpty);
      expect(d.aiGenerations, isEmpty);
      expect(d.subscriptions, isEmpty);
      expect(d.settings.updatedAt, isNull);
      expect(d.settings.countryCode, isNull);
      expect(d.settings.electricityPriceMode,
          api.CloudExportSettingsElectricityPriceModeEnum.automatic);
    });

    test('the export never has a field for secrets', () {
      final text = jsonEncode(
          api.CloudExportDocument.fromJson(exportDocumentJson)!.toJson());
      for (final secret in [
        'password',
        'passwordHash',
        'refreshToken',
        'accessToken',
        'tokenHash',
        'scrypt',
        'prompt',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('subscriptions: both stores and all four states are understood', () {
      for (final store in ['app_store', 'play']) {
        expect(api.CloudExportSubscriptionStoreEnum.fromJson(store), isNotNull);
      }
      for (final status in ['active', 'grace', 'expired', 'revoked']) {
        expect(
            api.CloudExportSubscriptionStatusEnum.fromJson(status), isNotNull);
      }
      expect(api.CloudExportSubscriptionStoreEnum.fromJson('appStore'), isNull,
          reason: 'the wire name is app_store');
    });
  });

  group('battery capacity: design capacity versus estimated full charge', () {
    // docs/BATTERY_CAPACITY.md: two groups, each stored atomically. The old
    // names could not say whether a number was nominal or measured.
    const designKeys = [
      'designCapacityMah',
      'designCapacityWh',
      'designCapacitySource',
    ];
    const estimateKeys = [
      'estimatedFullChargeCapacityMah',
      'estimatedFullChargeCapacityWh',
      'fullChargeCapacitySource',
      'fullChargeCapacityConfidence',
    ];
    const retiredKeys = [
      'batteryCapacityMah',
      'batteryCapacityWh',
      'batterySpecificationSource',
    ];

    List<String> wireNames(Iterable<Enum> values) =>
        [for (final v in values) (v as dynamic).toJson() as String];

    test('the request, the device and the catalog entry have the new names',
        () {
      final request = wireMap(api.DeviceRegisterRequest(
          installationId: 'install-1234',
          platform: api.DeviceRegisterRequestPlatformEnum.android));
      expect(
          request.keys,
          unorderedEquals([
            'installationId',
            'platform',
            'model',
            'modelIdentifier',
            ...designKeys,
            ...estimateKeys,
          ]));
      final device = wireMap(api.DeviceDto.fromJson(deviceFull));
      expect(
          device.keys,
          unorderedEquals([
            'id',
            'installationId',
            'platform',
            'model',
            'modelIdentifier',
            ...designKeys,
            ...estimateKeys,
            'createdAt',
            'lastSeenAt',
          ]));
      final catalog = wireMap(api.DeviceSpecificationDto.fromJson({
        'manufacturer': 'Google',
        'model': 'Pixel 8',
        'modelIdentifier': 'Pixel 8',
        'designCapacityMah': 4575,
        'designCapacityWh': null,
        'nominalVoltage': null,
        'catalogVersion': '2026.10',
      }));
      expect(
          catalog.keys,
          unorderedEquals([
            'manufacturer',
            'model',
            'modelIdentifier',
            'designCapacityMah',
            'designCapacityWh',
            'nominalVoltage',
            'catalogVersion',
          ]));
      for (final json in [request, device, catalog]) {
        for (final key in retiredKeys) {
          expect(json.containsKey(key), isFalse, reason: key);
        }
      }
    });

    test('a design capacity and an estimate are different fields on the device',
        () {
      final d = api.DeviceDto.fromJson(deviceEstimateOnly)!;
      // The charge counter reading is an estimate; the design stays unknown.
      expect(d.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.unknown);
      expect(d.designCapacityMah, isNull);
      expect(d.designCapacityWh, isNull);
      expect(d.estimatedFullChargeCapacityMah, 4321);
      expect(d.fullChargeCapacitySource,
          api.DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter);
      expect(d.fullChargeCapacityConfidence,
          api.DeviceDtoFullChargeCapacityConfidenceEnum.high);
      final unknown = api.DeviceDto.fromJson(deviceUnknownDesign)!;
      expect(unknown.designCapacitySource,
          api.DeviceDtoDesignCapacitySourceEnum.unknown);
      expect(unknown.designCapacityMah, isNull);
      expect(unknown.estimatedFullChargeCapacityMah, isNull);
      expect(unknown.fullChargeCapacitySource, isNull,
          reason: 'no estimate is null, not "unknown"');
    });

    test('the API requires all seven battery keys in a DeviceDto (null empty)',
        () {
      final required = ((schemas()['DeviceDto'] as Map)['required'] as List)
          .cast<String>()
          .toSet();
      expect(required.containsAll([...designKeys, ...estimateKeys]), isTrue,
          reason: 'the OpenAPI document lists them as required');
      expect(
          api.DeviceDto.requiredKeys.containsAll([
            ...designKeys,
            ...estimateKeys,
          ]),
          isTrue,
          reason: 'and so does the generated client');
      for (final key in [...designKeys, ...estimateKeys]) {
        expect(
            () => api.DeviceDto.fromJson({
                  for (final e in deviceBare.entries)
                    if (e.key != key) e.key: e.value
                }),
            throwsA(isA<AssertionError>()),
            reason: 'a server answer without $key is refused (debug builds)');
      }
      // A request only needs the installation and the platform.
      expect((schemas()['DeviceRegisterRequest'] as Map)['required'] as List,
          ['installationId', 'platform']);
    });

    test('the catalog entry is a design capacity by definition', () {
      final spec = schemas()['DeviceSpecificationDto'] as Map;
      final properties = spec['properties'] as Map<String, dynamic>;
      expect(properties.keys, contains('designCapacityMah'));
      expect((properties['designCapacityMah'] as Map)['nullable'], isNot(true),
          reason: 'a catalog entry always has a capacity');
      expect((spec['required'] as List), contains('designCapacityMah'));
      expect(properties.keys.where((k) => k.contains('estimated')), isEmpty);
    });

    test('the design source of the wire is the Dart one, with no measurement',
        () {
      final dart = {for (final v in DesignCapacitySource.values) v.name};
      for (final values in [
        api.DeviceRegisterRequestDesignCapacitySourceEnum.values,
        api.DeviceDtoDesignCapacitySourceEnum.values,
      ]) {
        expect(wireNames(values).toSet(), dart);
        for (final name in wireNames(values)) {
          expect(name.toLowerCase(), isNot(contains('charge')), reason: name);
          expect(name.toLowerCase(), isNot(contains('estimate')), reason: name);
          expect(name.toLowerCase(), isNot(contains('system')), reason: name);
        }
      }
    });

    test('the estimate source and confidence of the wire are the Dart ones',
        () {
      final source = {for (final v in FullChargeCapacitySource.values) v.name};
      final confidence = {
        for (final v in FullChargeCapacityConfidence.values)
          if (v.wireName != null) v.wireName!
      };
      expect(confidence, {'low', 'medium', 'high'},
          reason: '"none" is never sent: no estimate has no confidence');
      for (final values in [
        api.DeviceRegisterRequestFullChargeCapacitySourceEnum.values,
        api.DeviceDtoFullChargeCapacitySourceEnum.values,
      ]) {
        expect(wireNames(values).toSet(), source);
      }
      for (final values in [
        api.DeviceRegisterRequestFullChargeCapacityConfidenceEnum.values,
        api.DeviceDtoFullChargeCapacityConfidenceEnum.values,
      ]) {
        expect(wireNames(values).toSet(), confidence);
      }
    });

    test('request ranges: a capacity is 0.1 .. 30000 mAh and 0.001 .. 200 Wh',
        () {
      final properties = (schemas()['DeviceRegisterRequest']
          as Map)['properties'] as Map<String, dynamic>;
      for (final key in [
        'designCapacityMah',
        'estimatedFullChargeCapacityMah'
      ]) {
        final p = properties[key] as Map;
        expect([p['minimum'], p['maximum'], p['nullable']], [0.1, 30000, true],
            reason: key);
      }
      for (final key in ['designCapacityWh', 'estimatedFullChargeCapacityWh']) {
        final p = properties[key] as Map;
        expect([p['minimum'], p['maximum'], p['nullable']], [0.001, 200, true],
            reason: key);
      }
    });
  });

  group('coverage', () {
    test('every generated model is built or round-tripped above', () {
      final covered = {
        for (final c in requestCases) c.file,
        for (final c in responseCases) c.file,
      };
      final generated = generatedModelFiles();
      expect(generated, isNotEmpty);
      final uncovered = generated.where((f) => !covered.contains(f)).toList();
      expect(uncovered, isEmpty,
          reason: 'new generated models without a case in this file');
      final stale = covered.where((f) => !generated.contains(f)).toList();
      expect(stale, isEmpty, reason: 'cases for models that no longer exist');
    });
  });
}
