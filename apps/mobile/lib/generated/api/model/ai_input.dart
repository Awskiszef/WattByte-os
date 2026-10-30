//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AIInput {
  /// Returns a new [AIInput] instance.
  AIInput({
    required this.period,
    required this.periodType,
    required this.mobileDataGb,
    required this.wifiDataGb,
    required this.totalDataGb,
    required this.chargingSessions,
    this.batteryEnergyKwh,
    this.wallEnergyKwh,
    this.electricityCost,
    required this.currency,
    this.previousPeriodChangePercent,
    this.wifiSharePercent,
    this.averageSessionMah,
  });

  String period;

  AIInputPeriodTypeEnum periodType;

  /// Minimum value: 0
  /// Maximum value: 1000000
  num mobileDataGb;

  /// Minimum value: 0
  /// Maximum value: 1000000
  num wifiDataGb;

  /// Minimum value: 0
  /// Maximum value: 2000000
  num totalDataGb;

  /// Minimum value: 0
  /// Maximum value: 100000
  int chargingSessions;

  /// Minimum value: 0
  /// Maximum value: 1000000
  num? batteryEnergyKwh;

  /// Minimum value: 0
  /// Maximum value: 1000000
  num? wallEnergyKwh;

  /// Minimum value: 0
  /// Maximum value: 1000000000
  num? electricityCost;

  String currency;

  /// Minimum value: -100
  /// Maximum value: 1000000
  num? previousPeriodChangePercent;

  /// Minimum value: 0
  /// Maximum value: 100
  num? wifiSharePercent;

  /// Minimum value: 0
  /// Maximum value: 100000
  num? averageSessionMah;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIInput &&
          other.period == period &&
          other.periodType == periodType &&
          other.mobileDataGb == mobileDataGb &&
          other.wifiDataGb == wifiDataGb &&
          other.totalDataGb == totalDataGb &&
          other.chargingSessions == chargingSessions &&
          other.batteryEnergyKwh == batteryEnergyKwh &&
          other.wallEnergyKwh == wallEnergyKwh &&
          other.electricityCost == electricityCost &&
          other.currency == currency &&
          other.previousPeriodChangePercent == previousPeriodChangePercent &&
          other.wifiSharePercent == wifiSharePercent &&
          other.averageSessionMah == averageSessionMah;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (period.hashCode) +
      (periodType.hashCode) +
      (mobileDataGb.hashCode) +
      (wifiDataGb.hashCode) +
      (totalDataGb.hashCode) +
      (chargingSessions.hashCode) +
      (batteryEnergyKwh == null ? 0 : batteryEnergyKwh!.hashCode) +
      (wallEnergyKwh == null ? 0 : wallEnergyKwh!.hashCode) +
      (electricityCost == null ? 0 : electricityCost!.hashCode) +
      (currency.hashCode) +
      (previousPeriodChangePercent == null
          ? 0
          : previousPeriodChangePercent!.hashCode) +
      (wifiSharePercent == null ? 0 : wifiSharePercent!.hashCode) +
      (averageSessionMah == null ? 0 : averageSessionMah!.hashCode);

  @override
  String toString() =>
      'AIInput[period=$period, periodType=$periodType, mobileDataGb=$mobileDataGb, wifiDataGb=$wifiDataGb, totalDataGb=$totalDataGb, chargingSessions=$chargingSessions, batteryEnergyKwh=$batteryEnergyKwh, wallEnergyKwh=$wallEnergyKwh, electricityCost=$electricityCost, currency=$currency, previousPeriodChangePercent=$previousPeriodChangePercent, wifiSharePercent=$wifiSharePercent, averageSessionMah=$averageSessionMah]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'period'] = this.period;
    json[r'periodType'] = this.periodType;
    json[r'mobileDataGb'] = this.mobileDataGb;
    json[r'wifiDataGb'] = this.wifiDataGb;
    json[r'totalDataGb'] = this.totalDataGb;
    json[r'chargingSessions'] = this.chargingSessions;
    if (this.batteryEnergyKwh != null) {
      json[r'batteryEnergyKwh'] = this.batteryEnergyKwh;
    } else {
      json[r'batteryEnergyKwh'] = null;
    }
    if (this.wallEnergyKwh != null) {
      json[r'wallEnergyKwh'] = this.wallEnergyKwh;
    } else {
      json[r'wallEnergyKwh'] = null;
    }
    if (this.electricityCost != null) {
      json[r'electricityCost'] = this.electricityCost;
    } else {
      json[r'electricityCost'] = null;
    }
    json[r'currency'] = this.currency;
    if (this.previousPeriodChangePercent != null) {
      json[r'previousPeriodChangePercent'] = this.previousPeriodChangePercent;
    } else {
      json[r'previousPeriodChangePercent'] = null;
    }
    if (this.wifiSharePercent != null) {
      json[r'wifiSharePercent'] = this.wifiSharePercent;
    } else {
      json[r'wifiSharePercent'] = null;
    }
    if (this.averageSessionMah != null) {
      json[r'averageSessionMah'] = this.averageSessionMah;
    } else {
      json[r'averageSessionMah'] = null;
    }
    return json;
  }

  /// Returns a new [AIInput] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AIInput? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'period'),
            'Required key "AIInput[period]" is missing from JSON.');
        assert(json[r'period'] != null,
            'Required key "AIInput[period]" has a null value in JSON.');
        assert(json.containsKey(r'periodType'),
            'Required key "AIInput[periodType]" is missing from JSON.');
        assert(json[r'periodType'] != null,
            'Required key "AIInput[periodType]" has a null value in JSON.');
        assert(json.containsKey(r'mobileDataGb'),
            'Required key "AIInput[mobileDataGb]" is missing from JSON.');
        assert(json[r'mobileDataGb'] != null,
            'Required key "AIInput[mobileDataGb]" has a null value in JSON.');
        assert(json.containsKey(r'wifiDataGb'),
            'Required key "AIInput[wifiDataGb]" is missing from JSON.');
        assert(json[r'wifiDataGb'] != null,
            'Required key "AIInput[wifiDataGb]" has a null value in JSON.');
        assert(json.containsKey(r'totalDataGb'),
            'Required key "AIInput[totalDataGb]" is missing from JSON.');
        assert(json[r'totalDataGb'] != null,
            'Required key "AIInput[totalDataGb]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSessions'),
            'Required key "AIInput[chargingSessions]" is missing from JSON.');
        assert(json[r'chargingSessions'] != null,
            'Required key "AIInput[chargingSessions]" has a null value in JSON.');
        assert(json.containsKey(r'currency'),
            'Required key "AIInput[currency]" is missing from JSON.');
        assert(json[r'currency'] != null,
            'Required key "AIInput[currency]" has a null value in JSON.');
        return true;
      }());

      return AIInput(
        period: mapValueOfType<String>(json, r'period')!,
        periodType: AIInputPeriodTypeEnum.fromJson(json[r'periodType'])!,
        mobileDataGb: num.parse('${json[r'mobileDataGb']}'),
        wifiDataGb: num.parse('${json[r'wifiDataGb']}'),
        totalDataGb: num.parse('${json[r'totalDataGb']}'),
        chargingSessions: mapValueOfType<int>(json, r'chargingSessions')!,
        batteryEnergyKwh: json[r'batteryEnergyKwh'] == null
            ? null
            : num.parse('${json[r'batteryEnergyKwh']}'),
        wallEnergyKwh: json[r'wallEnergyKwh'] == null
            ? null
            : num.parse('${json[r'wallEnergyKwh']}'),
        electricityCost: json[r'electricityCost'] == null
            ? null
            : num.parse('${json[r'electricityCost']}'),
        currency: mapValueOfType<String>(json, r'currency')!,
        previousPeriodChangePercent:
            json[r'previousPeriodChangePercent'] == null
                ? null
                : num.parse('${json[r'previousPeriodChangePercent']}'),
        wifiSharePercent: json[r'wifiSharePercent'] == null
            ? null
            : num.parse('${json[r'wifiSharePercent']}'),
        averageSessionMah: json[r'averageSessionMah'] == null
            ? null
            : num.parse('${json[r'averageSessionMah']}'),
      );
    }
    return null;
  }

  static List<AIInput> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIInput>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIInput.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AIInput> mapFromJson(dynamic json) {
    final map = <String, AIInput>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AIInput.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AIInput-objects as value to a dart map
  static Map<String, List<AIInput>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AIInput>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AIInput.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'period',
    'periodType',
    'mobileDataGb',
    'wifiDataGb',
    'totalDataGb',
    'chargingSessions',
    'currency',
  };
}

