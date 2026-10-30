// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_providers.dart';
import 'package:wattbyte/config/feature_flags.dart';
import 'package:wattbyte/core/error_log.dart';
import 'package:wattbyte/providers.dart' show prefsProvider;

final _t0 = DateTime.utc(2026, 10, 13, 8);
final _t1 = DateTime.utc(2026, 10, 14, 9);

/// All eight flag combinations.
final _all = [
  for (final ai in [false, true])
    for (final sub in [false, true])
      for (final cloud in [false, true])
        FeatureFlags(ai: ai, subscriptions: sub, cloudSync: cloud),
];

ServerFeatureConfig _server(
  FeatureFlags features, {
  int free = 5,
  int premium = 100,
  DateTime? at,
}) =>
    ServerFeatureConfig(
      features: features,
      aiDailyLimits: AiDailyLimits(free: free, premium: premium),
      fetchedAt: at ?? _t0,
      environment: AppEnvironment.production,
    );

const _allOn = FeatureFlags(ai: true, subscriptions: true, cloudSync: true);
const _allOff = FeatureFlags(ai: false, subscriptions: false, cloudSync: false);

/// The body of `GET /api/v1/config` as `AppConfigDto` describes it.
Map<String, Object?> _body({
  Object? ai = true,
  Object? subscriptions = false,
  Object? cloudSync = true,
  Object? free = 5,
  Object? premium = 100,
  String environment = 'production',
}) =>
    {
      'environment': environment,
      'features': {
        'ai': ai,
        'subscriptions': subscriptions,
        'cloudSync': cloudSync
      },
      'ai': {
        'dailyLimits': {'free': free, 'premium': premium},
      },
    };

