//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportMonthlySummary {
  /// Returns a new [CloudExportMonthlySummary] instance.
  CloudExportMonthlySummary({
    required this.month,
    required this.mobileBytes,
    required this.wifiBytes,
    required this.wallWh,
    required this.chargingSessions,
    required this.estimatedCost,
    required this.currency,
    required this.computedAt,
  });

  String month;

  /// Minimum value: 0
  int mobileBytes;

  /// Minimum value: 0
  int wifiBytes;

  num wallWh;

  /// Minimum value: 0
  int chargingSessions;

  num estimatedCost;

  String currency;

  DateTime computedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportMonthlySummary &&
          other.month == month &&
          other.mobileBytes == mobileBytes &&
          other.wifiBytes == wifiBytes &&
          other.wallWh == wallWh &&
          other.chargingSessions == chargingSessions &&
          other.estimatedCost == estimatedCost &&
          other.currency == currency &&
          other.computedAt == computedAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (month.hashCode) +
      (mobileBytes.hashCode) +
      (wifiBytes.hashCode) +
      (wallWh.hashCode) +
      (chargingSessions.hashCode) +
      (estimatedCost.hashCode) +
      (currency.hashCode) +
      (computedAt.hashCode);

  @override
  String toString() =>
      'CloudExportMonthlySummary[month=$month, mobileBytes=$mobileBytes, wifiBytes=$wifiBytes, wallWh=$wallWh, chargingSessions=$chargingSessions, estimatedCost=$estimatedCost, currency=$currency, computedAt=$computedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'month'] = this.month;
    json[r'mobileBytes'] = this.mobileBytes;
    json[r'wifiBytes'] = this.wifiBytes;
    json[r'wallWh'] = this.wallWh;
    json[r'chargingSessions'] = this.chargingSessions;
    json[r'estimatedCost'] = this.estimatedCost;
    json[r'currency'] = this.currency;
    json[r'computedAt'] = this.computedAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [CloudExportMonthlySummary] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportMonthlySummary? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'month'),
            'Required key "CloudExportMonthlySummary[month]" is missing from JSON.');
        assert(json[r'month'] != null,
            'Required key "CloudExportMonthlySummary[month]" has a null value in JSON.');
        assert(json.containsKey(r'mobileBytes'),
            'Required key "CloudExportMonthlySummary[mobileBytes]" is missing from JSON.');
        assert(json[r'mobileBytes'] != null,
            'Required key "CloudExportMonthlySummary[mobileBytes]" has a null value in JSON.');
        assert(json.containsKey(r'wifiBytes'),
            'Required key "CloudExportMonthlySummary[wifiBytes]" is missing from JSON.');
        assert(json[r'wifiBytes'] != null,
            'Required key "CloudExportMonthlySummary[wifiBytes]" has a null value in JSON.');
        assert(json.containsKey(r'wallWh'),
            'Required key "CloudExportMonthlySummary[wallWh]" is missing from JSON.');
        assert(json[r'wallWh'] != null,
            'Required key "CloudExportMonthlySummary[wallWh]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSessions'),
            'Required key "CloudExportMonthlySummary[chargingSessions]" is missing from JSON.');
        assert(json[r'chargingSessions'] != null,
            'Required key "CloudExportMonthlySummary[chargingSessions]" has a null value in JSON.');
        assert(json.containsKey(r'estimatedCost'),
            'Required key "CloudExportMonthlySummary[estimatedCost]" is missing from JSON.');
        assert(json[r'estimatedCost'] != null,
            'Required key "CloudExportMonthlySummary[estimatedCost]" has a null value in JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "CloudExportMonthlySummary[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "CloudExportMonthlySummary[currency]" has a null value in JSON.');
        assert(json.containsKey(r'computedAt'),
            'Required key "CloudExportMonthlySummary[computedAt]" is missing from JSON.');
        assert(json[r'computedAt'] != null,
            'Required key "CloudExportMonthlySummary[computedAt]" has a null value in JSON.');
        return true;
      }());

      return CloudExportMonthlySummary(
        month: mapValueOfType<String>(json, r'month')!,
        mobileBytes: mapValueOfType<int>(json, r'mobileBytes')!,
        wifiBytes: mapValueOfType<int>(json, r'wifiBytes')!,
        wallWh: num.parse('${json[r'wallWh']}'),
        chargingSessions: mapValueOfType<int>(json, r'chargingSessions')!,
        estimatedCost: num.parse('${json[r'estimatedCost']}'),
        currency: mapValueOfType<String>(json, r'currency')!,
        computedAt: mapDateTime(json, r'computedAt', r'')!,
      );
    }
    return null;
  }

  static List<CloudExportMonthlySummary> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportMonthlySummary>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportMonthlySummary.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportMonthlySummary> mapFromJson(dynamic json) {
    final map = <String, CloudExportMonthlySummary>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportMonthlySummary.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportMonthlySummary-objects as value to a dart map
  static Map<String, List<CloudExportMonthlySummary>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportMonthlySummary>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportMonthlySummary.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'month',
    'mobileBytes',
    'wifiBytes',
    'wallWh',
    'chargingSessions',
    'estimatedCost',
    'currency',
    'computedAt',
  };
}