enum AIInputPeriodTypeEnum {
  day._(r'day'),
  week._(r'week'),
  month._(r'month'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const AIInputPeriodTypeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [AIInputPeriodTypeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static AIInputPeriodTypeEnum? fromJson(dynamic value) =>
      AIInputPeriodTypeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [AIInputPeriodTypeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<AIInputPeriodTypeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIInputPeriodTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIInputPeriodTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [AIInputPeriodTypeEnum] to String,
/// and [decode] dynamic data back to [AIInputPeriodTypeEnum].
class AIInputPeriodTypeEnumTypeTransformer {
  factory AIInputPeriodTypeEnumTypeTransformer() =>
      _instance ??= const AIInputPeriodTypeEnumTypeTransformer._();

  const AIInputPeriodTypeEnumTypeTransformer._();

  String encode(AIInputPeriodTypeEnum data) => data._value;

  /// Returns the instance of [AIInputPeriodTypeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  AIInputPeriodTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is AIInputPeriodTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'day':
          return AIInputPeriodTypeEnum.day;
        case r'week':
          return AIInputPeriodTypeEnum.week;
        case r'month':
          return AIInputPeriodTypeEnum.month;
        case r'unknown_default_open_api':
          return AIInputPeriodTypeEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return AIInputPeriodTypeEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static AIInputPeriodTypeEnumTypeTransformer? _instance;
}
