//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportChargingSummary {
  /// Returns a new [CloudExportChargingSummary] instance.
  CloudExportChargingSummary({
    required this.deviceId,
    required this.startedAt,
    required this.endedAt,
    required this.startPercent,
    required this.endPercent,
    required this.mah,
    required this.mahEstimated,
    required this.batteryWh,
    required this.wallWh,
    required this.estimatedCost,
    required this.createdAt,
  });

  String deviceId;

  DateTime startedAt;

  DateTime endedAt;

  int startPercent;

  int endPercent;

  num mah;

  bool mahEstimated;

  num batteryWh;

  num wallWh;

  num estimatedCost;

  DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportChargingSummary &&
          other.deviceId == deviceId &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.startPercent == startPercent &&
          other.endPercent == endPercent &&
          other.mah == mah &&
          other.mahEstimated == mahEstimated &&
          other.batteryWh == batteryWh &&
          other.wallWh == wallWh &&
          other.estimatedCost == estimatedCost &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (deviceId.hashCode) +
      (startedAt.hashCode) +
      (endedAt.hashCode) +
      (startPercent.hashCode) +
      (endPercent.hashCode) +
      (mah.hashCode) +
      (mahEstimated.hashCode) +
      (batteryWh.hashCode) +
      (wallWh.hashCode) +
      (estimatedCost.hashCode) +
      (createdAt.hashCode);

  @override
  String toString() =>
      'CloudExportChargingSummary[deviceId=$deviceId, startedAt=$startedAt, endedAt=$endedAt, startPercent=$startPercent, endPercent=$endPercent, mah=$mah, mahEstimated=$mahEstimated, batteryWh=$batteryWh, wallWh=$wallWh, estimatedCost=$estimatedCost, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'deviceId'] = this.deviceId;
    json[r'startedAt'] = this.startedAt.toUtc().toIso8601String();
    json[r'endedAt'] = this.endedAt.toUtc().toIso8601String();
    json[r'startPercent'] = this.startPercent;
    json[r'endPercent'] = this.endPercent;
    json[r'mah'] = this.mah;
    json[r'mahEstimated'] = this.mahEstimated;
    json[r'batteryWh'] = this.batteryWh;
    json[r'wallWh'] = this.wallWh;
    json[r'estimatedCost'] = this.estimatedCost;
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [CloudExportChargingSummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportChargingSummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'deviceId'),
            'Required key "CloudExportChargingSummary[deviceId]" is missing from JSON.');
        assert(json[r'deviceId'] != null,
            'Required key "CloudExportChargingSummary[deviceId]" has a null value in JSON.');
        assert(json.containsKey(r'startedAt'),
            'Required key "CloudExportChargingSummary[startedAt]" is missing from JSON.');
        assert(json[r'startedAt'] != null,
            'Required key "CloudExportChargingSummary[startedAt]" has a null value in JSON.');
        assert(json.containsKey(r'endedAt'),
            'Required key "CloudExportChargingSummary[endedAt]" is missing from JSON.');
        assert(json[r'endedAt'] != null,
            'Required key "CloudExportChargingSummary[endedAt]" has a null value in JSON.');
        assert(json.containsKey(r'startPercent'),
            'Required key "CloudExportChargingSummary[startPercent]" is missing from JSON.');
        assert(json[r'startPercent'] != null,
            'Required key "CloudExportChargingSummary[startPercent]" has a null value in JSON.');
        assert(json.containsKey(r'endPercent'),
            'Required key "CloudExportChargingSummary[endPercent]" is missing from JSON.');
        assert(json[r'endPercent'] != null,
            'Required key "CloudExportChargingSummary[endPercent]" has a null value in JSON.');
        assert(json.containsKey(r'mah'),
            'Required key "CloudExportChargingSummary[mah]" is missing from JSON.');
        assert(json[r'mah'] != null,
            'Required key "CloudExportChargingSummary[mah]" has a null value in JSON.');
        assert(json.containsKey(r'mahEstimated'),
            'Required key "CloudExportChargingSummary[mahEstimated]" is missing from JSON.');
        assert(json[r'mahEstimated'] != null,
            'Required key "CloudExportChargingSummary[mahEstimated]" has a null value in JSON.');
        assert(json.containsKey(r'batteryWh'),
            'Required key "CloudExportChargingSummary[batteryWh]" is missing from JSON.');
        assert(json[r'batteryWh'] != null,
            'Required key "CloudExportChargingSummary[batteryWh]" has a null value in JSON.');
        assert(json.containsKey(r'wallWh'),
            'Required key "CloudExportChargingSummary[wallWh]" is missing from JSON.');
        assert(json[r'wallWh'] != null,
            'Required key "CloudExportChargingSummary[wallWh]" has a null value in JSON.');
        assert(json.containsKey(r'estimatedCost'),
            'Required key "CloudExportChargingSummary[estimatedCost]" is missing from JSON.');
        assert(json[r'estimatedCost'] != null,
            'Required key "CloudExportChargingSummary[estimatedCost]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "CloudExportChargingSummary[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "CloudExportChargingSummary[createdAt]" has a null value in JSON.');
        return true;
      }());

      return CloudExportChargingSummary(
        deviceId: mapValueOfType<String>(json, r'deviceId')!,
        startedAt: mapDateTime(json, r'startedAt', r'')!,
        endedAt: mapDateTime(json, r'endedAt', r'')!,
        startPercent: mapValueOfType<int>(json, r'startPercent')!,
        endPercent: mapValueOfType<int>(json, r'endPercent')!,
        mah: num.parse('${json[r'mah']}'),
        mahEstimated: mapValueOfType<bool>(json, r'mahEstimated')!,
        batteryWh: num.parse('${json[r'batteryWh']}'),
        wallWh: num.parse('${json[r'wallWh']}'),
        estimatedCost: num.parse('${json[r'estimatedCost']}'),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<CloudExportChargingSummary> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportChargingSummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportChargingSummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportChargingSummary> mapFromJson(dynamic json) {
    final map = <String, CloudExportChargingSummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportChargingSummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportChargingSummary-objects as value to a dart map
  static Map<String, List<CloudExportChargingSummary>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportChargingSummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportChargingSummary.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'deviceId',
    'startedAt',
    'endedAt',
    'startPercent',
    'endPercent',
    'mah',
    'mahEstimated',
    'batteryWh',
    'wallWh',
    'estimatedCost',
    'createdAt',
  };
}
