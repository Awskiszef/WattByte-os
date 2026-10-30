// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/feature_flags.dart';
import 'package:wattbyte/config/local_only_banner.dart';
import 'package:wattbyte/config/startup.dart';
import 'package:wattbyte/config/url_rules.dart';

// Fixtures only: a made-up public host, never an address of this product.
const _publicApi = 'https://api.sample-company.io';
const _publicPolicy = 'https://policies.sample-company.io/wattbyte/privacy';

/// Whether the test run itself was started with build defines; the tests that
/// look at the compiled-in values only make sense without them.
const _hasDefines = bool.hasEnvironment('APP_ENV') ||
    bool.hasEnvironment('API_BASE_URL') ||
    bool.hasEnvironment('LOCAL_ONLY_DEV') ||
    bool.hasEnvironment('PRIVACY_POLICY_URL') ||
    bool.hasEnvironment('FEATURE_AI') ||
    bool.hasEnvironment('FEATURE_SUBSCRIPTIONS') ||
    bool.hasEnvironment('FEATURE_CLOUD_SYNC');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppEnvironment', () {
    test('names parse regardless of case and whitespace', () {
      expect(AppEnvironment.tryParse('production'), AppEnvironment.production);
      expect(AppEnvironment.tryParse(' Staging '), AppEnvironment.staging);
      expect(
          AppEnvironment.tryParse('DEVELOPMENT'), AppEnvironment.development);
      expect(AppEnvironment.tryParse('prod'), isNull);
      expect(AppEnvironment.tryParse(''), isNull);
      expect(AppEnvironment.tryParse(null), isNull);
    });

    test('unset means development, a typo means production (fail closed)', () {
      expect(AppEnvironment.resolve(''), AppEnvironment.development);
      expect(AppEnvironment.resolve('  '), AppEnvironment.development);
      expect(AppEnvironment.resolve('staging'), AppEnvironment.staging);
      expect(AppEnvironment.resolve('prod'), AppEnvironment.production);
      expect(AppEnvironment.resolve('dev'), AppEnvironment.production);
      expect(AppEnvironment.isValidDefine(''), isTrue);
      expect(AppEnvironment.isValidDefine('production'), isTrue);
      expect(AppEnvironment.isValidDefine('prod'), isFalse);
    });

    test('only development may use cleartext', () {
      expect(AppEnvironment.development.requiresHttps, isFalse);
      expect(AppEnvironment.staging.requiresHttps, isTrue);
      expect(AppEnvironment.production.requiresHttps, isTrue);
    });
  });

  group('ApiConfig per environment', () {
    ApiConfig api(String url, AppEnvironment env) =>
        ApiConfig(url, environment: env);

    test('empty address: not configured, not a problem, in every environment',
        () {
      for (final env in AppEnvironment.values) {
        final c = api('', env);
        expect(c.isConfigured, isFalse, reason: env.name);
        expect(c.baseUrl, isEmpty);
        expect(c.problem, isNull);
        expect(api('   ', env).isConfigured, isFalse);
      }
      // The default constructor (all existing call sites) is development.
      expect(const ApiConfig('').isConfigured, isFalse);
      expect(const ApiConfig('').environment, AppEnvironment.development);
    });

    test('development accepts http and https, with or without a port', () {
      for (final url in [
        'http://127.0.0.1:8080',
        'http://10.0.2.2:8080',
        'http://localhost:8080',
        'http://[::1]:8080',
        'http://api.test',
        'https://api.sample-company.io',
      ]) {
        final c = api(url, AppEnvironment.development);
        expect(c.isConfigured, isTrue, reason: url);
        expect(c.baseUrl, url);
        expect(c.problem, isNull);
      }
      expect(const ApiConfig('http://api.test').isConfigured, isTrue);
      expect(const ApiConfig('http://api.test').isSecure,
          isFalse); // cleartext dev
    });

    test('staging and production require https', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        final ok = api(_publicApi, env);
        expect(ok.isConfigured, isTrue, reason: env.name);
        expect(ok.isSecure, isTrue);
        expect(ok.problem, isNull);

        final cleartext = api('http://api.sample-company.io', env);
        expect(cleartext.isConfigured, isFalse, reason: env.name);
        expect(cleartext.baseUrl, isEmpty, reason: 'no request may use it');
        expect(cleartext.problem, contains('https'));
        expect(cleartext.problem, contains(env.name));
        // The address is never echoed back in the diagnosis.
        expect(cleartext.problem, isNot(contains('sample-company')));

        expect(api('http://127.0.0.1:8080', env).isConfigured, isFalse);
      }
    });

    test('placeholder .invalid hosts are refused outside development', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        final c = api('https://api.wattbyte.invalid', env);
        expect(c.isConfigured, isFalse);
        expect(c.problem, contains('placeholder'));
      }
    });

    test('malformed addresses are not configured and say why', () {
      final cases = {
        'api.sample-company.io': 'absolute',
        '//api.sample-company.io': 'absolute',
        'https://': 'absolute',
        'ftp://api.sample-company.io': 'http or https',
        'https://user:secret@api.sample-company.io': 'credentials',
        'https://api.sample-company.io?x=1': 'query or fragment',
        'https://api.sample-company.io#top': 'query or fragment',
        'https://exa mple.com': 'invalid host',
        'https://api.sample-company.io/a b': 'whitespace',
        'https://-bad-.sample-company.io': 'invalid host',
        'https://api..sample-company.io': 'invalid host',
        'https://api.sample-company.io:99999': 'invalid port',
        'https://api.sample-company.io:0': 'invalid port',
      };
      for (final entry in cases.entries) {
        for (final env in AppEnvironment.values) {
          final c = api(entry.key, env);
          expect(c.isConfigured, isFalse,
              reason: '${entry.key} in ${env.name}');
          expect(c.baseUrl, isEmpty);
          expect(c.problem, contains(entry.value),
              reason: '${entry.key} in ${env.name}');
          expect(c.problem, isNot(contains('secret')));
        }
      }
    });

    test('whitespace and trailing slashes are normalised, a path prefix stays',
        () {
      expect(
          api('  https://api.sample-company.io/  ', AppEnvironment.production)
              .baseUrl,
          'https://api.sample-company.io');
      expect(
          api('https://api.sample-company.io///', AppEnvironment.staging)
              .baseUrl,
          'https://api.sample-company.io');
      expect(
          api('https://api.sample-company.io/edge', AppEnvironment.staging)
              .baseUrl,
          'https://api.sample-company.io/edge');
    });
  });

  group('AppConfig.fromDefines', () {
    test('no defines: development, no API, privacy URL blocked, build INVALID',
        () {
      final c = AppConfig.fromDefines();
      expect(c.environment, AppEnvironment.development);
      expect(c.api.isConfigured, isFalse);
      expect(c.hasPrivacyPolicyUrl, isFalse);
      expect(c.privacyPolicyUrl, isNull);
      expect(c.privacyPolicyStatus, 'BLOCKED — PUBLIC URL REQUIRED');
      expect(c.privacyPolicyStatus, kPrivacyPolicyBlockedStatus);
      expect(c.featureDefaults, FeatureFlags.builtInDefaults);
      expect(c.isProduction, isFalse);
      // A missing API address is no longer "a local build": without the
      // explicit LOCAL_ONLY_DEV=true the configuration is simply wrong.
      expect(c.isValid, isFalse);
      expect(c.backendMode, isNull);
      expect(c.isLocalOnlyDev, isFalse);
      expect(c.problems.single, contains('API_BASE_URL is required'));
    });

    test(
        'LOCAL_ONLY_DEV=true in a debug build: development, no API, privacy URL '
        'blocked, valid without problems', () {
      final c = AppConfig.fromDefines(
          localOnlyDev: 'true', buildMode: BuildMode.debug);
      expect(c.environment, AppEnvironment.development);
      expect(c.api.isConfigured, isFalse);
      expect(c.hasPrivacyPolicyUrl, isFalse);
      expect(c.privacyPolicyUrl, isNull);
      expect(c.privacyPolicyStatus, kPrivacyPolicyBlockedStatus);
      expect(c.featureDefaults, FeatureFlags.builtInDefaults);
      expect(c.problems, isEmpty);
      expect(c.isProduction, isFalse);
      expect(c.isValid, isTrue);
      expect(c.backendMode, BackendMode.localOnlyDev);
      expect(c.isLocalOnlyDev, isTrue);
    });

    test('a complete production configuration', () {
      final c = AppConfig.fromDefines(
        appEnv: 'production',
        apiBaseUrl: _publicApi,
        privacyPolicyUrl: _publicPolicy,
      );
      expect(c.environment, AppEnvironment.production);
      expect(c.isProduction, isTrue);
      expect(c.api.isConfigured, isTrue);
      expect(c.api.environment, AppEnvironment.production);
      expect(c.hasPrivacyPolicyUrl, isTrue);
      expect(c.privacyPolicyUrl, Uri.parse(_publicPolicy));
      expect(c.privacyPolicyStatus, kPrivacyPolicyConfiguredStatus);
      expect(c.problems, isEmpty);
    });

    test('the privacy-policy URL must be a public https URL', () {
      for (final bad in [
        'http://policies.sample-company.io/privacy', // not https
        'policies.sample-company.io/privacy', // no scheme
        '/privacy', // relative
        'https://', // no host
        'https://user:pw@policies.sample-company.io/p', // credentials
        'https://exa mple.org/privacy', // invalid host
        'https://policies.sample-company.io:70000/privacy', // invalid port
        'https://policies.sample-company.io/a b', // whitespace
        'https://localhost/privacy',
        'https://127.0.0.1/privacy',
        'https://[::1]/privacy',
        'https://192.168.1.10/privacy',
        'https://intranet/privacy', // single label
        'https://printer.local/privacy',
        'https://privacy.wattbyte.invalid/policy', // placeholder of the examples
        'https://privacy.example/policy',
        'https://www.example.com/privacy',
        'https://host.test/privacy',
        'javascript:alert(1)',
        'https://policies.sample-company.io/${'a' * 2100}',
      ]) {
        // The API address satisfies the backend rule, so the privacy-policy
        // URL is the only thing that can be wrong here.
        final c = AppConfig.fromDefines(
            apiBaseUrl: _publicApi, privacyPolicyUrl: bad);
        expect(c.hasPrivacyPolicyUrl, isFalse, reason: bad);
        expect(c.privacyPolicyUrl, isNull, reason: bad);
        expect(c.privacyPolicyStatus, kPrivacyPolicyBlockedStatus);
        expect(c.problems.single, startsWith('PRIVACY_POLICY_URL '),
            reason: bad);
        expect(c.problems.single, isNot(contains('pw@')), reason: bad);
      }
    });

    test('surrounding whitespace is ignored, path and query are kept', () {
      final c = AppConfig.fromDefines(
          apiBaseUrl: _publicApi,
          privacyPolicyUrl: '  $_publicPolicy?lang=pl#data  ');
      expect(c.privacyPolicyUrl.toString(), '$_publicPolicy?lang=pl#data');
      expect(c.problems, isEmpty);
    });

    test('the environment decides the API rules', () {
      final dev = AppConfig.fromDefines(apiBaseUrl: 'http://127.0.0.1:8080');
      expect(dev.api.isConfigured, isTrue);
      for (final env in ['staging', 'production']) {
        final c = AppConfig.fromDefines(
            appEnv: env, apiBaseUrl: 'http://127.0.0.1:8080');
        expect(c.api.isConfigured, isFalse, reason: env);
        expect(c.problems.single, contains('https'));
      }
    });

    test('an unknown APP_ENV is reported and treated as production', () {
      final c =
          AppConfig.fromDefines(appEnv: 'prod', apiBaseUrl: 'http://x.test');
      expect(c.environment, AppEnvironment.production);
      expect(c.api.isConfigured, isFalse);
      expect(c.problems, hasLength(2));
      expect(c.problems.first, contains('APP_ENV'));
    });

    test('build flags come from the defines and mistakes are reported', () {
      final c = AppConfig.fromDefines(
        apiBaseUrl: _publicApi,
        flags: const FlagDefines(
            ai: 'false', subscriptions: 'on', cloudSync: 'maybe'),
      );
      expect(c.featureDefaults.ai, isFalse);
      expect(c.featureDefaults.subscriptions, isTrue);
      expect(c.featureDefaults.cloudSync, isTrue); // default kept
      expect(c.problems.single, contains('FEATURE_CLOUD_SYNC'));
    });

    test('diagnostics carry no address, path or credential', () {
      final c = AppConfig.fromDefines(
        appEnv: 'staging',
        apiBaseUrl: '$_publicApi/secret-prefix',
        privacyPolicyUrl: '$_publicPolicy?token=abc',
      );
      expect(c.diagnostics, contains('env=staging'));
      expect(c.diagnostics, contains('api=configured (api.sample-company.io)'));
      expect(c.diagnostics, contains('privacyPolicy=CONFIGURED'));
      expect(c.diagnostics, isNot(contains('secret-prefix')));
      expect(c.diagnostics, isNot(contains('token=abc')));
      // No API address: the diagnosis says so without an address, and the
      // backend verdict is part of it (INVALID, or the explicit local-only mode).
      final noApi = AppConfig.fromDefines(localOnlyDev: 'true');
      expect(noApi.diagnostics,
          contains('privacyPolicy=BLOCKED — PUBLIC URL REQUIRED'));
      expect(noApi.diagnostics, contains('api=not configured'));
      expect(noApi.diagnostics, contains('backend=localOnlyDev'));
      expect(AppConfig.fromDefines().diagnostics, contains('backend=INVALID'));
      expect(c.diagnostics, contains('backend=online'));
    });

    test('problems is unmodifiable', () {
      expect(() => AppConfig.fromDefines().problems.add('x'),
          throwsUnsupportedError);
    });
  });

  group('AppConfig backend rules', () {
    AppConfig cfg(
      BuildMode mode, {
      String api = '',
      String flag = '',
      String env = '',
    }) =>
        AppConfig.fromDefines(
            buildMode: mode, apiBaseUrl: api, localOnlyDev: flag, appEnv: env);

    test('an API address makes a valid online build in every build mode', () {
      for (final mode in BuildMode.values) {
        for (final flag in ['', 'false']) {
          final c = cfg(mode, api: _publicApi, flag: flag);
          final why = '${mode.name}, LOCAL_ONLY_DEV="$flag"';
          expect(c.buildMode, mode, reason: why);
          expect(c.isValid, isTrue, reason: why);
          expect(c.backend.isValid, isTrue, reason: why);
          expect(c.backendMode, BackendMode.online, reason: why);
          expect(c.isLocalOnlyDev, isFalse, reason: why);
          expect(c.api.isConfigured, isTrue, reason: why);
          expect(c.problems, isEmpty, reason: why);
        }
      }
    });

    test('LOCAL_ONLY_DEV=true without an address is valid in debug only', () {
      final c = cfg(BuildMode.debug, flag: 'true');
      expect(c.isValid, isTrue);
      expect(c.backend.isValid, isTrue);
      expect(c.backendMode, BackendMode.localOnlyDev);
      expect(c.isLocalOnlyDev, isTrue);
      expect(c.api.isConfigured, isFalse);
      expect(c.problems, isEmpty);

      for (final mode in [BuildMode.profile, BuildMode.release]) {
        final c = cfg(mode, flag: 'true');
        expect(c.isValid, isFalse, reason: mode.name);
        expect(c.backendMode, isNull, reason: mode.name);
        expect(c.isLocalOnlyDev, isFalse, reason: mode.name);
        expect(
            c.problems.where((p) => p.contains('LOCAL_ONLY_DEV')), isNotEmpty,
            reason: mode.name);
      }
    });

    test('every configuration the spec forbids is invalid and never local-only',
        () {
      final cases = <(String, BuildMode, String, String)>[
        // (what, build mode, API_BASE_URL, LOCAL_ONLY_DEV)
        ('debug, no API, flag false', BuildMode.debug, '', 'false'),
        ('debug, no API, flag unset', BuildMode.debug, '', ''),
        ('profile, no API', BuildMode.profile, '', ''),
        ('profile, no API, flag false', BuildMode.profile, '', 'false'),
        ('release, no API', BuildMode.release, '', ''),
        ('release, no API, flag false', BuildMode.release, '', 'false'),
        ('release, flag true', BuildMode.release, '', 'true'),
        ('release, API and flag true', BuildMode.release, _publicApi, 'true'),
        ('profile, API and flag true', BuildMode.profile, _publicApi, 'true'),
      ];
      for (final (what, mode, api, flag) in cases) {
        final c = cfg(mode, api: api, flag: flag);
        expect(c.isValid, isFalse, reason: what);
        expect(c.backend.isValid, isFalse, reason: what);
        expect(c.backendMode, isNull, reason: what);
        expect(c.isLocalOnlyDev, isFalse, reason: what);
        expect(c.problems, isNotEmpty, reason: what);
        expect(c.backend.errors, isNotEmpty, reason: what);
      }
    });

    test(
        'local-only is never reported outside debug, with an address, or '
        'without the explicit flag', () {
      for (final mode in BuildMode.values) {
        for (final api in [
          '',
          _publicApi,
          'http://127.0.0.1:8080',
          'nonsense'
        ]) {
          for (final flag in ['', 'false', 'true', ' true ', 'TRUE', 'bogus']) {
            final c = cfg(mode, api: api, flag: flag);
            final why = '${mode.name}, API="$api", flag="$flag"';
            // The only road to local-only: debug, no address, flag exactly true.
            final expected =
                mode == BuildMode.debug && api.isEmpty && flag.trim() == 'true';
            expect(c.isLocalOnlyDev, expected, reason: why);
            expect(c.isLocalOnlyDev, c.backendMode == BackendMode.localOnlyDev,
                reason: why);
            expect(c.isValid, c.backendMode != null, reason: why);
            if (c.isLocalOnlyDev) {
              expect(c.api.isConfigured, isFalse, reason: why);
              expect(c.isValid, isTrue, reason: why);
            }
          }
        }
      }
    });

    test('a present but invalid address never degrades into local-only', () {
      const bad = [
        ('ftp://api.sample-company.io', ''),
        ('api.sample-company.io', ''),
        ('https://', ''),
        ('https://user:pw@api.sample-company.io', ''),
        ('https://api.sample-company.io?x=1', ''),
        // https-only environments refuse the development spelling and the
        // placeholder hosts of the example files.
        ('http://api.sample-company.io', 'staging'),
        ('http://127.0.0.1:8080', 'production'),
        ('https://api.wattbyte.invalid', 'production'),
      ];
      for (final (api, env) in bad) {
        for (final mode in BuildMode.values) {
          for (final flag in ['', 'false', 'true']) {
            final c = cfg(mode, api: api, flag: flag, env: env);
            final why = '${mode.name}, "$api", env="$env", flag="$flag"';
            expect(c.isValid, isFalse, reason: why);
            expect(c.backendMode, isNull, reason: why);
            expect(c.isLocalOnlyDev, isFalse, reason: why);
            expect(c.api.isConfigured, isFalse, reason: why);
            expect(c.problems.where((p) => p.startsWith('API_BASE_URL')),
                isNotEmpty,
                reason: why);
          }
        }
      }
    });

    test('debug with an address and LOCAL_ONLY_DEV=true is a contradiction',
        () {
      final c = cfg(BuildMode.debug, api: _publicApi, flag: 'true');
      expect(c.isValid, isFalse);
      expect(c.backendMode, isNull);
      // The account must not be skipped because both switches were given.
      expect(c.isLocalOnlyDev, isFalse);
      expect(c.problems.single,
          allOf(contains('LOCAL_ONLY_DEV'), contains('API_BASE_URL')));
    });

    test('LOCAL_ONLY_DEV is exactly true or false; whitespace is ignored', () {
      for (final flag in ['1', 'TRUE', 'True', 'yes', 'on', 'tru', 'bogus']) {
        final c = cfg(BuildMode.debug, flag: flag);
        expect(c.isValid, isFalse, reason: flag);
        expect(c.isLocalOnlyDev, isFalse, reason: flag);
        expect(
            c.problems.where((p) => p.contains('LOCAL_ONLY_DEV')), isNotEmpty,
            reason: flag);
        // Not even a valid address rescues an unreadable safety switch.
        expect(
            cfg(BuildMode.debug, api: _publicApi, flag: flag).isValid, isFalse,
            reason: flag);
      }
      expect(cfg(BuildMode.debug, flag: ' true ').isLocalOnlyDev, isTrue);
      expect(cfg(BuildMode.debug, flag: ' false ').isValid, isFalse,
          reason: 'false means "needs an API", and there is none');
      expect(cfg(BuildMode.release, api: _publicApi, flag: ' false ').isValid,
          isTrue);
    });

    test(
        'buildMode defaults to this run\'s mode, which is debug in flutter test',
        () {
      expect(kBuildMode, BuildMode.debug);
      expect(AppConfig.fromDefines().buildMode, BuildMode.debug);
      // Left at its default the build counts as debug, so the explicit flag works.
      expect(
          AppConfig.fromDefines(localOnlyDev: 'true').isLocalOnlyDev, isTrue);
      for (final mode in BuildMode.values) {
        expect(AppConfig.fromDefines(buildMode: mode).buildMode, mode);
      }
    });

    test(
        'a build that ships is production without APP_ENV, a debug build is not',
        () {
      expect(AppConfig.fromDefines(buildMode: BuildMode.debug).environment,
          AppEnvironment.development);
      for (final mode in [BuildMode.profile, BuildMode.release]) {
        final c =
            AppConfig.fromDefines(buildMode: mode, apiBaseUrl: _publicApi);
        expect(c.environment, AppEnvironment.production, reason: mode.name);
        expect(c.isValid, isTrue, reason: mode.name);
        expect(c.api.environment, AppEnvironment.production);
        // Cleartext and placeholders are refused although APP_ENV was forgotten.
        for (final bad in [
          'http://api.sample-company.io',
          'https://api.wattbyte.invalid',
        ]) {
          final c = AppConfig.fromDefines(buildMode: mode, apiBaseUrl: bad);
          expect(c.isValid, isFalse, reason: '${mode.name} $bad');
          expect(c.isLocalOnlyDev, isFalse);
        }
        // A shipped build is never `development`, whatever the define says (F-14).
        expect(
            AppConfig.fromDefines(
                    buildMode: mode,
                    appEnv: 'development',
                    apiBaseUrl: 'http://127.0.0.1:8080')
                .isValid,
            isFalse,
            reason: 'explicit development in ${mode.name}');
        expect(
            AppConfig.fromDefines(
                    buildMode: mode,
                    appEnv: 'development',
                    apiBaseUrl: _publicApi)
                .isValid,
            isFalse,
            reason: 'development with a public address in ${mode.name}');
      }
    });

    test('LOCAL_ONLY_DEV needs the development environment', () {
      for (final env in ['staging', 'production', 'prod']) {
        final c = AppConfig.fromDefines(appEnv: env, localOnlyDev: 'true');
        expect(c.isValid, isFalse, reason: env);
        expect(c.isLocalOnlyDev, isFalse, reason: env);
      }
      expect(
          AppConfig.fromDefines(appEnv: 'development', localOnlyDev: 'true')
              .isLocalOnlyDev,
          isTrue);
    });

    test(
        'problems list the backend errors, other problems stay, no value leaks',
        () {
      const secretAddress =
          'https://user:hunter2@api.sample-company.io/secret-path';
      final c = AppConfig.fromDefines(
        buildMode: BuildMode.release,
        apiBaseUrl: secretAddress,
        localOnlyDev: 'true',
        privacyPolicyUrl: 'http://policies.sample-company.io/privacy',
      );
      expect(c.backend.errors, hasLength(3),
          reason: 'LOCAL_ONLY_DEV in a release build, LOCAL_ONLY_DEV outside '
              'the development environment (a release build without APP_ENV '
              'is production), credentials in the address');
      expect(c.problems, containsAllInOrder(c.backend.errors));
      expect(c.problems.where((p) => p.startsWith('PRIVACY_POLICY_URL ')),
          hasLength(1));
      expect(c.problems.where((p) => p.contains('credentials')), hasLength(1));
      for (final p in c.problems) {
        expect(p, isNot(contains('hunter2')));
        expect(p, isNot(contains('sample-company')));
        expect(p, isNot(contains('secret-path')));
      }

      final missing = cfg(BuildMode.release);
      expect(missing.problems.single, contains('API_BASE_URL is required'));
      expect(missing.problems.single, contains('release'));
    });

    test('diagnostics name the build mode and the backend verdict', () {
      for (final mode in BuildMode.values) {
        final d = cfg(mode, api: _publicApi).diagnostics;
        expect(d, contains('build=${mode.name}'));
        expect(d, contains('backend=online'));
        expect(d, isNot(contains('problems=')));
      }
      final local = cfg(BuildMode.debug, flag: 'true').diagnostics;
      expect(local, contains('build=debug'));
      expect(local, contains('backend=localOnlyDev'));
      expect(local, contains('api=not configured'));

      final invalid = cfg(BuildMode.release).diagnostics;
      expect(invalid, contains('build=release'));
      expect(invalid, contains('backend=INVALID'));
      expect(invalid, contains('problems=1'));

      final leaky = cfg(BuildMode.release,
              api: 'https://user:hunter2@api.sample-company.io/secret-path',
              flag: 'true')
          .diagnostics;
      expect(leaky, contains('backend=INVALID'));
      expect(leaky, isNot(contains('hunter2')));
      expect(leaky, isNot(contains('sample-company')));
      expect(leaky, isNot(contains('secret-path')));
    });
  });

  group('the compiled-in configuration', () {
    test(
        'a plain run is development, debug, flags at their defaults and '
        'INVALID: nothing is configured', () {
      final c = AppConfig.fromEnvironment;
      expect(c.environment, AppEnvironment.development);
      expect(kBuildMode, BuildMode.debug);
      expect(c.buildMode, BuildMode.debug);
      expect(c.api.isConfigured, isFalse);
      expect(c.hasPrivacyPolicyUrl, isFalse);
      expect(c.featureDefaults, FeatureFlags.builtInDefaults);
      // No API_BASE_URL and no LOCAL_ONLY_DEV: the app would refuse to start
      // (ConfigErrorApp); it must never fall back to the local-only mode.
      expect(c.isValid, isFalse);
      expect(c.backendMode, isNull);
      expect(c.isLocalOnlyDev, isFalse);
      expect(c.problems.single, contains('API_BASE_URL is required'));
    }, skip: _hasDefines ? 'run without --dart-define' : null);
  });

  group('config/*.example.json', () {
    Map<String, String> defines(String name) {
      final raw =
          jsonDecode(File('config/$name.example.json').readAsStringSync())
              as Map<String, Object?>;
      return {for (final e in raw.entries) e.key: '${e.value}'};
    }

    AppConfig load(String name, {BuildMode buildMode = BuildMode.debug}) {
      final d = defines(name);
      return AppConfig.fromDefines(
        appEnv: d['APP_ENV'] ?? '',
        apiBaseUrl: d['API_BASE_URL'] ?? '',
        localOnlyDev: d['LOCAL_ONLY_DEV'] ?? '',
        privacyPolicyUrl: d['PRIVACY_POLICY_URL'] ?? '',
        flags: FlagDefines(
          ai: d['FEATURE_AI'] ?? '',
          subscriptions: d['FEATURE_SUBSCRIPTIONS'] ?? '',
          cloudSync: d['FEATURE_CLOUD_SYNC'] ?? '',
        ),
        buildMode: buildMode,
      );
    }

    test('there is one example per environment, and they only use known keys',
        () {
      const keys = {
        '_NOTE',
        'APP_ENV',
        'API_BASE_URL',
        'LOCAL_ONLY_DEV',
        'PRIVACY_POLICY_URL',
        'FEATURE_AI',
        'FEATURE_SUBSCRIPTIONS',
        'FEATURE_CLOUD_SYNC',
      };
      for (final env in AppEnvironment.values) {
        final d = defines(env.name);
        expect(d['APP_ENV'], env.name);
        expect(keys.containsAll(d.keys), isTrue,
            reason: '${env.name}: ${d.keys}');
      }
      expect(keys.containsAll(defines('local-only-dev').keys), isTrue);
    });

    test('only the local-only example carries LOCAL_ONLY_DEV', () {
      for (final env in AppEnvironment.values) {
        expect(defines(env.name).containsKey('LOCAL_ONLY_DEV'), isFalse,
            reason: '${env.name} must not enable the account-free mode');
      }
      expect(defines('local-only-dev')['LOCAL_ONLY_DEV'], 'true');
    });

    test('development points at the local machine and works as is', () {
      final c = load('development');
      expect(c.environment, AppEnvironment.development);
      expect(c.api.isConfigured, isTrue);
      expect(Uri.parse(c.api.baseUrl).host, '127.0.0.1');
      expect(c.problems, isEmpty);
      // Normal development runs the full Flutter -> API -> auth flow.
      expect(c.isValid, isTrue);
      expect(c.backendMode, BackendMode.online);
      expect(c.isLocalOnlyDev, isFalse);
    });

    test(
        'local-only-dev is valid local-only in debug and invalid in '
        'profile and release', () {
      final d = defines('local-only-dev');
      expect(d['LOCAL_ONLY_DEV'], 'true');
      expect(d.containsKey('API_BASE_URL'), isFalse);
      expect(d['APP_ENV'] ?? 'development', 'development');
      expect(d['_NOTE'],
          allOf(contains('DEBUG'), contains('LOCAL ONLY DEVELOPMENT MODE')),
          reason: 'the note must say debug only and name the banner');

      final debug = load('local-only-dev');
      expect(debug.environment, AppEnvironment.development);
      expect(debug.isValid, isTrue);
      expect(debug.backendMode, BackendMode.localOnlyDev);
      expect(debug.isLocalOnlyDev, isTrue);
      expect(debug.api.isConfigured, isFalse);
      expect(debug.problems, isEmpty);

      for (final mode in [BuildMode.profile, BuildMode.release]) {
        final c = load('local-only-dev', buildMode: mode);
        expect(c.isValid, isFalse, reason: mode.name);
        expect(c.backendMode, isNull, reason: mode.name);
        expect(c.isLocalOnlyDev, isFalse, reason: mode.name);
        expect(
            c.problems.where((p) => p.contains('LOCAL_ONLY_DEV')), isNotEmpty,
            reason: mode.name);
      }
    });

    test(
        'staging and production carry only .invalid placeholders, which the app refuses',
        () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        final d = defines(env.name);
        expect(Uri.parse(d['API_BASE_URL']!).host, endsWith('.invalid'));
        expect(Uri.parse(d['PRIVACY_POLICY_URL']!).host, endsWith('.invalid'));
        final c = load(env.name);
        expect(c.environment, env);
        expect(c.api.isConfigured, isFalse);
        expect(c.hasPrivacyPolicyUrl, isFalse);
        expect(
            c.problems.where((p) => p.contains('placeholder')), hasLength(2));
        // A refused placeholder is a wrong address, not "no backend": it never
        // turns into local-only, in any build mode.
        for (final mode in BuildMode.values) {
          final m = load(env.name, buildMode: mode);
          expect(m.isValid, isFalse, reason: '${env.name} ${mode.name}');
          expect(m.backendMode, isNull, reason: '${env.name} ${mode.name}');
          expect(m.isLocalOnlyDev, isFalse, reason: '${env.name} ${mode.name}');
        }
      }
    });

    test('substituting real https hosts makes them valid', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        final d = defines(env.name);
        final c = AppConfig.fromDefines(
          appEnv: d['APP_ENV']!,
          apiBaseUrl: _publicApi,
          privacyPolicyUrl: _publicPolicy,
        );
        expect(c.api.isConfigured, isTrue);
        expect(c.hasPrivacyPolicyUrl, isTrue);
        expect(c.problems, isEmpty);
        expect(c.backendMode, BackendMode.online);
        for (final mode in BuildMode.values) {
          final m = AppConfig.fromDefines(
            appEnv: d['APP_ENV']!,
            apiBaseUrl: _publicApi,
            privacyPolicyUrl: _publicPolicy,
            buildMode: mode,
          );
          expect(m.isValid, isTrue, reason: '${env.name} ${mode.name}');
          expect(m.isLocalOnlyDev, isFalse);
        }
      }
    });

    test('no example enables subscriptions before the server says so', () {
      for (final env in AppEnvironment.values) {
        expect(load(env.name).featureDefaults.subscriptions, isFalse);
      }
    });
  });

  group('no environment address is hardcoded in lib/', () {
    test('no source or ARB line carries a URL with a host', () {
      final offenders = <String>[];
      final url = RegExp(r'https?://[A-Za-z0-9\[]');
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        final isCode = path.endsWith('.dart');
        if ((!isCode && !path.endsWith('.arb')) ||
            path.startsWith('lib/generated/') ||
            path.startsWith('lib/l10n/generated/')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          // Comments may show an example command; code and strings may not.
          final code = isCode
              ? lines[i].replaceFirst(RegExp(r'(?<!:)//.*$'), '')
              : lines[i];
          if (url.hasMatch(code)) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason:
              'addresses belong in --dart-define / config/*.json (see docs/CONFIGURATION_MOBILE.md)');
    });
  });

  group('startup', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('the app locks to portrait-up, as the native projects do', () async {
      expect(kAppOrientations, [DeviceOrientation.portraitUp]);
      await lockOrientation();
      final call = calls.singleWhere(
          (c) => c.method == 'SystemChrome.setPreferredOrientations');
      expect(call.arguments, ['DeviceOrientation.portraitUp']);
    });

    test('the iPhone Info.plist allows exactly the orientations Dart locks to',
        () {
      const plistName = {
        DeviceOrientation.portraitUp: 'UIInterfaceOrientationPortrait',
        DeviceOrientation.portraitDown:
            'UIInterfaceOrientationPortraitUpsideDown',
        DeviceOrientation.landscapeLeft: 'UIInterfaceOrientationLandscapeLeft',
        DeviceOrientation.landscapeRight:
            'UIInterfaceOrientationLandscapeRight',
      };
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final block = RegExp(
              r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>',
              dotAll: true)
          .firstMatch(plist)!
          .group(1)!;
      final allowed = RegExp(r'<string>(.*?)</string>')
          .allMatches(block)
          .map((m) => m[1])
          .toSet();
      expect(kAppOrientations.map((o) => plistName[o]).toSet(), allowed);
    });

    test('the startup log names the privacy-policy status and every problem',
        () {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      addTearDown(() => debugPrint = original);

      logStartupConfiguration(AppConfig.fromDefines(
          appEnv: 'staging', apiBaseUrl: 'http://127.0.0.1:1'));
      expect(printed, hasLength(2));
      expect(printed.first,
          contains('privacyPolicy=BLOCKED — PUBLIC URL REQUIRED'));
      expect(printed.first, contains('env=staging'));
      expect(printed.last, contains('API_BASE_URL must use https in staging'));
    });

    test(
        'the startup log shows the development banner text only in the '
        'explicit local-only mode', () {
      List<String> logged(AppConfig config) {
        final printed = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        try {
          logStartupConfiguration(config);
        } finally {
          debugPrint = original;
        }
        return printed;
      }

      expect(kLocalOnlyDevBannerText, 'LOCAL ONLY DEVELOPMENT MODE');
      final local = logged(AppConfig.fromDefines(localOnlyDev: 'true'));
      expect(local.where((l) => l.contains(kLocalOnlyDevBannerText)),
          hasLength(1));

      for (final config in [
        AppConfig.fromDefines(apiBaseUrl: _publicApi), // normal development
        AppConfig.fromDefines(), // nothing configured: invalid
        AppConfig.fromDefines(
            apiBaseUrl: _publicApi, localOnlyDev: 'true'), // contradiction
        AppConfig.fromDefines(localOnlyDev: 'bogus'),
      ]) {
        expect(logged(config).where((l) => l.contains(kLocalOnlyDevBannerText)),
            isEmpty,
            reason: config.diagnostics);
      }
    });
  });

  group('url rules', () {
    test('placeholder and non-public hosts', () {
      expect(isPlaceholderHost('api.wattbyte.invalid'), isTrue);
      expect(isPlaceholderHost('INVALID'), isTrue);
      expect(isPlaceholderHost('api.sample-company.io'), isFalse);
      expect(isNonPublicHost('localhost'), isTrue);
      expect(isNonPublicHost('10.0.0.5'), isTrue);
      expect(isNonPublicHost('::1'), isTrue);
      expect(isNonPublicHost('a.example.org'), isTrue);
      expect(isNonPublicHost('policies.sample-company.io'), isFalse);
      expect(isNonPublicHost('sample-company.pl'), isFalse);
    });
  });
}
