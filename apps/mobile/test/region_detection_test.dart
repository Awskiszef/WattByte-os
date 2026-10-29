import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/setup/region_detection.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import 'support/fake_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('currency mapping', () {
    test(
        'PL -> PLN, US -> USD, DE -> EUR, GB -> GBP, FR -> EUR, CH -> CHF, CZ -> CZK',
        () {
      expect(currencyForCountry('PL'), 'PLN');
      expect(currencyForCountry('US'), 'USD');
      expect(currencyForCountry('DE'), 'EUR');
      expect(currencyForCountry('GB'), 'GBP');
      expect(currencyForCountry('FR'), 'EUR');
      expect(currencyForCountry('CH'), 'CHF');
      expect(currencyForCountry('CZ'), 'CZK');
      expect(currencyForCountry('pl'), 'PLN', reason: 'case-insensitive');
    });

    test(
        'countries outside the table get no currency (user picks); garbage is empty',
        () {
      expect(currencyForCountry('TH'), 'THB');
      expect(currencyForCountry('AQ'), '', reason: 'Antarctica: no currency');
      expect(currencyForCountry('XX'), '');
      expect(currencyForCountry('Poland'), '');
      expect(currencyForCountry(''), '');
    });

    test('country from a locale tag', () {
      expect(countryFromLocaleTag('en-PL'), 'PL');
      expect(countryFromLocaleTag('pl_PL'), 'PL');
      expect(countryFromLocaleTag('pl'), isNull);
      expect(countryFromLocaleTag('zh-Hant-TW'), 'TW');
      expect(countryFromLocaleTag(null), isNull);
    });
  });

  group('RegionDetectionService', () {
    test('device Region setting wins over the locale and the backend',
        () async {
      final system = fakeSystem(deviceInfo: {
        'manufacturer': 'Apple',
        'model': 'iPhone',
        'modelIdentifier': 'iPhone16,1',
        'regionCode': 'pl',
        'localeTag': 'en-US',
      });
      var backendCalls = 0;
      final r = await RegionDetectionService(
        system: system,
        localeTag: () => 'en_US',
        backendCountry: () async {
          backendCalls++;
          return 'DE';
        },
      ).detect();
      expect(r!.countryCode, 'PL');
      expect(r.currencyCode, 'PLN');
      expect(r.source, RegionDetectionSource.deviceRegion);
      expect(r.confidence, greaterThan(0.8));
      expect(backendCalls, 0);
    });

    test('no Region setting -> locale country; none -> backend; none -> null',
        () async {
      final noRegion = fakeSystem(deviceInfo: {
        'manufacturer': 'Google',
        'model': 'Pixel 8',
        'modelIdentifier': 'Pixel 8',
        'regionCode': null,
        'localeTag': 'de-DE',
      });
      final fromLocale = await RegionDetectionService(
          system: noRegion, localeTag: () => 'en_GB').detect();
      expect(fromLocale!.countryCode, 'GB');
      expect(fromLocale.currencyCode, 'GBP');
      expect(fromLocale.source, RegionDetectionSource.deviceLocale);

      final fromBackend = await RegionDetectionService(
        system: noRegion,
        localeTag: () => 'en',
        backendCountry: () async => 'US',
      ).detect();
      // The plugin's own locale tag (de-DE) is still a device signal, so it comes first.
      expect(fromBackend!.countryCode, 'DE');

      final bare = fakeSystem(deviceInfo: {
        'manufacturer': '',
        'model': '',
        'modelIdentifier': '',
        'regionCode': null,
        'localeTag': null,
      });
      final backendOnly = await RegionDetectionService(
        system: bare,
        localeTag: () => 'en',
        backendCountry: () async => 'US',
      ).detect();
      expect(backendOnly!.source, RegionDetectionSource.backendCountry);
      expect(backendOnly.currencyCode, 'USD');

      final nothing = await RegionDetectionService(
        system: bare,
        localeTag: () => 'en',
        backendCountry: () async => throw const SocketExceptionLike(),
      ).detect();
      expect(nothing, isNull);
    });

    test('a missing platform implementation falls back to the locale',
        () async {
      final system = WattByteSystem(
          channel: const MethodChannel('wattbyte/system-missing'));
      final r =
          await RegionDetectionService(system: system, localeTag: () => 'pl_PL')
              .detect();
      expect(r!.countryCode, 'PL');
      expect(r.source, RegionDetectionSource.deviceLocale);
    });
  });
  test(
      'Bulgaria\'s default currency is the euro (adopted 2026-01-01), not the lev (C-09)',
      () {
    expect(currencyForCountry('BG'), 'EUR');
    expect(currencyForCountry('PL'), 'PLN');
    expect(currencyForCountry('HR'), 'EUR');
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
