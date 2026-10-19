//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportDocument {
  /// Returns a new [CloudExportDocument] instance.
  CloudExportDocument({
    required this.schemaVersion,
    required this.exportedAt,
    required this.account,
    required this.settings,
    this.devices = const [],
    this.dailyUsage = const [],
    this.chargingSummaries = const [],
    this.monthlySummaries = const [],
    this.aiGenerations = const [],
    this.subscriptions = const [],
    required this.limits,
  });

  /// Minimum value: 0
  int schemaVersion;

  DateTime exportedAt;

  UserDto account;

  CloudExportSettings settings;

  List<DeviceDto> devices;

  List<CloudExportDailyUsage> dailyUsage;

  List<CloudExportChargingSummary> chargingSummaries;

  List<CloudExportMonthlySummary> monthlySummaries;

  List<CloudExportAiGeneration> aiGenerations;

  List<CloudExportSubscription> subscriptions;

  CloudExportLimits limits;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportDocument &&
          other.schemaVersion == schemaVersion &&
          other.exportedAt == exportedAt &&
          other.account == account &&
          other.settings == settings &&
          _deepEquality.equals(other.devices, devices) &&
          _deepEquality.equals(other.dailyUsage, dailyUsage) &&
          _deepEquality.equals(other.chargingSummaries, chargingSummaries) &&
          _deepEquality.equals(other.monthlySummaries, monthlySummaries) &&
          _deepEquality.equals(other.aiGenerations, aiGenerations) &&
          _deepEquality.equals(other.subscriptions, subscriptions) &&
          other.limits == limits;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (schemaVersion.hashCode) +
      (exportedAt.hashCode) +
      (account.hashCode) +
      (settings.hashCode) +
      (devices.hashCode) +
      (dailyUsage.hashCode) +
      (chargingSummaries.hashCode) +
      (monthlySummaries.hashCode) +
      (aiGenerations.hashCode) +
      (subscriptions.hashCode) +
      (limits.hashCode);

  @override
  String toString() =>
      'CloudExportDocument[schemaVersion=$schemaVersion, exportedAt=$exportedAt, account=$account, settings=$settings, devices=$devices, dailyUsage=$dailyUsage, chargingSummaries=$chargingSummaries, monthlySummaries=$monthlySummaries, aiGenerations=$aiGenerations, subscriptions=$subscriptions, limits=$limits]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'schemaVersion'] = this.schemaVersion;
    json[r'exportedAt'] = this.exportedAt.toUtc().toIso8601String();
    json[r'account'] = this.account;
    json[r'settings'] = this.settings;
    json[r'devices'] = this.devices;
    json[r'dailyUsage'] = this.dailyUsage;
    json[r'chargingSummaries'] = this.chargingSummaries;
    json[r'monthlySummaries'] = this.monthlySummaries;
    json[r'aiGenerations'] = this.aiGenerations;
    json[r'subscriptions'] = this.subscriptions;
    json[r'limits'] = this.limits;
    return json;
  }

  /// Returns a new [CloudExportDocument] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportDocument? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'schemaVersion'),
            'Required key "CloudExportDocument[schemaVersion]" is missing from JSON.');
        assert(json[r'schemaVersion'] != null,
            'Required key "CloudExportDocument[schemaVersion]" has a null value in JSON.');
        assert(json.containsKey(r'exportedAt'),
            'Required key "CloudExportDocument[exportedAt]" is missing from JSON.');
        assert(json[r'exportedAt'] != null,
            'Required key "CloudExportDocument[exportedAt]" has a null value in JSON.');
        assert(json.containsKey(r'account'),
            'Required key "CloudExportDocument[account]" is missing from JSON.');
        assert(json[r'account'] != null,
            'Required key "CloudExportDocument[account]" has a null value in JSON.');
        assert(json.containsKey(r'settings'),
            'Required key "CloudExportDocument[settings]" is missing from JSON.');
        assert(json[r'settings'] != null,
            'Required key "CloudExportDocument[settings]" has a null value in JSON.');
        assert(json.containsKey(r'devices'),
            'Required key "CloudExportDocument[devices]" is missing from JSON.');
        assert(json[r'devices'] != null,
            'Required key "CloudExportDocument[devices]" has a null value in JSON.');
        assert(json.containsKey(r'dailyUsage'),
            'Required key "CloudExportDocument[dailyUsage]" is missing from JSON.');
        assert(json[r'dailyUsage'] != null,
            'Required key "CloudExportDocument[dailyUsage]" has a null value in JSON.');
        assert(json.containsKey(r'chargingSummaries'),
            'Required key "CloudExportDocument[chargingSummaries]" is missing from JSON.');
        assert(json[r'chargingSummaries'] != null,
            'Required key "CloudExportDocument[chargingSummaries]" has a null value in JSON.');
        assert(json.containsKey(r'monthlySummaries'),
            'Required key "CloudExportDocument[monthlySummaries]" is missing from JSON.');
        assert(json[r'monthlySummaries'] != null,
            'Required key "CloudExportDocument[monthlySummaries]" has a null value in JSON.');
        assert(json.containsKey(r'aiGenerations'),
            'Required key "CloudExportDocument[aiGenerations]" is missing from JSON.');
        assert(json[r'aiGenerations'] != null,
            'Required key "CloudExportDocument[aiGenerations]" has a null value in JSON.');
        assert(json.containsKey(r'subscriptions'),
            'Required key "CloudExportDocument[subscriptions]" is missing from JSON.');
        assert(json[r'subscriptions'] != null,
            'Required key "CloudExportDocument[subscriptions]" has a null value in JSON.');
        assert(json.containsKey(r'limits'),
            'Required key "CloudExportDocument[limits]" is missing from JSON.');
        assert(json[r'limits'] != null,
            'Required key "CloudExportDocument[limits]" has a null value in JSON.');
        return true;
      }());

      return CloudExportDocument(
        schemaVersion: mapValueOfType<int>(json, r'schemaVersion')!,
        exportedAt: mapDateTime(json, r'exportedAt', r'')!,
        account: UserDto.fromJson(json[r'account'])!,
        settings: CloudExportSettings.fromJson(json[r'settings'])!,
        devices: DeviceDto.listFromJson(json[r'devices']),
        dailyUsage: CloudExportDailyUsage.listFromJson(json[r'dailyUsage']),
        chargingSummaries:
            CloudExportChargingSummary.listFromJson(json[r'chargingSummaries']),
        monthlySummaries:
            CloudExportMonthlySummary.listFromJson(json[r'monthlySummaries']),
        aiGenerations:
            CloudExportAiGeneration.listFromJson(json[r'aiGenerations']),
        subscriptions:
            CloudExportSubscription.listFromJson(json[r'subscriptions']),
        limits: CloudExportLimits.fromJson(json[r'limits'])!,
      );
    }
    return null;
  }

  static List<CloudExportDocument> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportDocument>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportDocument.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportDocument> mapFromJson(dynamic json) {
    final map = <String, CloudExportDocument>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportDocument.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportDocument-objects as value to a dart map
  static Map<String, List<CloudExportDocument>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportDocument>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportDocument.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'schemaVersion',
    'exportedAt',
    'account',
    'settings',
    'devices',
    'dailyUsage',
    'chargingSummaries',
    'monthlySummaries',
    'aiGenerations',
    'subscriptions',
    'limits',
  };
}
