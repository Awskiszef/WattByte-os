// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:http/http.dart' as http;

import '../generated/api/api.dart';
import '../config/app_build.dart';
import 'api_config.dart';
import 'retry_after_client.dart';

/// Builds clients of the generated API (`lib/generated/api`, never edited by hand).
///
/// Every client shares one [RetryAfterClient] over [httpClient] (or a plain
/// `http.Client`), so a `Retry-After` header on a `429`/`503` reaches
/// `ApiFailure.retryAfter` and connections are reused instead of one new socket
/// pool per request.
class ApiFactory {
  ApiFactory(this.config,
      {http.Client? httpClient, DateTime Function()? clock, this.appBuild})
      : _http = httpClient,
        _clock = clock;

  final ApiConfig config;

  /// Sent as `X-WattByte-App` so the server can tell which builds are still in use (F-11). Null: no header.
  final AppBuildInfo? appBuild;
  final http.Client? _http;
  final DateTime Function()? _clock;

  late final http.Client _client =
      RetryAfterClient(_http ?? http.Client(), clock: _clock);

  ApiClient _make(Authentication? auth) {
    final c = ApiClient(basePath: config.baseUrl, authentication: auth);
    c.client = _client;
    final header = appBuild?.header;
    if (header != null) c.addDefaultHeader('X-WattByte-App', header);
    return c;
  }

  /// For register, login, refresh and logout.
  ApiClient anonymous() => _make(null);

  /// Sends `Authorization: Bearer <accessToken>`.
  ApiClient bearer(String accessToken) =>
      _make(HttpBearerAuth()..accessToken = accessToken);

  /// Releases the connection pool. The factory must not be used afterwards.
  void close() => _client.close();
}
