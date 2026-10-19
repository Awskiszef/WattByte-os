import 'package:http/http.dart' as http;

import '../generated/api/api.dart';
import 'api_config.dart';
import 'retry_after_client.dart';

/// Builds clients of the generated API (`lib/generated/api`, never edited by hand).
///
/// Every client shares one [RetryAfterClient] over [httpClient] (or a plain
/// `http.Client`), so a `Retry-After` header on a `429`/`503` reaches
/// `ApiFailure.retryAfter` and connections are reused instead of one new socket
/// pool per request.
class ApiFactory {
  ApiFactory(this.config, {http.Client? httpClient, DateTime Function()? clock})
      : _http = httpClient,
        _clock = clock;

  final ApiConfig config;
  final http.Client? _http;
  final DateTime Function()? _clock;

  late final http.Client _client =
      RetryAfterClient(_http ?? http.Client(), clock: _clock);

  ApiClient _make(Authentication? auth) {
    final c = ApiClient(basePath: config.baseUrl, authentication: auth);
    c.client = _client;
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
