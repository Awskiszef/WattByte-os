import 'dart:convert';

import 'app_environment.dart';

/// The three switches the app understands. The same shape is used for the
/// build defaults, for the server's `features` object (`GET /api/v1/config`)
/// and for the effective result of [mergeFeatureFlags].
class FeatureFlags {
  const FeatureFlags({
    required this.ai,
    required this.subscriptions,
    required this.cloudSync,
  });

  final bool ai;
  final bool subscriptions;
  final bool cloudSync;

  /// What a build ships with when no `FEATURE_*` define is given.
  static const FeatureFlags builtInDefaults = FeatureFlags(
    ai: true,
    subscriptions: false,
    cloudSync: true,
  );

  /// This build's flags: `--dart-define=FEATURE_AI / FEATURE_SUBSCRIPTIONS /
  /// FEATURE_CLOUD_SYNC`, falling back to [builtInDefaults].
  static final FeatureFlags buildDefaults = FlagDefines.fromEnvironment.flags;

  FeatureFlags copyWith({bool? ai, bool? subscriptions, bool? cloudSync}) =>
      FeatureFlags(
        ai: ai ?? this.ai,
        subscriptions: subscriptions ?? this.subscriptions,
        cloudSync: cloudSync ?? this.cloudSync,
      );

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      other.ai == ai &&
      other.subscriptions == subscriptions &&
      other.cloudSync == cloudSync;

  @override
  int get hashCode => Object.hash(ai, subscriptions, cloudSync);

  @override
  String toString() =>
      'FeatureFlags(ai: $ai, subscriptions: $subscriptions, cloudSync: $cloudSync)';
}

/// The raw `--dart-define` strings behind [FeatureFlags.buildDefaults].
///
/// Kept separate (and constructible in tests) because `String.fromEnvironment`
/// is fixed at compile time. Accepted spellings, case-insensitive: `true`,
/// `false`, `1`, `0`, `yes`, `no`, `on`, `off`. Unset means "use the default";
/// anything else also uses the default and is listed in [problems], so a typo
/// is visible instead of silently flipping a feature.
class FlagDefines {
  const FlagDefines(
      {this.ai = '', this.subscriptions = '', this.cloudSync = ''});

  static const FlagDefines fromEnvironment = FlagDefines(
    ai: String.fromEnvironment('FEATURE_AI'),
    subscriptions: String.fromEnvironment('FEATURE_SUBSCRIPTIONS'),
    cloudSync: String.fromEnvironment('FEATURE_CLOUD_SYNC'),
  );

  final String ai;
  final String subscriptions;
  final String cloudSync;

  /// `true` / `false` for a recognised spelling, `null` for unset or unrecognised.
  static bool? parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'true' || '1' || 'yes' || 'on':
        return true;
      case 'false' || '0' || 'no' || 'off':
        return false;
      default:
        return null;
    }
  }

  FeatureFlags get flags => FeatureFlags(
        ai: parse(ai) ?? FeatureFlags.builtInDefaults.ai,
        subscriptions:
            parse(subscriptions) ?? FeatureFlags.builtInDefaults.subscriptions,
        cloudSync: parse(cloudSync) ?? FeatureFlags.builtInDefaults.cloudSync,
      );

  /// One line per define that is set but not a recognised boolean.
  List<String> get problems => [
        for (final (name, raw) in [
          ('FEATURE_AI', ai),
          ('FEATURE_SUBSCRIPTIONS', subscriptions),
          ('FEATURE_CLOUD_SYNC', cloudSync),
        ])
          if (raw.trim().isNotEmpty && parse(raw) == null)
            '$name is not a boolean (use true or false); the default applies',
      ];
}

/// Daily AI generations per UTC day as configured on the server. The app never
/// hardcodes plan limits: it shows these or nothing.
class AiDailyLimits {
  const AiDailyLimits({required this.free, required this.premium});

  final int free;
  final int premium;

  @override
  bool operator ==(Object other) =>
      other is AiDailyLimits && other.free == free && other.premium == premium;

  @override
  int get hashCode => Object.hash(free, premium);

  @override
  String toString() => 'AiDailyLimits(free: $free, premium: $premium)';
}

/// The server's public runtime configuration (`GET /api/v1/config`, schema
/// `AppConfigDto` in packages/contracts) plus the moment the app received it.
///
/// Parsing is strict about everything that decides behaviour: a missing or
/// mistyped flag or limit makes the whole document unusable rather than
/// defaulting a switch. Unknown extra fields are ignored so a newer server
/// does not break an older app.
class ServerFeatureConfig {
  const ServerFeatureConfig({
    required this.features,
    required this.aiDailyLimits,
    required this.fetchedAt,
    this.environment,
    this.minimumAppVersion = const {},
  });

  /// Bumped when the cache layout changes; an unknown version is discarded.
  static const int cacheVersion = 1;

  /// The server's own flags, before they are combined with the build's.
  final FeatureFlags features;
  final AiDailyLimits aiDailyLimits;

  /// When the app received this document (not a server timestamp).
  final DateTime fetchedAt;

  /// The deployment the server says it is (informational; unknown names are `null`).
  final AppEnvironment? environment;

  /// The oldest app version the server still serves, by platform (`android`, `ios`); empty = no minimum (F-11).
  final Map<String, String> minimumAppVersion;

