//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class ElectricityPriceDto {
  /// Returns a new [ElectricityPriceDto] instance.
  ElectricityPriceDto({
    required this.countryCode,
    required this.currency,
    required this.pricePerKwh,
    required this.period,
    required this.source_,
    required this.includesTaxes,
    required this.includesNetworkCosts,
    required this.updatedAt,
    required this.stale,
  });

  String countryCode;

  String currency;

  num pricePerKwh;

  String period;

  ElectricityPriceDtoSource_Enum source_;

  bool? includesTaxes;

  bool? includesNetworkCosts;

  DateTime updatedAt;

  bool stale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElectricityPriceDto &&
          other.countryCode == countryCode &&
          other.currency == currency &&
          other.pricePerKwh == pricePerKwh &&
          other.period == period &&
          other.source_ == source_ &&
          other.includesTaxes == includesTaxes &&
          other.includesNetworkCosts == includesNetworkCosts &&
          other.updatedAt == updatedAt &&
          other.stale == stale;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (countryCode.hashCode) +
      (currency.hashCode) +
      (pricePerKwh.hashCode) +
      (period.hashCode) +
      (source_.hashCode) +
      (includesTaxes == null ? 0 : includesTaxes!.hashCode) +
      (includesNetworkCosts == null ? 0 : includesNetworkCosts!.hashCode) +
      (updatedAt.hashCode) +
      (stale.hashCode);

  @override
  String toString() =>
      'ElectricityPriceDto[countryCode=$countryCode, currency=$currency, pricePerKwh=$pricePerKwh, period=$period, source_=$source_, includesTaxes=$includesTaxes, includesNetworkCosts=$includesNetworkCosts, updatedAt=$updatedAt, stale=$stale]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'countryCode'] = this.countryCode;
    json[r'currency'] = this.currency;
    json[r'pricePerKwh'] = this.pricePerKwh;
    json[r'period'] = this.period;
    json[r'source'] = this.source_;
    if (this.includesTaxes != null) {
      json[r'includesTaxes'] = this.includesTaxes;
    } else {
      json[r'includesTaxes'] = null;
    }
    if (this.includesNetworkCosts != null) {
      json[r'includesNetworkCosts'] = this.includesNetworkCosts;
    } else {
      json[r'includesNetworkCosts'] = null;
    }
    json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    json[r'stale'] = this.stale;
    return json;
  }

  /// Returns a new [ElectricityPriceDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ElectricityPriceDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'countryCode'),
            'Required key "ElectricityPriceDto[countryCode]" is missing from JSON.');
        assert(json[r'countryCode'] != null,
            'Required key "ElectricityPriceDto[countryCode]" has a null value in JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "ElectricityPriceDto[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "ElectricityPriceDto[currency]" has a null value in JSON.');
        assert(json.containsKey(r'pricePerKwh'),
            'Required key "ElectricityPriceDto[pricePerKwh]" is missing from JSON.');
        assert(json[r'pricePerKwh'] != null,
            'Required key "ElectricityPriceDto[pricePerKwh]" has a null value in JSON.');
        assert(json.containsKey(r'period'),
            'Required key "ElectricityPriceDto[period]" is missing from JSON.');
        assert(json[r'period'] != null,
            'Required key "ElectricityPriceDto[period]" has a null value in JSON.');
        assert(json.containsKey(r'source'),
            'Required key "ElectricityPriceDto[source]" is missing from JSON.');
        assert(json[r'source'] != null,
            'Required key "ElectricityPriceDto[source]" has a null value in JSON.');
        assert(json.containsKey(r'includesTaxes'),
            'Required key "ElectricityPriceDto[includesTaxes]" is missing from JSON.');
        assert(json.containsKey(r'includesNetworkCosts'),
            'Required key "ElectricityPriceDto[includesNetworkCosts]" is missing from JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "ElectricityPriceDto[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null,
            'Required key "ElectricityPriceDto[updatedAt]" has a null value in JSON.');
        assert(json.containsKey(r'stale'),
            'Required key "ElectricityPriceDto[stale]" is missing from JSON.');
        assert(json[r'stale'] != null,
            'Required key "ElectricityPriceDto[stale]" has a null value in JSON.');
        return true;
      }());

      return ElectricityPriceDto(
        countryCode: mapValueOfType<String>(json, r'countryCode')!,
        currency: mapValueOfType<String>(json, r'currency')!,
        pricePerKwh: num.parse('${json[r'pricePerKwh']}'),
        period: mapValueOfType<String>(json, r'period')!,
        source_: ElectricityPriceDtoSource_Enum.fromJson(json[r'source'])!,
        includesTaxes: mapValueOfType<bool>(json, r'includesTaxes'),
        includesNetworkCosts:
            mapValueOfType<bool>(json, r'includesNetworkCosts'),
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
        stale: mapValueOfType<bool>(json, r'stale')!,
      );
    }
    return null;
  }

  static List<ElectricityPriceDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ElectricityPriceDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ElectricityPriceDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ElectricityPriceDto> mapFromJson(dynamic json) {
    final map = <String, ElectricityPriceDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ElectricityPriceDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ElectricityPriceDto-objects as value to a dart map
  static Map<String, List<ElectricityPriceDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ElectricityPriceDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ElectricityPriceDto.listFromJson(
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
    'currency',
    'pricePerKwh',
    'period',
    'source',
    'includesTaxes',
    'includesNetworkCosts',
    'updatedAt',
    'stale',
  };
}

enum ElectricityPriceDtoSource_Enum {
  eurostat._(r'eurostat'),
  government._(r'government'),
  manual._(r'manual'),
  fallback._(r'fallback'),
  ;

  /// Instantiate a new enum with the provided value.
  const ElectricityPriceDtoSource_Enum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ElectricityPriceDtoSource_Enum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ElectricityPriceDtoSource_Enum? fromJson(dynamic value) =>
      ElectricityPriceDtoSource_EnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ElectricityPriceDtoSource_Enum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ElectricityPriceDtoSource_Enum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ElectricityPriceDtoSource_Enum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ElectricityPriceDtoSource_Enum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ElectricityPriceDtoSource_Enum] to String,
/// and [decode] dynamic data back to [ElectricityPriceDtoSource_Enum].
class ElectricityPriceDtoSource_EnumTypeTransformer {
  factory ElectricityPriceDtoSource_EnumTypeTransformer() =>
      _instance ??= const ElectricityPriceDtoSource_EnumTypeTransformer._();

  const ElectricityPriceDtoSource_EnumTypeTransformer._();

  String encode(ElectricityPriceDtoSource_Enum data) => data._value;

  /// Returns the instance of [ElectricityPriceDtoSource_Enum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ElectricityPriceDtoSource_Enum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is ElectricityPriceDtoSource_Enum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'eurostat':
          return ElectricityPriceDtoSource_Enum.eurostat;
        case r'government':
          return ElectricityPriceDtoSource_Enum.government;
        case r'manual':
          return ElectricityPriceDtoSource_Enum.manual;
        case r'fallback':
          return ElectricityPriceDtoSource_Enum.fallback;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ElectricityPriceDtoSource_EnumTypeTransformer? _instance;
}
