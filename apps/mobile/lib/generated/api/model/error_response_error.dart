//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class ErrorResponseError {
  /// Returns a new [ErrorResponseError] instance.
  ErrorResponseError({
    required this.code,
    required this.message,
  });

  String code;

  String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorResponseError &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (code.hashCode) + (message.hashCode);

  @override
  String toString() => 'ErrorResponseError[code=$code, message=$message]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'code'] = this.code;
    json[r'message'] = this.message;
    return json;
  }

  /// Returns a new [ErrorResponseError] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ErrorResponseError? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'code'),
            'Required key "ErrorResponseError[code]" is missing from JSON.');
        assert(json[r'code'] != null,
            'Required key "ErrorResponseError[code]" has a null value in JSON.');
        assert(json.containsKey(r'message'),
            'Required key "ErrorResponseError[message]" is missing from JSON.');
        assert(json[r'message'] != null,
            'Required key "ErrorResponseError[message]" has a null value in JSON.');
        return true;
      }());

      return ErrorResponseError(
        code: mapValueOfType<String>(json, r'code')!,
        message: mapValueOfType<String>(json, r'message')!,
      );
    }
    return null;
  }

  static List<ErrorResponseError> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ErrorResponseError>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ErrorResponseError.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ErrorResponseError> mapFromJson(dynamic json) {
    final map = <String, ErrorResponseError>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ErrorResponseError.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ErrorResponseError-objects as value to a dart map
  static Map<String, List<ErrorResponseError>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ErrorResponseError>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ErrorResponseError.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'code',
    'message',
  };
}
