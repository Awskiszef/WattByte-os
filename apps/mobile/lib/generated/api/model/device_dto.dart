//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DeviceDto {
  /// Returns a new [DeviceDto] instance.
  DeviceDto({
    required this.id,
    required this.installationId,
    required this.platform,
    required this.model,
    required this.modelIdentifier,
    required this.designCapacityMah,
    required this.designCapacityWh,
    required this.designCapacitySource,
    required this.estimatedFullChargeCapacityMah,
    required this.estimatedFullChargeCapacityWh,
    required this.fullChargeCapacitySource,
    required this.fullChargeCapacityConfidence,
    required this.createdAt,
    required this.lastSeenAt,
  });

  String id;

  String installationId;

  DeviceDtoPlatformEnum platform;

  String? model;

  String? modelIdentifier;

  num? designCapacityMah;

  num? designCapacityWh;

  DeviceDtoDesignCapacitySourceEnum? designCapacitySource;

  num? estimatedFullChargeCapacityMah;

  num? estimatedFullChargeCapacityWh;

  DeviceDtoFullChargeCapacitySourceEnum? fullChargeCapacitySource;

  DeviceDtoFullChargeCapacityConfidenceEnum? fullChargeCapacityConfidence;

  DateTime createdAt;

  DateTime lastSeenAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceDto &&
          other.id == id &&
          other.installationId == installationId &&
          other.platform == platform &&
          other.model == model &&
          other.modelIdentifier == modelIdentifier &&
          other.designCapacityMah == designCapacityMah &&
          other.designCapacityWh == designCapacityWh &&
          other.designCapacitySource == designCapacitySource &&
          other.estimatedFullChargeCapacityMah ==
              estimatedFullChargeCapacityMah &&
          other.estimatedFullChargeCapacityWh ==
              estimatedFullChargeCapacityWh &&
          other.fullChargeCapacitySource == fullChargeCapacitySource &&
          other.fullChargeCapacityConfidence == fullChargeCapacityConfidence &&
          other.createdAt == createdAt &&
          other.lastSeenAt == lastSeenAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (id.hashCode) +
      (installationId.hashCode) +
      (platform.hashCode) +
      (model == null ? 0 : model!.hashCode) +
      (modelIdentifier == null ? 0 : modelIdentifier!.hashCode) +
      (designCapacityMah == null ? 0 : designCapacityMah!.hashCode) +
      (designCapacityWh == null ? 0 : designCapacityWh!.hashCode) +
      (designCapacitySource == null ? 0 : designCapacitySource!.hashCode) +
      (estimatedFullChargeCapacityMah == null
          ? 0
          : estimatedFullChargeCapacityMah!.hashCode) +
      (estimatedFullChargeCapacityWh == null
          ? 0
          : estimatedFullChargeCapacityWh!.hashCode) +
      (fullChargeCapacitySource == null
          ? 0
          : fullChargeCapacitySource!.hashCode) +
      (fullChargeCapacityConfidence == null
          ? 0
          : fullChargeCapacityConfidence!.hashCode) +
      (createdAt.hashCode) +
      (lastSeenAt.hashCode);

  @override
  String toString() =>
      'DeviceDto[id=$id, installationId=$installationId, platform=$platform, model=$model, modelIdentifier=$modelIdentifier, designCapacityMah=$designCapacityMah, designCapacityWh=$designCapacityWh, designCapacitySource=$designCapacitySource, estimatedFullChargeCapacityMah=$estimatedFullChargeCapacityMah, estimatedFullChargeCapacityWh=$estimatedFullChargeCapacityWh, fullChargeCapacitySource=$fullChargeCapacitySource, fullChargeCapacityConfidence=$fullChargeCapacityConfidence, createdAt=$createdAt, lastSeenAt=$lastSeenAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'id'] = this.id;
    json[r'installationId'] = this.installationId;
    json[r'platform'] = this.platform;
    if (this.model != null) {
      json[r'model'] = this.model;
    } else {
      json[r'model'] = null;
    }
    if (this.modelIdentifier != null) {
      json[r'modelIdentifier'] = this.modelIdentifier;
    } else {
      json[r'modelIdentifier'] = null;
    }
    if (this.designCapacityMah != null) {
      json[r'designCapacityMah'] = this.designCapacityMah;
    } else {
      json[r'designCapacityMah'] = null;
    }
    if (this.designCapacityWh != null) {
      json[r'designCapacityWh'] = this.designCapacityWh;
    } else {
      json[r'designCapacityWh'] = null;
    }
    if (this.designCapacitySource != null) {
      json[r'designCapacitySource'] = this.designCapacitySource;
    } else {
      json[r'designCapacitySource'] = null;
    }
    if (this.estimatedFullChargeCapacityMah != null) {
      json[r'estimatedFullChargeCapacityMah'] =
          this.estimatedFullChargeCapacityMah;
    } else {
      json[r'estimatedFullChargeCapacityMah'] = null;
    }
    if (this.estimatedFullChargeCapacityWh != null) {
      json[r'estimatedFullChargeCapacityWh'] =
          this.estimatedFullChargeCapacityWh;
    } else {
      json[r'estimatedFullChargeCapacityWh'] = null;
    }
    if (this.fullChargeCapacitySource != null) {
      json[r'fullChargeCapacitySource'] = this.fullChargeCapacitySource;
    } else {
      json[r'fullChargeCapacitySource'] = null;
    }
    if (this.fullChargeCapacityConfidence != null) {
      json[r'fullChargeCapacityConfidence'] = this.fullChargeCapacityConfidence;
    } else {
      json[r'fullChargeCapacityConfidence'] = null;
    }
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    json[r'lastSeenAt'] = this.lastSeenAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [DeviceDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'id'),
            'Required key "DeviceDto[id]" is missing from JSON.');
        assert(json[r'id'] != null,
            'Required key "DeviceDto[id]" has a null value in JSON.');
        assert(json.containsKey(r'installationId'),
            'Required key "DeviceDto[installationId]" is missing from JSON.');
        assert(json[r'installationId'] != null,
            'Required key "DeviceDto[installationId]" has a null value in JSON.');
        assert(json.containsKey(r'platform'),
            'Required key "DeviceDto[platform]" is missing from JSON.');
        assert(json[r'platform'] != null,
            'Required key "DeviceDto[platform]" has a null value in JSON.');
        assert(json.containsKey(r'model'),
            'Required key "DeviceDto[model]" is missing from JSON.');
        assert(json.containsKey(r'modelIdentifier'),
            'Required key "DeviceDto[modelIdentifier]" is missing from JSON.');
        assert(json.containsKey(r'designCapacityMah'),
            'Required key "DeviceDto[designCapacityMah]" is missing from JSON.');
        assert(json.containsKey(r'designCapacityWh'),
            'Required key "DeviceDto[designCapacityWh]" is missing from JSON.');
        assert(json.containsKey(r'designCapacitySource'),
            'Required key "DeviceDto[designCapacitySource]" is missing from JSON.');
        assert(json.containsKey(r'estimatedFullChargeCapacityMah'),
            'Required key "DeviceDto[estimatedFullChargeCapacityMah]" is missing from JSON.');
        assert(json.containsKey(r'estimatedFullChargeCapacityWh'),
            'Required key "DeviceDto[estimatedFullChargeCapacityWh]" is missing from JSON.');
        assert(json.containsKey(r'fullChargeCapacitySource'),
            'Required key "DeviceDto[fullChargeCapacitySource]" is missing from JSON.');
        assert(json.containsKey(r'fullChargeCapacityConfidence'),
            'Required key "DeviceDto[fullChargeCapacityConfidence]" is missing from JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "DeviceDto[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "DeviceDto[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'lastSeenAt'),
            'Required key "DeviceDto[lastSeenAt]" is missing from JSON.');
        assert(json[r'lastSeenAt'] != null,
            'Required key "DeviceDto[lastSeenAt]" has a null value in JSON.');
        return true;
      }());

      return DeviceDto(
        id: mapValueOfType<String>(json, r'id')!,
        installationId: mapValueOfType<String>(json, r'installationId')!,
        platform: DeviceDtoPlatformEnum.fromJson(json[r'platform'])!,
        model: mapValueOfType<String>(json, r'model'),
        modelIdentifier: mapValueOfType<String>(json, r'modelIdentifier'),
        designCapacityMah: json[r'designCapacityMah'] == null
            ? null
            : num.parse('${json[r'designCapacityMah']}'),
        designCapacityWh: json[r'designCapacityWh'] == null
            ? null
            : num.parse('${json[r'designCapacityWh']}'),
        designCapacitySource: DeviceDtoDesignCapacitySourceEnum.fromJson(
            json[r'designCapacitySource']),
        estimatedFullChargeCapacityMah:
            json[r'estimatedFullChargeCapacityMah'] == null
                ? null
                : num.parse('${json[r'estimatedFullChargeCapacityMah']}'),
        estimatedFullChargeCapacityWh:
            json[r'estimatedFullChargeCapacityWh'] == null
                ? null
                : num.parse('${json[r'estimatedFullChargeCapacityWh']}'),
        fullChargeCapacitySource:
            DeviceDtoFullChargeCapacitySourceEnum.fromJson(
                json[r'fullChargeCapacitySource']),
        fullChargeCapacityConfidence:
            DeviceDtoFullChargeCapacityConfidenceEnum.fromJson(
                json[r'fullChargeCapacityConfidence']),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        lastSeenAt: mapDateTime(json, r'lastSeenAt', r'')!,
      );
    }
    return null;
  }

  static List<DeviceDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceDto> mapFromJson(dynamic json) {
    final map = <String, DeviceDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceDto-objects as value to a dart map
  static Map<String, List<DeviceDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeviceDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceDto.listFromJson(
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
    'installationId',
    'platform',
    'model',
    'modelIdentifier',
    'designCapacityMah',
    'designCapacityWh',
    'designCapacitySource',
    'estimatedFullChargeCapacityMah',
    'estimatedFullChargeCapacityWh',
    'fullChargeCapacitySource',
    'fullChargeCapacityConfidence',
    'createdAt',
    'lastSeenAt',
  };
}

