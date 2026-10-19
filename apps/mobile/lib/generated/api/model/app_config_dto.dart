//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AppConfigDto {
  /// Returns a new [AppConfigDto] instance.
  AppConfigDto({
    required this.environment,
    required this.features,
    required this.ai,
  });

  AppConfigDtoEnvironmentEnum environment;

  AppConfigDtoFeatures features;

  AppConfigDtoAi ai;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfigDto &&
          other.environment == environment &&
          other.features == features &&
          other.ai == ai;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (environment.hashCode) + (features.hashCode) + (ai.hashCode);

  @override
  String toString() =>
      'AppConfigDto[environment=$environment, features=$features, ai=$ai]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'environment'] = this.environment;
    json[r'features'] = this.features;
    json[r'ai'] = this.ai;
    return json;
  }

  /// Returns a new [AppConfigDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AppConfigDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'environment'),
            'Required key "AppConfigDto[environment]" is missing from JSON.');
        assert(json[r'environment'] != null,
            'Required key "AppConfigDto[environment]" has a null value in JSON.');
        assert(json.containsKey(r'features'),
            'Required key "AppConfigDto[features]" is missing from JSON.');
        assert(json[r'features'] != null,
            'Required key "AppConfigDto[features]" has a null value in JSON.');
        assert(json.containsKey(r'ai'),
            'Required key "AppConfigDto[ai]" is missing from JSON.');
        assert(json[r'ai'] != null,
            'Required key "AppConfigDto[ai]" has a null value in JSON.');
        return true;
      }());

      return AppConfigDto(
        environment:
            AppConfigDtoEnvironmentEnum.fromJson(json[r'environment'])!,
        features: AppConfigDtoFeatures.fromJson(json[r'features'])!,
        ai: AppConfigDtoAi.fromJson(json[r'ai'])!,
      );
    }
    return null;
  }

  static List<AppConfigDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AppConfigDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AppConfigDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AppConfigDto> mapFromJson(dynamic json) {
    final map = <String, AppConfigDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AppConfigDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AppConfigDto-objects as value to a dart map
  static Map<String, List<AppConfigDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AppConfigDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AppConfigDto.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'environment',
    'features',
    'ai',
  };
}

enum AppConfigDtoEnvironmentEnum {
  development._(r'development'),
  staging._(r'staging'),
  production._(r'production'),
  ;

  /// Instantiate a new enum with the provided value.
  const AppConfigDtoEnvironmentEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AppConfigDtoEnvironmentEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AppConfigDtoEnvironmentEnum? fromJson(dynamic value) =>
      AppConfigDtoEnvironmentEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AppConfigDtoEnvironmentEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AppConfigDtoEnvironmentEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AppConfigDtoEnvironmentEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AppConfigDtoEnvironmentEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AppConfigDtoEnvironmentEnum] to String,
/// and [decode] dynamic data back to [AppConfigDtoEnvironmentEnum].
class AppConfigDtoEnvironmentEnumTypeTransformer {
  factory AppConfigDtoEnvironmentEnumTypeTransformer() =>
      _instance ??= const AppConfigDtoEnvironmentEnumTypeTransformer._();

  const AppConfigDtoEnvironmentEnumTypeTransformer._();

  String encode(AppConfigDtoEnvironmentEnum data) => data._value;

  /// Returns the instance of [AppConfigDtoEnvironmentEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AppConfigDtoEnvironmentEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AppConfigDtoEnvironmentEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'development':
          return AppConfigDtoEnvironmentEnum.development;
        case r'staging':
          return AppConfigDtoEnvironmentEnum.staging;
        case r'production':
          return AppConfigDtoEnvironmentEnum.production;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AppConfigDtoEnvironmentEnumTypeTransformer? _instance;
}
