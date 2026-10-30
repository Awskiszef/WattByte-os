// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// The server's feature kill switches reach the app and are obeyed (audit F-04): the default fetcher asks
// GET /api/v1/config, the flags merge build and server, the AI card and the cloud sync switch follow them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_providers.dart';
import 'package:wattbyte/features/auth/presentation/auth_controller.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/insights/ai_card.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart' show WbCard;

import 'support/app_harness.dart';

Map<String, Object?> _config({bool ai = true, bool cloudSync = true}) => {
      'environment': 'production',
      'features': {'ai': ai, 'subscriptions': false, 'cloudSync': cloudSync},
      'ai': {
        'dailyLimits': {'free': 5, 'premium': 100}
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, FakeBackend, DateTime Function())> make() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backend = FakeBackend();
    var now = DateTime(2026, 10, 30, 12);
    const config = ApiConfig('http://api.test');
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(AppConfig.fromDefines(
          buildMode: BuildMode.debug, apiBaseUrl: 'http://api.test')),
      apiConfigProvider.overrideWithValue(config),
      apiFactoryProvider
          .overrideWithValue(ApiFactory(config, httpClient: backend.client)),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    return (c, backend, () => now = now.add(const Duration(minutes: 20)));
  }

  test(
      'the default fetcher reads GET /api/v1/config, and the kill switch turns AI off',
      () async {
    final (c, backend, _) = await make();
    backend.routes['GET /api/v1/config'] =
        (_) => FakeBackend.json(_config(ai: false));
    expect(c.read(featureFlagsProvider).ai, isTrue,
        reason: 'before the server has spoken: the build default');
    expect(await c.read(serverConfigProvider.notifier).refresh(),
        ServerConfigRefresh.updated);
    expect(backend.where('GET', '/api/v1/config'), hasLength(1));
    expect(
        backend
            .where('GET', '/api/v1/config')
            .single
            .headers
            .keys
            .map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
        reason: 'the configuration is public');
    expect(c.read(featureFlagsProvider).ai, isFalse);
    expect(c.read(featureFlagsProvider).cloudSync, isTrue);
  });

  test(
      'an unreachable server leaves the cached (or default) configuration in force',
      () async {
    final (c, backend, _) = await make();
    backend.routes['GET /api/v1/config'] =
        (_) => FakeBackend.json(_config(cloudSync: false));
    await c.read(serverConfigProvider.notifier).refresh();
    expect(c.read(featureFlagsProvider).cloudSync, isFalse);
    backend.offline = true;
    expect(await c.read(serverConfigProvider.notifier).refresh(),
        ServerConfigRefresh.unavailable);
    expect(c.read(featureFlagsProvider).cloudSync, isFalse,
        reason: 'the last known switch stays');
  });

  test('refreshIfStale asks at most once per interval', () async {
    final (c, backend, advance) = await make();
    backend.routes['GET /api/v1/config'] = (_) => FakeBackend.json(_config());
    final notifier = c.read(serverConfigProvider.notifier);
    await notifier.refreshIfStale();
    await notifier.refreshIfStale();
    await notifier.refreshIfStale();
    expect(backend.where('GET', '/api/v1/config'), hasLength(1));
    advance(); // 20 minutes later
    await notifier.refreshIfStale();
    expect(backend.where('GET', '/api/v1/config'), hasLength(2));
  });

  test('a build without an API address has nothing to ask', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      prefsProvider.overrideWithValue(prefs),
      apiConfigProvider.overrideWithValue(const ApiConfig('')),
    ]);
    addTearDown(c.dispose);
    expect(c.read(serverConfigFetcherProvider), isNull);
    expect(await c.read(serverConfigProvider.notifier).refresh(),
        ServerConfigRefresh.noFetcher);
  });

  testWidgets('the AI card disappears when the server switches AI off',
      (tester) async {
    final h =
        await AppHarness.create(tester, platform: HarnessPlatform.android);
    var aiOn = true;
    h.backend.routes['GET /api/v1/config'] =
        (_) => FakeBackend.json(_config(ai: aiOn));
    await pumpScreen(
        tester, const Scaffold(body: SingleChildScrollView(child: AiCard())),
        harness: h);
    final card =
        find.descendant(of: find.byType(AiCard), matching: find.byType(WbCard));
    expect(card, findsOneWidget,
        reason:
            'before the server has spoken the build default (AI on) applies');
    final container = h.container(tester);
    aiOn = false; // the operator flips the kill switch
    await container.read(serverConfigProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(container.read(featureFlagsProvider).ai, isFalse);
    expect(card, findsNothing);
  });
}
