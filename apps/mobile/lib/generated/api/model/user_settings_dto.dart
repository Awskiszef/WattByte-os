//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UserSettingsDto {
  /// Returns a new [UserSettingsDto] instance.
  UserSettingsDto({
    required this.countryCode,
    required this.countryCodeSource,
    required this.currencyCode,
    required this.currencyCodeSource,
    required this.electricityPriceMode,
    required this.manualElectricityPrice,
    required this.electricityPriceSource,
    required this.updatedAt,
  });

  String? countryCode;

  UserSettingsDtoCountryCodeSourceEnum? countryCodeSource;

  String? currencyCode;

  UserSettingsDtoCurrencyCodeSourceEnum? currencyCodeSource;

  UserSettingsDtoElectricityPriceModeEnum electricityPriceMode;

  num? manualElectricityPrice;

  UserSettingsDtoElectricityPriceSourceEnum? electricityPriceSource;

  DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSettingsDto &&
          other.countryCode == countryCode &&
          other.countryCodeSource == countryCodeSource &&
          other.currencyCode == currencyCode &&
          other.currencyCodeSource == currencyCodeSource &&
          other.electricityPriceMode == electricityPriceMode &&
          other.manualElectricityPrice == manualElectricityPrice &&
          other.electricityPriceSource == electricityPriceSource &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (countryCode == null ? 0 : countryCode!.hashCode) +
      (countryCodeSource == null ? 0 : countryCodeSource!.hashCode) +
      (currencyCode == null ? 0 : currencyCode!.hashCode) +
      (currencyCodeSource == null ? 0 : currencyCodeSource!.hashCode) +
      (electricityPriceMode.hashCode) +
      (manualElectricityPrice == null ? 0 : manualElectricityPrice!.hashCode) +
      (electricityPriceSource == null ? 0 : electricityPriceSource!.hashCode) +
      (updatedAt.hashCode);

  @override
  String toString() =>
      'UserSettingsDto[countryCode=$countryCode, countryCodeSource=$countryCodeSource, currencyCode=$currencyCode, currencyCodeSource=$currencyCodeSource, electricityPriceMode=$electricityPriceMode, manualElectricityPrice=$manualElectricityPrice, electricityPriceSource=$electricityPriceSource, updatedAt=$updatedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.countryCode != null) {
      json[r'countryCode'] = this.countryCode;
    } else {
      json[r'countryCode'] = null;
    }
    if (this.countryCodeSource != null) {
      json[r'countryCodeSource'] = this.countryCodeSource;
    } else {
      json[r'countryCodeSource'] = null;
    }
    if (this.currencyCode != null) {
      json[r'currencyCode'] = this.currencyCode;
    } else {
      json[r'currencyCode'] = null;
    }
    if (this.currencyCodeSource != null) {
      json[r'currencyCodeSource'] = this.currencyCodeSource;
    } else {
      json[r'currencyCodeSource'] = null;
    }
    json[r'electricityPriceMode'] = this.electricityPriceMode;
    if (this.manualElectricityPrice != null) {
      json[r'manualElectricityPrice'] = this.manualElectricityPrice;
    } else {
      json[r'manualElectricityPrice'] = null;
    }
    if (this.electricityPriceSource != null) {
      json[r'electricityPriceSource'] = this.electricityPriceSource;
    } else {
      json[r'electricityPriceSource'] = null;
    }
    json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [UserSettingsDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UserSettingsDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'countryCode'),
            'Required key "UserSettingsDto[countryCode]" is missing from JSON.');
        assert(json.containsKey(r'countryCodeSource'),
            'Required key "UserSettingsDto[countryCodeSource]" is missing from JSON.');
        assert(json.containsKey(r'currencyCode'),
            'Required key "UserSettingsDto[currencyCode]" is missing from JSON.');
        assert(json.containsKey(r'currencyCodeSource'),
            'Required key "UserSettingsDto[currencyCodeSource]" is missing from JSON.');
        assert(json.containsKey(r'electricityPriceMode'),
            'Required key "UserSettingsDto[electricityPriceMode]" is missing from JSON.');
        assert(json[r'electricityPriceMode'] != null,
            'Required key "UserSettingsDto[electricityPriceMode]" has a null value in JSON.');
        assert(json.containsKey(r'manualElectricityPrice'),
            'Required key "UserSettingsDto[manualElectricityPrice]" is missing from JSON.');
        assert(json.containsKey(r'electricityPriceSource'),
            'Required key "UserSettingsDto[electricityPriceSource]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "UserSettingsDto[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null,
            'Required key "UserSettingsDto[updatedAt]" has a null value in JSON.');
        return true;
      }());

      return UserSettingsDto(
        countryCode: mapValueOfType<String>(json, r'countryCode'),
        countryCodeSource: UserSettingsDtoCountryCodeSourceEnum.fromJson(
            json[r'countryCodeSource']),
        currencyCode: mapValueOfType<String>(json, r'currencyCode'),
        currencyCodeSource: UserSettingsDtoCurrencyCodeSourceEnum.fromJson(
            json[r'currencyCodeSource']),
        electricityPriceMode: UserSettingsDtoElectricityPriceModeEnum.fromJson(
            json[r'electricityPriceMode'])!,
        manualElectricityPrice: json[r'manualElectricityPrice'] == null
            ? null
            : num.parse('${json[r'manualElectricityPrice']}'),
        electricityPriceSource:
            UserSettingsDtoElectricityPriceSourceEnum.fromJson(
                json[r'electricityPriceSource']),
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
      );
    }
    return null;
  }

  static List<UserSettingsDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserSettingsDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserSettingsDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UserSettingsDto> mapFromJson(dynamic json) {
    final map = <String, UserSettingsDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UserSettingsDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UserSettingsDto-objects as value to a dart map
  static Map<String, List<UserSettingsDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UserSettingsDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UserSettingsDto.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'countryCode',
    'countryCodeSource',
    'currencyCode',
    'currencyCodeSource',
    'electricityPriceMode',
    'manualElectricityPrice',
    'electricityPriceSource',
    'updatedAt',
  };
}

enum UserSettingsDtoCountryCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const UserSettingsDtoCountryCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UserSettingsDtoCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UserSettingsDtoCountryCodeSourceEnum? fromJson(dynamic value) =>
      UserSettingsDtoCountryCodeSourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [UserSettingsDtoCountryCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UserSettingsDtoCountryCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserSettingsDtoCountryCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserSettingsDtoCountryCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserSettingsDtoCountryCodeSourceEnum] to String,
/// and [decode] dynamic data back to [UserSettingsDtoCountryCodeSourceEnum].
class UserSettingsDtoCountryCodeSourceEnumTypeTransformer {
  factory UserSettingsDtoCountryCodeSourceEnumTypeTransformer() => _instance ??=
      const UserSettingsDtoCountryCodeSourceEnumTypeTransformer._();

  const UserSettingsDtoCountryCodeSourceEnumTypeTransformer._();

  String encode(UserSettingsDtoCountryCodeSourceEnum data) => data._value;

  /// Returns the instance of [UserSettingsDtoCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserSettingsDtoCountryCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UserSettingsDtoCountryCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UserSettingsDtoCountryCodeSourceEnum.detected;
        case r'manual':
          return UserSettingsDtoCountryCodeSourceEnum.manual;
        case r'migratedManual':
          return UserSettingsDtoCountryCodeSourceEnum.migratedManual;
        case r'unknown_default_open_api':
          return UserSettingsDtoCountryCodeSourceEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return UserSettingsDtoCountryCodeSourceEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UserSettingsDtoCountryCodeSourceEnumTypeTransformer? _instance;
}

enum UserSettingsDtoCurrencyCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const UserSettingsDtoCurrencyCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UserSettingsDtoCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UserSettingsDtoCurrencyCodeSourceEnum? fromJson(dynamic value) =>
      UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [UserSettingsDtoCurrencyCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UserSettingsDtoCurrencyCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserSettingsDtoCurrencyCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserSettingsDtoCurrencyCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserSettingsDtoCurrencyCodeSourceEnum] to String,
/// and [decode] dynamic data back to [UserSettingsDtoCurrencyCodeSourceEnum].
class UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer {
  factory UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer() =>
      _instance ??=
          const UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer._();

  const UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer._();

