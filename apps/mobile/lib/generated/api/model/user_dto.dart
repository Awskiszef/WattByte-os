//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UserDto {
  /// Returns a new [UserDto] instance.
  UserDto({
    required this.id,
    required this.email,
    required this.displayName,
    required this.plan,
    required this.createdAt,
  });

  String id;

  String email;

  String? displayName;

  UserDtoPlanEnum plan;

  DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserDto &&
          other.id == id &&
          other.email == email &&
          other.displayName == displayName &&
          other.plan == plan &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (email.hashCode) +
      (displayName == null ? 0 : displayName!.hashCode) +
      (plan.hashCode) +
      (createdAt.hashCode);

  @override
  String toString() =>
      'UserDto[id=$id, email=$email, displayName=$displayName, plan=$plan, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'email'] = this.email;
    if (this.displayName != null) {
      json[r'displayName'] = this.displayName;
    } else {
      json[r'displayName'] = null;
    }
    json[r'plan'] = this.plan;
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [UserDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UserDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "UserDto[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "UserDto[id]" has a null value in JSON.');
        assert(json.containsKey(r'email'),
            'Required key "UserDto[email]" is missing from JSON.');
        assert(json[r'email'] != null,
            'Required key "UserDto[email]" has a null value in JSON.');
        assert(json.containsKey(r'displayName'),
            'Required key "UserDto[displayName]" is missing from JSON.');
        assert(json.containsKey(r'plan'),
            'Required key "UserDto[plan]" is missing from JSON.');
        assert(json[r'plan'] != null,
            'Required key "UserDto[plan]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "UserDto[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "UserDto[createdAt]" has a null value in JSON.');
        return true;
      }());

      return UserDto(
        id: mapValueOfType<String>(json, r'id')!,
        email: mapValueOfType<String>(json, r'email')!,
        displayName: mapValueOfType<String>(json, r'displayName'),
        plan: UserDtoPlanEnum.fromJson(json[r'plan'])!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<UserDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UserDto> mapFromJson(dynamic json) {
    final map = <String, UserDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UserDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UserDto-objects as value to a dart map
  static Map<String, List<UserDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UserDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UserDto.listFromJson(
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
    'email',
    'displayName',
    'plan',
    'createdAt',
  };
}

enum UserDtoPlanEnum {
  free._(r'free'),
  premium._(r'premium'),
  ;

  /// Instantiate a new enum with the provided value.
  const UserDtoPlanEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [UserDtoPlanEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static UserDtoPlanEnum? fromJson(dynamic value) =>
      UserDtoPlanEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [UserDtoPlanEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<UserDtoPlanEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UserDtoPlanEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UserDtoPlanEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UserDtoPlanEnum] to String,
/// and [decode] dynamic data back to [UserDtoPlanEnum].
class UserDtoPlanEnumTypeTransformer {
  factory UserDtoPlanEnumTypeTransformer() =>
      _instance ??= const UserDtoPlanEnumTypeTransformer._();

  const UserDtoPlanEnumTypeTransformer._();

  String encode(UserDtoPlanEnum data) => data._value;

  /// Returns the instance of [UserDtoPlanEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UserDtoPlanEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is UserDtoPlanEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'free':
          return UserDtoPlanEnum.free;
        case r'premium':
          return UserDtoPlanEnum.premium;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static UserDtoPlanEnumTypeTransformer? _instance;
}