enum DeviceDtoPlatformEnum {
  android._(r'android'),
  ios._(r'ios'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceDtoPlatformEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceDtoPlatformEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceDtoPlatformEnum? fromJson(dynamic value) =>
      DeviceDtoPlatformEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceDtoPlatformEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceDtoPlatformEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceDtoPlatformEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceDtoPlatformEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceDtoPlatformEnum] to String,
/// and [decode] dynamic data back to [DeviceDtoPlatformEnum].
class DeviceDtoPlatformEnumTypeTransformer {
  factory DeviceDtoPlatformEnumTypeTransformer() =>
      _instance ??= const DeviceDtoPlatformEnumTypeTransformer._();

  const DeviceDtoPlatformEnumTypeTransformer._();

  String encode(DeviceDtoPlatformEnum data) => data._value;

  /// Returns the instance of [DeviceDtoPlatformEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceDtoPlatformEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is DeviceDtoPlatformEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'android':
          return DeviceDtoPlatformEnum.android;
        case r'ios':
          return DeviceDtoPlatformEnum.ios;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceDtoPlatformEnumTypeTransformer? _instance;
}

enum DeviceDtoDesignCapacitySourceEnum {
  manufacturerSpecification._(r'manufacturerSpecification'),
  localDeviceDatabase._(r'localDeviceDatabase'),
  backendDeviceDatabase._(r'backendDeviceDatabase'),
  manual._(r'manual'),
  unknown._(r'unknown'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceDtoDesignCapacitySourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceDtoDesignCapacitySourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceDtoDesignCapacitySourceEnum? fromJson(dynamic value) =>
      DeviceDtoDesignCapacitySourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceDtoDesignCapacitySourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceDtoDesignCapacitySourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceDtoDesignCapacitySourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceDtoDesignCapacitySourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceDtoDesignCapacitySourceEnum] to String,
/// and [decode] dynamic data back to [DeviceDtoDesignCapacitySourceEnum].
class DeviceDtoDesignCapacitySourceEnumTypeTransformer {
  factory DeviceDtoDesignCapacitySourceEnumTypeTransformer() =>
      _instance ??= const DeviceDtoDesignCapacitySourceEnumTypeTransformer._();

