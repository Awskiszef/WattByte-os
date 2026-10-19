//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AppConfigDtoFeatures {
  /// Returns a new [AppConfigDtoFeatures] instance.
  AppConfigDtoFeatures({
    required this.ai,
    required this.subscriptions,
    required this.cloudSync,
  });

  bool ai;

  bool subscriptions;

  bool cloudSync;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfigDtoFeatures &&
          other.ai == ai &&
          other.subscriptions == subscriptions &&
          other.cloudSync == cloudSync;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (ai.hashCode) + (subscriptions.hashCode) + (cloudSync.hashCode);

  @override
  String toString() =>
      'AppConfigDtoFeatures[ai=$ai, subscriptions=$subscriptions, cloudSync=$cloudSync]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'ai'] = this.ai;
    json[r'subscriptions'] = this.subscriptions;
    json[r'cloudSync'] = this.cloudSync;
    return json;
  }

  /// Returns a new [AppConfigDtoFeatures] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AppConfigDtoFeatures? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'ai'),
            'Required key "AppConfigDtoFeatures[ai]" is missing from JSON.');
        assert(json[r'ai'] != null,
            'Required key "AppConfigDtoFeatures[ai]" has a null value in JSON.');
        assert(json.containsKey(r'subscriptions'),
            'Required key "AppConfigDtoFeatures[subscriptions]" is missing from JSON.');
        assert(json[r'subscriptions'] != null,
            'Required key "AppConfigDtoFeatures[subscriptions]" has a null value in JSON.');
        assert(json.containsKey(r'cloudSync'),
            'Required key "AppConfigDtoFeatures[cloudSync]" is missing from JSON.');
        assert(json[r'cloudSync'] != null,
            'Required key "AppConfigDtoFeatures[cloudSync]" has a null value in JSON.');
        return true;
      }());

      return AppConfigDtoFeatures(
        ai: mapValueOfType<bool>(json, r'ai')!,
        subscriptions: mapValueOfType<bool>(json, r'subscriptions')!,
        cloudSync: mapValueOfType<bool>(json, r'cloudSync')!,
      );
    }
    return null;
  }

  static List<AppConfigDtoFeatures> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AppConfigDtoFeatures>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AppConfigDtoFeatures.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AppConfigDtoFeatures> mapFromJson(dynamic json) {
    final map = <String, AppConfigDtoFeatures>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AppConfigDtoFeatures.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AppConfigDtoFeatures-objects as value to a dart map
  static Map<String, List<AppConfigDtoFeatures>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AppConfigDtoFeatures>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AppConfigDtoFeatures.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'ai',
    'subscriptions',
    'cloudSync',
  };
}
