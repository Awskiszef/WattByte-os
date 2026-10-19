//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DeviceListResponse {
  /// Returns a new [DeviceListResponse] instance.
  DeviceListResponse({
    this.devices = const [],
  });

  List<DeviceDto> devices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceListResponse &&
          _deepEquality.equals(other.devices, devices);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (devices.hashCode);

  @override
  String toString() => 'DeviceListResponse[devices=$devices]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'devices'] = this.devices;
    return json;
  }

  /// Returns a new [DeviceListResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DeviceListResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'devices'),
            'Required key "DeviceListResponse[devices]" is missing from JSON.');
        assert(json[r'devices'] != null,
            'Required key "DeviceListResponse[devices]" has a null value in JSON.');
        return true;
      }());

      return DeviceListResponse(
        devices: DeviceDto.listFromJson(json[r'devices']),
      );
    }
    return null;
  }

  static List<DeviceListResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DeviceListResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DeviceListResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DeviceListResponse> mapFromJson(dynamic json) {
    final map = <String, DeviceListResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DeviceListResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DeviceListResponse-objects as value to a dart map
  static Map<String, List<DeviceListResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DeviceListResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DeviceListResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'devices',
  };
}