void main() {
  group('FlagDefines (the FEATURE_* dart-defines)', () {
    test('built-in defaults: ai on, subscriptions off, cloudSync on', () {
      expect(FeatureFlags.builtInDefaults,
          const FeatureFlags(ai: true, subscriptions: false, cloudSync: true));
      expect(const FlagDefines().flags, FeatureFlags.builtInDefaults);
      expect(const FlagDefines().problems, isEmpty);
    });

    test('accepted spellings', () {
      for (final yes in ['true', 'TRUE', ' True ', '1', 'yes', 'on']) {
        expect(FlagDefines.parse(yes), isTrue, reason: yes);
      }
      for (final no in ['false', 'False', '0', 'no', 'OFF']) {
        expect(FlagDefines.parse(no), isFalse, reason: no);
      }
      for (final unknown in ['', ' ', 'maybe', 'ture', '2', 'null']) {
        expect(FlagDefines.parse(unknown), isNull, reason: unknown);
      }
    });

    test('every flag can be flipped from its default', () {
      const d = FlagDefines(ai: 'false', subscriptions: 'true', cloudSync: '0');
      expect(d.flags,
          const FeatureFlags(ai: false, subscriptions: true, cloudSync: false));
      expect(d.problems, isEmpty);
    });

    test('a typo keeps the default and is reported by name, without its value',
        () {
      const d = FlagDefines(ai: 'ture', subscriptions: '', cloudSync: 'yep');
      expect(d.flags, FeatureFlags.builtInDefaults);
      expect(d.problems, hasLength(2));
      expect(d.problems[0], startsWith('FEATURE_AI '));
      expect(d.problems[1], startsWith('FEATURE_CLOUD_SYNC '));
      expect(d.problems.join(), isNot(contains('ture')));
    });

    test('FeatureFlags.buildDefaults is the compiled-in set', () {
      // Without --dart-define=FEATURE_* this is the built-in default.
      const defined = bool.hasEnvironment('FEATURE_AI') ||
          bool.hasEnvironment('FEATURE_SUBSCRIPTIONS') ||
          bool.hasEnvironment('FEATURE_CLOUD_SYNC');
      if (!defined) {
        expect(FeatureFlags.buildDefaults, FeatureFlags.builtInDefaults);
      }
    });
  });

  group('mergeFeatureFlags', () {
    test(
        'with a server configuration a feature is on only if build AND server allow it',
        () {
      var checked = 0;
      for (final build in _all) {
        for (final features in _all) {
          final merged =
              mergeFeatureFlags(build: build, server: _server(features));
          expect(merged.ai, build.ai && features.ai,
              reason: '$build + $features');
          expect(merged.subscriptions,
              build.subscriptions && features.subscriptions,
              reason: '$build + $features');
          expect(merged.cloudSync, build.cloudSync && features.cloudSync,
              reason: '$build + $features');
          checked++;
        }
      }
      expect(checked, 64);
    });

    test('never fetched: build default for ai and cloudSync, subscriptions off',
        () {
      for (final build in _all) {
        final merged = mergeFeatureFlags(build: build);
        expect(merged.ai, build.ai, reason: '$build');
        expect(merged.cloudSync, build.cloudSync, reason: '$build');
        expect(merged.subscriptions, isFalse,
            reason: 'a paid feature needs the server: $build');
      }
      expect(mergeFeatureFlags(build: _allOn),
          const FeatureFlags(ai: true, subscriptions: false, cloudSync: true));
      expect(mergeFeatureFlags(build: _allOff), _allOff);
    });

    test('the server can switch a feature off but never on past the build', () {
      expect(
          mergeFeatureFlags(build: _allOff, server: _server(_allOn)), _allOff);
      expect(
          mergeFeatureFlags(build: _allOn, server: _server(_allOff)), _allOff);
      expect(
        mergeFeatureFlags(
            build: FeatureFlags.builtInDefaults, server: _server(_allOn)),
        FeatureFlags.builtInDefaults,
      );
    });

    test('effectiveServerConfig: fresh beats cached beats nothing', () {
      final fresh = _server(_allOn, at: _t1);
      final cached = _server(_allOff, at: _t0);
      expect(effectiveServerConfig(fresh: fresh, cached: cached), same(fresh));
      expect(effectiveServerConfig(cached: cached), same(cached));
      expect(effectiveServerConfig(fresh: fresh), same(fresh));
      expect(effectiveServerConfig(), isNull);
      // The documented combination: server unreachable, cache decides.
      expect(
        mergeFeatureFlags(
            build: _allOn,
            server: effectiveServerConfig(cached: _server(_allOff))),
        _allOff,
      );
    });
  });

  group('ServerFeatureConfig.fromServerJson', () {
    test('reads the body of GET /api/v1/config', () {
      final c = ServerFeatureConfig.fromServerJson(
        _body(
            ai: true,
            subscriptions: true,
            cloudSync: false,
            free: 4,
            premium: 250),
        fetchedAt: _t0,
      );
      expect(c.features,
          const FeatureFlags(ai: true, subscriptions: true, cloudSync: false));
      expect(c.aiDailyLimits, const AiDailyLimits(free: 4, premium: 250));
      expect(c.environment, AppEnvironment.production);
      expect(c.fetchedAt, _t0);
    });

    test('a limit of zero is valid (AI disabled for that plan)', () {
      final c = ServerFeatureConfig.fromServerJson(_body(free: 0, premium: 0),
          fetchedAt: _t0);
      expect(c.aiDailyLimits, const AiDailyLimits(free: 0, premium: 0));
    });

    test('unknown extra fields and an unknown environment are tolerated', () {
      final body = _body(environment: 'canary')..['newThing'] = {'x': 1};
      (body['features']! as Map<String, Object?>)['voice'] = true;
      final c = ServerFeatureConfig.fromServerJson(body, fetchedAt: _t0);
      expect(c.environment, isNull);
      expect(c.features.ai, isTrue);
    });

    test('anything that decides behaviour must be present and typed', () {
      final bad = <String, Object?>{
        'not an object': 'config',
        'a list': [1, 2],
        'null': null,
        'ai as string': _body(ai: 'true'),
        'subscriptions as int': _body(subscriptions: 1),
        'cloudSync null': _body(cloudSync: null),
        'negative limit': _body(free: -1),
        'fractional limit': _body(premium: 2.5),
        'limit as string': _body(free: '5'),
        'limit null': _body(premium: null),
      };
      for (final entry in bad.entries) {
        expect(
            () =>
                ServerFeatureConfig.fromServerJson(entry.value, fetchedAt: _t0),
            throwsFormatException,
            reason: entry.key);
        expect(
            ServerFeatureConfig.tryParseServerJson(entry.value, fetchedAt: _t0),
            isNull,
            reason: entry.key);
      }
      for (final path in ['features', 'ai']) {
        final body = _body()..remove(path);
        expect(() => ServerFeatureConfig.fromServerJson(body, fetchedAt: _t0),
            throwsFormatException,
            reason: 'missing $path');
      }
      final noLimits = _body()..['ai'] = <String, Object?>{};
      expect(() => ServerFeatureConfig.fromServerJson(noLimits, fetchedAt: _t0),
          throwsFormatException);
      final noFlag = _body();
      (noFlag['features']! as Map<String, Object?>).remove('subscriptions');
      expect(() => ServerFeatureConfig.fromServerJson(noFlag, fetchedAt: _t0),
          throwsFormatException);
    });

    test('error messages name the field, never a value', () {
      try {
        ServerFeatureConfig.fromServerJson(_body(ai: 'sk-live-123'),
            fetchedAt: _t0);
        fail('should throw');
      } on FormatException catch (e) {
        expect(e.message, contains('features.ai'));
        expect(e.message, isNot(contains('sk-live')));
      }
    });
  });

  group('cache (de)serialisation', () {
    test('round-trips every field exactly', () {
      for (final features in _all) {
        final original = _server(features, free: 7, premium: 321, at: _t1);
        final restored =
            ServerFeatureConfig.decodeCache(original.encodeCache());
        expect(restored, original, reason: '$features');
        expect(restored.fetchedAt.isUtc, isTrue);
      }
      final noEnv = ServerFeatureConfig(
          features: _allOn,
          aiDailyLimits: const AiDailyLimits(free: 1, premium: 2),
          fetchedAt: _t0);
      expect(ServerFeatureConfig.decodeCache(noEnv.encodeCache()), noEnv);
    });

    test('the stored document has the server shape plus fetchedAt and version',
        () {
      final json = jsonDecode(_server(_allOn, at: _t1).encodeCache())
          as Map<String, Object?>;
      expect(json['version'], ServerFeatureConfig.cacheVersion);
      expect(json['fetchedAt'], '2026-10-14T09:00:00.000Z');
      expect(json['features'],
          {'ai': true, 'subscriptions': true, 'cloudSync': true});
      expect((json['ai']! as Map)['dailyLimits'], {'free': 5, 'premium': 100});
      expect(json.keys, isNot(contains('token')));
    });

    test('unreadable caches are rejected, not guessed at', () {
      final valid =
          jsonDecode(_server(_allOn).encodeCache()) as Map<String, Object?>;
      Map<String, Object?> without(String k) => {...valid}..remove(k);
      final bad = <String, String>{
        'empty': '',
        'not json': '{"features":',
        'a list': '[]',
        'old version': jsonEncode({...valid, 'version': 0}),
        'future version': jsonEncode({...valid, 'version': 2}),
        'no version': jsonEncode(without('version')),
        'no fetchedAt': jsonEncode(without('fetchedAt')),
        'bad fetchedAt': jsonEncode({...valid, 'fetchedAt': 'yesterday'}),
        'flag not a bool': jsonEncode({
          ...valid,
          'features': {'ai': 'yes', 'subscriptions': false, 'cloudSync': true},
        }),
        'no limits': jsonEncode(without('ai')),
      };
      for (final entry in bad.entries) {
        expect(() => ServerFeatureConfig.decodeCache(entry.value),
            throwsFormatException,
            reason: entry.key);
      }
    });
  });

  group('providers', () {
    ProviderContainer container(
      SharedPreferences prefs, {
      FlagDefines build = const FlagDefines(),
      ServerConfigFetcher? fetcher,
    }) {
      final c = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        appConfigProvider
            .overrideWithValue(AppConfig.fromDefines(flags: build)),
        if (fetcher != null)
          serverConfigFetcherProvider.overrideWithValue(fetcher),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<SharedPreferences> prefsWith(
        [Map<String, Object> values = const {}]) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    Map<String, Object> cacheOf(ServerFeatureConfig c) =>
        {kServerConfigCacheKey: c.encodeCache()};

    test(
        'first launch, nothing cached, no fetcher: build defaults, subscriptions off, no limits',
        () async {
      final c = container(await prefsWith());
      expect(c.read(serverConfigProvider), isNull);
      expect(c.read(featureFlagsProvider),
          const FeatureFlags(ai: true, subscriptions: false, cloudSync: true));
      expect(c.read(aiDailyLimitsProvider), isNull);
    });

    test('the build flag switches ai and cloudSync off when nothing is known',
        () async {
      final c = container(await prefsWith(),
          build: const FlagDefines(
              ai: 'false', cloudSync: 'false', subscriptions: 'true'));
      expect(c.read(featureFlagsProvider), _allOff);
    });

    test(
        'the cached server configuration applies when the server is unreachable',
        () async {
      final cached = _server(
          const FeatureFlags(ai: false, subscriptions: true, cloudSync: true),
          free: 3,
          premium: 40);
      final c = container(await prefsWith(cacheOf(cached)),
          build: const FlagDefines(subscriptions: 'true'));
      expect(c.read(serverConfigProvider), cached);
      expect(c.read(featureFlagsProvider),
          const FeatureFlags(ai: false, subscriptions: true, cloudSync: true));
      expect(c.read(aiDailyLimitsProvider),
          const AiDailyLimits(free: 3, premium: 40));
    });

    test('a cached "on" never beats a build "off"', () async {
      final c = container(await prefsWith(cacheOf(_server(_allOn))),
          build: const FlagDefines(
              ai: 'false', subscriptions: 'false', cloudSync: 'false'));
      expect(c.read(featureFlagsProvider), _allOff);
    });

    test('an unreadable cache is reported and treated as never fetched',
        () async {
      final before = recentErrors.length;
      final c = container(await prefsWith({kServerConfigCacheKey: '{"broken'}),
          build: const FlagDefines(subscriptions: 'true'));
      expect(c.read(serverConfigProvider), isNull);
      expect(c.read(featureFlagsProvider).subscriptions, isFalse);
      expect(recentErrors.length, greaterThan(before));
      expect(recentErrors.last, contains('server config cache'));
    });

    test('without a fetcher refresh says so and changes nothing', () async {
      final c = container(await prefsWith());
      expect(await c.read(serverConfigProvider.notifier).refresh(),
          ServerConfigRefresh.noFetcher);
      expect(c.read(serverConfigProvider), isNull);
    });

    test('a successful refresh replaces the state, the flags and the cache',
        () async {
      final prefs = await prefsWith(cacheOf(_server(_allOff, at: _t0)));
      final fresh = _server(_allOn, free: 9, premium: 900, at: _t1);
      final c = container(prefs,
          build: const FlagDefines(subscriptions: 'true'),
          fetcher: () async => fresh);
      expect(c.read(featureFlagsProvider),
          _allOff); // the cache, until the fetch lands
      final flagsSeen = <FeatureFlags>[];
      c.listen(featureFlagsProvider, (_, next) => flagsSeen.add(next));

      expect(await c.read(serverConfigProvider.notifier).refresh(),
          ServerConfigRefresh.updated);
      expect(c.read(serverConfigProvider), fresh);
      expect(c.read(featureFlagsProvider), _allOn);
      expect(c.read(aiDailyLimitsProvider),
          const AiDailyLimits(free: 9, premium: 900));
      expect(flagsSeen.last, _allOn);

      // A later launch starts from what was stored.
      final next =
          container(prefs, build: const FlagDefines(subscriptions: 'true'));
      expect(next.read(serverConfigProvider), fresh);
      expect(next.read(featureFlagsProvider), _allOn);
    });

    test('an unreachable server (null) keeps the cached configuration',
        () async {
      final cached = _server(
          const FeatureFlags(ai: true, subscriptions: false, cloudSync: false));
      final prefs = await prefsWith(cacheOf(cached));
      final c = container(prefs, fetcher: () async => null);
      expect(await c.read(serverConfigProvider.notifier).refresh(),
          ServerConfigRefresh.unavailable);
      expect(c.read(serverConfigProvider), cached);
      expect(c.read(featureFlagsProvider).cloudSync, isFalse);
      expect(prefs.getString(kServerConfigCacheKey), cached.encodeCache());
    });

    test('a fetcher that throws is reported and keeps the cache', () async {
      final cached = _server(_allOn);
      final prefs = await prefsWith(cacheOf(cached));
      final before = recentErrors.length;
      final c = container(prefs,
          fetcher: () async =>
              throw const FormatException('503 feature_disabled'));
      expect(await c.read(serverConfigProvider.notifier).refresh(),
          ServerConfigRefresh.unavailable);
      expect(c.read(serverConfigProvider), cached);
      expect(recentErrors.length, greaterThan(before));
      expect(recentErrors.last, contains('[server config]'));
    });

    test('concurrent refreshes share one fetch', () async {
      var calls = 0;
      final gate = Completer<ServerFeatureConfig?>();
      final c = container(await prefsWith(), fetcher: () {
        calls++;
        return gate.future;
      });
      final notifier = c.read(serverConfigProvider.notifier);
      await Future<void>.delayed(Duration.zero); // the automatic first refresh
      final a = notifier.refresh();
      final b = notifier.refresh();
      expect(identical(a, b), isTrue);
      gate.complete(_server(_allOn));
      expect(await Future.wait([a, b]),
          [ServerConfigRefresh.updated, ServerConfigRefresh.updated]);
      expect(calls, 1);
      // Afterwards a new refresh fetches again.
      await notifier.refresh();
      expect(calls, 2);
    });

    test('with a fetcher wired, the first read starts one refresh by itself',
        () async {
      var calls = 0;
      final c = container(await prefsWith(), fetcher: () async {
        calls++;
        return _server(_allOn, free: 2, premium: 20);
      });
      expect(c.read(featureFlagsProvider).subscriptions, isFalse); // not yet
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(c.read(featureFlagsProvider).subscriptions,
          isFalse); // build default off
      expect(c.read(aiDailyLimitsProvider),
          const AiDailyLimits(free: 2, premium: 20));
    });

    test('a refresh that lands after the container is gone does nothing',
        () async {
      final prefs = await prefsWith();
      final gate = Completer<ServerFeatureConfig?>();
      final c = ProviderContainer(overrides: [
        prefsProvider.overrideWithValue(prefs),
        serverConfigFetcherProvider.overrideWithValue(() => gate.future),
      ]);
      final pending = c.read(serverConfigProvider.notifier).refresh();
      c.dispose();
      gate.complete(_server(_allOn));
      expect(await pending, ServerConfigRefresh.unavailable);
      expect(prefs.getString(kServerConfigCacheKey), isNull);
    });
  });

  group('ServerConfigCache', () {
    test('write then read', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = ServerConfigCache(prefs);
      expect(cache.read(), isNull);
      final config = _server(_allOn, at: _t1);
      expect(await cache.write(config), isTrue);
      expect(cache.read(), config);
    });
  });
}