  const DeviceDtoDesignCapacitySourceEnumTypeTransformer._();

  String encode(DeviceDtoDesignCapacitySourceEnum data) => data._value;

  /// Returns the instance of [DeviceDtoDesignCapacitySourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceDtoDesignCapacitySourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceDtoDesignCapacitySourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'manufacturerSpecification':
          return DeviceDtoDesignCapacitySourceEnum.manufacturerSpecification;
        case r'localDeviceDatabase':
          return DeviceDtoDesignCapacitySourceEnum.localDeviceDatabase;
        case r'backendDeviceDatabase':
          return DeviceDtoDesignCapacitySourceEnum.backendDeviceDatabase;
        case r'manual':
          return DeviceDtoDesignCapacitySourceEnum.manual;
        case r'unknown':
          return DeviceDtoDesignCapacitySourceEnum.unknown;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceDtoDesignCapacitySourceEnumTypeTransformer? _instance;
}

enum DeviceDtoFullChargeCapacitySourceEnum {
  androidChargeCounter._(r'androidChargeCounter'),
  unknown._(r'unknown'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceDtoFullChargeCapacitySourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceDtoFullChargeCapacitySourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceDtoFullChargeCapacitySourceEnum? fromJson(dynamic value) =>
      DeviceDtoFullChargeCapacitySourceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceDtoFullChargeCapacitySourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceDtoFullChargeCapacitySourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceDtoFullChargeCapacitySourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceDtoFullChargeCapacitySourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceDtoFullChargeCapacitySourceEnum] to String,
/// and [decode] dynamic data back to [DeviceDtoFullChargeCapacitySourceEnum].
class DeviceDtoFullChargeCapacitySourceEnumTypeTransformer {
  factory DeviceDtoFullChargeCapacitySourceEnumTypeTransformer() =>
      _instance ??=
          const DeviceDtoFullChargeCapacitySourceEnumTypeTransformer._();

