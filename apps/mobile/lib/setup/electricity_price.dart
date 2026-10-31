// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import '../api/api_factory.dart';
import '../api/api_failure.dart';
import '../api/session_manager.dart';
import '../generated/api/api.dart' as api;
import '../settings/settings.dart';

/// Household electricity price through the WattByte API only (the API talks to
/// Eurostat, caches and normalises). The app never calls the statistics source.
///
///   Flutter -> GET /api/v1/electricity-price?country=PL -> API -> Eurostat
///
/// Returns null when no source covers the country (HTTP 404); throws
/// [ApiFailure] when the API cannot be reached, so the caller keeps the last
/// known value.
class ElectricityPriceService {
  ElectricityPriceService({
    required this.apis,
    required this.sessions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ApiFactory apis;
  final SessionManager sessions;
  final DateTime Function() _clock;

  /// Cached automatic prices are refreshed at most this often (the source
  /// updates twice a year; the API caches for a week).
  static const refreshAfter = Duration(hours: 24);

  Future<AutoPrice?> fetch(String countryCode) async {
    try {
      final dto = await sessions.authorized((token) => guarded(() =>
          api.ElectricityApi(apis.bearer(token))
              .apiV1ElectricityPriceGet(country: countryCode)));
      if (dto == null) throw const ApiFailure(ApiFailureKind.server);
      return AutoPrice(
        pricePerKwh: dto.pricePerKwh.toDouble(),
        currency: dto.currency,
        countryCode: dto.countryCode,
        period: dto.period,
        source: dto.source_.toString(),
        updatedAt: _clock(),
        stale: dto.stale,
      );
    } on ApiFailure catch (f) {
      if (f.kind == ApiFailureKind.notFound) return null;
      rethrow;
    }
  }

  /// True when the stored automatic price is missing, for another country, or older than [refreshAfter].
  bool isStale(Settings s) {
    final a = s.autoPrice;
    if (a == null) return true;
    if (a.countryCode != s.countryCode) return true;
    return _clock().difference(a.updatedAt) >= refreshAfter;
  }
}
