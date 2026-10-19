import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

/// An [http.Client] that makes `Retry-After` visible to the layers above.
///
/// The generated Dart client turns a failed response into an `ApiException(code,
/// body)` and throws the headers away, so the server's "come back in 30 seconds"
/// would be lost. This wrapper looks at the response of a `429` or `503` that
/// carries the header and writes the delay, in whole seconds, INTO THE RESPONSE
/// BODY as `error.retryAfterSeconds` (see [rewriteBody]); `ApiFailure.of` reads it
/// back out of `ApiException.message`.
///
/// Why the body: it travels with exactly the response it belongs to. There is no
/// shared field, no "last response" and no request id to correlate, so two
/// concurrent requests (or two clients) cannot see each other's delay.
class RetryAfterClient extends http.BaseClient {
  RetryAfterClient(this._inner, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final http.Client _inner;
  final DateTime Function() _clock;

  /// The statuses for which a `Retry-After` header is meaningful here.
  static const statuses = {429, 503};

  /// The longest delay a server can ask for (24 h); anything beyond is clamped.
  static const maxSeconds = 24 * 60 * 60;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (!statuses.contains(response.statusCode)) return response;
    final seconds = parse(response.headers['retry-after'], _clock());
    if (seconds == null) return response;
    final bytes = await response.stream.toBytes();
    final body = rewriteBody(utf8.decode(bytes, allowMalformed: true), seconds);
    final encoded = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(encoded),
      response.statusCode,
      contentLength: encoded.length,
      request: response.request,
      headers: {
        for (final e in response.headers.entries)
          if (e.key != 'content-length' &&
              e.key != 'content-encoding' &&
              e.key != 'content-type')
            e.key: e.value,
        'content-type': 'application/json; charset=utf-8',
        'content-length': '${encoded.length}',
      },
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

  /// `Retry-After` is either a number of seconds or an HTTP date (RFC 9110
  /// section 10.2.3). Returns whole seconds (rounded up, clamped to
  /// `[0, maxSeconds]`), or null for an absent or unparseable value.
  static int? parse(String? header, DateTime now) {
    final value = header?.trim();
    if (value == null || value.isEmpty) return null;
    final delta = int.tryParse(value);
    if (delta != null) {
      if (delta < 0) return null;
      return delta > maxSeconds ? maxSeconds : delta;
    }
    // A decimal ("1.5") is not valid HTTP but some proxies send it.
    final decimal = double.tryParse(value);
    if (decimal != null) {
      if (!decimal.isFinite || decimal < 0) return null;
      return decimal.ceil().clamp(0, maxSeconds);
    }
    try {
      final at = HttpDate.parse(value);
      final ms = at.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
      return (ms / 1000).ceil().clamp(0, maxSeconds);
    } on Object {
      // Not a date either: treated as absent, the caller's own backoff applies.
      return null;
    }
  }

  /// [body] with `error.retryAfterSeconds` set to [seconds]. A body that is not a
  /// JSON object (a proxy's HTML page, an empty body) is replaced by
  /// `{"error":{"retryAfterSeconds":N}}`: it carried nothing the app can use.
  static String rewriteBody(String body, int seconds) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        return jsonEncode({
          ...decoded,
          'error': {...error, 'retryAfterSeconds': seconds},
        });
      }
      return jsonEncode({...decoded, 'retryAfterSeconds': seconds});
    }
    return jsonEncode({
      'error': {'retryAfterSeconds': seconds}
    });
  }
}
