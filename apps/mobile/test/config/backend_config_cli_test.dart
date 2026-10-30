import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/backend_config_cli.dart';

// Fixtures only: made-up hosts, never an address of this product.
const _https = 'https://api.ci-guard.dev';
const _http = 'http://api.ci-guard.test';
const _local = 'http://127.0.0.1:8080';
const _placeholder = 'https://api.ci-guard.invalid';

/// What one run of the check printed.
class _Run {
  _Run(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;

  String get all => '$out$err';

  @override
  String toString() => 'exit $code\nstdout: $out\nstderr: $err';
}

_Run _run(List<String> args) {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = runBackendConfigCheck(args, out: out, err: err);
  return _Run(code, out.toString(), err.toString());
}

/// The arguments of one build: `--build-mode` plus one `--dart-define` per
/// value that is set.
List<String> _args(
  String mode, {
  String? api,
  String? localOnlyDev,
  String? appEnv,
  List<String> extra = const [],
}) =>
    [
      '--build-mode=$mode',
      if (api != null) '--dart-define=API_BASE_URL=$api',
      if (localOnlyDev != null) '--dart-define=LOCAL_ONLY_DEV=$localOnlyDev',
      if (appEnv != null) '--dart-define=APP_ENV=$appEnv',
      ...extra,
    ];

void main() {
  group('the six cases of the specification', () {
    test('debug + API URL -> valid normal mode', () {
      final r = _run(_args('debug', api: _local));
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      expect(r.out.trim(), 'OK: online (debug)');
      expect(r.err, isEmpty);
    });

    test('debug + no API + LOCAL_ONLY_DEV=true -> valid local-only', () {
      final r = _run(_args('debug', localOnlyDev: 'true'));
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      expect(r.out.trim(), 'OK: localOnlyDev (debug)');
      expect(r.err, isEmpty);
    });

    test('debug + no API + LOCAL_ONLY_DEV=false -> invalid', () {
      final r = _run(_args('debug', localOnlyDev: 'false'));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expect(r.out, isEmpty);
      expect(r.err, startsWith('INVALID BUILD CONFIGURATION (debug)\n'));
      expect(r.err, contains('API_BASE_URL is required'));
    });

    test('release + API URL -> valid', () {
      final r = _run(_args('release', api: _https));
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      expect(r.out.trim(), 'OK: online (release)');
      expect(r.err, isEmpty);
    });

    test('release + no API -> invalid', () {
      final r = _run(_args('release'));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expect(r.out, isEmpty);
      expect(r.err, startsWith('INVALID BUILD CONFIGURATION (release)\n'));
      expect(r.err, contains('API_BASE_URL is required in release builds'));
    });

    test('release + LOCAL_ONLY_DEV=true -> invalid, with or without an API',
        () {
      for (final api in <String?>[null, _https]) {
        final r = _run(_args('release', api: api, localOnlyDev: 'true'));
        expect(r.code, kBackendConfigExitInvalid, reason: 'api=$api $r');
        expect(r.err, startsWith('INVALID BUILD CONFIGURATION (release)\n'));
        expect(r.err, contains('LOCAL_ONLY_DEV=true is only allowed in debug'));
      }
    });
  });

  group('the rest of the matrix', () {
    // (description, arguments, expected exit code)
    final cases = <(String, List<String>, int)>[
      ('debug, nothing set', _args('debug'), 1),
      (
        'debug, address + LOCAL_ONLY_DEV=false',
        _args('debug', api: _local, localOnlyDev: 'false'),
        0
      ),
      (
        'debug, address + LOCAL_ONLY_DEV=true is a contradiction',
        _args('debug', api: _local, localOnlyDev: 'true'),
        1
      ),
      (
        'debug, a broken address never degrades to local-only',
        _args('debug', api: 'not a url', localOnlyDev: 'true'),
        1
      ),
      (
        'debug, a broken address without the flag',
        _args('debug', api: 'not a url'),
        1
      ),
      (
        'debug, https address with APP_ENV=production',
        _args('debug', api: _https, appEnv: 'production'),
        0
      ),
      ('profile + https address', _args('profile', api: _https), 0),
      ('profile + no API', _args('profile'), 1),
      (
        'profile + LOCAL_ONLY_DEV=false + no API',
        _args('profile', localOnlyDev: 'false'),
        1
      ),
      (
        'profile + LOCAL_ONLY_DEV=true + address',
        _args('profile', api: _https, localOnlyDev: 'true'),
        1
      ),
      (
        'release + LOCAL_ONLY_DEV=false + no API',
        _args('release', localOnlyDev: 'false'),
        1
      ),
      (
        'release + LOCAL_ONLY_DEV=false + https address',
        _args('release', api: _https, localOnlyDev: 'false'),
        0
      ),
      (
        'release + production + https address',
        _args('release', api: _https, appEnv: 'production'),
        0
      ),
      (
        'release + staging + https address',
        _args('release', api: _https, appEnv: 'staging'),
        0
      ),
      (
        'release + production + http address',
        _args('release', api: _http, appEnv: 'production'),
        1
      ),
      (
        'release + production + .invalid placeholder',
        _args('release', api: _placeholder, appEnv: 'production'),
        1
      ),
      (
        'release + an APP_ENV typo gets the strictest rules (http refused)',
        _args('release', api: _http, appEnv: 'prod'),
        1
      ),
      (
        'release + address with credentials',
        _args('release',
            api: 'https://user:pw@api.ci-guard.test', appEnv: 'production'),
        1
      ),
      (
        'release + address that is not a URL',
        _args('release', api: 'api.ci-guard.test'),
        1
      ),
      ('whitespace is not an address', _args('release', api: '   '), 1),
      for (final spelling in ['TRUE', '1', 'yes', 'on'])
        (
          'LOCAL_ONLY_DEV=$spelling is not a boolean (fail closed)',
          _args('debug', localOnlyDev: spelling),
          1
        ),
    ];

    for (final (description, args, expected) in cases) {
      test(description, () {
        final r = _run(args);
        expect(r.code, expected, reason: '$r');
        if (expected == kBackendConfigExitOk) {
          expect(r.out, startsWith('OK: '));
          expect(r.err, isEmpty);
        } else {
          expect(r.out, isEmpty);
          expect(r.err, startsWith('INVALID BUILD CONFIGURATION ('));
        }
      });
    }

    test('every error is one "  - " line below the header', () {
      final r = _run(_args('release',
          api: _http, localOnlyDev: 'true', appEnv: 'production'));
      expect(r.code, kBackendConfigExitInvalid);
      final lines = r.err.trimRight().split('\n');
      expect(lines.first, 'INVALID BUILD CONFIGURATION (release)');
      expect(lines.length, greaterThan(2), reason: 'two rules are broken');
      expect(lines.skip(1), everyElement(startsWith('  - ')));
    });

    test('the build mode is case-insensitive and printed in lowercase', () {
      final r =
          _run(['--build-mode=Release', '--dart-define=API_BASE_URL=$_https']);
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      expect(r.out.trim(), 'OK: online (release)');
    });

    test('the option can also be written as "--option value"', () {
      final r = _run([
        '--build-mode',
        'release',
        '--dart-define',
        'API_BASE_URL=$_https',
        '--dart-define',
        'APP_ENV=production',
      ]);
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      final bad = _run(
          ['--build-mode', 'release', '--dart-define', 'LOCAL_ONLY_DEV=true']);
      expect(bad.code, kBackendConfigExitInvalid, reason: '$bad');
    });

    test('other defines are ignored, an empty --dart-define too', () {
      final r = _run(_args('release', api: _https, extra: [
        '--dart-define=FEATURE_AI=true',
        '--dart-define=PRIVACY_POLICY_URL=',
        '--dart-define=',
      ]));
      expect(r.code, kBackendConfigExitOk, reason: '$r');
    });

    test('a value may contain = and commas', () {
      final r = _run(_args('release', api: '$_https/path?a=1,b=2'));
      // The query is refused by the rules, but it was read as one value.
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expect(r.err, contains('query or fragment'));
    });
  });

  group(
      'define precedence (Flutter: files first, then --dart-define; last wins)',
      () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('wb_cfg_cli_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String file(String name, String content) {
      final f = File('${dir.path}/$name')..writeAsStringSync(content);
      return f.path;
    }

    test('a later --dart-define replaces an earlier one', () {
      final on = _run([
        '--build-mode=debug',
        '--dart-define=LOCAL_ONLY_DEV=false',
        '--dart-define=LOCAL_ONLY_DEV=true',
      ]);
      expect(on.code, kBackendConfigExitOk, reason: '$on');
      expect(on.out.trim(), 'OK: localOnlyDev (debug)');

      final off = _run([
        '--build-mode=debug',
        '--dart-define=LOCAL_ONLY_DEV=true',
        '--dart-define=LOCAL_ONLY_DEV=false',
      ]);
      expect(off.code, kBackendConfigExitInvalid, reason: '$off');
    });

    test('a later empty value unsets the define, like the compiler does', () {
      final r = _run([
        '--build-mode=release',
        '--dart-define=API_BASE_URL=$_https',
        '--dart-define=API_BASE_URL=',
      ]);
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expect(r.err, contains('API_BASE_URL is required in release builds'));
    });

    test('the last API_BASE_URL decides which address is validated', () {
      final r = _run([
        '--build-mode=release',
        '--dart-define=APP_ENV=production',
        '--dart-define=API_BASE_URL=$_http',
        '--dart-define=API_BASE_URL=$_https',
      ]);
      expect(r.code, kBackendConfigExitOk, reason: '$r');
    });

    test('--dart-define beats a file, whatever the order on the command line',
        () {
      final f = file('d.json', '{"LOCAL_ONLY_DEV": false}');
      final defineAfter = _run([
        '--build-mode=debug',
        '--dart-define-from-file=$f',
        '--dart-define=LOCAL_ONLY_DEV=true',
      ]);
      final defineBefore = _run([
        '--build-mode=debug',
        '--dart-define=LOCAL_ONLY_DEV=true',
        '--dart-define-from-file=$f',
      ]);
      for (final r in [defineAfter, defineBefore]) {
        expect(r.code, kBackendConfigExitOk, reason: '$r');
        expect(r.out.trim(), 'OK: localOnlyDev (debug)');
      }
    });

    test('a later file replaces an earlier one', () {
      final base = file(
          'base.json', '{"APP_ENV": "production", "API_BASE_URL": "$_http"}');
      final fix = file('fix.json', '{"API_BASE_URL": "$_https"}');
      expect(
          _run(['--build-mode=release', '--dart-define-from-file=$base']).code,
          kBackendConfigExitInvalid);
      final r = _run([
        '--build-mode=release',
        '--dart-define-from-file=$base',
        '--dart-define-from-file=$fix',
      ]);
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      final reversed = _run([
        '--build-mode=release',
        '--dart-define-from-file=$fix',
        '--dart-define-from-file=$base',
      ]);
      expect(reversed.code, kBackendConfigExitInvalid, reason: '$reversed');
    });

    test('a key repeated inside one file: the last one wins', () {
      final f = file(
          'dup.json', '{"API_BASE_URL": "$_http", "API_BASE_URL": "$_https"}');
      final r = _run(['--build-mode=release', '--dart-define-from-file=$f']);
      expect(r.code, kBackendConfigExitOk, reason: '$r');
    });
  });

