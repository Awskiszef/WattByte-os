//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DeviceRegisterRequest {
  /// Returns a new [DeviceRegisterRequest] instance.
  DeviceRegisterRequest({
    required this.installationId,
    required this.platform,
    this.model,
    this.modelIdentifier,
    this.designCapacityMah,
    this.designCapacityWh,
    this.designCapacitySource,
    this.estimatedFullChargeCapacityMah,
    this.estimatedFullChargeCapacityWh,
    this.fullChargeCapacitySource,
    this.fullChargeCapacityConfidence,
  });

  String installationId;

  DeviceRegisterRequestPlatformEnum platform;

  String? model;

  String? modelIdentifier;

  /// Minimum value: 0.1
  /// Maximum value: 30000
  num? designCapacityMah;

  /// Minimum value: 0.001
  /// Maximum value: 200
  num? designCapacityWh;

  DeviceRegisterRequestDesignCapacitySourceEnum? designCapacitySource;

  /// Minimum value: 0.1
  /// Maximum value: 30000
  num? estimatedFullChargeCapacityMah;

  /// Minimum value: 0.001
  /// Maximum value: 200
  num? estimatedFullChargeCapacityWh;

  DeviceRegisterRequestFullChargeCapacitySourceEnum? fullChargeCapacitySource;

  DeviceRegisterRequestFullChargeCapacityConfidenceEnum?
      fullChargeCapacityConfidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceRegisterRequest &&
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
          other.fullChargeCapacityConfidence == fullChargeCapacityConfidence;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
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
          : fullChargeCapacityConfidence!.hashCode);

  @override
  String toString() =>
      'DeviceRegisterRequest[installationId=$installationId, platform=$platform, model=$model, modelIdentifier=$modelIdentifier, designCapacityMah=$designCapacityMah, designCapacityWh=$designCapacityWh, designCapacitySource=$designCapacitySource, estimatedFullChargeCapacityMah=$estimatedFullChargeCapacityMah, estimatedFullChargeCapacityWh=$estimatedFullChargeCapacityWh, fullChargeCapacitySource=$fullChargeCapacitySource, fullChargeCapacityConfidence=$fullChargeCapacityConfidence]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
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
    return json;
  }

  /// Returns a new [DeviceRegisterRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceRegisterRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'installationId'),
            'Required key "DeviceRegisterRequest[installationId]" is missing from JSON.');
        assert(json[r'installationId'] != null,
            'Required key "DeviceRegisterRequest[installationId]" has a null value in JSON.');
        assert(json.containsKey(r'platform'),
            'Required key "DeviceRegisterRequest[platform]" is missing from JSON.');
        assert(json[r'platform'] != null,
            'Required key "DeviceRegisterRequest[platform]" has a null value in JSON.');
        return true;
      }());

      return DeviceRegisterRequest(
        installationId: mapValueOfType<String>(json, r'installationId')!,
        platform:
            DeviceRegisterRequestPlatformEnum.fromJson(json[r'platform'])!,
        model: mapValueOfType<String>(json, r'model'),
        modelIdentifier: mapValueOfType<String>(json, r'modelIdentifier'),
        designCapacityMah: json[r'designCapacityMah'] == null
            ? null
            : num.parse('${json[r'designCapacityMah']}'),
        designCapacityWh: json[r'designCapacityWh'] == null
            ? null
            : num.parse('${json[r'designCapacityWh']}'),
        designCapacitySource:
            DeviceRegisterRequestDesignCapacitySourceEnum.fromJson(
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
            DeviceRegisterRequestFullChargeCapacitySourceEnum.fromJson(
                json[r'fullChargeCapacitySource']),
        fullChargeCapacityConfidence:
            DeviceRegisterRequestFullChargeCapacityConfidenceEnum.fromJson(
                json[r'fullChargeCapacityConfidence']),
      );
    }
    return null;
  }

  static List<DeviceRegisterRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceRegisterRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceRegisterRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceRegisterRequest> mapFromJson(dynamic json) {
    final map = <String, DeviceRegisterRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceRegisterRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceRegisterRequest-objects as value to a dart map
  static Map<String, List<DeviceRegisterRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeviceRegisterRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceRegisterRequest.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'installationId',
    'platform',
  };
}

