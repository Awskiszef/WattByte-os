//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class UsageSyncRequest {
  /// Returns a new [UsageSyncRequest] instance.
  UsageSyncRequest({
    required this.installationId,
    this.days = const [],
  });

  String installationId;

  List<DailyUsageDto> days;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageSyncRequest &&
          other.installationId == installationId &&
          _deepEquality.equals(other.days, days);

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (installationId.hashCode) + (days.hashCode);

  @override
  String toString() =>
      'UsageSyncRequest[installationId=$installationId, days=$days]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'installationId'] = this.installationId;
    json[r'days'] = this.days;
    return json;
  }

  /// Returns a new [UsageSyncRequest] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UsageSyncRequest? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'installationId'),
            'Required key "UsageSyncRequest[installationId]" is missing from JSON.');
        assert(json[r'installationId'] != null,
            'Required key "UsageSyncRequest[installationId]" has a null value in JSON.');
        assert(json.containsKey(r'days'),
            'Required key "UsageSyncRequest[days]" is missing from JSON.');
        assert(json[r'days'] != null,
            'Required key "UsageSyncRequest[days]" has a null value in JSON.');
        return true;
      }());

      return UsageSyncRequest(
        installationId: mapValueOfType<String>(json, r'installationId')!,
        days: DailyUsageDto.listFromJson(json[r'days']),
      );
    }
    return null;
  }

  static List<UsageSyncRequest> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <UsageSyncRequest>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UsageSyncRequest.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UsageSyncRequest> mapFromJson(dynamic json) {
    final map = <String, UsageSyncRequest>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UsageSyncRequest.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UsageSyncRequest-objects as value to a dart map
  static Map<String, List<UsageSyncRequest>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<UsageSyncRequest>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UsageSyncRequest.listFromJson(
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
    'days',
  };
}
