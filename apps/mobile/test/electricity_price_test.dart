// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_config.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/features/auth/data/secure_token_store.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/setup/electricity_price.dart';

import 'support/fake_auth.dart';
import 'support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late ElectricityPriceService service;
  var now = DateTime(2026, 10, 13, 12);

  Map<String, Object?> plPrice() => {
        'countryCode': 'PL',
        'currency': 'PLN',
        'pricePerKwh': 1.2724,
        'period': '2026-S1',
        'source': 'eurostat',
        'includesTaxes': true,
        'includesNetworkCosts': true,
        'updatedAt': '2026-10-13T09:00:00.000Z',
        'stale': false,
      };

  setUp(() async {
    backend = FakeBackend()
      ..routes['GET /api/v1/electricity-price'] =
          (_) => FakeBackend.json(plPrice());
    final store = InMemoryTokenStore();
    await store.write(session('a'));
    service = ElectricityPriceService(
      apis: ApiFactory(const ApiConfig('http://api.test'),
          httpClient: backend.client),
      sessions: SessionManager(store: store, repository: FakeAuthRepository()),
      clock: () => now,
    );
  });

  test('PL -> the API (never Eurostat directly) with a bearer token', () async {
    final p = await service.fetch('PL');
    expect(p!.pricePerKwh, 1.2724);
    expect(p.currency, 'PLN');
    expect(p.period, '2026-S1');
    expect(p.source, 'eurostat');
    expect(p.updatedAt, now);
    final req = backend.requests.single;
    expect(req.path, '/api/v1/electricity-price');
    expect(req.bearer, 'access-a');
    expect(backend.requests.every((r) => !r.path.contains('eurostat')), isTrue);
  });

  test('API unavailable -> the stored value stays (caller keeps the cache)',
      () async {
    var s = const Settings(countryCode: 'PL', currency: 'PLN')
        .withAutoPrice((await service.fetch('PL'))!);
    expect(s.pricePerKwh, 1.2724);

    backend.offline = true;
    await expectLater(service.fetch('PL'), throwsA(isA<ApiFailure>()));
    // Nothing in Settings changed; the dashboard keeps showing the last known price.
    expect(s.pricePerKwh, 1.2724);
    expect(s.autoPrice!.period, '2026-S1');

    // 23 h later: still fresh, no refresh needed; after 24 h it is stale.
    now = now.add(const Duration(hours: 23));
    expect(service.isStale(s), isFalse);
    now = now.add(const Duration(hours: 2));
    expect(service.isStale(s), isTrue);
    s = s.copyWith(countryCode: 'DE');
    expect(service.isStale(s), isTrue, reason: 'another country');
  });

  test('no source for the country (404) -> unavailable, no price is invented',
      () async {
    backend.routes['GET /api/v1/electricity-price'] =
        (_) => FakeBackend.error(404, 'electricity_price_unavailable');
    expect(await service.fetch('US'), isNull);
    const s = Settings(countryCode: 'US', currency: 'USD');
    expect(s.hasPrice, isFalse);
    expect(s.priceIsAverage, isFalse);
  });

  test('manual override is preserved: automatic refresh never overwrites it',
      () async {
    final auto = (await service.fetch('PL'))!;
    var s =
        const Settings(countryCode: 'PL', currency: 'PLN').withAutoPrice(auto);
    s = s.withManualPrice(0.95);
    expect(s.priceMode, ElectricityPriceMode.manual);
    expect(s.pricePerKwh, 0.95);

    final newer = AutoPrice(
        pricePerKwh: 1.4,
        currency: 'PLN',
        countryCode: 'PL',
        period: '2026-S2',
        source: 'eurostat',
        updatedAt: now);
    s = s.withAutoPrice(newer);
    expect(s.pricePerKwh, 0.95, reason: 'manual wins');
    expect(s.autoPrice!.pricePerKwh, 1.4,
        reason: 'but the newer average is kept');

    s = s.withAutomaticPrice();
    expect(s.pricePerKwh, 1.4);
    expect(s.manualPricePerKwh, 0.95,
        reason: 'the custom tariff survives for later');
  });

  test(
      'an automatic price in another currency than the chosen one is not applied',
      () async {
    final auto = (await service.fetch('PL'))!;
    final s = const Settings(countryCode: 'PL', currency: 'PLN')
        .withAutoPrice(auto)
        .withManualCurrency('EUR');
    expect(s.hasPrice, isFalse);
    expect(s.autoPrice, isNotNull);
    expect(s.withManualCurrency('PLN').pricePerKwh, 1.2724);
  });
}
