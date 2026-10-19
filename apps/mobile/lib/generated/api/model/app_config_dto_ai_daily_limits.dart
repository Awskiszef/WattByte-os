//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AppConfigDtoAiDailyLimits {
  /// Returns a new [AppConfigDtoAiDailyLimits] instance.
  AppConfigDtoAiDailyLimits({
    required this.free,
    required this.premium,
  });

  /// Minimum value: 0
  int free;

  /// Minimum value: 0
  int premium;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppConfigDtoAiDailyLimits &&
          other.free == free &&
          other.premium == premium;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (free.hashCode) + (premium.hashCode);

  @override
  String toString() =>
      'AppConfigDtoAiDailyLimits[free=$free, premium=$premium]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'free'] = this.free;
    json[r'premium'] = this.premium;
    return json;
  }

  /// Returns a new [AppConfigDtoAiDailyLimits] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AppConfigDtoAiDailyLimits? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'free'),
            'Required key "AppConfigDtoAiDailyLimits[free]" is missing from JSON.');
        assert(json[r'free'] != null,
            'Required key "AppConfigDtoAiDailyLimits[free]" has a null value in JSON.');
        assert(json.containsKey(r'premium'),
            'Required key "AppConfigDtoAiDailyLimits[premium]" is missing from JSON.');
        assert(json[r'premium'] != null,
            'Required key "AppConfigDtoAiDailyLimits[premium]" has a null value in JSON.');
        return true;
      }());

      return AppConfigDtoAiDailyLimits(
        free: mapValueOfType<int>(json, r'free')!,
        premium: mapValueOfType<int>(json, r'premium')!,
      );
    }
    return null;
  }

  static List<AppConfigDtoAiDailyLimits> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AppConfigDtoAiDailyLimits>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AppConfigDtoAiDailyLimits.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AppConfigDtoAiDailyLimits> mapFromJson(dynamic json) {
    final map = <String, AppConfigDtoAiDailyLimits>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AppConfigDtoAiDailyLimits.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AppConfigDtoAiDailyLimits-objects as value to a dart map
  static Map<String, List<AppConfigDtoAiDailyLimits>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AppConfigDtoAiDailyLimits>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AppConfigDtoAiDailyLimits.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'free',
    'premium',
  };
}
