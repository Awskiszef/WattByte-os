//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class RegionResponse {
  /// Returns a new [RegionResponse] instance.
  RegionResponse({
    required this.countryCode,
    required this.source_,
  });

  String? countryCode;

  RegionResponseSource_Enum source_;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegionResponse &&
          other.countryCode == countryCode &&
          other.source_ == source_;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (countryCode == null ? 0 : countryCode!.hashCode) + (source_.hashCode);

  @override
  String toString() =>
      'RegionResponse[countryCode=$countryCode, source_=$source_]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.countryCode != null) {
      json[r'countryCode'] = this.countryCode;
    } else {
      json[r'countryCode'] = null;
    }
    json[r'source'] = this.source_;
    return json;
  }

  /// Returns a new [RegionResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static RegionResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'countryCode'),
            'Required key "RegionResponse[countryCode]" is missing from JSON.');
        assert(json.containsKey(r'source'),
            'Required key "RegionResponse[source]" is missing from JSON.');
        assert(json[r'source'] != null,
            'Required key "RegionResponse[source]" has a null value in JSON.');
        return true;
      }());

      return RegionResponse(
        countryCode: mapValueOfType<String>(json, r'countryCode'),
        source_: RegionResponseSource_Enum.fromJson(json[r'source'])!,
      );
    }
    return null;
  }

  static List<RegionResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <RegionResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RegionResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, RegionResponse> mapFromJson(dynamic json) {
    final map = <String, RegionResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = RegionResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of RegionResponse-objects as value to a dart map
  static Map<String, List<RegionResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<RegionResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = RegionResponse.listFromJson(
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
    'source',
  };
}

enum RegionResponseSource_Enum {
  backendCountry._(r'backendCountry'),
  none._(r'none'),
  ;

  /// Instantiate a new enum with the provided value.
  const RegionResponseSource_Enum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [RegionResponseSource_Enum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static RegionResponseSource_Enum? fromJson(dynamic value) =>
      RegionResponseSource_EnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [RegionResponseSource_Enum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<RegionResponseSource_Enum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <RegionResponseSource_Enum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = RegionResponseSource_Enum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [RegionResponseSource_Enum] to String,
/// and [decode] dynamic data back to [RegionResponseSource_Enum].
class RegionResponseSource_EnumTypeTransformer {
  factory RegionResponseSource_EnumTypeTransformer() =>
      _instance ??= const RegionResponseSource_EnumTypeTransformer._();

  const RegionResponseSource_EnumTypeTransformer._();

  String encode(RegionResponseSource_Enum data) => data._value;

  /// Returns the instance of [RegionResponseSource_Enum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  RegionResponseSource_Enum? decode(dynamic data, {bool allowNull = true}) {
    if (data is RegionResponseSource_Enum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'backendCountry':
          return RegionResponseSource_Enum.backendCountry;
        case r'none':
          return RegionResponseSource_Enum.none;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static RegionResponseSource_EnumTypeTransformer? _instance;
}
