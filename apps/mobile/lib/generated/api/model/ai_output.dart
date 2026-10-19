//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AIOutput {
  /// Returns a new [AIOutput] instance.
  AIOutput({
    required this.title,
    required this.message,
    required this.tone,
    required this.severity,
    required this.emoji,
  });

  String title;

  String message;

  AIOutputToneEnum tone;

  AIOutputSeverityEnum severity;

  String emoji;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIOutput &&
          other.title == title &&
          other.message == message &&
          other.tone == tone &&
          other.severity == severity &&
          other.emoji == emoji;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (title.hashCode) +
      (message.hashCode) +
      (tone.hashCode) +
      (severity.hashCode) +
      (emoji.hashCode);

  @override
  String toString() =>
      'AIOutput[title=$title, message=$message, tone=$tone, severity=$severity, emoji=$emoji]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'title'] = this.title;
    json[r'message'] = this.message;
    json[r'tone'] = this.tone;
    json[r'severity'] = this.severity;
    json[r'emoji'] = this.emoji;
    return json;
  }

  /// Returns a new [AIOutput] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AIOutput? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'title'),
            'Required key "AIOutput[title]" is missing from JSON.');
        assert(json[r'title'] != null,
            'Required key "AIOutput[title]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "AIOutput[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "AIOutput[message]" has a null value in JSON.');
        assert(json.containsKey(r'tone'),
            'Required key "AIOutput[tone]" is missing from JSON.');
        assert(json[r'tone'] != null,
            'Required key "AIOutput[tone]" has a null value in JSON.');
        assert(json.containsKey(r'severity'),
            'Required key "AIOutput[severity]" is missing from JSON.');
        assert(json[r'severity'] != null,
            'Required key "AIOutput[severity]" has a null value in JSON.');
        assert(json.containsKey(r'emoji'),
            'Required key "AIOutput[emoji]" is missing from JSON.');
        assert(json[r'emoji'] != null,
            'Required key "AIOutput[emoji]" has a null value in JSON.');
        return true;
      }());

      return AIOutput(
        title: mapValueOfType<String>(json, r'title')!,
        message: mapValueOfType<String>(json, r'message')!,
        tone: AIOutputToneEnum.fromJson(json[r'tone'])!,
        severity: AIOutputSeverityEnum.fromJson(json[r'severity'])!,
        emoji: mapValueOfType<String>(json, r'emoji')!,
      );
    }
    return null;
  }

  static List<AIOutput> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIOutput>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIOutput.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AIOutput> mapFromJson(dynamic json) {
    final map = <String, AIOutput>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AIOutput.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AIOutput-objects as value to a dart map
  static Map<String, List<AIOutput>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AIOutput>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AIOutput.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'title',
    'message',
    'tone',
    'severity',
    'emoji',
  };
}

enum AIOutputToneEnum {
  normal._(r'normal'),
  friendly._(r'friendly'),
  funny._(r'funny'),
  roast._(r'roast'),
  ;

  /// Instantiate a new enum with the provided value.
  const AIOutputToneEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AIOutputToneEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AIOutputToneEnum? fromJson(dynamic value) =>
      AIOutputToneEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AIOutputToneEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AIOutputToneEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIOutputToneEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIOutputToneEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AIOutputToneEnum] to String,
/// and [decode] dynamic data back to [AIOutputToneEnum].
class AIOutputToneEnumTypeTransformer {
  factory AIOutputToneEnumTypeTransformer() =>
      _instance ??= const AIOutputToneEnumTypeTransformer._();

  const AIOutputToneEnumTypeTransformer._();

  String encode(AIOutputToneEnum data) => data._value;

  /// Returns the instance of [AIOutputToneEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AIOutputToneEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AIOutputToneEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'normal':
          return AIOutputToneEnum.normal;
        case r'friendly':
          return AIOutputToneEnum.friendly;
        case r'funny':
          return AIOutputToneEnum.funny;
        case r'roast':
          return AIOutputToneEnum.roast;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AIOutputToneEnumTypeTransformer? _instance;
}

enum AIOutputSeverityEnum {
  info._(r'info'),
  notice._(r'notice'),
  celebrate._(r'celebrate'),
  ;

  /// Instantiate a new enum with the provided value.
  const AIOutputSeverityEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AIOutputSeverityEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AIOutputSeverityEnum? fromJson(dynamic value) =>
      AIOutputSeverityEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AIOutputSeverityEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AIOutputSeverityEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIOutputSeverityEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIOutputSeverityEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AIOutputSeverityEnum] to String,
/// and [decode] dynamic data back to [AIOutputSeverityEnum].
class AIOutputSeverityEnumTypeTransformer {
  factory AIOutputSeverityEnumTypeTransformer() =>
      _instance ??= const AIOutputSeverityEnumTypeTransformer._();

  const AIOutputSeverityEnumTypeTransformer._();

  String encode(AIOutputSeverityEnum data) => data._value;

  /// Returns the instance of [AIOutputSeverityEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AIOutputSeverityEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AIOutputSeverityEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'info':
          return AIOutputSeverityEnum.info;
        case r'notice':
          return AIOutputSeverityEnum.notice;
        case r'celebrate':
          return AIOutputSeverityEnum.celebrate;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AIOutputSeverityEnumTypeTransformer? _instance;
}
