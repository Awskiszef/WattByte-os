import 'package:flutter/foundation.dart';

// Where unexpected errors end up. There is deliberately no network crash reporter
// (see docs/privacy.md): errors are kept in a small in-memory ring for diagnostics
// and printed in debug builds only. Everything is passed through
// [sanitizeLogText] before it is stored or printed, because exception messages
// routinely carry what the user typed or what the server echoed back: request
// bodies with e-mail and password, `Authorization` headers, refresh tokens.

/// How many entries the log keeps; the oldest is dropped first.
const int kErrorLogCapacity = 50;

/// Per-entry limits, so one runaway exception cannot fill memory.
const int kMaxLogMessageChars = 1500;
const int kMaxLogStackLines = 12;
const int kMaxLogStackLineChars = 240;

/// Input longer than this is cut before the patterns run (and long before the
/// result is clipped), bounding the cost of sanitising a huge response body.
const int _kMaxSanitizeInput = 16000;

// A secret-looking key followed by `:` or `=` and its value: JSON
// (`"refreshToken":"..."`), Dart map output (`{password: x}`), query strings
// (`?token=...`), headers (`Authorization: Bearer ...`, `Cookie: ...`). The key
// is not anchored at its start, so `refresh_token`, `accessToken`, `X-Api-Key`
// and `clientSecret` match too. A value that is already `[redacted]` is left
// alone, which keeps [sanitizeLogText] idempotent.
//
// Two flavours differ only in where an unquoted value ends. Tokens, keys and
// headers never contain `&`, so a query string keeps its other parameters. A
// password may contain anything, `&` included, so for those keys the value runs
// to the next whitespace or delimiter: `password=a&b&country=PL` loses the
// country, not half of the password.
RegExp _secretKeyValueRegExp(String keys, {required bool stopAtAmpersand}) {
  final end = stopAtAmpersand ? r'\s,;&}\])"' : r'\s,;}\])"';
  return RegExp(
    "((?:$keys)[\\w.\\-]*)([\"']?)(\\s*[:=]\\s*)(?!\\[redacted\\])"
    "(?:\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"
    "|(?:(?:bearer|basic)\\s+)?[^$end']+)",
    caseSensitive: false,
  );
}

final RegExp _passwordKeyValue = _secretKeyValueRegExp(
  r'password|passwd|pwd|passphrase|secret',
  stopAtAmpersand: false,
);
final RegExp _tokenKeyValue = _secretKeyValueRegExp(
  r'token|api[_-]?key|authorization|credential|cookie',
  stopAtAmpersand: true,
);

// `Bearer <token>` outside a header: in a message, a log line, a stack trace.
final RegExp _bearer = RegExp(
  r'\b(Bearer)\s+[A-Za-z0-9._~+/=\-]{8,}',
  caseSensitive: false,
);

// `https://user:password@host`.
final RegExp _urlCredentials = RegExp(r'(://)[^/\s:@]+:[^/\s@]+@');

// A JSON Web Token: base64url header (always starts `eyJ`), payload, signature.
final RegExp _jwt = RegExp(r'\beyJ[\w\-]+\.[\w\-]+(?:\.[\w\-]*)?');

// The look-behinds anchor every match at the start of a run of token
// characters, which keeps the patterns linear on long inputs.
final RegExp _email = RegExp(
  r'(?<![\w.%+\-])[\w.%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
);

// 32 or more hex digits: session ids, hashes of tokens, hex-encoded keys.
final RegExp _longHex = RegExp(
  r'(?<![0-9A-Za-z])[0-9a-fA-F]{32,}(?![0-9A-Za-z])',
);

// 40 or more url-safe characters mixing letters and digits: an opaque token such
// as the API's refresh token (32 random bytes, base64url, 43 characters).
final RegExp _longOpaque = RegExp(
  r'(?<![\w\-])(?=[\w\-]*\d)(?=[\w\-]*[A-Za-z])[\w\-]{40,}',
);

// The account name in a home directory shows up in file URLs of stack traces.
final RegExp _unixHome = RegExp(r'(/Users/|/home/)[^/\s]+');
final RegExp _windowsHome = RegExp(r'([A-Za-z]:\\Users\\)[^\\\s]+');

