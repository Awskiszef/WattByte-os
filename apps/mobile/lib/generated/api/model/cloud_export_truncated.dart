//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportTruncated {
  /// Returns a new [CloudExportTruncated] instance.
  CloudExportTruncated({
    required this.devices,
    required this.dailyUsage,
    required this.chargingSummaries,
    required this.monthlySummaries,
    required this.aiGenerations,
    required this.subscriptions,
  });

  bool devices;

  bool dailyUsage;

  bool chargingSummaries;

  bool monthlySummaries;

  bool aiGenerations;

  bool subscriptions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportTruncated &&
          other.devices == devices &&
          other.dailyUsage == dailyUsage &&
          other.chargingSummaries == chargingSummaries &&
          other.monthlySummaries == monthlySummaries &&
          other.aiGenerations == aiGenerations &&
          other.subscriptions == subscriptions;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (devices.hashCode) +
      (dailyUsage.hashCode) +
      (chargingSummaries.hashCode) +
      (monthlySummaries.hashCode) +
      (aiGenerations.hashCode) +
      (subscriptions.hashCode);

  @override
  String toString() =>
      'CloudExportTruncated[devices=$devices, dailyUsage=$dailyUsage, chargingSummaries=$chargingSummaries, monthlySummaries=$monthlySummaries, aiGenerations=$aiGenerations, subscriptions=$subscriptions]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'devices'] = this.devices;
    json[r'dailyUsage'] = this.dailyUsage;
    json[r'chargingSummaries'] = this.chargingSummaries;
    json[r'monthlySummaries'] = this.monthlySummaries;
    json[r'aiGenerations'] = this.aiGenerations;
    json[r'subscriptions'] = this.subscriptions;
    return json;
  }

  /// Returns a new [CloudExportTruncated] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportTruncated? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'devices'),
            'Required key "CloudExportTruncated[devices]" is missing from JSON.');
        assert(json[r'devices'] != null,
            'Required key "CloudExportTruncated[devices]" has a null value in JSON.');
        assert(json.containsKey(r'dailyUsage'),
            'Required key "CloudExportTruncated[dailyUsage]" is missing from JSON.');
        assert(json[r'dailyUsage'] != null,
            'Required key "CloudExportTruncated[dailyUsage]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSummaries'),
            'Required key "CloudExportTruncated[chargingSummaries]" is missing from JSON.');
        assert(json[r'chargingSummaries'] != null,
            'Required key "CloudExportTruncated[chargingSummaries]" has a null value in JSON.');
        assert(json.containsKey(r'monthlySummaries'),
            'Required key "CloudExportTruncated[monthlySummaries]" is missing from JSON.');
        assert(json[r'monthlySummaries'] != null,
            'Required key "CloudExportTruncated[monthlySummaries]" has a null value in JSON.');
        assert(json.containsKey(r'aiGenerations'),
            'Required key "CloudExportTruncated[aiGenerations]" is missing from JSON.');
        assert(json[r'aiGenerations'] != null,
            'Required key "CloudExportTruncated[aiGenerations]" has a null value in JSON.');
        assert(json.containsKey(r'subscriptions'),
            'Required key "CloudExportTruncated[subscriptions]" is missing from JSON.');
        assert(json[r'subscriptions'] != null,
            'Required key "CloudExportTruncated[subscriptions]" has a null value in JSON.');
        return true;
      }());

      return CloudExportTruncated(
        devices: mapValueOfType<bool>(json, r'devices')!,
        dailyUsage: mapValueOfType<bool>(json, r'dailyUsage')!,
        chargingSummaries: mapValueOfType<bool>(json, r'chargingSummaries')!,
        monthlySummaries: mapValueOfType<bool>(json, r'monthlySummaries')!,
        aiGenerations: mapValueOfType<bool>(json, r'aiGenerations')!,
        subscriptions: mapValueOfType<bool>(json, r'subscriptions')!,
      );
    }
    return null;
  }

  static List<CloudExportTruncated> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportTruncated>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportTruncated.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportTruncated> mapFromJson(dynamic json) {
    final map = <String, CloudExportTruncated>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportTruncated.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportTruncated-objects as value to a dart map
  static Map<String, List<CloudExportTruncated>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportTruncated>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportTruncated.listFromJson(
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
    'dailyUsage',
    'chargingSummaries',
    'monthlySummaries',
    'aiGenerations',
    'subscriptions',
  };
}
