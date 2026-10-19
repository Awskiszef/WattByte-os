//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DeviceSpecificationDto {
  /// Returns a new [DeviceSpecificationDto] instance.
  DeviceSpecificationDto({
    required this.manufacturer,
    required this.model,
    required this.modelIdentifier,
    required this.designCapacityMah,
    required this.designCapacityWh,
    required this.nominalVoltage,
    required this.catalogVersion,
  });

  String manufacturer;

  String model;

  String modelIdentifier;

  num designCapacityMah;

  num? designCapacityWh;

  num? nominalVoltage;

  String catalogVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceSpecificationDto &&
          other.manufacturer == manufacturer &&
          other.model == model &&
          other.modelIdentifier == modelIdentifier &&
          other.designCapacityMah == designCapacityMah &&
          other.designCapacityWh == designCapacityWh &&
          other.nominalVoltage == nominalVoltage &&
          other.catalogVersion == catalogVersion;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (manufacturer.hashCode) +
      (model.hashCode) +
      (modelIdentifier.hashCode) +
      (designCapacityMah.hashCode) +
      (designCapacityWh == null ? 0 : designCapacityWh!.hashCode) +
      (nominalVoltage == null ? 0 : nominalVoltage!.hashCode) +
      (catalogVersion.hashCode);

  @override
  String toString() =>
      'DeviceSpecificationDto[manufacturer=$manufacturer, model=$model, modelIdentifier=$modelIdentifier, designCapacityMah=$designCapacityMah, designCapacityWh=$designCapacityWh, nominalVoltage=$nominalVoltage, catalogVersion=$catalogVersion]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'manufacturer'] = this.manufacturer;
    json[r'model'] = this.model;
    json[r'modelIdentifier'] = this.modelIdentifier;
    json[r'designCapacityMah'] = this.designCapacityMah;
    if (this.designCapacityWh != null) {
      json[r'designCapacityWh'] = this.designCapacityWh;
    } else {
      json[r'designCapacityWh'] = null;
    }
    if (this.nominalVoltage != null) {
      json[r'nominalVoltage'] = this.nominalVoltage;
    } else {
      json[r'nominalVoltage'] = null;
    }
    json[r'catalogVersion'] = this.catalogVersion;
    return json;
  }

  /// Returns a new [DeviceSpecificationDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceSpecificationDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'manufacturer'),
            'Required key "DeviceSpecificationDto[manufacturer]" is missing from JSON.');
        assert(json[r'manufacturer'] != null,
            'Required key "DeviceSpecificationDto[manufacturer]" has a null value in JSON.');
        assert(json.containsKey(r'model'),
            'Required key "DeviceSpecificationDto[model]" is missing from JSON.');
        assert(json[r'model'] != null,
            'Required key "DeviceSpecificationDto[model]" has a null value in JSON.');
        assert(json.containsKey(r'modelIdentifier'),
            'Required key "DeviceSpecificationDto[modelIdentifier]" is missing from JSON.');
        assert(json[r'modelIdentifier'] != null,
            'Required key "DeviceSpecificationDto[modelIdentifier]" has a null value in JSON.');
        assert(json.containsKey(r'designCapacityMah'),
            'Required key "DeviceSpecificationDto[designCapacityMah]" is missing from JSON.');
        assert(json[r'designCapacityMah'] != null,
            'Required key "DeviceSpecificationDto[designCapacityMah]" has a null value in JSON.');
        assert(json.containsKey(r'designCapacityWh'),
            'Required key "DeviceSpecificationDto[designCapacityWh]" is missing from JSON.');
        assert(json.containsKey(r'nominalVoltage'),
            'Required key "DeviceSpecificationDto[nominalVoltage]" is missing from JSON.');
        assert(json.containsKey(r'catalogVersion'),
            'Required key "DeviceSpecificationDto[catalogVersion]" is missing from JSON.');
        assert(json[r'catalogVersion'] != null,
            'Required key "DeviceSpecificationDto[catalogVersion]" has a null value in JSON.');
        return true;
      }());

      return DeviceSpecificationDto(
        manufacturer: mapValueOfType<String>(json, r'manufacturer')!,
        model: mapValueOfType<String>(json, r'model')!,
        modelIdentifier: mapValueOfType<String>(json, r'modelIdentifier')!,
        designCapacityMah: num.parse('${json[r'designCapacityMah']}'),
        designCapacityWh: json[r'designCapacityWh'] == null
            ? null
            : num.parse('${json[r'designCapacityWh']}'),
        nominalVoltage: json[r'nominalVoltage'] == null
            ? null
            : num.parse('${json[r'nominalVoltage']}'),
        catalogVersion: mapValueOfType<String>(json, r'catalogVersion')!,
      );
    }
    return null;
  }

  static List<DeviceSpecificationDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceSpecificationDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceSpecificationDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceSpecificationDto> mapFromJson(dynamic json) {
    final map = <String, DeviceSpecificationDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceSpecificationDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceSpecificationDto-objects as value to a dart map
  static Map<String, List<DeviceSpecificationDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeviceSpecificationDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceSpecificationDto.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'manufacturer',
    'model',
    'modelIdentifier',
    'designCapacityMah',
    'designCapacityWh',
    'nominalVoltage',
    'catalogVersion',
  };
}
