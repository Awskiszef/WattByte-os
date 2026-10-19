//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UsageDailyResponse {
  /// Returns a new [UsageDailyResponse] instance.
  UsageDailyResponse({
    this.days = const [],
  });

  List<DailyUsageDto> days;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageDailyResponse && _deepEquality.equals(other.days, days);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (days.hashCode);

  @override
  String toString() => 'UsageDailyResponse[days=$days]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'days'] = this.days;
    return json;
  }

  /// Returns a new [UsageDailyResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UsageDailyResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'days'),
            'Required key "UsageDailyResponse[days]" is missing from JSON.');
        assert(json[r'days'] != null,
            'Required key "UsageDailyResponse[days]" has a null value in JSON.');
        return true;
      }());

      return UsageDailyResponse(
        days: DailyUsageDto.listFromJson(json[r'days']),
      );
    }
    return null;
  }

  static List<UsageDailyResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UsageDailyResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UsageDailyResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UsageDailyResponse> mapFromJson(dynamic json) {
    final map = <String, UsageDailyResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UsageDailyResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UsageDailyResponse-objects as value to a dart map
  static Map<String, List<UsageDailyResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UsageDailyResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UsageDailyResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'days',
  };
}
