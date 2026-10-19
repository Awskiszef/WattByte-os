//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AIGenerateRequest {
  /// Returns a new [AIGenerateRequest] instance.
  AIGenerateRequest({
    this.mode,
    this.locale,
    required this.input,
  });

  AIGenerateRequestModeEnum? mode;

  AIGenerateRequestLocaleEnum? locale;

  AIInput input;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIGenerateRequest &&
          other.mode == mode &&
          other.locale == locale &&
          other.input == input;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (mode == null ? 0 : mode!.hashCode) +
      (locale == null ? 0 : locale!.hashCode) +
      (input.hashCode);

  @override
  String toString() =>
      'AIGenerateRequest[mode=$mode, locale=$locale, input=$input]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (this.mode != null) {
      json[r'mode'] = this.mode;
    } else {
      json[r'mode'] = null;
    }
    if (this.locale != null) {
      json[r'locale'] = this.locale;
    } else {
      json[r'locale'] = null;
    }
    json[r'input'] = this.input;
    return json;
  }

  /// Returns a new [AIGenerateRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AIGenerateRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'input'),
            'Required key "AIGenerateRequest[input]" is missing from JSON.');
        assert(json[r'input'] != null,
            'Required key "AIGenerateRequest[input]" has a null value in JSON.');
        return true;
      }());

      return AIGenerateRequest(
        mode: AIGenerateRequestModeEnum.fromJson(json[r'mode']),
        locale: AIGenerateRequestLocaleEnum.fromJson(json[r'locale']),
        input: AIInput.fromJson(json[r'input'])!,
      );
    }
    return null;
  }

  static List<AIGenerateRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIGenerateRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIGenerateRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AIGenerateRequest> mapFromJson(dynamic json) {
    final map = <String, AIGenerateRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AIGenerateRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AIGenerateRequest-objects as value to a dart map
  static Map<String, List<AIGenerateRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AIGenerateRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AIGenerateRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'input',
  };
}

enum AIGenerateRequestModeEnum {
  normal._(r'normal'),
  friendly._(r'friendly'),
  funny._(r'funny'),
  roast._(r'roast'),
  ;

  /// Instantiate a new enum with the provided value.
  const AIGenerateRequestModeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AIGenerateRequestModeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AIGenerateRequestModeEnum? fromJson(dynamic value) =>
      AIGenerateRequestModeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AIGenerateRequestModeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AIGenerateRequestModeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIGenerateRequestModeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIGenerateRequestModeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AIGenerateRequestModeEnum] to String,
/// and [decode] dynamic data back to [AIGenerateRequestModeEnum].
class AIGenerateRequestModeEnumTypeTransformer {
  factory AIGenerateRequestModeEnumTypeTransformer() =>
      _instance ??= const AIGenerateRequestModeEnumTypeTransformer._();

  const AIGenerateRequestModeEnumTypeTransformer._();

  String encode(AIGenerateRequestModeEnum data) => data._value;

  /// Returns the instance of [AIGenerateRequestModeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AIGenerateRequestModeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AIGenerateRequestModeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'normal':
          return AIGenerateRequestModeEnum.normal;
        case r'friendly':
          return AIGenerateRequestModeEnum.friendly;
        case r'funny':
          return AIGenerateRequestModeEnum.funny;
        case r'roast':
          return AIGenerateRequestModeEnum.roast;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AIGenerateRequestModeEnumTypeTransformer? _instance;
}

enum AIGenerateRequestLocaleEnum {
  en._(r'en'),
  pl._(r'pl'),
  ;

  /// Instantiate a new enum with the provided value.
  const AIGenerateRequestLocaleEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AIGenerateRequestLocaleEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AIGenerateRequestLocaleEnum? fromJson(dynamic value) =>
      AIGenerateRequestLocaleEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AIGenerateRequestLocaleEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AIGenerateRequestLocaleEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIGenerateRequestLocaleEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIGenerateRequestLocaleEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AIGenerateRequestLocaleEnum] to String,
/// and [decode] dynamic data back to [AIGenerateRequestLocaleEnum].
class AIGenerateRequestLocaleEnumTypeTransformer {
  factory AIGenerateRequestLocaleEnumTypeTransformer() =>
      _instance ??= const AIGenerateRequestLocaleEnumTypeTransformer._();

  const AIGenerateRequestLocaleEnumTypeTransformer._();

  String encode(AIGenerateRequestLocaleEnum data) => data._value;

  /// Returns the instance of [AIGenerateRequestLocaleEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AIGenerateRequestLocaleEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AIGenerateRequestLocaleEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'en':
          return AIGenerateRequestLocaleEnum.en;
        case r'pl':
          return AIGenerateRequestLocaleEnum.pl;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AIGenerateRequestLocaleEnumTypeTransformer? _instance;
}
