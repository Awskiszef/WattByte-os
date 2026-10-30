import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/error_log.dart';
import '../api/api_failure.dart' show guarded;
import '../features/auth/presentation/auth_controller.dart'
    show apiConfigProvider, apiFactoryProvider;
import '../generated/api/api.dart' as generated;
import '../providers.dart' show clockProvider, prefsProvider;
import 'app_config.dart';
import 'feature_flags.dart';

/// The build's configuration (`APP_ENV`, `API_BASE_URL`, `PRIVACY_POLICY_URL`,
/// `FEATURE_*`). Tests override it with `AppConfig.fromDefines(...)`.
final appConfigProvider = Provider<AppConfig>((_) => AppConfig.fromEnvironment);

/// The build-time flag defaults.
final buildFeatureFlagsProvider = Provider<FeatureFlags>(
    (ref) => ref.watch(appConfigProvider).featureDefaults);

/// THE SEAM for the remote fetch. Override this provider with a function that
/// calls `GET /api/v1/config` (public, no token needed) and returns
/// [ServerFeatureConfig.fromServerJson] of the body, or `null` when the server
/// cannot be reached. Throwing an [Exception] is treated like `null` and
/// reported to the local error log. While it is `null` (the default, no
/// generated client call yet) the app runs on the cache or the build defaults.
typedef ServerConfigFetcher = Future<ServerFeatureConfig?> Function();

///
/// The default (F-04) asks the build's own API when there is one: `GET /api/v1/config`, public, through the same client and
/// timeout rules as every other call. A build without an API address has nothing to ask.
final serverConfigFetcherProvider = Provider<ServerConfigFetcher?>((ref) {
  final api = ref.watch(apiConfigProvider);
  if (!api.isConfigured) return null;
  final apis = ref.watch(apiFactoryProvider);
  final clock = ref.watch(clockProvider);
  return () async {
    final dto = await guarded(
        () => generated.ConfigApi(apis.anonymous()).apiV1ConfigGet());
    return dto == null
        ? null
        : ServerFeatureConfig.fromServerJson(
            // Through JSON text: the generated toJson() keeps nested model objects, the parser wants plain maps.
            jsonDecode(jsonEncode(dto)),
            fetchedAt: clock());
  };
});

/// What [ServerConfigNotifier.refresh] did.
enum ServerConfigRefresh {
  /// A new configuration was received, stored and is now in effect.
  updated,

  /// The server could not be reached (or answered nonsense); the cached or
  /// default configuration stays in effect.
  unavailable,

  /// No [serverConfigFetcherProvider] is wired yet.
  noFetcher,
}

/// SharedPreferences slot of the last server configuration.
const String kServerConfigCacheKey = 'wb.serverConfig.v1';

/// Reads and writes the cached server configuration. Plain functions over a
/// [SharedPreferences] so tests need no provider.
class ServerConfigCache {
  const ServerConfigCache(this._prefs);

  final SharedPreferences _prefs;

  /// The last stored configuration, or `null` when none was ever stored or the
  /// stored text is unreadable (reported, then treated as "never fetched").
  ServerFeatureConfig? read() {
    final raw = _prefs.getString(kServerConfigCacheKey);
    if (raw == null) return null;
    try {
      return ServerFeatureConfig.decodeCache(raw);
    } on FormatException catch (e, st) {
      reportError(e, st, 'server config cache');
      return null;
    }
  }

  Future<bool> write(ServerFeatureConfig config) =>
      _prefs.setString(kServerConfigCacheKey, config.encodeCache());
}

/// The last server configuration the app knows: loaded from the cache when the
/// provider is first read, replaced by every successful [refresh]. `null`
/// means "never fetched".
class ServerConfigNotifier extends Notifier<ServerFeatureConfig?> {
  bool _disposed = false;
  Future<ServerConfigRefresh>? _inFlight;

  @override
  ServerFeatureConfig? build() {
    ref.onDispose(() => _disposed = true);
    final cached = ServerConfigCache(ref.watch(prefsProvider)).read();
    if (ref.read(serverConfigFetcherProvider) != null) {
      // The first read starts one refresh; the cache serves until it lands.
      unawaited(Future<void>.microtask(refresh));
    }
    return cached;
  }

  /// Fetches the server configuration through [serverConfigFetcherProvider].
  /// Concurrent calls share one fetch. A failed fetch leaves the cached
  /// configuration (or none) in effect.
  Future<ServerConfigRefresh> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  DateTime? _lastAttempt;

  /// [refresh] unless one was made within [every] (the foreground calls this on every resume; a kill switch should reach
  /// the app within minutes, not hammer the server).
  Future<ServerConfigRefresh> refreshIfStale(
      {Duration every = const Duration(minutes: 15)}) {
    final now = ref.read(clockProvider)();
    final last = _lastAttempt;
    if (last != null && now.difference(last) < every) {
      return Future.value(ServerConfigRefresh.unavailable);
    }
    _lastAttempt = now;
    return refresh();
  }

  Future<ServerConfigRefresh> _refresh() async {
    if (_disposed) return ServerConfigRefresh.unavailable;
    final fetch = ref.read(serverConfigFetcherProvider);
    if (fetch == null) return ServerConfigRefresh.noFetcher;
    final cache = ServerConfigCache(ref.read(prefsProvider));
    final ServerFeatureConfig? fresh;
    try {
      fresh = await fetch();
    } on Exception catch (e, st) {
      reportError(e, st, 'server config');
      return ServerConfigRefresh.unavailable;
    }
    if (fresh == null || _disposed) return ServerConfigRefresh.unavailable;
    if (!await cache.write(fresh)) {
      reportError(StateError('server config could not be cached'), null,
          'server config');
    }
    if (_disposed) return ServerConfigRefresh.unavailable;
    state = fresh;
    return ServerConfigRefresh.updated;
  }
}

final serverConfigProvider =
    NotifierProvider<ServerConfigNotifier, ServerFeatureConfig?>(
        ServerConfigNotifier.new);

/// The flags the UI and the services obey: build AND server, see
/// [mergeFeatureFlags].
final featureFlagsProvider = Provider<FeatureFlags>((ref) => mergeFeatureFlags(
      build: ref.watch(buildFeatureFlagsProvider),
      server: ref.watch(serverConfigProvider),
    ));

/// The server's daily AI limits, or `null` until the server has told us.
/// Plan limits are never hardcoded in the app.
final aiDailyLimitsProvider = Provider<AiDailyLimits?>(
    (ref) => ref.watch(serverConfigProvider)?.aiDailyLimits);
