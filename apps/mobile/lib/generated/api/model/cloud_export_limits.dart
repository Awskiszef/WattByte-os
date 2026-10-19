//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportLimits {
  /// Returns a new [CloudExportLimits] instance.
  CloudExportLimits({
    required this.maxRowsPerCollection,
    required this.truncated,
  });

  /// Minimum value: 0
  int maxRowsPerCollection;

  CloudExportTruncated truncated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportLimits &&
          other.maxRowsPerCollection == maxRowsPerCollection &&
          other.truncated == truncated;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (maxRowsPerCollection.hashCode) + (truncated.hashCode);

  @override
  String toString() =>
      'CloudExportLimits[maxRowsPerCollection=$maxRowsPerCollection, truncated=$truncated]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'maxRowsPerCollection'] = this.maxRowsPerCollection;
    json[r'truncated'] = this.truncated;
    return json;
  }

  /// Returns a new [CloudExportLimits] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportLimits? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'maxRowsPerCollection'),
            'Required key "CloudExportLimits[maxRowsPerCollection]" is missing from JSON.');
        assert(json[r'maxRowsPerCollection'] != null,
            'Required key "CloudExportLimits[maxRowsPerCollection]" has a null value in JSON.');
        assert(json.containsKey(r'truncated'),
            'Required key "CloudExportLimits[truncated]" is missing from JSON.');
        assert(json[r'truncated'] != null,
            'Required key "CloudExportLimits[truncated]" has a null value in JSON.');
        return true;
      }());

      return CloudExportLimits(
        maxRowsPerCollection:
            mapValueOfType<int>(json, r'maxRowsPerCollection')!,
        truncated: CloudExportTruncated.fromJson(json[r'truncated'])!,
      );
    }
    return null;
  }

  static List<CloudExportLimits> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportLimits>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportLimits.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportLimits> mapFromJson(dynamic json) {
    final map = <String, CloudExportLimits>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportLimits.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportLimits-objects as value to a dart map
  static Map<String, List<CloudExportLimits>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportLimits>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportLimits.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'maxRowsPerCollection',
    'truncated',
  };
}
