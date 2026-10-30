//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class HealthResponse {
  /// Returns a new [HealthResponse] instance.
  HealthResponse({
    required this.status,
    required this.version,
    required this.uptimeSec,
  });

  HealthResponseStatusEnum status;

  String version;

  /// Minimum value: 0
  int uptimeSec;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthResponse &&
          other.status == status &&
          other.version == version &&
          other.uptimeSec == uptimeSec;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (status.hashCode) + (version.hashCode) + (uptimeSec.hashCode);

  @override
  String toString() =>
      'HealthResponse[status=$status, version=$version, uptimeSec=$uptimeSec]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'status'] = this.status;
    json[r'version'] = this.version;
    json[r'uptimeSec'] = this.uptimeSec;
    return json;
  }

  /// Returns a new [HealthResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static HealthResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'),
            'Required key "HealthResponse[status]" is missing from JSON.');
        assert(json[r'status'] != null,
            'Required key "HealthResponse[status]" has a null value in JSON.');
        assert(json.containsKey(r'version'),
            'Required key "HealthResponse[version]" is missing from JSON.');
        assert(json[r'version'] != null,
            'Required key "HealthResponse[version]" has a null value in JSON.');
        assert(json.containsKey(r'uptimeSec'),
            'Required key "HealthResponse[uptimeSec]" is missing from JSON.');
        assert(json[r'uptimeSec'] != null,
            'Required key "HealthResponse[uptimeSec]" has a null value in JSON.');
        return true;
      }());

      return HealthResponse(
        status: HealthResponseStatusEnum.fromJson(json[r'status'])!,
        version: mapValueOfType<String>(json, r'version')!,
        uptimeSec: mapValueOfType<int>(json, r'uptimeSec')!,
      );
    }
    return null;
  }

  static List<HealthResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <HealthResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, HealthResponse> mapFromJson(dynamic json) {
    final map = <String, HealthResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = HealthResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of HealthResponse-objects as value to a dart map
  static Map<String, List<HealthResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<HealthResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = HealthResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'status',
    'version',
    'uptimeSec',
  };
}

enum HealthResponseStatusEnum {
  ok._(r'ok'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const HealthResponseStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [HealthResponseStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static HealthResponseStatusEnum? fromJson(dynamic value) =>
      HealthResponseStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [HealthResponseStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<HealthResponseStatusEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <HealthResponseStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = HealthResponseStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [HealthResponseStatusEnum] to String,
/// and [decode] dynamic data back to [HealthResponseStatusEnum].
class HealthResponseStatusEnumTypeTransformer {
  factory HealthResponseStatusEnumTypeTransformer() =>
      _instance ??= const HealthResponseStatusEnumTypeTransformer._();

  const HealthResponseStatusEnumTypeTransformer._();

  String encode(HealthResponseStatusEnum data) => data._value;

  /// Returns the instance of [HealthResponseStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  HealthResponseStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is HealthResponseStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok':
          return HealthResponseStatusEnum.ok;
        case r'unknown_default_open_api':
          return HealthResponseStatusEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return HealthResponseStatusEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static HealthResponseStatusEnumTypeTransformer? _instance;
}
