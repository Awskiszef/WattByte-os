//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class DailyUsageDto {
  /// Returns a new [DailyUsageDto] instance.
  DailyUsageDto({
    required this.date,
    required this.mobileBytes,
    required this.wifiBytes,
    required this.chargedWh,
    required this.wallWh,
    required this.chargingSessions,
    required this.estimatedCost,
    required this.currency,
    this.dataEstimated = false,
    this.energyEstimated = true,
  });

  String date;

  /// Minimum value: 0
  /// Maximum value: 10000000000000
  int mobileBytes;

  /// Minimum value: 0
  /// Maximum value: 10000000000000
  int wifiBytes;

  /// Minimum value: 0
  /// Maximum value: 100000
  num chargedWh;

  /// Minimum value: 0
  /// Maximum value: 100000
  num wallWh;

  /// Minimum value: 0
  /// Maximum value: 1000
  int chargingSessions;

  /// Minimum value: 0
  /// Maximum value: 100000
  num estimatedCost;

  String currency;

  bool dataEstimated;

  bool energyEstimated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyUsageDto &&
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
      'DailyUsageDto[date=$date, mobileBytes=$mobileBytes, wifiBytes=$wifiBytes, chargedWh=$chargedWh, wallWh=$wallWh, chargingSessions=$chargingSessions, estimatedCost=$estimatedCost, currency=$currency, dataEstimated=$dataEstimated, energyEstimated=$energyEstimated]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
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

  /// Returns a new [DailyUsageDto] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static DailyUsageDto? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'date'),
            'Required key "DailyUsageDto[date]" is missing from JSON.');
        assert(json[r'date'] != null,
            'Required key "DailyUsageDto[date]" has a null value in JSON.');
        assert(json.containsKey(r'mobileBytes'),
            'Required key "DailyUsageDto[mobileBytes]" is missing from JSON.');
        assert(json[r'mobileBytes'] != null,
            'Required key "DailyUsageDto[mobileBytes]" has a null value in JSON.');
        assert(json.containsKey(r'wifiBytes'),
            'Required key "DailyUsageDto[wifiBytes]" is missing from JSON.');
        assert(json[r'wifiBytes'] != null,
            'Required key "DailyUsageDto[wifiBytes]" has a null value in JSON.');
        assert(json.containsKey(r'chargedWh'),
            'Required key "DailyUsageDto[chargedWh]" is missing from JSON.');
        assert(json[r'chargedWh'] != null,
            'Required key "DailyUsageDto[chargedWh]" has a null value in JSON.');
        assert(json.containsKey(r'wallWh'),
            'Required key "DailyUsageDto[wallWh]" is missing from JSON.');
        assert(json[r'wallWh'] != null,
            'Required key "DailyUsageDto[wallWh]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSessions'),
            'Required key "DailyUsageDto[chargingSessions]" is missing from JSON.');
        assert(json[r'chargingSessions'] != null,
            'Required key "DailyUsageDto[chargingSessions]" has a null value in JSON.');
        assert(json.containsKey(r'estimatedCost'),
            'Required key "DailyUsageDto[estimatedCost]" is missing from JSON.');
        assert(json[r'estimatedCost'] != null,
            'Required key "DailyUsageDto[estimatedCost]" has a null value in JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "DailyUsageDto[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "DailyUsageDto[currency]" has a null value in JSON.');
        return true;
      }());

      return DailyUsageDto(
        date: mapValueOfType<String>(json, r'date')!,
        mobileBytes: mapValueOfType<int>(json, r'mobileBytes')!,
        wifiBytes: mapValueOfType<int>(json, r'wifiBytes')!,
        chargedWh: num.parse('${json[r'chargedWh']}'),
        wallWh: num.parse('${json[r'wallWh']}'),
        chargingSessions: mapValueOfType<int>(json, r'chargingSessions')!,
        estimatedCost: num.parse('${json[r'estimatedCost']}'),
        currency: mapValueOfType<String>(json, r'currency')!,
        dataEstimated: mapValueOfType<bool>(json, r'dataEstimated') ?? false,
        energyEstimated: mapValueOfType<bool>(json, r'energyEstimated') ?? true,
      );
    }
    return null;
  }

  static List<DailyUsageDto> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <DailyUsageDto>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = DailyUsageDto.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, DailyUsageDto> mapFromJson(dynamic json) {
    final map = <String, DailyUsageDto>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = DailyUsageDto.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of DailyUsageDto-objects as value to a dart map
  static Map<String, List<DailyUsageDto>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<DailyUsageDto>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = DailyUsageDto.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'date',
    'mobileBytes',
    'wifiBytes',
    'chargedWh',
    'wallWh',
    'chargingSessions',
    'estimatedCost',
    'currency',
  };
}