  group('--dart-define-from-file', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('wb_cfg_cli_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String file(String content, {String name = 'defines.json'}) {
      final f = File('${dir.path}/$name')..writeAsStringSync(content);
      return f.path;
    }

    _Run runFile(String mode, String path) =>
        _run(['--build-mode=$mode', '--dart-define-from-file=$path']);

    test('JSON booleans are stringified like Flutter does: true -> "true"', () {
      final on = runFile('debug', file('{"LOCAL_ONLY_DEV": true}'));
      expect(on.code, kBackendConfigExitOk, reason: '$on');
      expect(on.out.trim(), 'OK: localOnlyDev (debug)');

      final off = runFile('debug', file('{"LOCAL_ONLY_DEV": false}'));
      expect(off.code, kBackendConfigExitInvalid, reason: '$off');

      final release = runFile('release',
          file('{"API_BASE_URL": "$_https", "LOCAL_ONLY_DEV": true}'));
      expect(release.code, kBackendConfigExitInvalid, reason: '$release');
      expect(release.err, contains('only allowed in debug'));

      final releaseFalse = runFile('release',
          file('{"API_BASE_URL": "$_https", "LOCAL_ONLY_DEV": false}'));
      expect(releaseFalse.code, kBackendConfigExitOk, reason: '$releaseFalse');
    });

    test('other JSON types become their Dart text: numbers, null', () {
      // 1 is not a boolean spelling; null becomes the text "null", which is
      // neither an address nor empty.
      final number = runFile('debug', file('{"LOCAL_ONLY_DEV": 1}'));
      expect(number.code, kBackendConfigExitInvalid, reason: '$number');
      expect(number.err, contains('LOCAL_ONLY_DEV must be true or false'));

      final nullAddress = runFile(
          'release', file('{"API_BASE_URL": null, "APP_ENV": "production"}'));
      expect(nullAddress.code, kBackendConfigExitInvalid,
          reason: '$nullAddress');
      expect(nullAddress.err, contains('not an absolute http(s) URL'));
    });

    test('a string "TRUE" is not a boolean (only true and false are)', () {
      final r = runFile('debug', file('{"LOCAL_ONLY_DEV": "TRUE"}'));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
    });

    test('keys starting with _ and unrelated keys are harmless', () {
      final r = runFile(
        'release',
        file('''
{
  "_NOTE": "Dart defines are readable inside the shipped app: no secrets here.",
  "_nested": {"a": [1, 2, {"b": null}]},
  "APP_ENV": "production",
  "API_BASE_URL": "$_https",
  "PRIVACY_POLICY_URL": "",
  "FEATURE_AI": true,
  "FEATURE_SUBSCRIPTIONS": false
}'''),
      );
      expect(r.code, kBackendConfigExitOk, reason: '$r');
      expect(r.out.trim(), 'OK: online (release)');
    });

    test('an empty object defines nothing', () {
      expect(runFile('release', file('{}')).code, kBackendConfigExitInvalid);
      expect(runFile('debug', file('{}')).code, kBackendConfigExitInvalid);
    });

    test('the example files of config/ behave as documented', () {
      // Tests run from apps/mobile (like native_config_test.dart).
      final development = runFile('debug', 'config/development.example.json');
      expect(development.code, kBackendConfigExitOk, reason: '$development');
      expect(development.out.trim(), 'OK: online (debug)');

      // Their hosts are .invalid placeholders: a release or profile build made
      // from an unedited copy must be refused.
      for (final name in ['production', 'staging']) {
        for (final mode in ['release', 'profile']) {
          final r = runFile(mode, 'config/$name.example.json');
          expect(r.code, kBackendConfigExitInvalid, reason: '$name $mode $r');
          expect(r.err, contains('placeholder host'));
        }
      }
    });

    test('unusable files are a usage error, not a verdict', () {
      final bad = <String, String>{
        'missing': '${dir.path}/does-not-exist.json',
        'directory': dir.path,
        'empty': file('', name: 'empty.json'),
        'not json': file('API_BASE_URL=$_https\n', name: 'x.env'),
        'truncated': file('{"API_BASE_URL": ', name: 'cut.json'),
        'array': file('["API_BASE_URL"]', name: 'array.json'),
        'string': file('"API_BASE_URL"', name: 'string.json'),
      };
      for (final entry in bad.entries) {
        final r = runFile('release', entry.value);
        expect(r.code, kBackendConfigExitUsage, reason: '${entry.key}: $r');
        expect(r.out, isEmpty);
        expect(r.err, contains('--dart-define-from-file'), reason: entry.key);
        expect(r.err, contains('Usage:'), reason: entry.key);
      }
    });

    test('a file that cannot be used is never treated as "no defines"', () {
      // A debug build that would otherwise be valid must not pass silently.
      final r = _run([
        '--build-mode=debug',
        '--dart-define=LOCAL_ONLY_DEV=true',
        '--dart-define-from-file=${dir.path}/does-not-exist.json',
      ]);
      expect(r.code, kBackendConfigExitUsage, reason: '$r');
    });
  });

  group('a build that ships is checked as production', () {
    test('release and profile without APP_ENV refuse http and placeholders',
        () {
      for (final mode in ['release', 'profile']) {
        for (final bad in [_http, _placeholder]) {
          final r = _run(_args(mode, api: bad));
          expect(r.code, kBackendConfigExitInvalid, reason: '$mode\n$r');
          expect(r.err, contains('API_BASE_URL'), reason: mode);
        }
        expect(_run(_args(mode, api: _https)).code, kBackendConfigExitOk,
            reason: mode);
      }
    });

    test('debug without APP_ENV is development: http is fine', () {
      expect(_run(_args('debug', api: _http)).code, kBackendConfigExitOk);
    });

    test('an explicit APP_ENV=development is refused in a release check (F-14)',
        () {
      final r = _run(_args('release', api: _local, appEnv: 'development'));
      expect(r.code, isNot(kBackendConfigExitOk));
      expect(_run(_args('release', api: _https, appEnv: 'development')).code,
          isNot(kBackendConfigExitOk),
          reason: 'not even with a public https address');
      expect(_run(_args('debug', api: _local, appEnv: 'development')).code,
          kBackendConfigExitOk);
    });
  });

  group('defines that override the build mode', () {
    test('dart.vm.* defines are rejected, wherever they come from', () {
      for (final extra in [
        ['--dart-define=dart.vm.product=false'],
        ['--dart-define=dart.vm.profile=false'],
        ['--dart-define=dart.vm.product=true'],
      ]) {
        for (final mode in ['debug', 'profile', 'release']) {
          final r = _run(_args(mode, api: _https, extra: extra));
          expect(r.code, kBackendConfigExitInvalid, reason: '$mode $extra\n$r');
          expect(r.err, contains('dart.vm.'), reason: '$mode $extra');
          expect(r.err, isNot(contains('=false')));
        }
      }
    });

    test('the spoofed local-only build (profile as "debug") is rejected', () {
      final r = _run(_args('profile',
          localOnlyDev: 'true',
          extra: ['--dart-define=dart.vm.profile=false']));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
    });

    test('also from a --dart-define-from-file', () {
      final dir = Directory.systemTemp.createTempSync('wb-cli-vm');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/spoof.json')
        ..writeAsStringSync(
            '{"API_BASE_URL": "$_https", "dart.vm.product": false}');
      final r = _run(
          ['--build-mode=release', '--dart-define-from-file=${file.path}']);
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expect(r.err, contains('dart.vm.'));
    });
  });

  group('usage errors exit with 64', () {
    final bad = <String, List<String>>{
      'no arguments': [],
      'no --build-mode': ['--dart-define=API_BASE_URL=$_https'],
      'unknown build mode': ['--build-mode=staging'],
      'empty build mode': ['--build-mode='],
      '--build-mode without a value': ['--build-mode'],
      '--build-mode given twice': ['--build-mode=debug', '--build-mode=debug'],
      'unknown option': ['--build-mode=release', '--api-base-url=$_https'],
      'a flag Flutter has but this tool does not': ['--release'],
      'a positional argument': ['--build-mode=release', _https],
      '--dart-define without a value': [
        '--build-mode=release',
        '--dart-define'
      ],
      '--dart-define without =': [
        '--build-mode=release',
        '--dart-define=API_BASE_URL'
      ],
      '--dart-define with an empty key': [
        '--build-mode=release',
        '--dart-define==x'
      ],
      '--dart-define-from-file without a value': [
        '--build-mode=release',
        '--dart-define-from-file'
      ],
      '--dart-define-from-file with an empty path': [
        '--build-mode=release',
        '--dart-define-from-file='
      ],
    };

    for (final entry in bad.entries) {
      test(entry.key, () {
        final r = _run(entry.value);
        expect(r.code, kBackendConfigExitUsage, reason: '$r');
        expect(r.out, isEmpty);
        expect(r.err, startsWith('check_backend_config: '));
        expect(
            r.err, contains('Usage: dart run tool/check_backend_config.dart'));
      });
    }

    test('--help prints the usage and succeeds', () {
      for (final flag in ['--help', '-h']) {
        final r = _run([flag]);
        expect(r.code, kBackendConfigExitOk, reason: '$r');
        expect(r.out,
            startsWith('Usage: dart run tool/check_backend_config.dart'));
        expect(r.err, isEmpty);
      }
    });

    test('--help next to other options is a usage error, never a verdict', () {
      for (final args in [
        [
          '--build-mode=release',
          '--dart-define=API_BASE_URL=$_https',
          '--help'
        ],
        ['--help', '--build-mode=release'],
        ['-h', '--build-mode=release'],
      ]) {
        final r = _run(args);
        expect(r.code, kBackendConfigExitUsage, reason: '$args\n$r');
        expect(r.out, isEmpty);
      }
    });

    test('a usage error is never the verdict "valid"', () {
      // Whatever else is wrong, only exit code 0 means the build may go on.
      for (final entry in bad.entries) {
        expect(_run(entry.value).code, isNot(kBackendConfigExitOk),
            reason: entry.key);
      }
    });
  });

  group('no define value is ever printed', () {
    // The address of a misconfigured build may carry credentials.
    const secret = 'hunter2';
    const credentialUrl =
        'https://deploy:$secret@api.ci-guard.test/v1?token=$secret';

    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('wb_cfg_cli_'));
    tearDown(() => dir.deleteSync(recursive: true));

    String file(String content) {
      final f = File('${dir.path}/secret.json')..writeAsStringSync(content);
      return f.path;
    }

    void expectNothingEchoed(_Run r, String what) {
      for (final fragment in [secret, 'ci-guard', 'deploy:', 'token=']) {
        expect(r.all, isNot(contains(fragment)),
            reason: '$what echoed "$fragment":\n$r');
      }
    }

    test('an invalid address', () {
      for (final mode in ['debug', 'profile', 'release']) {
        for (final env in [null, 'production']) {
          final r = _run(_args(mode, api: credentialUrl, appEnv: env));
          expect(r.code, kBackendConfigExitInvalid, reason: '$r');
          expectNothingEchoed(r, '$mode/$env');
        }
      }
    });

    test('an invalid address combined with LOCAL_ONLY_DEV', () {
      final r = _run(_args('debug', api: credentialUrl, localOnlyDev: 'true'));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expectNothingEchoed(r, 'debug + local-only');
    });

    test('a malformed LOCAL_ONLY_DEV value', () {
      final r = _run(_args('debug', localOnlyDev: secret));
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expectNothingEchoed(r, 'LOCAL_ONLY_DEV');
    });

    test('a valid address', () {
      for (final mode in ['debug', 'profile', 'release']) {
        final r = _run(_args(mode, api: '$_https/v1'));
        expect(r.code, kBackendConfigExitOk, reason: '$r');
        expectNothingEchoed(r, mode);
        expect(r.out.trim(), 'OK: online ($mode)');
      }
    });

    test('a value in a file', () {
      final r = _run([
        '--build-mode=release',
        '--dart-define-from-file=${file('{"API_BASE_URL": "$credentialUrl"}')}',
      ]);
      expect(r.code, kBackendConfigExitInvalid, reason: '$r');
      expectNothingEchoed(r, 'file');
    });

    test('a file that is not JSON', () {
      final r = _run([
        '--build-mode=release',
        '--dart-define-from-file=${file('API_BASE_URL=$credentialUrl')}',
      ]);
      expect(r.code, kBackendConfigExitUsage, reason: '$r');
      expectNothingEchoed(r, 'env file');
      final truncated = _run([
        '--build-mode=release',
        '--dart-define-from-file=${file('{"API_BASE_URL": "$credentialUrl')}',
      ]);
      expect(truncated.code, kBackendConfigExitUsage, reason: '$truncated');
      expectNothingEchoed(truncated, 'truncated file');
    });

    test('arguments that are not understood', () {
      final cases = <String, List<String>>{
        'unknown option': ['--build-mode=release', '--api=$credentialUrl'],
        'option that is not a name': [
          '--build-mode=release',
          '--$credentialUrl'
        ],
        'positional': ['--build-mode=release', credentialUrl],
        'define without =': ['--build-mode=release', '--dart-define=$secret'],
        'build mode': ['--build-mode=$credentialUrl'],
        'build mode twice': [
          '--build-mode=release',
          '--build-mode=$credentialUrl'
        ],
      };
      for (final entry in cases.entries) {
        final r = _run(entry.value);
        expect(r.code, kBackendConfigExitUsage, reason: '${entry.key}: $r');
        expectNothingEchoed(r, entry.key);
      }
    });
  });
}
