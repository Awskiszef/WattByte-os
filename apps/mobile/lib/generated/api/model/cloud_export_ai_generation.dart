//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportAiGeneration {
  /// Returns a new [CloudExportAiGeneration] instance.
  CloudExportAiGeneration({
    required this.task,
    required this.mode,
    required this.provider,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.estimatedCostUsd,
    required this.latencyMs,
    required this.createdAt,
  });

  String task;

  String mode;

  String provider;

  String model;

  /// Minimum value: 0
  int inputTokens;

  /// Minimum value: 0
  int outputTokens;

  /// Minimum value: 0
  num estimatedCostUsd;

  /// Minimum value: 0
  int latencyMs;

  DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportAiGeneration &&
          other.task == task &&
          other.mode == mode &&
          other.provider == provider &&
          other.model == model &&
          other.inputTokens == inputTokens &&
          other.outputTokens == outputTokens &&
          other.estimatedCostUsd == estimatedCostUsd &&
          other.latencyMs == latencyMs &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (task.hashCode) +
      (mode.hashCode) +
      (provider.hashCode) +
      (model.hashCode) +
      (inputTokens.hashCode) +
      (outputTokens.hashCode) +
      (estimatedCostUsd.hashCode) +
      (latencyMs.hashCode) +
      (createdAt.hashCode);

  @override
  String toString() =>
      'CloudExportAiGeneration[task=$task, mode=$mode, provider=$provider, model=$model, inputTokens=$inputTokens, outputTokens=$outputTokens, estimatedCostUsd=$estimatedCostUsd, latencyMs=$latencyMs, createdAt=$createdAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'task'] = this.task;
    json[r'mode'] = this.mode;
    json[r'provider'] = this.provider;
    json[r'model'] = this.model;
    json[r'inputTokens'] = this.inputTokens;
    json[r'outputTokens'] = this.outputTokens;
    json[r'estimatedCostUsd'] = this.estimatedCostUsd;
    json[r'latencyMs'] = this.latencyMs;
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [CloudExportAiGeneration] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportAiGeneration? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'task'),
            'Required key "CloudExportAiGeneration[task]" is missing from JSON.');
        assert(json[r'task'] != null,
            'Required key "CloudExportAiGeneration[task]" has a null value in JSON.');
        assert(json.containsKey(r'mode'),
            'Required key "CloudExportAiGeneration[mode]" is missing from JSON.');
        assert(json[r'mode'] != null,
            'Required key "CloudExportAiGeneration[mode]" has a null value in JSON.');
        assert(json.containsKey(r'provider'),
            'Required key "CloudExportAiGeneration[provider]" is missing from JSON.');
        assert(json[r'provider'] != null,
            'Required key "CloudExportAiGeneration[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'),
            'Required key "CloudExportAiGeneration[model]" is missing from JSON.');
        assert(json[r'model'] != null,
            'Required key "CloudExportAiGeneration[model]" has a null value in JSON.');
        assert(json.containsKey(r'inputTokens'),
            'Required key "CloudExportAiGeneration[inputTokens]" is missing from JSON.');
        assert(json[r'inputTokens'] != null,
            'Required key "CloudExportAiGeneration[inputTokens]" has a null value in JSON.');
        assert(json.containsKey(r'outputTokens'),
            'Required key "CloudExportAiGeneration[outputTokens]" is missing from JSON.');
        assert(json[r'outputTokens'] != null,
            'Required key "CloudExportAiGeneration[outputTokens]" has a null value in JSON.');
        assert(json.containsKey(r'estimatedCostUsd'),
            'Required key "CloudExportAiGeneration[estimatedCostUsd]" is missing from JSON.');
        assert(json[r'estimatedCostUsd'] != null,
            'Required key "CloudExportAiGeneration[estimatedCostUsd]" has a null value in JSON.');
        assert(json.containsKey(r'latencyMs'),
            'Required key "CloudExportAiGeneration[latencyMs]" is missing from JSON.');
        assert(json[r'latencyMs'] != null,
            'Required key "CloudExportAiGeneration[latencyMs]" has a null value in JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "CloudExportAiGeneration[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "CloudExportAiGeneration[createdAt]" has a null value in JSON.');
        return true;
      }());

      return CloudExportAiGeneration(
        task: mapValueOfType<String>(json, r'task')!,
        mode: mapValueOfType<String>(json, r'mode')!,
        provider: mapValueOfType<String>(json, r'provider')!,
        model: mapValueOfType<String>(json, r'model')!,
        inputTokens: mapValueOfType<int>(json, r'inputTokens')!,
        outputTokens: mapValueOfType<int>(json, r'outputTokens')!,
        estimatedCostUsd: num.parse('${json[r'estimatedCostUsd']}'),
        latencyMs: mapValueOfType<int>(json, r'latencyMs')!,
        createdAt: mapDateTime(json, r'createdAt', r'')!,
      );
    }
    return null;
  }

  static List<CloudExportAiGeneration> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportAiGeneration>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportAiGeneration.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportAiGeneration> mapFromJson(dynamic json) {
    final map = <String, CloudExportAiGeneration>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportAiGeneration.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportAiGeneration-objects as value to a dart map
  static Map<String, List<CloudExportAiGeneration>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportAiGeneration>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportAiGeneration.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'task',
    'mode',
    'provider',
    'model',
    'inputTokens',
    'outputTokens',
    'estimatedCostUsd',
    'latencyMs',
    'createdAt',
  };
}
