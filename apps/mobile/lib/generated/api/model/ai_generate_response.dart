//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class AIGenerateResponse {
  /// Returns a new [AIGenerateResponse] instance.
  AIGenerateResponse({
    required this.output,
    required this.provider,
    required this.model,
    required this.remainingToday,
  });

  AIOutput output;

  String provider;

  String model;

  /// Minimum value: 0
  int remainingToday;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AIGenerateResponse &&
          other.output == output &&
          other.provider == provider &&
          other.model == model &&
          other.remainingToday == remainingToday;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (output.hashCode) +
      (provider.hashCode) +
      (model.hashCode) +
      (remainingToday.hashCode);

  @override
  String toString() =>
      'AIGenerateResponse[output=$output, provider=$provider, model=$model, remainingToday=$remainingToday]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'output'] = this.output;
    json[r'provider'] = this.provider;
    json[r'model'] = this.model;
    json[r'remainingToday'] = this.remainingToday;
    return json;
  }

  /// Returns a new [AIGenerateResponse] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static AIGenerateResponse? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'output'),
            'Required key "AIGenerateResponse[output]" is missing from JSON.');
        assert(json[r'output'] != null,
            'Required key "AIGenerateResponse[output]" has a null value in JSON.');
        assert(json.containsKey(r'provider'),
            'Required key "AIGenerateResponse[provider]" is missing from JSON.');
        assert(json[r'provider'] != null,
            'Required key "AIGenerateResponse[provider]" has a null value in JSON.');
        assert(json.containsKey(r'model'),
            'Required key "AIGenerateResponse[model]" is missing from JSON.');
        assert(json[r'model'] != null,
            'Required key "AIGenerateResponse[model]" has a null value in JSON.');
        assert(json.containsKey(r'remainingToday'),
            'Required key "AIGenerateResponse[remainingToday]" is missing from JSON.');
        assert(json[r'remainingToday'] != null,
            'Required key "AIGenerateResponse[remainingToday]" has a null value in JSON.');
        return true;
      }());

      return AIGenerateResponse(
        output: AIOutput.fromJson(json[r'output'])!,
        provider: mapValueOfType<String>(json, r'provider')!,
        model: mapValueOfType<String>(json, r'model')!,
        remainingToday: mapValueOfType<int>(json, r'remainingToday')!,
      );
    }
    return null;
  }

  static List<AIGenerateResponse> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <AIGenerateResponse>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = AIGenerateResponse.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, AIGenerateResponse> mapFromJson(dynamic json) {
    final map = <String, AIGenerateResponse>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = AIGenerateResponse.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of AIGenerateResponse-objects as value to a dart map
  static Map<String, List<AIGenerateResponse>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<AIGenerateResponse>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = AIGenerateResponse.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'output',
    'provider',
    'model',
    'remainingToday',
  };
}
