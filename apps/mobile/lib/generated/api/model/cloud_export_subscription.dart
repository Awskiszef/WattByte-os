//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of wattbyte_api;

class CloudExportSubscription {
  /// Returns a new [CloudExportSubscription] instance.
  CloudExportSubscription({
    required this.store,
    required this.productId,
    required this.originalTransactionId,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  CloudExportSubscriptionStoreEnum store;

  String productId;

  String originalTransactionId;

  CloudExportSubscriptionStatusEnum status;

  DateTime? expiresAt;

  DateTime createdAt;

  DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudExportSubscription &&
          other.store == store &&
          other.productId == productId &&
          other.originalTransactionId == originalTransactionId &&
          other.status == status &&
          other.expiresAt == expiresAt &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      // ignore: unnecessary_parenthesis
      (store.hashCode) +
      (productId.hashCode) +
      (originalTransactionId.hashCode) +
      (status.hashCode) +
      (expiresAt == null ? 0 : expiresAt!.hashCode) +
      (createdAt.hashCode) +
      (updatedAt.hashCode);

  @override
  String toString() =>
      'CloudExportSubscription[store=$store, productId=$productId, originalTransactionId=$originalTransactionId, status=$status, expiresAt=$expiresAt, createdAt=$createdAt, updatedAt=$updatedAt]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json[r'store'] = this.store;
    json[r'productId'] = this.productId;
    json[r'originalTransactionId'] = this.originalTransactionId;
    json[r'status'] = this.status;
    if (this.expiresAt != null) {
      json[r'expiresAt'] = this.expiresAt!.toUtc().toIso8601String();
    } else {
      json[r'expiresAt'] = null;
    }
    json[r'createdAt'] = this.createdAt.toUtc().toIso8601String();
    json[r'updatedAt'] = this.updatedAt.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [CloudExportSubscription] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static CloudExportSubscription? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        assert(json.containsKey(r'store'),
            'Required key "CloudExportSubscription[store]" is missing from JSON.');
        assert(json[r'store'] != null,
            'Required key "CloudExportSubscription[store]" has a null value in JSON.');
        assert(json.containsKey(r'productId'),
            'Required key "CloudExportSubscription[productId]" is missing from JSON.');
        assert(json[r'productId'] != null,
            'Required key "CloudExportSubscription[productId]" has a null value in JSON.');
        assert(json.containsKey(r'originalTransactionId'),
            'Required key "CloudExportSubscription[originalTransactionId]" is missing from JSON.');
        assert(json[r'originalTransactionId'] != null,
            'Required key "CloudExportSubscription[originalTransactionId]" has a null value in JSON.');
        assert(json.containsKey(r'status'),
            'Required key "CloudExportSubscription[status]" is missing from JSON.');
        assert(json[r'status'] != null,
            'Required key "CloudExportSubscription[status]" has a null value in JSON.');
        assert(json.containsKey(r'expiresAt'),
            'Required key "CloudExportSubscription[expiresAt]" is missing from JSON.');
        assert(json.containsKey(r'createdAt'),
            'Required key "CloudExportSubscription[createdAt]" is missing from JSON.');
        assert(json[r'createdAt'] != null,
            'Required key "CloudExportSubscription[createdAt]" has a null value in JSON.');
        assert(json.containsKey(r'updatedAt'),
            'Required key "CloudExportSubscription[updatedAt]" is missing from JSON.');
        assert(json[r'updatedAt'] != null,
            'Required key "CloudExportSubscription[updatedAt]" has a null value in JSON.');
        return true;
      }());

      return CloudExportSubscription(
        store: CloudExportSubscriptionStoreEnum.fromJson(json[r'store'])!,
        productId: mapValueOfType<String>(json, r'productId')!,
        originalTransactionId:
            mapValueOfType<String>(json, r'originalTransactionId')!,
        status: CloudExportSubscriptionStatusEnum.fromJson(json[r'status'])!,
        expiresAt: mapDateTime(json, r'expiresAt', r''),
        createdAt: mapDateTime(json, r'createdAt', r'')!,
        updatedAt: mapDateTime(json, r'updatedAt', r'')!,
      );
    }
    return null;
  }

  static List<CloudExportSubscription> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSubscription>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSubscription.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, CloudExportSubscription> mapFromJson(dynamic json) {
    final map = <String, CloudExportSubscription>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = CloudExportSubscription.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of CloudExportSubscription-objects as value to a dart map
  static Map<String, List<CloudExportSubscription>> mapListFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final map = <String, List<CloudExportSubscription>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = CloudExportSubscription.listFromJson(
          entry.value,
          growable: growable,
        );
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'store',
    'productId',
    'originalTransactionId',
    'status',
    'expiresAt',
    'createdAt',
    'updatedAt',
  };
}

