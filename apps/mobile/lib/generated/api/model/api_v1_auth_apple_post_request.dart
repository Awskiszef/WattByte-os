//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class ApiV1AuthApplePostRequest {
  /// Returns a new [ApiV1AuthApplePostRequest] instance.
  ApiV1AuthApplePostRequest({
    required this.idToken,
  });

  String idToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApiV1AuthApplePostRequest && other.idToken == idToken;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (idToken.hashCode);

  @override
  String toString() => 'ApiV1AuthApplePostRequest[idToken=$idToken]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'idToken'] = this.idToken;
    return json;
  }

  /// Returns a new [ApiV1AuthApplePostRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ApiV1AuthApplePostRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'idToken'),
            'Required key "ApiV1AuthApplePostRequest[idToken]" is missing from JSON.');
        assert(json[r'idToken'] != null,
            'Required key "ApiV1AuthApplePostRequest[idToken]" has a null value in JSON.');
        return true;
      }());

      return ApiV1AuthApplePostRequest(
        idToken: mapValueOfType<String>(json, r'idToken')!,
      );
    }
    return null;
  }

  static List<ApiV1AuthApplePostRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ApiV1AuthApplePostRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ApiV1AuthApplePostRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ApiV1AuthApplePostRequest> mapFromJson(dynamic json) {
    final map = <String, ApiV1AuthApplePostRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ApiV1AuthApplePostRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ApiV1AuthApplePostRequest-objects as value to a dart map
  static Map<String, List<ApiV1AuthApplePostRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ApiV1AuthApplePostRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ApiV1AuthApplePostRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'idToken',
  };
}
