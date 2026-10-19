//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UpdateUserSettingsRequest {
  /// Returns a new [UpdateUserSettingsRequest] instance.
  UpdateUserSettingsRequest({
    this.countryCode,
    this.countryCodeSource,
    this.currencyCode,
    this.currencyCodeSource,
    this.electricityPriceMode,
    this.manualElectricityPrice,
    this.electricityPriceSource,
  });

  String? countryCode;

  UpdateUserSettingsRequestCountryCodeSourceEnum? countryCodeSource;

  String? currencyCode;

  UpdateUserSettingsRequestCurrencyCodeSourceEnum? currencyCodeSource;

  UpdateUserSettingsRequestElectricityPriceModeEnum? electricityPriceMode;

  /// Minimum value: 0
  /// Maximum value: 1000
  num? manualElectricityPrice;

  UpdateUserSettingsRequestElectricityPriceSourceEnum? electricityPriceSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateUserSettingsRequest &&
          other.countryCode == countryCode &&
          other.countryCodeSource == countryCodeSource &&
          other.currencyCode == currencyCode &&
          other.currencyCodeSource == currencyCodeSource &&
          other.electricityPriceMode == electricityPriceMode &&
          other.manualElectricityPrice == manualElectricityPrice &&
          other.electricityPriceSource == electricityPriceSource;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (countryCode == null ? 0 : countryCode!.hashCode) +
      (countryCodeSource == null ? 0 : countryCodeSource!.hashCode) +
      (currencyCode == null ? 0 : currencyCode!.hashCode) +
      (currencyCodeSource == null ? 0 : currencyCodeSource!.hashCode) +
      (electricityPriceMode == null ? 0 : electricityPriceMode!.hashCode) +
      (manualElectricityPrice == null ? 0 : manualElectricityPrice!.hashCode) +
      (electricityPriceSource == null ? 0 : electricityPriceSource!.hashCode);

  @override
  String toString() =>
      'UpdateUserSettingsRequest[countryCode=$countryCode, countryCodeSource=$countryCodeSource, currencyCode=$currencyCode, currencyCodeSource=$currencyCodeSource, electricityPriceMode=$electricityPriceMode, manualElectricityPrice=$manualElectricityPrice, electricityPriceSource=$electricityPriceSource]';

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
    if (this.electricityPriceMode != null) {
      json[r'electricityPriceMode'] = this.electricityPriceMode;
    } else {
      json[r'electricityPriceMode'] = null;
    }
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
    return json;
  }

  /// Returns a new [UpdateUserSettingsRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UpdateUserSettingsRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        return true;
      }());

      return UpdateUserSettingsRequest(
        countryCode: mapValueOfType<String>(json, r'countryCode'),
        countryCodeSource:
            UpdateUserSettingsRequestCountryCodeSourceEnum.fromJson(
                json[r'countryCodeSource']),
        currencyCode: mapValueOfType<String>(json, r'currencyCode'),
        currencyCodeSource:
            UpdateUserSettingsRequestCurrencyCodeSourceEnum.fromJson(
                json[r'currencyCodeSource']),
        electricityPriceMode:
            UpdateUserSettingsRequestElectricityPriceModeEnum.fromJson(
                json[r'electricityPriceMode']),
        manualElectricityPrice: json[r'manualElectricityPrice'] == null
            ? null
            : num.parse('${json[r'manualElectricityPrice']}'),
        electricityPriceSource:
            UpdateUserSettingsRequestElectricityPriceSourceEnum.fromJson(
                json[r'electricityPriceSource']),
      );
    }
    return null;
  }

  static List<UpdateUserSettingsRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdateUserSettingsRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UpdateUserSettingsRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UpdateUserSettingsRequest> mapFromJson(dynamic json) {
    final map = <String, UpdateUserSettingsRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UpdateUserSettingsRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UpdateUserSettingsRequest-objects as value to a dart map
  static Map<String, List<UpdateUserSettingsRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UpdateUserSettingsRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UpdateUserSettingsRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{};
}

enum UpdateUserSettingsRequestCountryCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const UpdateUserSettingsRequestCountryCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UpdateUserSettingsRequestCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UpdateUserSettingsRequestCountryCodeSourceEnum? fromJson(
          dynamic value) =>
      UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [UpdateUserSettingsRequestCountryCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UpdateUserSettingsRequestCountryCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdateUserSettingsRequestCountryCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            UpdateUserSettingsRequestCountryCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UpdateUserSettingsRequestCountryCodeSourceEnum] to String,
/// and [decode] dynamic data back to [UpdateUserSettingsRequestCountryCodeSourceEnum].
class UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer {
  factory UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer() =>
      _instance ??=
          const UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer
              ._();

  const UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer._();

  String encode(UpdateUserSettingsRequestCountryCodeSourceEnum data) =>
      data._value;

