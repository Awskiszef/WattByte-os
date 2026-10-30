// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The server can tell an installed app that it is too old (audit F-11): the build says which version it is, the server
// publishes the oldest version it serves, and an older app says so instead of failing on requests.
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/config/app_build.dart';
import 'package:wattbyte/config/feature_flags.dart';
import 'package:wattbyte/ui/onboarding/update_required_screen.dart';

import 'support/app_harness.dart';

Map<String, Object?> _config({Map<String, Object?>? minimum}) => {
      'environment': 'production',
      'features': {'ai': true, 'subscriptions': false, 'cloudSync': true},
      'ai': {
        'dailyLimits': {'free': 5, 'premium': 100}
      },
      if (minimum != null) 'minimumAppVersion': minimum,
    };

void main() {
  group('versions', () {
    test('parse and compare', () {
      expect(parseVersion('1.4.0'), [1, 4, 0]);
      expect(parseVersion('1.4.0+27'), [1, 4, 0]);
      expect(parseVersion('2.0.1-beta.1'), [2, 0, 1]);
      expect(parseVersion('1.4'), isNull);
      expect(parseVersion('latest'), isNull);
      const build =
          AppBuildInfo(platform: 'ios', version: '1.4.0', build: '27');
      expect(build.isOlderThan('1.4.1'), isTrue);
      expect(build.isOlderThan('1.10.0'), isTrue, reason: 'numbers, not text');
      expect(build.isOlderThan('2.0.0'), isTrue);
      expect(build.isOlderThan('1.4.0'), isFalse);
      expect(build.isOlderThan('1.3.9'), isFalse);
      expect(build.isOlderThan(null), isFalse);
      expect(build.isOlderThan('garbage'), isFalse,
          reason: 'an unreadable minimum never locks anyone out');
      expect(AppBuildInfo.unknown.isOlderThan('9.9.9'), isFalse);
    });

    test(
        'the header names platform, version and build and nothing about the person',
        () {
      expect(
          const AppBuildInfo(platform: 'android', version: '1.4.0', build: '27')
              .header,
          'android/1.4.0+27');
      expect(const AppBuildInfo(platform: 'ios', version: '1.4.0').header,
          'ios/1.4.0');
      expect(AppBuildInfo.unknown.header, isNull);
      expect(const AppBuildInfo(platform: 'ios', version: 'x').header, isNull);
    });
  });

  group('the server document', () {
    final at = DateTime.utc(2026, 10, 30);
    test(
        'minimumAppVersion is read per platform, survives the cache, and a bad entry is ignored',
        () {
      final config = ServerFeatureConfig.fromServerJson(
          _config(minimum: {'android': '1.4.0', 'ios': 'soon'}),
          fetchedAt: at);
      expect(config.minimumAppVersion, {'android': '1.4.0'});
      final again = ServerFeatureConfig.decodeCache(config.encodeCache());
      expect(again.minimumAppVersion, {'android': '1.4.0'});
      expect(again, config);
      expect(
          ServerFeatureConfig.fromServerJson(_config(), fetchedAt: at)
              .minimumAppVersion,
          isEmpty);
    });
  });

  test('every API call carries the build header', () async {
    final h = ApiFactory(const ApiConfig('http://api.test'),
        appBuild: const AppBuildInfo(
            platform: 'android', version: '1.4.0', build: '27'));
    expect(h.appBuild!.header, 'android/1.4.0+27');
    // The header is set on the generated client the factory hands out.
    expect(
        h.anonymous().defaultHeaderMap['X-WattByte-App'], 'android/1.4.0+27');
    expect(
        h.bearer('t').defaultHeaderMap['X-WattByte-App'], 'android/1.4.0+27');
    expect(
        ApiFactory(const ApiConfig('http://api.test'))
            .anonymous()
            .defaultHeaderMap
            .containsKey('X-WattByte-App'),
        isFalse);
  });

  group('the screen', () {
    Future<AppHarness> app(WidgetTester tester,
        {required String installed,
        required Map<String, Object?>? minimum}) async {
      final h =
          await AppHarness.create(tester, platform: HarnessPlatform.android);
      h.backend.routes['GET /api/v1/config'] =
          (_) => FakeBackend.json(_config(minimum: minimum));
      h.overrides.add(appBuildProvider.overrideWithValue(
          AppBuildInfo(platform: 'android', version: installed, build: '1')));
      await pumpApp(tester, harness: h);
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets(
        'an app older than the minimum says so, and Continue lets the user on',
        (tester) async {
      await app(tester, installed: '1.0.0', minimum: {'android': '1.4.0'});
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
      expect(find.text('Please update WattByte'), findsOneWidget);
      await tester.tap(find.text('Continue without updating'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });

    testWidgets(
        'a current app, another platform\'s minimum, or no minimum: no notice',
        (tester) async {
      await app(tester, installed: '1.4.0', minimum: {'android': '1.4.0'});
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });

    testWidgets('only the other platform has a minimum: no notice',
        (tester) async {
      await app(tester, installed: '1.0.0', minimum: {'ios': '9.0.0'});
      expect(find.byType(UpdateRequiredScreen), findsNothing);
    });
  });
}
