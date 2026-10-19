import 'package:http/http.dart' as http;

import '../sync_support.dart' show userOfToken;
import 'fake_backend.dart';

/// `GET` / `PUT /api/v1/me/settings` of the real API as a tiny in-memory server,
/// per user, with the same rules as `apps/api/src/modules/users/routes.ts`:
///
/// * a `null` field is read like the generated client sends it. The price MODE is
///   "not given" when null; a null country or currency clears it;
/// * manual mode needs a price (400 `manual_price_required`);
/// * an origin is one of `detected | manual | migratedManual`: `accountSynced`
///   (and anything else) is a 400 `validation`;
/// * an origin that is not sent survives only while its value is unchanged, a
///   cleared value has no origin.
class FakeAccountSettings {
  FakeAccountSettings(this.backend) {
    backend.routes['GET /api/v1/me/settings'] =
        (r) => FakeBackend.json(of(userOfToken(r.bearer)));
    backend.routes['PUT /api/v1/me/settings'] = (r) => _put(r);
  }

  final FakeBackend backend;
  final Map<String, Map<String, Object?>> _rows = {};

  /// Every accepted PUT body, newest last: what the phones actually sent.
  final List<Map<String, dynamic>> puts = [];

  static const origins = {'detected', 'manual', 'migratedManual'};

  /// The stored `UserSettingsDto` of [userId] (defaults before the first save).
  Map<String, Object?> of(String userId) =>
      _rows[userId] ??
      {
        'countryCode': null,
        'countryCodeSource': null,
        'currencyCode': null,
        'currencyCodeSource': null,
        'electricityPriceMode': 'automatic',
        'manualElectricityPrice': null,
        'electricityPriceSource': null,
        'updatedAt': '1970-01-01T00:00:00.000Z',
      };

  /// Writes a row as an OLDER client would have: values without origins.
  void seedLegacy(String userId,
      {String? country,
      String? currency,
      String mode = 'automatic',
      double? price}) {
    _rows[userId] = {
      ...of(userId),
      'countryCode': country,
      'currencyCode': currency,
      'electricityPriceMode': mode,
      'manualElectricityPrice': price,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// The origin the server stores for a value after a write.
  Object? _next(Object? given, bool changed, {bool cleared = false}) {
    if (cleared) return null;
    if (given != null) return given;
    return changed ? null : _keep;
  }

  static const _keep = Object();

  http.Response _put(Recorded r) {
    final user = userOfToken(r.bearer);
    final b = r.body!;
    for (final k in const [
      'countryCodeSource',
      'currencyCodeSource',
      'electricityPriceSource'
    ]) {
      final v = b[k];
      if (v != null && !origins.contains(v)) {
        return FakeBackend.error(400, 'validation', '$k: $v');
      }
    }
    final stored = of(user);
    final mode =
        (b['electricityPriceMode'] ?? stored['electricityPriceMode']) as String;
    final price = b.containsKey('manualElectricityPrice')
        ? b['manualElectricityPrice']
        : stored['manualElectricityPrice'];
    if (mode == 'manual' && price == null) {
      return FakeBackend.error(
          400, 'manual_price_required', 'manual mode needs a price');
    }
    final next = {...stored};
    void group(String valueKey, String sourceKey) {
      if (!b.containsKey(valueKey)) {
        if (b[sourceKey] != null) next[sourceKey] = b[sourceKey];
        return;
      }
      final value = b[valueKey];
      final changed = value != stored[valueKey];
      next[valueKey] = value;
      final s = _next(b[sourceKey], changed, cleared: value == null);
      if (!identical(s, _keep)) next[sourceKey] = s;
    }

    group('countryCode', 'countryCodeSource');
    group('currencyCode', 'currencyCodeSource');
    final priceChanged = mode != stored['electricityPriceMode'] ||
        price != stored['manualElectricityPrice'];
    next['electricityPriceMode'] = mode;
    next['manualElectricityPrice'] = price;
    final ps = _next(b['electricityPriceSource'], priceChanged);
    if (!identical(ps, _keep)) next['electricityPriceSource'] = ps;
    next['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    _rows[user] = next;
    puts.add(b);
    return FakeBackend.json(next);
  }
}
