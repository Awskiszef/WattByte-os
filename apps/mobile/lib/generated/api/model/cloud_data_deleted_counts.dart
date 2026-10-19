//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudDataDeletedCounts {
  /// Returns a new [CloudDataDeletedCounts] instance.
  CloudDataDeletedCounts({
    required this.dailyUsage,
    required this.chargingSummaries,
    required this.monthlySummaries,
    required this.aiGenerations,
    required this.devices,
  });

  /// Minimum value: 0
  int dailyUsage;

  /// Minimum value: 0
  int chargingSummaries;

  /// Minimum value: 0
  int monthlySummaries;

  /// Minimum value: 0
  int aiGenerations;

  /// Minimum value: 0
  int devices;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudDataDeletedCounts &&
          other.dailyUsage == dailyUsage &&
          other.chargingSummaries == chargingSummaries &&
          other.monthlySummaries == monthlySummaries &&
          other.aiGenerations == aiGenerations &&
          other.devices == devices;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (dailyUsage.hashCode) +
      (chargingSummaries.hashCode) +
      (monthlySummaries.hashCode) +
      (aiGenerations.hashCode) +
      (devices.hashCode);

  @override
  String toString() =>
      'CloudDataDeletedCounts[dailyUsage=$dailyUsage, chargingSummaries=$chargingSummaries, monthlySummaries=$monthlySummaries, aiGenerations=$aiGenerations, devices=$devices]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'dailyUsage'] = this.dailyUsage;
    json[r'chargingSummaries'] = this.chargingSummaries;
    json[r'monthlySummaries'] = this.monthlySummaries;
    json[r'aiGenerations'] = this.aiGenerations;
    json[r'devices'] = this.devices;
    return json;
  }

  /// Returns a new [CloudDataDeletedCounts] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudDataDeletedCounts? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'dailyUsage'),
            'Required key "CloudDataDeletedCounts[dailyUsage]" is missing from JSON.');
        assert(json[r'dailyUsage'] != null,
            'Required key "CloudDataDeletedCounts[dailyUsage]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSummaries'),
            'Required key "CloudDataDeletedCounts[chargingSummaries]" is missing from JSON.');
        assert(json[r'chargingSummaries'] != null,
            'Required key "CloudDataDeletedCounts[chargingSummaries]" has a null value in JSON.');
        assert(json.containsKey(r'monthlySummaries'),
            'Required key "CloudDataDeletedCounts[monthlySummaries]" is missing from JSON.');
        assert(json[r'monthlySummaries'] != null,
            'Required key "CloudDataDeletedCounts[monthlySummaries]" has a null value in JSON.');
        assert(json.containsKey(r'aiGenerations'),
            'Required key "CloudDataDeletedCounts[aiGenerations]" is missing from JSON.');
        assert(json[r'aiGenerations'] != null,
            'Required key "CloudDataDeletedCounts[aiGenerations]" has a null value in JSON.');
        assert(json.containsKey(r'devices'),
            'Required key "CloudDataDeletedCounts[devices]" is missing from JSON.');
        assert(json[r'devices'] != null,
            'Required key "CloudDataDeletedCounts[devices]" has a null value in JSON.');
        return true;
      }());

      return CloudDataDeletedCounts(
        dailyUsage: mapValueOfType<int>(json, r'dailyUsage')!,
        chargingSummaries: mapValueOfType<int>(json, r'chargingSummaries')!,
        monthlySummaries: mapValueOfType<int>(json, r'monthlySummaries')!,
        aiGenerations: mapValueOfType<int>(json, r'aiGenerations')!,
        devices: mapValueOfType<int>(json, r'devices')!,
      );
    }
    return null;
  }

  static List<CloudDataDeletedCounts> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudDataDeletedCounts>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudDataDeletedCounts.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudDataDeletedCounts> mapFromJson(dynamic json) {
    final map = <String, CloudDataDeletedCounts>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudDataDeletedCounts.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudDataDeletedCounts-objects as value to a dart map
  static Map<String, List<CloudDataDeletedCounts>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudDataDeletedCounts>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudDataDeletedCounts.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'dailyUsage',
    'chargingSummaries',
    'monthlySummaries',
    'aiGenerations',
    'devices',
  };
}
