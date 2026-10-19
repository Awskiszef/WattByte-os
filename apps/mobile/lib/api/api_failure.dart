import 'dart:async';
import 'dart:convert';

import '../generated/api/api.dart';

enum ApiFailureKind {
  /// No connection, DNS, TLS or socket failure; the request may not have reached the server.
  network,
  timeout,
  unauthorized,
  badRequest,
  notFound,
  conflict,
  rateLimited,
  server,
  other,
}

/// What went wrong with an API call, in terms the callers can act on.
///
/// The generated client reports every transport failure as `ApiException(400, ...)`
/// with an inner exception; a real `400` from the server has none. That ambiguity
/// is resolved here, once.
class ApiFailure implements Exception {
  const ApiFailure(this.kind,
      {this.status, this.code, this.message, this.retryAfter});

  final ApiFailureKind kind;
  final int? status;

  /// Machine code from the server's `{ error: { code } }` body, e.g. `ai_quota_exceeded`.
  final String? code;
  final String? message;

  /// How long the server asked us to wait (`Retry-After` on a 429 or 503), or null.
  /// The header reaches here through `RetryAfterClient`, which writes it into the
  /// response body of exactly that response.
  final Duration? retryAfter;

  /// The AI daily quota is used up. It is a business limit that only the passing of
  /// the day resets, so it is never a transport retry whatever `Retry-After` says.
  bool get isQuotaExceeded => code == 'ai_quota_exceeded';

  /// Retrying later can succeed.
  bool get isTransient => switch (kind) {
        ApiFailureKind.network ||
        ApiFailureKind.timeout ||
        ApiFailureKind.server =>
          true,
        ApiFailureKind.rateLimited => !isQuotaExceeded,
        _ => false,
      };

  static ApiFailure of(Object error) {
    if (error is ApiFailure) return error;
    if (error is TimeoutException) {
      return const ApiFailure(ApiFailureKind.timeout);
    }
    if (error is ApiException) {
      if (error.innerException != null) {
        return const ApiFailure(ApiFailureKind.network);
      }
      final body = _parseBody(error.message);
      final kind = switch (error.code) {
        401 => ApiFailureKind.unauthorized,
        400 => ApiFailureKind.badRequest,
        404 => ApiFailureKind.notFound,
        408 => ApiFailureKind.timeout,
        409 => ApiFailureKind.conflict,
        429 => ApiFailureKind.rateLimited,
        >= 500 => ApiFailureKind.server,
        _ => ApiFailureKind.other,
      };
      return ApiFailure(kind,
          status: error.code,
          code: body.code,
          message: body.message,
          retryAfter: body.retryAfter);
    }
    return const ApiFailure(ApiFailureKind.other);
  }

  static ({String? code, String? message, Duration? retryAfter}) _parseBody(
      String? body) {
    if (body == null || body.isEmpty) {
      return (code: null, message: null, retryAfter: null);
    }
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final e = j['error'];
        final seconds = (e is Map ? e['retryAfterSeconds'] : null) ??
            j['retryAfterSeconds'];
        return (
          code: e is Map && e['code'] is String ? e['code'] as String : null,
          message: e is Map && e['message'] is String
              ? e['message'] as String
              : null,
          retryAfter: seconds is int && seconds >= 0
              ? Duration(seconds: seconds)
              : null,
        );
      }
    } on FormatException {
      // Not our JSON error envelope (proxy page, empty body).
    }
    return (code: null, message: null, retryAfter: null);
  }

  @override
  String toString() =>
      'ApiFailure($kind, status: $status, code: $code${retryAfter == null ? '' : ', retryAfter: ${retryAfter!.inSeconds}s'})';
}

/// Runs [call] with a hard timeout and normalises every failure to [ApiFailure].
Future<T> guarded<T>(Future<T> Function() call,
    {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    return await call().timeout(timeout);
  } catch (e) {
    throw ApiFailure.of(e);
  }
}