  /// Returns the instance of [UpdateUserSettingsRequestCountryCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UpdateUserSettingsRequestCountryCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UpdateUserSettingsRequestCountryCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UpdateUserSettingsRequestCountryCodeSourceEnum.detected;
        case r'manual':
          return UpdateUserSettingsRequestCountryCodeSourceEnum.manual;
        case r'migratedManual':
          return UpdateUserSettingsRequestCountryCodeSourceEnum.migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UpdateUserSettingsRequestCountryCodeSourceEnumTypeTransformer?
      _instance;
}

enum UpdateUserSettingsRequestCurrencyCodeSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const UpdateUserSettingsRequestCurrencyCodeSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UpdateUserSettingsRequestCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UpdateUserSettingsRequestCurrencyCodeSourceEnum? fromJson(
          dynamic value) =>
      UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [UpdateUserSettingsRequestCurrencyCodeSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UpdateUserSettingsRequestCurrencyCodeSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdateUserSettingsRequestCurrencyCodeSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            UpdateUserSettingsRequestCurrencyCodeSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UpdateUserSettingsRequestCurrencyCodeSourceEnum] to String,
/// and [decode] dynamic data back to [UpdateUserSettingsRequestCurrencyCodeSourceEnum].
class UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer {
  factory UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer() =>
      _instance ??=
          const UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer
              ._();

  const UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer._();

  String encode(UpdateUserSettingsRequestCurrencyCodeSourceEnum data) =>
      data._value;

  /// Returns the instance of [UpdateUserSettingsRequestCurrencyCodeSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UpdateUserSettingsRequestCurrencyCodeSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UpdateUserSettingsRequestCurrencyCodeSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UpdateUserSettingsRequestCurrencyCodeSourceEnum.detected;
        case r'manual':
          return UpdateUserSettingsRequestCurrencyCodeSourceEnum.manual;
        case r'migratedManual':
          return UpdateUserSettingsRequestCurrencyCodeSourceEnum.migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UpdateUserSettingsRequestCurrencyCodeSourceEnumTypeTransformer?
      _instance;
}

enum UpdateUserSettingsRequestElectricityPriceModeEnum {
  automatic._(r'automatic'),
  manual._(r'manual'),
  ;

  /// Instantiate a new enum with the provided value.
  const UpdateUserSettingsRequestElectricityPriceModeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UpdateUserSettingsRequestElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UpdateUserSettingsRequestElectricityPriceModeEnum? fromJson(
          dynamic value) =>
      UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [UpdateUserSettingsRequestElectricityPriceModeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UpdateUserSettingsRequestElectricityPriceModeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdateUserSettingsRequestElectricityPriceModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            UpdateUserSettingsRequestElectricityPriceModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UpdateUserSettingsRequestElectricityPriceModeEnum] to String,
/// and [decode] dynamic data back to [UpdateUserSettingsRequestElectricityPriceModeEnum].
class UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer {
  factory UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer() =>
      _instance ??=
          const UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer
              ._();

  const UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer._();

  String encode(UpdateUserSettingsRequestElectricityPriceModeEnum data) =>
      data._value;

  /// Returns the instance of [UpdateUserSettingsRequestElectricityPriceModeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UpdateUserSettingsRequestElectricityPriceModeEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UpdateUserSettingsRequestElectricityPriceModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'automatic':
          return UpdateUserSettingsRequestElectricityPriceModeEnum.automatic;
        case r'manual':
          return UpdateUserSettingsRequestElectricityPriceModeEnum.manual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UpdateUserSettingsRequestElectricityPriceModeEnumTypeTransformer?
      _instance;
}

enum UpdateUserSettingsRequestElectricityPriceSourceEnum {
  detected._(r'detected'),
  manual._(r'manual'),
  migratedManual._(r'migratedManual'),
  ;

  /// Instantiate a new enum with the provided value.
  const UpdateUserSettingsRequestElectricityPriceSourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UpdateUserSettingsRequestElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UpdateUserSettingsRequestElectricityPriceSourceEnum? fromJson(
          dynamic value) =>
      UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [UpdateUserSettingsRequestElectricityPriceSourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UpdateUserSettingsRequestElectricityPriceSourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UpdateUserSettingsRequestElectricityPriceSourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            UpdateUserSettingsRequestElectricityPriceSourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UpdateUserSettingsRequestElectricityPriceSourceEnum] to String,
/// and [decode] dynamic data back to [UpdateUserSettingsRequestElectricityPriceSourceEnum].
class UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer {
  factory UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer() =>
      _instance ??=
          const UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer
              ._();

  const UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer._();

  String encode(UpdateUserSettingsRequestElectricityPriceSourceEnum data) =>
      data._value;

  /// Returns the instance of [UpdateUserSettingsRequestElectricityPriceSourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UpdateUserSettingsRequestElectricityPriceSourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is UpdateUserSettingsRequestElectricityPriceSourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'detected':
          return UpdateUserSettingsRequestElectricityPriceSourceEnum.detected;
        case r'manual':
          return UpdateUserSettingsRequestElectricityPriceSourceEnum.manual;
        case r'migratedManual':
          return UpdateUserSettingsRequestElectricityPriceSourceEnum
              .migratedManual;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UpdateUserSettingsRequestElectricityPriceSourceEnumTypeTransformer?
      _instance;
}
