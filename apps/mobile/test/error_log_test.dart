import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/error_log.dart';

// Synthetic credentials: the shapes of the real ones, none of them valid.
const _jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiIxMjM0NTY3ODkwIiwicGxhbiI6ImZyZWUifQ.'
    'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

/// 32 random bytes in base64url, like `TokenService.newRefreshToken()`.
const _refresh = 'q8Z1xN4vB7cL0pRtY2uW5eH9kJ3mS6aD1fG8hT_Vb-w';
const _email = 'jan.kowalski+wb@poczta-test.pl';
const _password = 'Tr0ub4dor&3-horse';

void main() {
  group('sanitizeLogText', () {
    void expectClean(String raw, List<String> secrets, {String? reason}) {
      final out = sanitizeLogText(raw);
      for (final s in secrets) {
        expect(out, isNot(contains(s)),
            reason: reason ?? 'leaked "$s" in: $out');
      }
      expect(sanitizeLogText(out), out, reason: 'must be idempotent: $out');
    }

    test('an Authorization header keeps its name and loses its value', () {
      final out = sanitizeLogText(
          'GET /api/v1/me\nAuthorization: Bearer $_jwt\nAccept: */*');
      expect(out, contains('Authorization: [redacted]'));
      expect(out, contains('GET /api/v1/me'));
      expect(out, contains('Accept: */*'));
      expectClean(out, [_jwt, 'eyJ']);
    });

    test('Basic credentials in a header and a bare Bearer token are removed',
        () {
      expectClean(
          'authorization: Basic dXNlcjpwYXNzd29yZA==', ['dXNlcjpwYXNzd29yZA']);
      final out =
          sanitizeLogText('request failed with Bearer abcDEF0123456789xyz');
      expect(out, 'request failed with Bearer [redacted]');
    });

    test('a refresh token in JSON, in a Dart map and in a query string', () {
      final json =
          sanitizeLogText('{"refreshToken":"$_refresh","expiresIn":900}');
      expect(json, contains('"expiresIn":900'));
      expectClean(json, [_refresh]);

      final snake = sanitizeLogText("{'refresh_token': '$_refresh'}");
      expectClean(snake, [_refresh]);

      final map =
          sanitizeLogText('Bad request {refreshToken: $_refresh, deviceId: 7}');
      expect(map, contains('deviceId: 7'));
      expectClean(map, [_refresh]);

      final query = sanitizeLogText('POST /auth/refresh?token=$_refresh&x=1');
      expect(query, contains('x=1'));
      expectClean(query, [_refresh]);
    });

    test('a bare refresh token without any key is caught by its shape', () {
      final out = sanitizeLogText('session $_refresh was revoked');
      expect(out, 'session [secret] was revoked');
    });

    test('a JWT without a key or header', () {
      final out = sanitizeLogText('rejected token $_jwt after 3 attempts');
      expect(out, 'rejected token [jwt] after 3 attempts');
    });

    test('e-mail addresses, also inside JSON and URLs', () {
      expect(sanitizeLogText('No account for $_email.'),
          'No account for [email].');
      final json = sanitizeLogText('{"email":"$_email","country":"PL"}');
      expect(json, '{"email":"[email]","country":"PL"}');
      expectClean(
          'https://host.invalid/reset?to=$_email', [_email, 'kowalski']);
    });

    test('passwords in JSON and in a map', () {
      final json =
          sanitizeLogText('{"email":"$_email","password":"$_password"}');
      expectClean(json, [_password, _email]);
      final map = sanitizeLogText('{email: $_email, password: $_password}');
      expectClean(map, [_password, _email]);
      // A password may contain `&`: the whole value goes, not the part before it.
      final form = sanitizeLogText('password=$_password&country=PL');
      expect(form, 'password=[redacted]');
      expectClean(form, [_password, 'Tr0ub4dor', '3-horse']);
      // A token never contains `&`: the neighbouring parameter survives.
      expect(sanitizeLogText('access_token=$_refresh&country=PL'),
          'access_token=[redacted]&country=PL');
      expect(sanitizeLogText('{"password":12345,"country":"PL"}'),
          '{"password":[redacted],"country":"PL"}');
      expectClean('"password" : "two words and a quote \\" inside"',
          ['two words', 'inside']);
    });

    test('an ApiException with a body that echoes the request back', () {
      const error = 'ApiException 422: {"error":{"code":"validation_failed",'
          '"message":"Invalid input","details":[{"path":"email","value":"$_email"},'
          '{"path":"password","password":"$_password"}]},"echo":{"refreshToken":"$_refresh"}}';
      final out = sanitizeLogText(error);
      expect(out, contains('ApiException 422'));
      expect(out, contains('validation_failed'));
      expectClean(out, [_email, _password, _refresh]);
    });

    test('an ApiException with an inner exception and a stack trace', () {
      const raw = 'ApiException 401: Unauthorized (Inner exception: '
          'HttpException: Authorization: Bearer $_jwt)\n\n'
          '#0      ApiClient.invokeAPI (package:wattbyte/generated/api/api_client.dart:104:7)';
      final out = sanitizeLogText(raw);
      expect(out, contains('api_client.dart:104:7'));
      expectClean(out, [_jwt, 'eyJ']);
    });

    test('URL credentials, long hex ids and home directories', () {
      expectClean('connect https://svc:s3cr3tpass@db.example.org/x failed',
          ['s3cr3tpass', 'svc:']);
      final hex = 'a1b2c3d4' * 8;
      expect(sanitizeLogText('device $hex gone'), 'device [hex] gone');
      expect(sanitizeLogText('file:///Users/jan.kowalski/Library/App/x.dart:3'),
          'file:///Users/[user]/Library/App/x.dart:3');
      expect(sanitizeLogText(r'C:\Users\jan\AppData\x.dart'),
          r'C:\Users\[user]\AppData\x.dart');
    });

    test('ordinary diagnostics are left alone', () {
      const ordinary = [
        'Bad state: No element',
        'SocketException: Connection refused (OS Error: Connection refused, errno = 61), address = 127.0.0.1, port = 54321',
        '#0      SyncService._upload (package:wattbyte/sync/sync_service.dart:120:7)',
        'PlatformException(permission_denied, Usage access not granted, null, null)',
        'FormatException: Unexpected character (at character 1)',
        'RangeError (index): Invalid value: Not in inclusive range 0..3: 7',
        'Device 6b1f0e5c-8d1a-4f3b-9c2e-0a7d5e4f3b21 registered',
      ];
      for (final line in ordinary) {
        expect(sanitizeLogText(line), line);
      }
    });

    test('hostile inputs stay fast and are cut', () {
      final inputs = [
        'a' * 200000,
        '1' * 200000,
        'a.' * 100000,
        'eyJ' * 50000,
        'token=' * 30000,
        'a@' * 100000,
        'a1' * 100000,
        '-' * 200000,
      ];
      for (final input in inputs) {
        final sw = Stopwatch()..start();
        final out = sanitizeLogText(input);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000),
            reason: 'slow input starting ${input.substring(0, 6)}');
        expect(out.length, lessThanOrEqualTo(16000));
      }
    });
  });

  group('ErrorLog', () {
    late List<String> printed;

    ErrorLog make(
            {bool printEnabled = true, int capacity = kErrorLogCapacity}) =>
        ErrorLog(
          capacity: capacity,
          printEnabled: printEnabled,
          sink: printed.add,
          clock: () => DateTime.utc(2026, 10, 13, 12),
        );

    setUp(() => printed = []);

    test('keeps at most `capacity` entries, newest last', () {
      final log = make(capacity: 5);
      for (var i = 0; i < 12; i++) {
        log.report(StateError('failure $i'), null, 'test');
      }
      expect(log.entries, hasLength(5));
      expect(log.entries.first, contains('failure 7'));
      expect(log.entries.last, contains('failure 11'));
      expect(kErrorLogCapacity, 50);
    });

    test('release behaviour: nothing is printed, entries are still kept', () {
      final log = make(printEnabled: false);
      log.report(Exception('Authorization: Bearer $_jwt'), StackTrace.current,
          'flutter');
      log.debug('startup env=production');
      expect(printed, isEmpty);
      expect(log.entries, hasLength(1));
      expect(log.entries.single, isNot(contains('eyJ')));
    });

    test(
        'debug behaviour: prints the sanitised entry, `debug` lines are not stored',
        () {
      final log = make();
      log.report(Exception('login failed for $_email password=$_password'),
          null, 'setup register');
      log.debug('config: token=$_refresh');
      expect(printed, hasLength(2));
      expect(printed.first,
          startsWith('2026-10-13T12:00:00.000Z [setup register] '));
      for (final line in printed) {
        expect(line, isNot(contains(_email)));
        expect(line, isNot(contains(_password)));
        expect(line, isNot(contains(_refresh)));
      }
      expect(log.entries, hasLength(1));
    });

    test('by default printing follows kDebugMode', () {
      final lines = <String>[];
      ErrorLog(sink: lines.add).report(StateError('x'), null, 'test');
      expect(lines.isNotEmpty, kDebugMode);
    });

    test(
        'secrets in the message, the tag and every stack frame never reach the log',
        () {
      final log = make();
      final stack = StackTrace.fromString([
        '#0      ApiClient.invokeAPI (package:wattbyte/generated/api/api_client.dart:104:7)',
        '#1      AuthClient.send (file:///Users/jan.kowalski/dev/wattbyte/lib/x.dart:9:3) Authorization: Bearer $_jwt',
        '#2      Refresh.run (package:wattbyte/y.dart:1:1) refreshToken=$_refresh',
      ].join('\n'));
      log.report(
        'ApiException 400: {"email":"$_email","password":"$_password"}',
        stack,
        'tag $_email',
      );
      final entry = log.entries.single;
      for (final secret in [
        _jwt,
        'eyJ',
        _refresh,
        _email,
        _password,
        'kowalski'
      ]) {
        expect(entry, isNot(contains(secret)),
            reason: 'leaked $secret in $entry');
      }
      expect(entry, contains('api_client.dart:104:7'));
      expect(printed.single, entry);
    });

    test('stack and message length are bounded', () {
      final log = make();
      final stack = StackTrace.fromString(List.generate(
              100, (i) => '#$i      frame$i (package:wattbyte/f.dart:$i:1)')
          .join('\n'));
      log.report(StateError('x' * 50000), stack, 'test');
      final lines = log.entries.single.split('\n');
      expect(lines, hasLength(1 + kMaxLogStackLines));
      expect(
          log.entries.single.length,
          lessThan(kMaxLogMessageChars +
              kMaxLogStackLines * (kMaxLogStackLineChars + 20) +
              200));
      expect(lines.first, endsWith('...[truncated]'));
    });

    test('an error whose toString throws is still recorded', () {
      final log = make();
      log.report(_Hostile(), null, 'test');
      expect(log.entries.single, contains('_Hostile (toString() threw)'));
    });

    test('the global helpers share one sanitised ring', () {
      reportError(
          StateError('refresh_token=$_refresh for $_email'), null, 'global');
      final last = recentErrors.last;
      expect(last, contains('[global]'));
      expect(last, isNot(contains(_refresh)));
      expect(last, isNot(contains(_email)));
      expect(recentErrors.length, lessThanOrEqualTo(kErrorLogCapacity));
    });
  });

  group('release logging hygiene', () {
    test('lib/ prints only through error_log.dart', () {
      final offenders = <String>[];
      final printCall = RegExp(
          r'(^|[^\w.])(print|debugPrint|debugPrintStack|debugPrintSynchronously)\(');
      for (final f
          in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') ||
            path.startsWith('lib/generated/') ||
            path.startsWith('lib/l10n/generated/') ||
            path == 'lib/core/error_log.dart') {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].replaceFirst(RegExp(r'(?<!:)//.*$'), '');
          if (printCall.hasMatch(code) ||
              code.contains('developer.log(') ||
              code.contains('stdout.write') ||
              code.contains('stderr.write')) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'use debugLog()/reportError() from core/error_log.dart');
    });
  });
}

class _Hostile {
  @override
  String toString() => throw StateError('boom');
}
