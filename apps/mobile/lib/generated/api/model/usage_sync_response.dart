//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UsageSyncResponse {
  /// Returns a new [UsageSyncResponse] instance.
  UsageSyncResponse({
    required this.accepted,
    this.dates = const [],
  });

  /// Minimum value: 0
  int accepted;

  List<String> dates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageSyncResponse &&
          other.accepted == accepted &&
          _deepEquality.equals(other.dates, dates);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (accepted.hashCode) + (dates.hashCode);

  @override
  String toString() => 'UsageSyncResponse[accepted=$accepted, dates=$dates]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'accepted'] = this.accepted;
    json[r'dates'] = this.dates;
    return json;
  }

  /// Returns a new [UsageSyncResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UsageSyncResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'accepted'),
            'Required key "UsageSyncResponse[accepted]" is missing from JSON.');
        assert(json[r'accepted'] != null,
            'Required key "UsageSyncResponse[accepted]" has a null value in JSON.');
        assert(json.containsKey(r'dates'),
            'Required key "UsageSyncResponse[dates]" is missing from JSON.');
        assert(json[r'dates'] != null,
            'Required key "UsageSyncResponse[dates]" has a null value in JSON.');
        return true;
      }());

      return UsageSyncResponse(
        accepted: mapValueOfType<int>(json, r'accepted')!,
        dates: json[r'dates'] is Iterable
            ? (json[r'dates'] as Iterable)
                .cast<String>()
                .toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<UsageSyncResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UsageSyncResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UsageSyncResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UsageSyncResponse> mapFromJson(dynamic json) {
    final map = <String, UsageSyncResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UsageSyncResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UsageSyncResponse-objects as value to a dart map
  static Map<String, List<UsageSyncResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UsageSyncResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UsageSyncResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'accepted',
    'dates',
  };
}