  /// Reads the body of `GET /api/v1/config` (or the generated client's
  /// `AppConfigDto.toJson()`). Throws [FormatException] when it is malformed.
  factory ServerFeatureConfig.fromServerJson(
    Object? json, {
    required DateTime fetchedAt,
  }) {
    final root = _object(json, 'config');
    final features = _object(root['features'], 'features');
    final limits =
        _object(_object(root['ai'], 'ai')['dailyLimits'], 'ai.dailyLimits');
    final env = root['environment'];
    return ServerFeatureConfig(
      features: FeatureFlags(
        ai: _bool(features['ai'], 'features.ai'),
        subscriptions:
            _bool(features['subscriptions'], 'features.subscriptions'),
        cloudSync: _bool(features['cloudSync'], 'features.cloudSync'),
      ),
      aiDailyLimits: AiDailyLimits(
        free: _count(limits['free'], 'ai.dailyLimits.free'),
        premium: _count(limits['premium'], 'ai.dailyLimits.premium'),
      ),
      fetchedAt: fetchedAt,
      environment: env is String ? AppEnvironment.tryParse(env) : null,
      minimumAppVersion: _minimumVersions(root['minimumAppVersion']),
    );
  }

  /// Only well-formed `MAJOR.MINOR.PATCH` strings count; anything else is ignored rather than rejecting the document.
  static Map<String, String> _minimumVersions(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final platform in const ['android', 'ios'])
        if (v[platform] is String &&
            RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$')
                .hasMatch(v[platform] as String))
          platform: v[platform] as String,
    };
  }

  /// [fromServerJson], but `null` instead of an exception.
  static ServerFeatureConfig? tryParseServerJson(
    Object? json, {
    required DateTime fetchedAt,
  }) {
    try {
      return ServerFeatureConfig.fromServerJson(json, fetchedAt: fetchedAt);
    } on FormatException {
      return null;
    }
  }

  /// The document stored in SharedPreferences: the server's shape plus
  /// `fetchedAt` and a layout `version`. Contains no secret and nothing
  /// account-specific.
  String encodeCache() => jsonEncode({
        'version': cacheVersion,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        if (environment != null) 'environment': environment!.wireName,
        if (minimumAppVersion.isNotEmpty)
          'minimumAppVersion': minimumAppVersion,
        'features': {
          'ai': features.ai,
          'subscriptions': features.subscriptions,
          'cloudSync': features.cloudSync,
        },
        'ai': {
          'dailyLimits': {
            'free': aiDailyLimits.free,
            'premium': aiDailyLimits.premium,
          },
        },
      });

  /// Reads what [encodeCache] wrote. Throws [FormatException] for anything else
  /// (truncated, hand-edited, written by a different layout version).
  factory ServerFeatureConfig.decodeCache(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FormatException('config cache is not JSON: ${e.message}');
    }
    final root = _object(json, 'cache');
    if (root['version'] != cacheVersion) {
      throw FormatException(
          'config cache version ${root['version']} is not $cacheVersion');
    }
    final at = root['fetchedAt'];
    final fetchedAt = at is String ? DateTime.tryParse(at) : null;
    if (fetchedAt == null) {
      throw const FormatException('config cache has no valid fetchedAt');
    }
    return ServerFeatureConfig.fromServerJson(root, fetchedAt: fetchedAt);
  }

  @override
  bool operator ==(Object other) =>
      other is ServerFeatureConfig &&
      other.features == features &&
      other.aiDailyLimits == aiDailyLimits &&
      other.fetchedAt == fetchedAt &&
      other.environment == environment &&
      _sameMap(other.minimumAppVersion, minimumAppVersion);

  static bool _sameMap(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
      features,
      aiDailyLimits,
      fetchedAt,
      environment,
      Object.hashAll(
          minimumAppVersion.entries.map((e) => '${e.key}${e.value}')));

  @override
  String toString() =>
      'ServerFeatureConfig($features, $aiDailyLimits, fetchedAt: $fetchedAt)';

  static Map<String, Object?> _object(Object? v, String what) {
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.cast<String, Object?>();
    throw FormatException('$what is not an object');
  }

  static bool _bool(Object? v, String what) {
    if (v is bool) return v;
    throw FormatException('$what is not a boolean');
  }

  static int _count(Object? v, String what) {
    if (v is int && v >= 0) return v;
    throw FormatException('$what is not a non-negative integer');
  }
}

/// The effective flags: a feature is on only when the build allows it AND the
/// server allows it.
///
/// [server] is the last server configuration the app knows: the one just
/// fetched, or - when the server is unreachable - the cached one. When there is
/// none (never fetched), the build default decides for `ai` and `cloudSync`
/// and `subscriptions` stays off, because a paid feature must never switch on
/// before the server has said so.
FeatureFlags mergeFeatureFlags({
  required FeatureFlags build,
  ServerFeatureConfig? server,
}) {
  if (server == null) {
    return FeatureFlags(
      ai: build.ai,
      subscriptions: false,
      cloudSync: build.cloudSync,
    );
  }
  return FeatureFlags(
    ai: build.ai && server.features.ai,
    subscriptions: build.subscriptions && server.features.subscriptions,
    cloudSync: build.cloudSync && server.features.cloudSync,
  );
}

/// Which server configuration applies: the freshly fetched one when there is
/// one, otherwise the last cached one, otherwise none.
ServerFeatureConfig? effectiveServerConfig({
  ServerFeatureConfig? fresh,
  ServerFeatureConfig? cached,
}) =>
    fresh ?? cached;
