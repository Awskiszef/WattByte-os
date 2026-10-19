//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportSettings {
  /// Returns a new [CloudExportSettings] instance.
  CloudExportSettings({
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

  CloudExportSettingsCountryCodeSourceEnum? countryCodeSource;

  String? currencyCode;

  CloudExportSettingsCurrencyCodeSourceEnum? currencyCodeSource;

  CloudExportSettingsElectricityPriceModeEnum electricityPriceMode;

  num? manualElectricityPrice;

  CloudExportSettingsElectricityPriceSourceEnum? electricityPriceSource;

  DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportSettings &&
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
      (updatedAt == null ? 0 : updatedAt!.hashCode);

  @override
  String toString() =>
      'CloudExportSettings[countryCode=$countryCode, countryCodeSource=$countryCodeSource, currencyCode=$currencyCode, currencyCodeSource=$currencyCodeSource, electricityPriceMode=$electricityPriceMode, manualElectricityPrice=$manualElectricityPrice, electricityPriceSource=$electricityPriceSource, updatedAt=$updatedAt]';

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
    if (this.updatedAt != null) {
      json[r'updatedAt'] = this.updatedAt!.toUtc().toIso8601String();
    } else {
      json[r'updatedAt'] = null;
    }
    return json;
  }

  /// Returns a new [CloudExportSettings] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportSettings? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'countryCode'),
            'Required key "CloudExportSettings[countryCode]" is missing from JSON.');
        assert(json.containsKey(r'countryCodeSource'),
            'Required key "CloudExportSettings[countryCodeSource]" is missing from JSON.');
        assert(json.containsKey(r'currencyCode'),
            'Required key "CloudExportSettings[currencyCode]" is missing from JSON.');
        assert(json.containsKey(r'currencyCodeSource'),
            'Required key "CloudExportSettings[currencyCodeSource]" is missing from JSON.');
        assert(json.containsKey(r'electricityPriceMode'),
            'Required key "CloudExportSettings[electricityPriceMode]" is missing from JSON.');
        assert(json[r'electricityPriceMode'] != null,
            'Required key "CloudExportSettings[electricityPriceMode]" has a null value in JSON.');
        assert(json.containsKey(r'manualElectricityPrice'),
            'Required key "CloudExportSettings[manualElectricityPrice]" is missing from JSON.');
        assert(json.containsKey(r'electricityPriceSource'),
            'Required key "CloudExportSettings[electricityPriceSource]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "CloudExportSettings[updatedAt]" is missing from JSON.');
        return true;
      }());

      return CloudExportSettings(
        countryCode: mapValueOfType<String>(json, r'countryCode'),
        countryCodeSource: CloudExportSettingsCountryCodeSourceEnum.fromJson(
            json[r'countryCodeSource']),
        currencyCode: mapValueOfType<String>(json, r'currencyCode'),
        currencyCodeSource: CloudExportSettingsCurrencyCodeSourceEnum.fromJson(
            json[r'currencyCodeSource']),
        electricityPriceMode:
            CloudExportSettingsElectricityPriceModeEnum.fromJson(
                json[r'electricityPriceMode'])!,
        manualElectricityPrice: json[r'manualElectricityPrice'] == null
            ? null
            : num.parse('${json[r'manualElectricityPrice']}'),
        electricityPriceSource:
            CloudExportSettingsElectricityPriceSourceEnum.fromJson(
                json[r'electricityPriceSource']),
        updatedAt: mapDateTime(json, r'updatedAt', r''),
      );
    }
    return null;
  }

  static List<CloudExportSettings> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSettings>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSettings.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportSettings> mapFromJson(dynamic json) {
    final map = <String, CloudExportSettings>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportSettings.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportSettings-objects as value to a dart map
  static Map<String, List<CloudExportSettings>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportSettings>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportSettings.listFromJson(
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

enum CloudExportSettingsCountryCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSettingsCountryCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSettingsCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSettingsCountryCodeSourceEnum? fromJson(dynamic value) =>
      CloudExportSettingsCountryCodeSourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [CloudExportSettingsCountryCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSettingsCountryCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSettingsCountryCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSettingsCountryCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSettingsCountryCodeSourceEnum] to String,
/// and [decode] dynamic data back to [CloudExportSettingsCountryCodeSourceEnum].
class CloudExportSettingsCountryCodeSourceEnumTypeTransformer {
  factory CloudExportSettingsCountryCodeSourceEnumTypeTransformer() =>
      _instance ??=
          const CloudExportSettingsCountryCodeSourceEnumTypeTransformer._();

  const CloudExportSettingsCountryCodeSourceEnumTypeTransformer._();

  String encode(CloudExportSettingsCountryCodeSourceEnum data) => data._value;

  /// Returns the instance of [CloudExportSettingsCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSettingsCountryCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSettingsCountryCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return CloudExportSettingsCountryCodeSourceEnum.detected;
        case r'manual':
          return CloudExportSettingsCountryCodeSourceEnum.manual;
        case r'migratedManual':
          return CloudExportSettingsCountryCodeSourceEnum.migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSettingsCountryCodeSourceEnumTypeTransformer? _instance;
}

enum CloudExportSettingsCurrencyCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSettingsCurrencyCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSettingsCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSettingsCurrencyCodeSourceEnum? fromJson(dynamic value) =>
      CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [CloudExportSettingsCurrencyCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSettingsCurrencyCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSettingsCurrencyCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSettingsCurrencyCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSettingsCurrencyCodeSourceEnum] to String,
/// and [decode] dynamic data back to [CloudExportSettingsCurrencyCodeSourceEnum].
class CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer {
  factory CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer() =>
      _instance ??=
          const CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer._();

  const CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer._();

  String encode(CloudExportSettingsCurrencyCodeSourceEnum data) => data._value;

  /// Returns the instance of [CloudExportSettingsCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSettingsCurrencyCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSettingsCurrencyCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return CloudExportSettingsCurrencyCodeSourceEnum.detected;
        case r'manual':
          return CloudExportSettingsCurrencyCodeSourceEnum.manual;
        case r'migratedManual':
          return CloudExportSettingsCurrencyCodeSourceEnum.migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSettingsCurrencyCodeSourceEnumTypeTransformer? _instance;
}

enum CloudExportSettingsElectricityPriceModeEnum {
  automatic._(r'automatic'),
  manual._(r'manual'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSettingsElectricityPriceModeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSettingsElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSettingsElectricityPriceModeEnum? fromJson(dynamic value) =>
      CloudExportSettingsElectricityPriceModeEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [CloudExportSettingsElectricityPriceModeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSettingsElectricityPriceModeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSettingsElectricityPriceModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSettingsElectricityPriceModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSettingsElectricityPriceModeEnum] to String,
/// and [decode] dynamic data back to [CloudExportSettingsElectricityPriceModeEnum].
class CloudExportSettingsElectricityPriceModeEnumTypeTransformer {
  factory CloudExportSettingsElectricityPriceModeEnumTypeTransformer() =>
      _instance ??=
          const CloudExportSettingsElectricityPriceModeEnumTypeTransformer._();

  const CloudExportSettingsElectricityPriceModeEnumTypeTransformer._();

  String encode(CloudExportSettingsElectricityPriceModeEnum data) =>
      data._value;

  /// Returns the instance of [CloudExportSettingsElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSettingsElectricityPriceModeEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSettingsElectricityPriceModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'automatic':
          return CloudExportSettingsElectricityPriceModeEnum.automatic;
        case r'manual':
          return CloudExportSettingsElectricityPriceModeEnum.manual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSettingsElectricityPriceModeEnumTypeTransformer? _instance;
}

enum CloudExportSettingsElectricityPriceSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSettingsElectricityPriceSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSettingsElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSettingsElectricityPriceSourceEnum? fromJson(
          dynamic value) =>
      CloudExportSettingsElectricityPriceSourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [CloudExportSettingsElectricityPriceSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSettingsElectricityPriceSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSettingsElectricityPriceSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            CloudExportSettingsElectricityPriceSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSettingsElectricityPriceSourceEnum] to String,
/// and [decode] dynamic data back to [CloudExportSettingsElectricityPriceSourceEnum].
class CloudExportSettingsElectricityPriceSourceEnumTypeTransformer {
  factory CloudExportSettingsElectricityPriceSourceEnumTypeTransformer() =>
      _instance ??=
          const CloudExportSettingsElectricityPriceSourceEnumTypeTransformer
              ._();

  const CloudExportSettingsElectricityPriceSourceEnumTypeTransformer._();

  String encode(CloudExportSettingsElectricityPriceSourceEnum data) =>
      data._value;

  /// Returns the instance of [CloudExportSettingsElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSettingsElectricityPriceSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSettingsElectricityPriceSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return CloudExportSettingsElectricityPriceSourceEnum.detected;
        case r'manual':
          return CloudExportSettingsElectricityPriceSourceEnum.manual;
        case r'migratedManual':
          return CloudExportSettingsElectricityPriceSourceEnum.migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSettingsElectricityPriceSourceEnumTypeTransformer?
      _instance;
}
