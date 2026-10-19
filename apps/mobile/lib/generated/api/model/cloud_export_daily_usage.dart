//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportDailyUsage {
  /// Returns a new [CloudExportDailyUsage] instance.
  CloudExportDailyUsage({
    required this.deviceId,
    required this.date,
    required this.mobileBytes,
    required this.wifiBytes,
    required this.chargedWh,
    required this.wallWh,
    required this.chargingSessions,
    required this.estimatedCost,
    required this.currency,
    required this.dataEstimated,
    required this.energyEstimated,
  });

  String deviceId;

  String date;

  /// Minimum value: 0
  int mobileBytes;

  /// Minimum value: 0
  int wifiBytes;

  /// Minimum value: 0
  num chargedWh;

  /// Minimum value: 0
  num wallWh;

  /// Minimum value: 0
  int chargingSessions;

  /// Minimum value: 0
  num estimatedCost;

  String currency;

  bool dataEstimated;

  bool energyEstimated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportDailyUsage &&
          other.deviceId == deviceId &&
          other.date == date &&
          other.mobileBytes == mobileBytes &&
          other.wifiBytes == wifiBytes &&
          other.chargedWh == chargedWh &&
          other.wallWh == wallWh &&
          other.chargingSessions == chargingSessions &&
          other.estimatedCost == estimatedCost &&
          other.currency == currency &&
          other.dataEstimated == dataEstimated &&
          other.energyEstimated == energyEstimated;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (deviceId.hashCode) +
      (date.hashCode) +
      (mobileBytes.hashCode) +
      (wifiBytes.hashCode) +
      (chargedWh.hashCode) +
      (wallWh.hashCode) +
      (chargingSessions.hashCode) +
      (estimatedCost.hashCode) +
      (currency.hashCode) +
      (dataEstimated.hashCode) +
      (energyEstimated.hashCode);

  @override
  String toString() =>
      'CloudExportDailyUsage[deviceId=$deviceId, date=$date, mobileBytes=$mobileBytes, wifiBytes=$wifiBytes, chargedWh=$chargedWh, wallWh=$wallWh, chargingSessions=$chargingSessions, estimatedCost=$estimatedCost, currency=$currency, dataEstimated=$dataEstimated, energyEstimated=$energyEstimated]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'deviceId'] = this.deviceId;
    json[r'date'] = this.date;
    json[r'mobileBytes'] = this.mobileBytes;
    json[r'wifiBytes'] = this.wifiBytes;
    json[r'chargedWh'] = this.chargedWh;
    json[r'wallWh'] = this.wallWh;
    json[r'chargingSessions'] = this.chargingSessions;
    json[r'estimatedCost'] = this.estimatedCost;
    json[r'currency'] = this.currency;
    json[r'dataEstimated'] = this.dataEstimated;
    json[r'energyEstimated'] = this.energyEstimated;
    return json;
  }

  /// Returns a new [CloudExportDailyUsage] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportDailyUsage? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'deviceId'),
            'Required key "CloudExportDailyUsage[deviceId]" is missing from JSON.');
        assert(json[r'deviceId'] != null,
            'Required key "CloudExportDailyUsage[deviceId]" has a null value in JSON.');
        assert(json.containsKey(r'date'),
            'Required key "CloudExportDailyUsage[date]" is missing from JSON.');
        assert(json[r'date'] != null,
            'Required key "CloudExportDailyUsage[date]" has a null value in JSON.');
        assert(json.containsKey(r'mobileBytes'),
            'Required key "CloudExportDailyUsage[mobileBytes]" is missing from JSON.');
        assert(json[r'mobileBytes'] != null,
            'Required key "CloudExportDailyUsage[mobileBytes]" has a null value in JSON.');
        assert(json.containsKey(r'wifiBytes'),
            'Required key "CloudExportDailyUsage[wifiBytes]" is missing from JSON.');
        assert(json[r'wifiBytes'] != null,
            'Required key "CloudExportDailyUsage[wifiBytes]" has a null value in JSON.');
        assert(json.containsKey(r'chargedWh'),
            'Required key "CloudExportDailyUsage[chargedWh]" is missing from JSON.');
        assert(json[r'chargedWh'] != null,
            'Required key "CloudExportDailyUsage[chargedWh]" has a null value in JSON.');
        assert(json.containsKey(r'wallWh'),
            'Required key "CloudExportDailyUsage[wallWh]" is missing from JSON.');
        assert(json[r'wallWh'] != null,
            'Required key "CloudExportDailyUsage[wallWh]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSessions'),
            'Required key "CloudExportDailyUsage[chargingSessions]" is missing from JSON.');
        assert(json[r'chargingSessions'] != null,
            'Required key "CloudExportDailyUsage[chargingSessions]" has a null value in JSON.');
        assert(json.containsKey(r'estimatedCost'),
            'Required key "CloudExportDailyUsage[estimatedCost]" is missing from JSON.');
        assert(json[r'estimatedCost'] != null,
            'Required key "CloudExportDailyUsage[estimatedCost]" has a null value in JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "CloudExportDailyUsage[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "CloudExportDailyUsage[currency]" has a null value in JSON.');
        assert(json.containsKey(r'dataEstimated'),
            'Required key "CloudExportDailyUsage[dataEstimated]" is missing from JSON.');
        assert(json[r'dataEstimated'] != null,
            'Required key "CloudExportDailyUsage[dataEstimated]" has a null value in JSON.');
        assert(json.containsKey(r'energyEstimated'),
            'Required key "CloudExportDailyUsage[energyEstimated]" is missing from JSON.');
        assert(json[r'energyEstimated'] != null,
            'Required key "CloudExportDailyUsage[energyEstimated]" has a null value in JSON.');
        return true;
      }());

      return CloudExportDailyUsage(
        deviceId: mapValueOfType<String>(json, r'deviceId')!,
        date: mapValueOfType<String>(json, r'date')!,
        mobileBytes: mapValueOfType<int>(json, r'mobileBytes')!,
        wifiBytes: mapValueOfType<int>(json, r'wifiBytes')!,
        chargedWh: num.parse('${json[r'chargedWh']}'),
        wallWh: num.parse('${json[r'wallWh']}'),
        chargingSessions: mapValueOfType<int>(json, r'chargingSessions')!,
        estimatedCost: num.parse('${json[r'estimatedCost']}'),
        currency: mapValueOfType<String>(json, r'currency')!,
        dataEstimated: mapValueOfType<bool>(json, r'dataEstimated')!,
        energyEstimated: mapValueOfType<bool>(json, r'energyEstimated')!,
      );
    }
    return null;
  }

  static List<CloudExportDailyUsage> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportDailyUsage>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportDailyUsage.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportDailyUsage> mapFromJson(dynamic json) {
    final map = <String, CloudExportDailyUsage>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportDailyUsage.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportDailyUsage-objects as value to a dart map
  static Map<String, List<CloudExportDailyUsage>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportDailyUsage>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportDailyUsage.listFromJson(
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
    'date',
    'mobileBytes',
    'wifiBytes',
    'chargedWh',
    'wallWh',
    'chargingSessions',
    'estimatedCost',
    'currency',
    'dataEstimated',
    'energyEstimated',
  };
}
