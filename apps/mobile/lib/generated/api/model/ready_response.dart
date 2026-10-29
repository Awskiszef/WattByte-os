//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class ReadyResponse {
  /// Returns a new [ReadyResponse] instance.
  ReadyResponse({
    required this.status,
    required this.database,
    this.schema,
    this.aiProviders = const [],
  });

  ReadyResponseStatusEnum status;

  ReadyResponseDatabaseEnum database;

  ReadyResponseSchemaEnum? schema;

  List<String> aiProviders;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadyResponse &&
          other.status == status &&
          other.database == database &&
          other.schema == schema &&
          _deepEquality.equals(other.aiProviders, aiProviders);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (status.hashCode) +
      (database.hashCode) +
      (schema == null ? 0 : schema!.hashCode) +
      (aiProviders.hashCode);

  @override
  String toString() =>
      'ReadyResponse[status=$status, database=$database, schema=$schema, aiProviders=$aiProviders]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'status'] = this.status;
    json[r'database'] = this.database;
    if (this.schema != null) {
      json[r'schema'] = this.schema;
    } else {
      json[r'schema'] = null;
    }
    json[r'aiProviders'] = this.aiProviders;
    return json;
  }

  /// Returns a new [ReadyResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ReadyResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'status'),
            'Required key "ReadyResponse[status]" is missing from JSON.');
        assert(json[r'status'] != null,
            'Required key "ReadyResponse[status]" has a null value in JSON.');
        assert(json.containsKey(r'database'),
            'Required key "ReadyResponse[database]" is missing from JSON.');
        assert(json[r'database'] != null,
            'Required key "ReadyResponse[database]" has a null value in JSON.');
        assert(json.containsKey(r'aiProviders'),
            'Required key "ReadyResponse[aiProviders]" is missing from JSON.');
        assert(json[r'aiProviders'] != null,
            'Required key "ReadyResponse[aiProviders]" has a null value in JSON.');
        return true;
      }());

      return ReadyResponse(
        status: ReadyResponseStatusEnum.fromJson(json[r'status'])!,
        database: ReadyResponseDatabaseEnum.fromJson(json[r'database'])!,
        schema: ReadyResponseSchemaEnum.fromJson(json[r'schema']),
        aiProviders: json[r'aiProviders'] is Iterable
            ? (json[r'aiProviders'] as Iterable)
                .cast<String>()
                .toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<ReadyResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ReadyResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadyResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ReadyResponse> mapFromJson(dynamic json) {
    final map = <String, ReadyResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ReadyResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ReadyResponse-objects as value to a dart map
  static Map<String, List<ReadyResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<ReadyResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ReadyResponse.listFromJson(
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
    'database',
    'aiProviders',
  };
}

enum ReadyResponseStatusEnum {
  ok._(r'ok'),
  degraded._(r'degraded'),
  ;

  /// Instantiate a new enum with the provided value.
  const ReadyResponseStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ReadyResponseStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ReadyResponseStatusEnum? fromJson(dynamic value) =>
      ReadyResponseStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ReadyResponseStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ReadyResponseStatusEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ReadyResponseStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadyResponseStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ReadyResponseStatusEnum] to String,
/// and [decode] dynamic data back to [ReadyResponseStatusEnum].
class ReadyResponseStatusEnumTypeTransformer {
  factory ReadyResponseStatusEnumTypeTransformer() =>
      _instance ??= const ReadyResponseStatusEnumTypeTransformer._();

  const ReadyResponseStatusEnumTypeTransformer._();

  String encode(ReadyResponseStatusEnum data) => data._value;

  /// Returns the instance of [ReadyResponseStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ReadyResponseStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ReadyResponseStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok':
          return ReadyResponseStatusEnum.ok;
        case r'degraded':
          return ReadyResponseStatusEnum.degraded;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ReadyResponseStatusEnumTypeTransformer? _instance;
}

enum ReadyResponseDatabaseEnum {
  ok._(r'ok'),
  unavailable._(r'unavailable'),
  ;

  /// Instantiate a new enum with the provided value.
  const ReadyResponseDatabaseEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ReadyResponseDatabaseEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ReadyResponseDatabaseEnum? fromJson(dynamic value) =>
      ReadyResponseDatabaseEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ReadyResponseDatabaseEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ReadyResponseDatabaseEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ReadyResponseDatabaseEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadyResponseDatabaseEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ReadyResponseDatabaseEnum] to String,
/// and [decode] dynamic data back to [ReadyResponseDatabaseEnum].
class ReadyResponseDatabaseEnumTypeTransformer {
  factory ReadyResponseDatabaseEnumTypeTransformer() =>
      _instance ??= const ReadyResponseDatabaseEnumTypeTransformer._();

  const ReadyResponseDatabaseEnumTypeTransformer._();

  String encode(ReadyResponseDatabaseEnum data) => data._value;

  /// Returns the instance of [ReadyResponseDatabaseEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ReadyResponseDatabaseEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ReadyResponseDatabaseEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok':
          return ReadyResponseDatabaseEnum.ok;
        case r'unavailable':
          return ReadyResponseDatabaseEnum.unavailable;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ReadyResponseDatabaseEnumTypeTransformer? _instance;
}

enum ReadyResponseSchemaEnum {
  ok._(r'ok'),
  behind._(r'behind'),
  ahead._(r'ahead'),
  unchecked._(r'unchecked'),
  ;

  /// Instantiate a new enum with the provided value.
  const ReadyResponseSchemaEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [ReadyResponseSchemaEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static ReadyResponseSchemaEnum? fromJson(dynamic value) =>
      ReadyResponseSchemaEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [ReadyResponseSchemaEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<ReadyResponseSchemaEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <ReadyResponseSchemaEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ReadyResponseSchemaEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ReadyResponseSchemaEnum] to String,
/// and [decode] dynamic data back to [ReadyResponseSchemaEnum].
class ReadyResponseSchemaEnumTypeTransformer {
  factory ReadyResponseSchemaEnumTypeTransformer() =>
      _instance ??= const ReadyResponseSchemaEnumTypeTransformer._();

  const ReadyResponseSchemaEnumTypeTransformer._();

  String encode(ReadyResponseSchemaEnum data) => data._value;

  /// Returns the instance of [ReadyResponseSchemaEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ReadyResponseSchemaEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is ReadyResponseSchemaEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'ok':
          return ReadyResponseSchemaEnum.ok;
        case r'behind':
          return ReadyResponseSchemaEnum.behind;
        case r'ahead':
          return ReadyResponseSchemaEnum.ahead;
        case r'unchecked':
          return ReadyResponseSchemaEnum.unchecked;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static ReadyResponseSchemaEnumTypeTransformer? _instance;
}