  String encode(UserSettingsDtoCurrencyCodeSourceEnum data) => data._value;

  /// Returns the instance of [UserSettingsDtoCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserSettingsDtoCurrencyCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UserSettingsDtoCurrencyCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UserSettingsDtoCurrencyCodeSourceEnum.detected;
        case r'manual':
          return UserSettingsDtoCurrencyCodeSourceEnum.manual;
        case r'migratedManual':
          return UserSettingsDtoCurrencyCodeSourceEnum.migratedManual;
        case r'unknown_default_open_api':
          return UserSettingsDtoCurrencyCodeSourceEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return UserSettingsDtoCurrencyCodeSourceEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UserSettingsDtoCurrencyCodeSourceEnumTypeTransformer? _instance;
}

enum UserSettingsDtoElectricityPriceModeEnum {
  automatic._(r'automatic'),
  manual._(r'manual'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const UserSettingsDtoElectricityPriceModeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UserSettingsDtoElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UserSettingsDtoElectricityPriceModeEnum? fromJson(dynamic value) =>
      UserSettingsDtoElectricityPriceModeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [UserSettingsDtoElectricityPriceModeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UserSettingsDtoElectricityPriceModeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserSettingsDtoElectricityPriceModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserSettingsDtoElectricityPriceModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserSettingsDtoElectricityPriceModeEnum] to String,
/// and [decode] dynamic data back to [UserSettingsDtoElectricityPriceModeEnum].
class UserSettingsDtoElectricityPriceModeEnumTypeTransformer {
  factory UserSettingsDtoElectricityPriceModeEnumTypeTransformer() =>
      _instance ??=
          const UserSettingsDtoElectricityPriceModeEnumTypeTransformer._();

  const UserSettingsDtoElectricityPriceModeEnumTypeTransformer._();

  String encode(UserSettingsDtoElectricityPriceModeEnum data) => data._value;

  /// Returns the instance of [UserSettingsDtoElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserSettingsDtoElectricityPriceModeEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UserSettingsDtoElectricityPriceModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'automatic':
          return UserSettingsDtoElectricityPriceModeEnum.automatic;
        case r'manual':
          return UserSettingsDtoElectricityPriceModeEnum.manual;
        case r'unknown_default_open_api':
          return UserSettingsDtoElectricityPriceModeEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return UserSettingsDtoElectricityPriceModeEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UserSettingsDtoElectricityPriceModeEnumTypeTransformer? _instance;
}

enum UserSettingsDtoElectricityPriceSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const UserSettingsDtoElectricityPriceSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UserSettingsDtoElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UserSettingsDtoElectricityPriceSourceEnum? fromJson(dynamic value) =>
      UserSettingsDtoElectricityPriceSourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [UserSettingsDtoElectricityPriceSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UserSettingsDtoElectricityPriceSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserSettingsDtoElectricityPriceSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserSettingsDtoElectricityPriceSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserSettingsDtoElectricityPriceSourceEnum] to String,
/// and [decode] dynamic data back to [UserSettingsDtoElectricityPriceSourceEnum].
class UserSettingsDtoElectricityPriceSourceEnumTypeTransformer {
  factory UserSettingsDtoElectricityPriceSourceEnumTypeTransformer() =>
      _instance ??=
          const UserSettingsDtoElectricityPriceSourceEnumTypeTransformer._();

  const UserSettingsDtoElectricityPriceSourceEnumTypeTransformer._();

  String encode(UserSettingsDtoElectricityPriceSourceEnum data) => data._value;

  /// Returns the instance of [UserSettingsDtoElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserSettingsDtoElectricityPriceSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UserSettingsDtoElectricityPriceSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UserSettingsDtoElectricityPriceSourceEnum.detected;
        case r'manual':
          return UserSettingsDtoElectricityPriceSourceEnum.manual;
        case r'migratedManual':
          return UserSettingsDtoElectricityPriceSourceEnum.migratedManual;
        case r'unknown_default_open_api':
          return UserSettingsDtoElectricityPriceSourceEnum
              .unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return UserSettingsDtoElectricityPriceSourceEnum
              .unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UserSettingsDtoElectricityPriceSourceEnumTypeTransformer? _instance;
}