  const DeviceDtoFullChargeCapacitySourceEnumTypeTransformer._();

  String encode(DeviceDtoFullChargeCapacitySourceEnum data) => data._value;

  /// Returns the instance of [DeviceDtoFullChargeCapacitySourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceDtoFullChargeCapacitySourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceDtoFullChargeCapacitySourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'androidChargeCounter':
          return DeviceDtoFullChargeCapacitySourceEnum.androidChargeCounter;
        case r'unknown':
          return DeviceDtoFullChargeCapacitySourceEnum.unknown;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceDtoFullChargeCapacitySourceEnumTypeTransformer? _instance;
}

enum DeviceDtoFullChargeCapacityConfidenceEnum {
  low._(r'low'),
  medium._(r'medium'),
  high._(r'high'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceDtoFullChargeCapacityConfidenceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceDtoFullChargeCapacityConfidenceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceDtoFullChargeCapacityConfidenceEnum? fromJson(dynamic value) =>
      DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceDtoFullChargeCapacityConfidenceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceDtoFullChargeCapacityConfidenceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceDtoFullChargeCapacityConfidenceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceDtoFullChargeCapacityConfidenceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceDtoFullChargeCapacityConfidenceEnum] to String,
/// and [decode] dynamic data back to [DeviceDtoFullChargeCapacityConfidenceEnum].
class DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer {
  factory DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer() =>
      _instance ??=
          const DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer._();

  const DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer._();

  String encode(DeviceDtoFullChargeCapacityConfidenceEnum data) => data._value;

  /// Returns the instance of [DeviceDtoFullChargeCapacityConfidenceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceDtoFullChargeCapacityConfidenceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceDtoFullChargeCapacityConfidenceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'low':
          return DeviceDtoFullChargeCapacityConfidenceEnum.low;
        case r'medium':
          return DeviceDtoFullChargeCapacityConfidenceEnum.medium;
        case r'high':
          return DeviceDtoFullChargeCapacityConfidenceEnum.high;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceDtoFullChargeCapacityConfidenceEnumTypeTransformer? _instance;
}