/// Removes what must never reach a log from [input]:
///
/// * values of password / secret / token / api-key / authorization / cookie keys
///   (`"refreshToken":"..."`, `password=...`, `Authorization: Bearer ...`),
/// * `Bearer <token>` anywhere, `user:password@` in URLs,
/// * JWT-shaped strings, e-mail addresses,
/// * 32+ hex digits and 40+ character opaque tokens,
/// * the account name in `/Users/<name>` and `C:\Users\<name>` paths.
///
/// Replacements are `[redacted]`, `[jwt]`, `[email]`, `[hex]`, `[secret]` and
/// `[user]`. It over-redacts on purpose (`token: expired` loses `expired`):
/// a diagnostic log that is slightly vaguer is better than one that leaks.
/// Idempotent: sanitising twice gives the same text.
String sanitizeLogText(String input) {
  var s = input.length > _kMaxSanitizeInput
      ? input.substring(0, _kMaxSanitizeInput)
      : input;
  for (final keyValue in [_passwordKeyValue, _tokenKeyValue]) {
    s = s.replaceAllMapped(keyValue, (m) => '${m[1]}${m[2]}${m[3]}[redacted]');
  }
  s = s.replaceAllMapped(_bearer, (m) => '${m[1]} [redacted]');
  s = s.replaceAllMapped(_urlCredentials, (m) => '${m[1]}[redacted]@');
  s = s.replaceAll(_jwt, '[jwt]');
  s = s.replaceAll(_email, '[email]');
  s = s.replaceAll(_longHex, '[hex]');
  s = s.replaceAll(_longOpaque, '[secret]');
  s = s.replaceAllMapped(_unixHome, (m) => '${m[1]}[user]');
  s = s.replaceAllMapped(_windowsHome, (m) => '${m[1]}[user]');
  return s;
}

String _clip(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  // Do not cut a surrogate pair in half.
  final unit = s.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end--;
  return '${s.substring(0, end)}...[truncated]';
}

String _describe(Object error) {
  try {
    return error.toString();
  } catch (_) {
    // A broken toString() must not lose the report: keep what we can know.
    return '${error.runtimeType} (toString() threw)';
  }
}

/// A bounded, sanitised, in-memory error log. Nothing is persisted or sent.
///
/// [printEnabled] defaults to [kDebugMode]: release builds print nothing, they
/// only keep the ring. Tests inject [sink] and [printEnabled] to observe what
/// would be printed.
class ErrorLog {
  ErrorLog({
    this.capacity = kErrorLogCapacity,
    bool? printEnabled,
    void Function(String line)? sink,
    DateTime Function()? clock,
  })  : _printEnabled = printEnabled ?? kDebugMode,
        _sink = sink ?? _debugPrintSink,
        _clock = clock ?? DateTime.now;

  static void _debugPrintSink(String line) => debugPrint(line);

  final int capacity;
  final bool _printEnabled;
  final void Function(String line) _sink;
  final DateTime Function() _clock;
  final List<String> _entries = [];

  /// Oldest first, at most [capacity] entries, already sanitised.
  List<String> get entries => List.unmodifiable(_entries);

  String _header(String where) {
    final tag = _clip(sanitizeLogText(where), 40);
    return '${_clock().toIso8601String()} [$tag]';
  }

  /// Stores (and, when enabled, prints) one unexpected error.
  void report(Object error, StackTrace? stack, String where) {
    final message =
        _clip(sanitizeLogText(_describe(error)), kMaxLogMessageChars);
    final buffer = StringBuffer('${_header(where)} $message');
    if (stack != null) {
      final lines = stack
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(kMaxLogStackLines);
      for (final line in lines) {
        buffer
          ..write('\n')
          ..write(_clip(sanitizeLogText(line), kMaxLogStackLineChars));
      }
    }
    final entry = buffer.toString();
    _entries.add(entry);
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
    if (_printEnabled) _sink(entry);
  }

  /// A diagnostic line for developers: printed when enabled, never stored.
  void debug(String message, {String where = 'app'}) {
    if (!_printEnabled) return;
    _sink('${_header(where)} '
        '${_clip(sanitizeLogText(message), kMaxLogMessageChars)}');
  }
}

/// The app-wide log.
final ErrorLog errorLog = ErrorLog();

/// The most recent sanitised errors, oldest first.
List<String> get recentErrors => errorLog.entries;

void reportError(Object error, StackTrace? stack, String where) =>
    errorLog.report(error, stack, where);

/// Debug builds only; release builds print nothing.
void debugLog(String message, {String where = 'app'}) =>
    errorLog.debug(message, where: where);