enum DeviceRegisterRequestPlatformEnum {
  android._(r'android'),
  ios._(r'ios'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceRegisterRequestPlatformEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceRegisterRequestPlatformEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceRegisterRequestPlatformEnum? fromJson(dynamic value) =>
      DeviceRegisterRequestPlatformEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [DeviceRegisterRequestPlatformEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceRegisterRequestPlatformEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceRegisterRequestPlatformEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceRegisterRequestPlatformEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceRegisterRequestPlatformEnum] to String,
/// and [decode] dynamic data back to [DeviceRegisterRequestPlatformEnum].
class DeviceRegisterRequestPlatformEnumTypeTransformer {
  factory DeviceRegisterRequestPlatformEnumTypeTransformer() =>
      _instance ??= const DeviceRegisterRequestPlatformEnumTypeTransformer._();

  const DeviceRegisterRequestPlatformEnumTypeTransformer._();

  String encode(DeviceRegisterRequestPlatformEnum data) => data._value;

  /// Returns the instance of [DeviceRegisterRequestPlatformEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceRegisterRequestPlatformEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceRegisterRequestPlatformEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'android':
          return DeviceRegisterRequestPlatformEnum.android;
        case r'ios':
          return DeviceRegisterRequestPlatformEnum.ios;
        case r'unknown_default_open_api':
          return DeviceRegisterRequestPlatformEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return DeviceRegisterRequestPlatformEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceRegisterRequestPlatformEnumTypeTransformer? _instance;
}

enum DeviceRegisterRequestDesignCapacitySourceEnum {
  manufacturerSpecification._(r'manufacturerSpecification'),
  localDeviceDatabase._(r'localDeviceDatabase'),
  backendDeviceDatabase._(r'backendDeviceDatabase'),
  manual._(r'manual'),
  unknown._(r'unknown'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceRegisterRequestDesignCapacitySourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceRegisterRequestDesignCapacitySourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceRegisterRequestDesignCapacitySourceEnum? fromJson(
          dynamic value) =>
      DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [DeviceRegisterRequestDesignCapacitySourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceRegisterRequestDesignCapacitySourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceRegisterRequestDesignCapacitySourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            DeviceRegisterRequestDesignCapacitySourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceRegisterRequestDesignCapacitySourceEnum] to String,
/// and [decode] dynamic data back to [DeviceRegisterRequestDesignCapacitySourceEnum].
class DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer {
  factory DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer() =>
      _instance ??=
          const DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer
              ._();

  const DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer._();

  String encode(DeviceRegisterRequestDesignCapacitySourceEnum data) =>
      data._value;

  /// Returns the instance of [DeviceRegisterRequestDesignCapacitySourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceRegisterRequestDesignCapacitySourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceRegisterRequestDesignCapacitySourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'manufacturerSpecification':
          return DeviceRegisterRequestDesignCapacitySourceEnum
              .manufacturerSpecification;
        case r'localDeviceDatabase':
          return DeviceRegisterRequestDesignCapacitySourceEnum
              .localDeviceDatabase;
        case r'backendDeviceDatabase':
          return DeviceRegisterRequestDesignCapacitySourceEnum
              .backendDeviceDatabase;
        case r'manual':
          return DeviceRegisterRequestDesignCapacitySourceEnum.manual;
        case r'unknown':
          return DeviceRegisterRequestDesignCapacitySourceEnum.unknown;
        case r'unknown_default_open_api':
          return DeviceRegisterRequestDesignCapacitySourceEnum
              .unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return DeviceRegisterRequestDesignCapacitySourceEnum
              .unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceRegisterRequestDesignCapacitySourceEnumTypeTransformer?
      _instance;
}

enum DeviceRegisterRequestFullChargeCapacitySourceEnum {
  androidChargeCounter._(r'androidChargeCounter'),
  unknown._(r'unknown'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceRegisterRequestFullChargeCapacitySourceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceRegisterRequestFullChargeCapacitySourceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceRegisterRequestFullChargeCapacitySourceEnum? fromJson(
          dynamic value) =>
      DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [DeviceRegisterRequestFullChargeCapacitySourceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceRegisterRequestFullChargeCapacitySourceEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceRegisterRequestFullChargeCapacitySourceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            DeviceRegisterRequestFullChargeCapacitySourceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceRegisterRequestFullChargeCapacitySourceEnum] to String,
/// and [decode] dynamic data back to [DeviceRegisterRequestFullChargeCapacitySourceEnum].
class DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer {
  factory DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer() =>
      _instance ??=
          const DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer
              ._();

  const DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer._();

  String encode(DeviceRegisterRequestFullChargeCapacitySourceEnum data) =>
      data._value;

  /// Returns the instance of [DeviceRegisterRequestFullChargeCapacitySourceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceRegisterRequestFullChargeCapacitySourceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceRegisterRequestFullChargeCapacitySourceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'androidChargeCounter':
          return DeviceRegisterRequestFullChargeCapacitySourceEnum
              .androidChargeCounter;
        case r'unknown':
          return DeviceRegisterRequestFullChargeCapacitySourceEnum.unknown;
        case r'unknown_default_open_api':
          return DeviceRegisterRequestFullChargeCapacitySourceEnum
              .unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return DeviceRegisterRequestFullChargeCapacitySourceEnum
              .unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceRegisterRequestFullChargeCapacitySourceEnumTypeTransformer?
      _instance;
}

enum DeviceRegisterRequestFullChargeCapacityConfidenceEnum {
  low._(r'low'),
  medium._(r'medium'),
  high._(r'high'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const DeviceRegisterRequestFullChargeCapacityConfidenceEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [DeviceRegisterRequestFullChargeCapacityConfidenceEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static DeviceRegisterRequestFullChargeCapacityConfidenceEnum? fromJson(
          dynamic value) =>
      DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer()
          .decode(value);

  /// Returns a [List] containing instances of [DeviceRegisterRequestFullChargeCapacityConfidenceEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<DeviceRegisterRequestFullChargeCapacityConfidenceEnum>
      listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceRegisterRequestFullChargeCapacityConfidenceEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value =
            DeviceRegisterRequestFullChargeCapacityConfidenceEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [DeviceRegisterRequestFullChargeCapacityConfidenceEnum] to String,
/// and [decode] dynamic data back to [DeviceRegisterRequestFullChargeCapacityConfidenceEnum].
class DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer {
  factory DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer() =>
      _instance ??=
          const DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer
              ._();

  const DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer._();

  String encode(DeviceRegisterRequestFullChargeCapacityConfidenceEnum data) =>
      data._value;

  /// Returns the instance of [DeviceRegisterRequestFullChargeCapacityConfidenceEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  DeviceRegisterRequestFullChargeCapacityConfidenceEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is DeviceRegisterRequestFullChargeCapacityConfidenceEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'low':
          return DeviceRegisterRequestFullChargeCapacityConfidenceEnum.low;
        case r'medium':
          return DeviceRegisterRequestFullChargeCapacityConfidenceEnum.medium;
        case r'high':
          return DeviceRegisterRequestFullChargeCapacityConfidenceEnum.high;
        case r'unknown_default_open_api':
          return DeviceRegisterRequestFullChargeCapacityConfidenceEnum
              .unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return DeviceRegisterRequestFullChargeCapacityConfidenceEnum
              .unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static DeviceRegisterRequestFullChargeCapacityConfidenceEnumTypeTransformer?
      _instance;
}