enum CloudExportSubscriptionStoreEnum {
  appStore._(r'app_store'),
  play._(r'play'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSubscriptionStoreEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSubscriptionStoreEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSubscriptionStoreEnum? fromJson(dynamic value) =>
      CloudExportSubscriptionStoreEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [CloudExportSubscriptionStoreEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSubscriptionStoreEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSubscriptionStoreEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSubscriptionStoreEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSubscriptionStoreEnum] to String,
/// and [decode] dynamic data back to [CloudExportSubscriptionStoreEnum].
class CloudExportSubscriptionStoreEnumTypeTransformer {
  factory CloudExportSubscriptionStoreEnumTypeTransformer() =>
      _instance ??= const CloudExportSubscriptionStoreEnumTypeTransformer._();

  const CloudExportSubscriptionStoreEnumTypeTransformer._();

  String encode(CloudExportSubscriptionStoreEnum data) => data._value;

  /// Returns the instance of [CloudExportSubscriptionStoreEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSubscriptionStoreEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSubscriptionStoreEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'app_store':
          return CloudExportSubscriptionStoreEnum.appStore;
        case r'play':
          return CloudExportSubscriptionStoreEnum.play;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSubscriptionStoreEnumTypeTransformer? _instance;
}

enum CloudExportSubscriptionStatusEnum {
  active._(r'active'),
  grace._(r'grace'),
  expired._(r'expired'),
  revoked._(r'revoked'),
  ;

  /// Instantiate a new enum with the provided value.
  const CloudExportSubscriptionStatusEnum._(this._value);

  /// The underlying value of this enum member.
  final String _value;

  @override
  String toString() => _value;

  /// Encodes this enum as a value suitable for JSON.
  String toJson() => _value;

  /// Returns the instance of [CloudExportSubscriptionStatusEnum] that was successfully decoded
  /// from the passed [value] on success, null otherwise.
  static CloudExportSubscriptionStatusEnum? fromJson(dynamic value) =>
      CloudExportSubscriptionStatusEnumTypeTransformer().decode(value);

  /// Returns a [List] containing instances of [CloudExportSubscriptionStatusEnum]
  /// that were successfully decoded from the passed [JSON][json].
  static List<CloudExportSubscriptionStatusEnum> listFromJson(
    dynamic json, {
    bool growable = false,
  }) {
    final result = <CloudExportSubscriptionStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = CloudExportSubscriptionStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [CloudExportSubscriptionStatusEnum] to String,
/// and [decode] dynamic data back to [CloudExportSubscriptionStatusEnum].
class CloudExportSubscriptionStatusEnumTypeTransformer {
  factory CloudExportSubscriptionStatusEnumTypeTransformer() =>
      _instance ??= const CloudExportSubscriptionStatusEnumTypeTransformer._();

  const CloudExportSubscriptionStatusEnumTypeTransformer._();

  String encode(CloudExportSubscriptionStatusEnum data) => data._value;

  /// Returns the instance of [CloudExportSubscriptionStatusEnum] that was successfully decoded
  /// from the passed [data] value on success, null otherwise.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  CloudExportSubscriptionStatusEnum? decode(dynamic data,
      {bool allowNull = true}) {
    if (data is CloudExportSubscriptionStatusEnum) {
      return data;
    }
    if (data != null) {
      switch (data) {
        case r'active':
          return CloudExportSubscriptionStatusEnum.active;
        case r'grace':
          return CloudExportSubscriptionStatusEnum.grace;
        case r'expired':
          return CloudExportSubscriptionStatusEnum.expired;
        case r'revoked':
          return CloudExportSubscriptionStatusEnum.revoked;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// The singleton instance of this transformer.
  static CloudExportSubscriptionStatusEnumTypeTransformer? _instance;
}
