//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class SessionDto {
  /// Returns a new [SessionDto] instance.
  SessionDto({
    required this.id,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.current,
  });

  String id;

  DateTime createdAt;

  DateTime lastUsedAt;

  DateTime expiresAt;

  bool current;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionDto &&
          other.id == id &&
          other.createdAt == createdAt &&
          other.lastUsedAt == lastUsedAt &&
          other.expiresAt == expiresAt &&
          other.current == current;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (createdAt.hashCode) +
      (lastUsedAt.hashCode) +
      (expiresAt.hashCode) +
      (current.hashCode);

  @override
  String toString() =>
      'SessionDto[id=$id, createdAt=$createdAt, lastUsedAt=$lastUsedAt, expiresAt=$expiresAt, current=$current]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    json[r'lastUsedAt'] = this.lastUsedAt.toUtc().toIso8601String();
    json[r'expiresAt'] = this.expiresAt.toUtc().toIso8601String();
    json[r'current'] = this.current;
    return json;
  }

  /// Returns a new [SessionDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static SessionDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "SessionDto[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "SessionDto[id]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "SessionDto[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "SessionDto[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'lastUsedAt'),
            'Required key "SessionDto[lastUsedAt]" is missing from JSON.');
        assert(json[r'lastUsedAt'] != null,
            'Required key "SessionDto[lastUsedAt]" has a null value in JSON.');
        assert(json.containsKey(r'expiresAt'),
            'Required key "SessionDto[expiresAt]" is missing from JSON.');
        assert(json[r'expiresAt'] != null,
            'Required key "SessionDto[expiresAt]" has a null value in JSON.');
        assert(json.containsKey(r'current'),
            'Required key "SessionDto[current]" is missing from JSON.');
        assert(json[r'current'] != null,
            'Required key "SessionDto[current]" has a null value in JSON.');
        return true;
      }());

      return SessionDto(
        id: mapValueOfType<String>(json, r'id')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        lastUsedAt: mapDateTime(json, r'lastUsedAt', r'')!,
        expiresAt: mapDateTime(json, r'expiresAt', r'')!,
        current: mapValueOfType<bool>(json, r'current')!,
      );
    }
    return null;
  }

  static List<SessionDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <SessionDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = SessionDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, SessionDto> mapFromJson(dynamic json) {
    final map = <String, SessionDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = SessionDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of SessionDto-objects as value to a dart map
  static Map<String, List<SessionDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<SessionDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = SessionDto.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'id',
    'createdAt',
    'lastUsedAt',
    'expiresAt',
    'current',
  };
}
