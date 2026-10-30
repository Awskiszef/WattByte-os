//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class TokenPair {
  /// Returns a new [TokenPair] instance.
  TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
  });

  String accessToken;

  String refreshToken;

  /// Minimum value: 0
  int expiresIn;

  TokenPairTokenTypeEnum tokenType;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenPair &&
          other.accessToken == accessToken &&
          other.refreshToken == refreshToken &&
          other.expiresIn == expiresIn &&
          other.tokenType == tokenType;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (accessToken.hashCode) +
      (refreshToken.hashCode) +
      (expiresIn.hashCode) +
      (tokenType.hashCode);

  @override
  String toString() =>
      'TokenPair[accessToken=$accessToken, refreshToken=$refreshToken, expiresIn=$expiresIn, tokenType=$tokenType]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'accessToken'] = this.accessToken;
    json[r'refreshToken'] = this.refreshToken;
    json[r'expiresIn'] = this.expiresIn;
    json[r'tokenType'] = this.tokenType;
    return json;
  }

  /// Returns a new [TokenPair] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static TokenPair? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'accessToken'),
            'Required key "TokenPair[accessToken]" is missing from JSON.');
        assert(json[r'accessToken'] != null,
            'Required key "TokenPair[accessToken]" has a null value in JSON.');
        assert(json.containsKey(r'refreshToken'),
            'Required key "TokenPair[refreshToken]" is missing from JSON.');
        assert(json[r'refreshToken'] != null,
            'Required key "TokenPair[refreshToken]" has a null value in JSON.');
        assert(json.containsKey(r'expiresIn'),
            'Required key "TokenPair[expiresIn]" is missing from JSON.');
        assert(json[r'expiresIn'] != null,
            'Required key "TokenPair[expiresIn]" has a null value in JSON.');
        assert(json.containsKey(r'tokenType'),
            'Required key "TokenPair[tokenType]" is missing from JSON.');
        assert(json[r'tokenType'] != null,
            'Required key "TokenPair[tokenType]" has a null value in JSON.');
        return true;
      }());

      return TokenPair(
        accessToken: mapValueOfType<String>(json, r'accessToken')!,
        refreshToken: mapValueOfType<String>(json, r'refreshToken')!,
        expiresIn: mapValueOfType<int>(json, r'expiresIn')!,
        tokenType: TokenPairTokenTypeEnum.fromJson(json[r'tokenType'])!,
      );
    }
    return null;
  }

  static List<TokenPair> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <TokenPair>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TokenPair.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, TokenPair> mapFromJson(dynamic json) {
    final map = <String, TokenPair>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = TokenPair.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of TokenPair-objects as value to a dart map
  static Map<String, List<TokenPair>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<TokenPair>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = TokenPair.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'accessToken',
    'refreshToken',
    'expiresIn',
    'tokenType',
  };
}

enum TokenPairTokenTypeEnum {
  bearer._(r'Bearer'),
  unknownDefaultOpenApi._(r'unknown_default_open_api'),
  ;

  /// Instantiate a new enum with the provided value.
  const TokenPairTokenTypeEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [TokenPairTokenTypeEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static TokenPairTokenTypeEnum? fromJson(dynamic value) =>
      TokenPairTokenTypeEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [TokenPairTokenTypeEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<TokenPairTokenTypeEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <TokenPairTokenTypeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = TokenPairTokenTypeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [TokenPairTokenTypeEnum] to String,
/// and [decode] dynamic data back to [TokenPairTokenTypeEnum].
class TokenPairTokenTypeEnumTypeTransformer {
  factory TokenPairTokenTypeEnumTypeTransformer() =>
      _instance ??= const TokenPairTokenTypeEnumTypeTransformer._();

  const TokenPairTokenTypeEnumTypeTransformer._();

  String encode(TokenPairTokenTypeEnum data) => data._value;

  /// Returns the instance of [TokenPairTokenTypeEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  TokenPairTokenTypeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data is TokenPairTokenTypeEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'Bearer':
          return TokenPairTokenTypeEnum.bearer;
        case r'unknown_default_open_api':
          return TokenPairTokenTypeEnum.unknownDefaultOpenApi;
        default:
          // A member this client does not know (added by a newer server).
          return TokenPairTokenTypeEnum.unknownDefaultOpenApi;
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static TokenPairTokenTypeEnumTypeTransformer? _instance;
}
