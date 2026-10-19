import 'package:wattbyte_system/wattbyte_system.dart';

/// How the region was established, most to least reliable.
enum RegionDetectionSource {
  /// The device's Region setting (iOS Settings > General > Language & Region;
  /// Android system locale country).
  deviceRegion,

  /// Country part of the preferred language tag (`en-PL` -> PL).
  deviceLocale,

  /// Coarse country reported by the API's edge proxy (`GET /region`).
  backendCountry,

  /// Chosen by the user in Settings.
  manual,
}

class DetectedRegion {
  const DetectedRegion({
    required this.countryCode,
    required this.currencyCode,
    required this.source,
    required this.confidence,
  });

  /// ISO 3166-1 alpha-2.
  final String countryCode;

  /// ISO 4217; empty when no currency is known for the country.
  final String currencyCode;
  final RegionDetectionSource source;

  /// 0-1, how likely the region is the user's home region (not a travel destination).
  final double confidence;

  @override
  String toString() =>
      'DetectedRegion($countryCode/$currencyCode, ${source.name}, $confidence)';
}

/// Default currency of a country (ISO 3166-1 alpha-2 -> ISO 4217).
///
/// An explicit table rather than CLDR lookups: `intl` only knows the locales it
/// ships data for, so `en_TH` would silently fall back to USD. A country that is
/// not listed gets no currency and the user is asked, which is the honest answer.
const kCurrencyByCountry = <String, String>{
  'PL': 'PLN',
  'US': 'USD',
  'GB': 'GBP',
  'DE': 'EUR',
  'FR': 'EUR',
  'IT': 'EUR',
  'ES': 'EUR',
  'NL': 'EUR',
  'BE': 'EUR',
  'AT': 'EUR',
  'PT': 'EUR',
  'IE': 'EUR',
  'FI': 'EUR',
  'GR': 'EUR',
  'SK': 'EUR',
  'SI': 'EUR',
  'EE': 'EUR',
  'LV': 'EUR',
  'LT': 'EUR',
  'LU': 'EUR',
  'MT': 'EUR',
  'CY': 'EUR',
  'HR': 'EUR',
  'ME': 'EUR',
  'XK': 'EUR',
  'AD': 'EUR',
  'MC': 'EUR',
  'SM': 'EUR',
  'VA': 'EUR',
  'CH': 'CHF',
  'LI': 'CHF',
  'CZ': 'CZK',
  'HU': 'HUF',
  'RO': 'RON',
  'BG': 'BGN',
  'SE': 'SEK',
  'NO': 'NOK',
  'DK': 'DKK',
  'IS': 'ISK',
  'UA': 'UAH',
  'MD': 'MDL',
  'BY': 'BYN',
  'RU': 'RUB',
  'GE': 'GEL',
  'AM': 'AMD',
  'AZ': 'AZN',
  'TR': 'TRY',
  'RS': 'RSD',
  'BA': 'BAM',
  'MK': 'MKD',
  'AL': 'ALL',
  'KZ': 'KZT',
  'IL': 'ILS',
  'AE': 'AED',
  'SA': 'SAR',
  'QA': 'QAR',
  'EG': 'EGP',
  'MA': 'MAD',
  'NG': 'NGN',
  'KE': 'KES',
  'ZA': 'ZAR',
  'CA': 'CAD',
  'MX': 'MXN',
  'BR': 'BRL',
  'AR': 'ARS',
  'CL': 'CLP',
  'CO': 'COP',
  'PE': 'PEN',
  'AU': 'AUD',
  'NZ': 'NZD',
  'JP': 'JPY',
  'KR': 'KRW',
  'CN': 'CNY',
  'HK': 'HKD',
  'TW': 'TWD',
  'SG': 'SGD',
  'MY': 'MYR',
  'TH': 'THB',
  'ID': 'IDR',
  'PH': 'PHP',
  'VN': 'VND',
  'IN': 'INR',
  'PK': 'PKR',
  'BD': 'BDT',
  'LK': 'LKR',
  'NP': 'NPR',
};

/// ISO 4217 code for a country, or empty when the table has no entry.
String currencyForCountry(String countryCode) {
  final cc = countryCode.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(cc)) return '';
  return kCurrencyByCountry[cc] ?? '';
}

/// Country code from a locale tag such as `en-PL`, `pl_PL` or `pl`; null when absent.
String? countryFromLocaleTag(String? tag) {
  if (tag == null) return null;
  final parts = tag.replaceAll('_', '-').split('-');
  for (final part in parts.skip(1)) {
    final p = part.toUpperCase();
    if (RegExp(r'^[A-Z]{2}$').hasMatch(p)) return p;
  }
  return null;
}

/// Finds the user's region without location permission:
///
///   1. device Region setting   (`DeviceInfo.regionCode`)
///   2. preferred-language tag  (`en-PL`)
///   3. API edge-proxy country  (optional, coarse)
///
/// Runs during the first setup and on an explicit "detect again"; never on
/// every launch, so a trip abroad does not flip the currency.
class RegionDetectionService {
  RegionDetectionService({
    required this.system,
    required this.localeTag,
    this.backendCountry,
  });

  final WattByteSystem system;

  /// Current app locale tag (`PlatformDispatcher.locale`), e.g. `en_PL`.
  final String? Function() localeTag;

  /// `GET /region`; null when there is no API or it reports nothing.
  final Future<String?> Function()? backendCountry;

  Future<DetectedRegion?> detect() async {
    DeviceInfo? info;
    try {
      info = await system.deviceInfo();
    } catch (_) {
      info = null; // platform side unavailable: fall through to the locale
    }
    final region = info?.regionCode;
    if (region != null) {
      return _result(region, RegionDetectionSource.deviceRegion, 0.9);
    }

    final fromLocale = countryFromLocaleTag(localeTag()) ??
        countryFromLocaleTag(info?.localeTag);
    if (fromLocale != null) {
      return _result(fromLocale, RegionDetectionSource.deviceLocale, 0.7);
    }

    final remote = backendCountry;
    if (remote != null) {
      try {
        final cc = await remote();
        if (cc != null) {
          return _result(cc, RegionDetectionSource.backendCountry, 0.5);
        }
      } catch (_) {
        // Offline or no proxy header: nothing more to try.
      }
    }
    return null;
  }

  static DetectedRegion _result(
          String cc, RegionDetectionSource source, double confidence) =>
      DetectedRegion(
        countryCode: cc.toUpperCase(),
        currencyCode: currencyForCountry(cc),
        source: source,
        confidence: confidence,
      );
}
