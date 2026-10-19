import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_environment.dart';
import 'package:wattbyte/config/backend_config.dart';

// Tests of the pure rule behind `AppConfig`, the release guard tool and the
// start-up check. No Flutter binding is needed: the build mode is an argument,
// so the release and profile rules are tested here directly (a `flutter test`
// run is always a debug build).
//
// Fixtures only: made-up hosts, never an address of this product.
const _api = 'https://api.sample-company.io';
const _localApi = 'http://127.0.0.1:8080';

const _debug = BuildMode.debug;
const _profile = BuildMode.profile;
const _release = BuildMode.release;

BackendConfigCheck _check(
  BuildMode mode, {
  String api = '',
  String flag = '',
  AppEnvironment env = AppEnvironment.development,
}) =>
    validateBackendConfig(
      buildMode: mode,
      apiBaseUrl: api,
      localOnlyDev: flag,
      environment: env,
    );

/// A matcher for "this list of errors has a line that mentions all of [words]".
Matcher _hasError(List<String> words) =>
    contains(allOf(words.map(contains).toList()));

void _expectOnline(BackendConfigCheck c, {String? reason}) {
  expect(c.mode, BackendMode.online, reason: reason);
  expect(c.isValid, isTrue, reason: reason);
  expect(c.errors, isEmpty, reason: reason);
}

void _expectLocalOnly(BackendConfigCheck c, {String? reason}) {
  expect(c.mode, BackendMode.localOnlyDev, reason: reason);
  expect(c.isValid, isTrue, reason: reason);
  expect(c.errors, isEmpty, reason: reason);
}

void _expectInvalid(BackendConfigCheck c, {String? reason}) {
  expect(c.mode, isNull, reason: reason);
  expect(c.isValid, isFalse, reason: reason);
  expect(c.errors, isNotEmpty, reason: reason);
}

void main() {
  // The six cases the product owner asked for, under exactly these names.

  test('debug + API URL -> valid normal mode', () {
    _expectOnline(_check(_debug, api: _api));
    _expectOnline(_check(_debug, api: _localApi), reason: 'local API');
    _expectOnline(_check(_debug, api: _api, flag: 'false'),
        reason: 'LOCAL_ONLY_DEV=false changes nothing');
  });

  test('debug + no API + LOCAL_ONLY_DEV=true -> valid local-only', () {
    _expectLocalOnly(_check(_debug, flag: 'true'));
  });

  test('debug + no API + LOCAL_ONLY_DEV=false -> invalid', () {
    final c = _check(_debug, flag: 'false');
    _expectInvalid(c);
    // The error tells the developer the way out.
    expect(c.errors,
        _hasError(['API_BASE_URL', 'required', 'LOCAL_ONLY_DEV=true']));
    // Unset is the same as false: the default is never local-only.
    _expectInvalid(_check(_debug));
  });

  test('release + API URL -> valid', () {
    _expectOnline(_check(_release, api: _api));
  });

  test('release + no API -> invalid', () {
    final c = _check(_release);
    _expectInvalid(c);
    expect(c.errors, _hasError(['API_BASE_URL', 'required', 'release']));
  });

  test('release + LOCAL_ONLY_DEV=true -> invalid', () {
    final c = _check(_release, flag: 'true');
    _expectInvalid(c);
    expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'debug']));
    _expectInvalid(_check(_release, api: _api, flag: 'true'),
        reason: 'not even with an API address');
  });

  group('profile builds follow the release rules', () {
    test('profile + API URL -> valid', () {
      _expectOnline(_check(_profile, api: _api));
    });

    test('profile + no API -> invalid', () {
      final c = _check(_profile);
      _expectInvalid(c);
      expect(c.errors, _hasError(['API_BASE_URL', 'required', 'profile']));
      _expectInvalid(_check(_profile, flag: 'false'));
    });

    test('profile + no API + LOCAL_ONLY_DEV=true -> invalid', () {
      final c = _check(_profile, flag: 'true');
      _expectInvalid(c);
      expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'debug', 'profile']));
    });

    test('profile + API + LOCAL_ONLY_DEV=true -> invalid', () {
      final c = _check(_profile, api: _api, flag: 'true');
      _expectInvalid(c);
      expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'debug', 'profile']));
    });
  });

  group('release builds', () {
    test('release + API + LOCAL_ONLY_DEV=false -> valid', () {
      _expectOnline(_check(_release, api: _api, flag: 'false'));
    });

    test('release + no API + LOCAL_ONLY_DEV=true reports both reasons', () {
      final c = _check(_release, flag: 'true');
      _expectInvalid(c);
      expect(c.errors, hasLength(2));
      expect(c.errors, _hasError(['API_BASE_URL', 'required']));
      expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'only allowed in debug']));
    });

    test('release + no API + LOCAL_ONLY_DEV=false is invalid, one reason', () {
      final c = _check(_release, flag: 'false');
      _expectInvalid(c);
      expect(c.errors, hasLength(1));
      expect(c.errors, _hasError(['API_BASE_URL', 'required']));
    });
  });

  group('debug builds', () {
    test('API + LOCAL_ONLY_DEV=true is a contradiction, not local-only', () {
      final c = _check(_debug, api: _api, flag: 'true');
      _expectInvalid(c);
      expect(c.errors, hasLength(1));
      expect(c.errors.single,
          allOf(contains('LOCAL_ONLY_DEV'), contains('API_BASE_URL')));
    });
  });

  group('a present but invalid address', () {
    // address -> a word the error has to say about it.
    const invalidAddresses = {
      'api.sample-company.io': 'absolute',
      '//api.sample-company.io': 'absolute',
      'https://': 'absolute',
      'ftp://api.sample-company.io': 'http or https',
      'https://user:secret@api.sample-company.io': 'credentials',
      'https://api.sample-company.io?x=1': 'query or fragment',
      'https://api.sample-company.io#top': 'query or fragment',
      'https://exa mple.com': 'invalid host',
      'https://api.sample-company.io:99999': 'invalid port',
    };

    test('is invalid in every build mode, with or without the flag', () {
      for (final entry in invalidAddresses.entries) {
        for (final mode in BuildMode.values) {
          for (final flag in ['', 'false', 'true']) {
            final why = '${mode.name}, "${entry.key}", flag="$flag"';
            final c = _check(mode, api: entry.key, flag: flag);
            _expectInvalid(c, reason: why);
            expect(c.errors, _hasError(['API_BASE_URL', entry.value]),
                reason: why);
            // It is diagnosed as wrong, not as missing.
            expect(c.errors.where((e) => e.contains('is required')), isEmpty,
                reason: why);
          }
        }
      }
    });

    test('never degrades to local-only, also with LOCAL_ONLY_DEV=true in debug',
        () {
      for (final address in invalidAddresses.keys) {
        final c = _check(_debug, api: address, flag: 'true');
        expect(c.mode, isNot(BackendMode.localOnlyDev), reason: address);
        expect(c.isValid, isFalse, reason: address);
      }
      // The environment rule sets are part of "valid" too.
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        for (final api in ['http://api.sample-company.io', _localApi]) {
          final c = _check(_debug, api: api, flag: 'true', env: env);
          expect(c.isValid, isFalse, reason: '${env.name} $api');
          expect(c.mode, isNull, reason: '${env.name} $api');
        }
      }
    });
  });

  group('an absent address', () {
    test('is empty, whitespace or slashes only', () {
      for (final absent in ['', '   ', '\t', '/', '///', ' / ']) {
        final why = 'address="$absent"';
        _expectLocalOnly(_check(_debug, api: absent, flag: 'true'),
            reason: why);
        _expectInvalid(_check(_debug, api: absent), reason: why);
        _expectInvalid(_check(_debug, api: absent, flag: 'false'), reason: why);
        _expectInvalid(_check(_profile, api: absent), reason: why);
        _expectInvalid(_check(_release, api: absent), reason: why);
        _expectInvalid(_check(_release, api: absent, flag: 'true'),
            reason: why);
      }
    });

    test('a valid address with whitespace and slashes around it still counts',
        () {
      _expectOnline(_check(_release, api: '  $_api/  '));
      _expectOnline(_check(_debug, api: ' $_api '));
    });
  });

  group('the LOCAL_ONLY_DEV spelling', () {
    const malformed = [
      '1',
      '0',
      'TRUE',
      'True',
      'FALSE',
      'yes',
      'no',
      'on',
      'off',
      'tru',
      'bogus',
      't'
    ];

    test('anything but true / false is an error in every mode (fail closed)',
        () {
      for (final flag in malformed) {
        for (final mode in BuildMode.values) {
          for (final api in ['', _api]) {
            final why = '${mode.name}, API="$api", flag="$flag"';
            final c = _check(mode, api: api, flag: flag);
            _expectInvalid(c, reason: why);
            expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'true or false']),
                reason: why);
          }
        }
      }
    });

    test('a malformed flag in debug without an API is never local-only', () {
      for (final flag in malformed) {
        final c = _check(_debug, flag: flag);
        expect(c.mode, isNull, reason: flag);
      }
    });

    test('surrounding whitespace is ignored: " true " is true, " false " false',
        () {
      _expectLocalOnly(_check(_debug, flag: ' true '));
      _expectLocalOnly(_check(_debug, flag: '\ttrue\n'));
      _expectInvalid(_check(_debug, flag: ' false '));
      _expectOnline(_check(_debug, api: _api, flag: ' false '));
      _expectOnline(_check(_release, api: _api, flag: ' false '));
      _expectInvalid(_check(_release, flag: ' true '));
      _expectInvalid(_check(_release, api: _api, flag: ' true '));
      _expectInvalid(_check(_debug, api: _api, flag: ' true '));
    });

    test('a whitespace-only flag counts as unset', () {
      _expectInvalid(_check(_debug, flag: '   '));
      _expectOnline(_check(_debug, api: _api, flag: '   '));
      _expectOnline(_check(_release, api: _api, flag: '   '));
    });
  });

  group('APP_ENV decides which addresses are valid', () {
    test('staging and production refuse cleartext, also in debug', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        for (final flag in ['', 'false', 'true']) {
          for (final api in ['http://api.sample-company.io', _localApi]) {
            final c = _check(_debug, api: api, flag: flag, env: env);
            _expectInvalid(c, reason: '${env.name} $api flag="$flag"');
            expect(c.errors, _hasError(['https', env.name]),
                reason: '${env.name} $api');
          }
        }
      }
    });

    test('https is valid in every environment and mode', () {
      for (final env in AppEnvironment.values) {
        for (final mode in BuildMode.values) {
          _expectOnline(_check(mode, api: _api, env: env),
              reason: '${env.name} ${mode.name}');
        }
      }
    });

    test('development accepts http', () {
      _expectOnline(_check(_debug, api: _localApi));
      _expectOnline(_check(_debug, api: 'http://10.0.2.2:8080'));
    });

    test('the .invalid placeholders of the example files are refused', () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        for (final mode in BuildMode.values) {
          final c = _check(mode, api: 'https://api.wattbyte.invalid', env: env);
          _expectInvalid(c, reason: '${env.name} ${mode.name}');
          expect(c.errors, _hasError(['API_BASE_URL', 'placeholder']));
        }
      }
    });

    test(
        'an absent address is invalid in every environment but the debug '
        'local-only one', () {
      for (final env in AppEnvironment.values) {
        _expectInvalid(_check(_release, env: env), reason: env.name);
        _expectInvalid(_check(_debug, env: env), reason: env.name);
        _expectInvalid(_check(_release, flag: 'true', env: env),
            reason: env.name);
      }
    });
  });

  group('LOCAL_ONLY_DEV is a development-environment mode', () {
    test('debug + no API + LOCAL_ONLY_DEV=true + APP_ENV staging/production',
        () {
      for (final env in [AppEnvironment.staging, AppEnvironment.production]) {
        final c = _check(_debug, flag: 'true', env: env);
        _expectInvalid(c, reason: env.name);
        expect(c.errors, _hasError(['LOCAL_ONLY_DEV', 'development', env.name]),
            reason: env.name);
      }
    });

    test('the development environment (the default) still allows it', () {
      _expectLocalOnly(
          _check(_debug, flag: 'true', env: AppEnvironment.development));
    });
  });

  group('effectiveBuildMode: a binary that says debug but runs no asserts', () {
    test('is validated as a release build (dart.vm.* overridden by hand)', () {
      expect(effectiveBuildMode(compiled: _debug, assertsEnabled: false),
          _release);
    });

    test('a real debug build (assertions run) stays debug', () {
      expect(
          effectiveBuildMode(compiled: _debug, assertsEnabled: true), _debug);
    });

    test('profile and release never become anything else', () {
      for (final mode in [_profile, _release]) {
        for (final asserts in [true, false]) {
          expect(
              effectiveBuildMode(compiled: mode, assertsEnabled: asserts), mode,
              reason: '${mode.name} asserts=$asserts');
        }
      }
    });

    test('so a spoofed profile/release AOT binary cannot be local-only', () {
      // `-Ddart.vm.profile=false` makes a profile binary compile as "debug";
      // AOT runs no asserts, so the effective mode is release.
      final mode = effectiveBuildMode(compiled: _debug, assertsEnabled: false);
      _expectInvalid(_check(mode, flag: 'true'));
      _expectInvalid(_check(mode));
    });
  });

  group('effectiveEnvironment: a build that ships is production by default',
      () {
    test('debug without APP_ENV is development (a plain flutter run)', () {
      for (final raw in ['', '  ']) {
        expect(effectiveEnvironment(buildMode: _debug, appEnv: raw),
            AppEnvironment.development);
      }
    });

    test('profile and release without APP_ENV are production', () {
      for (final mode in [_profile, _release]) {
        for (final raw in ['', '  ']) {
          expect(effectiveEnvironment(buildMode: mode, appEnv: raw),
              AppEnvironment.production,
              reason: mode.name);
        }
      }
    });

    test('an explicit APP_ENV is honoured in every mode, a typo is production',
        () {
      for (final mode in BuildMode.values) {
        expect(effectiveEnvironment(buildMode: mode, appEnv: 'staging'),
            AppEnvironment.staging);
        expect(effectiveEnvironment(buildMode: mode, appEnv: ' Production '),
            AppEnvironment.production);
        expect(effectiveEnvironment(buildMode: mode, appEnv: 'prod'),
            AppEnvironment.production);
      }
      expect(effectiveEnvironment(buildMode: _debug, appEnv: 'development'),
          AppEnvironment.development);
      expect(effectiveEnvironment(buildMode: _release, appEnv: 'development'),
          AppEnvironment.development,
          reason: 'explicit is explicit (the flag rules and the guard stop '
              'a release build from going local-only regardless)');
    });

    test(
        'so a release build without APP_ENV refuses cleartext and placeholders',
        () {
      for (final mode in [_profile, _release]) {
        final env = effectiveEnvironment(buildMode: mode, appEnv: '');
        _expectInvalid(
            _check(mode, api: 'http://api.sample-company.io', env: env),
            reason: mode.name);
        _expectInvalid(
            _check(mode, api: 'https://api.wattbyte.invalid', env: env),
            reason: mode.name);
        _expectOnline(_check(mode, api: _api, env: env), reason: mode.name);
      }
    });
  });

  group('errors carry no value', () {
    const secretAddresses = [
      'https://user:hunter2@api.sample-company.io/secret-path',
      'http://api.sample-company.io/secret-path',
      'ftp://api.sample-company.io/secret-path?token=abc',
      'https://api.sample-company.io/secret path',
    ];

    test('no error contains the address, a credential or the path', () {
      for (final address in secretAddresses) {
        for (final mode in BuildMode.values) {
          for (final flag in ['', 'false', 'true']) {
            for (final env in AppEnvironment.values) {
              final c = _check(mode, api: address, flag: flag, env: env);
              for (final e in c.errors) {
                final why = '${mode.name} ${env.name} flag="$flag": $e';
                expect(e, isNot(contains('hunter2')), reason: why);
                expect(e, isNot(contains('sample-company')), reason: why);
                expect(e, isNot(contains('secret')), reason: why);
                expect(e, isNot(contains('token')), reason: why);
              }
            }
          }
        }
      }
    });

    test('no error echoes a malformed flag value', () {
      const spelling = 'maybe-later';
      for (final mode in BuildMode.values) {
        final c = _check(mode, api: _api, flag: spelling);
        _expectInvalid(c);
        for (final e in c.errors) {
          expect(e, isNot(contains(spelling)));
        }
      }
    });

    test('every error is a single readable line', () {
      for (final mode in BuildMode.values) {
        for (final flag in ['', 'true', 'bogus']) {
          for (final api in ['', _api, 'ftp://x.test']) {
            for (final e in _check(mode, api: api, flag: flag).errors) {
              expect(e.trim(), isNotEmpty);
              expect(e, isNot(contains('\n')));
            }
          }
        }
      }
    });
  });

  group('the result object', () {
    test('errors of an invalid result cannot be modified', () {
      final c = _check(_release, flag: 'true');
      expect(c.errors, isNotEmpty);
      expect(() => c.errors.add('x'), throwsUnsupportedError);
      expect(() => c.errors.clear(), throwsUnsupportedError);
    });

    test('errors of a valid result are empty and cannot be modified', () {
      final c = _check(_debug, api: _api);
      expect(c.errors, isEmpty);
      expect(() => c.errors.add('x'), throwsUnsupportedError);
    });

    test('valid, mode and errors always agree', () {
      for (final mode in BuildMode.values) {
        for (final api in ['', _api, 'ftp://x.test']) {
          for (final flag in ['', 'false', 'true', 'bogus']) {
            final c = _check(mode, api: api, flag: flag);
            final why = '${mode.name}, "$api", flag="$flag"';
            expect(c.isValid, c.mode != null, reason: why);
            expect(c.errors.isEmpty, c.isValid, reason: why);
          }
        }
      }
    });

    test('the same input always gives the same verdict', () {
      for (final mode in BuildMode.values) {
        final a = _check(mode, api: _api, flag: 'true');
        final b = _check(mode, api: _api, flag: 'true');
        expect(a.mode, b.mode);
        expect(a.errors, b.errors);
      }
    });
  });

  group('BuildMode.tryParse', () {
    test('names parse regardless of case and whitespace', () {
      expect(BuildMode.tryParse('debug'), BuildMode.debug);
      expect(BuildMode.tryParse('profile'), BuildMode.profile);
      expect(BuildMode.tryParse('release'), BuildMode.release);
      expect(BuildMode.tryParse(' Release '), BuildMode.release);
      expect(BuildMode.tryParse('DEBUG'), BuildMode.debug);
      expect(BuildMode.tryParse('\tprofile\n'), BuildMode.profile);
    });

    test('anything else is null', () {
      for (final raw in [
        '',
        '  ',
        'prod',
        'production',
        'releasee',
        'dev',
        null
      ]) {
        expect(BuildMode.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('wireName is the lowercase name and parses back', () {
      for (final mode in BuildMode.values) {
        expect(mode.wireName, mode.name);
        expect(mode.wireName, mode.wireName.toLowerCase());
        expect(BuildMode.tryParse(mode.wireName), mode);
      }
      expect(BuildMode.values, hasLength(3));
    });
  });

  group('exhaustive cross-product', () {
    // The oracle: a truth table written out by hand from the rules in the
    // product owner's brief, one row per combination. It is deliberately a
    // table and not a second implementation of the rule:
    //
    //   * API_BASE_URL is required, unless the build is debug AND
    //     LOCAL_ONLY_DEV is true;
    //   * LOCAL_ONLY_DEV=true is only allowed in debug, and not next to an API
    //     address (a contradiction);
    //   * an address that is present but wrong is an error, never "no backend";
    //   * LOCAL_ONLY_DEV is exactly true or false (or unset): anything else is
    //     an error, whatever the rest says.
    const none = _Address.none;
    const valid = _Address.valid;
    const wrong = _Address.wrong;
    const online = _Verdict.online;
    const localOnly = _Verdict.localOnly;
    const invalid = _Verdict.invalid;

    const table = <(BuildMode, _Address, String, _Verdict)>[
      // build    address  LOCAL_ONLY_DEV  expected
      (_debug, none, '', invalid), //  no backend, nothing explicit
      (
        _debug,
        none,
        'false',
        invalid
      ), //  no backend, explicitly not local-only
      (_debug, none, 'true', localOnly), //  the one local-only case
      (_debug, none, 'bogus', invalid),
      (_debug, valid, '', online), //  normal development
      (_debug, valid, 'false', online),
      (_debug, valid, 'true', invalid), //  contradiction
      (_debug, valid, 'bogus', invalid),
      (_debug, wrong, '', invalid),
      (_debug, wrong, 'false', invalid),
      (_debug, wrong, 'true', invalid), //  a broken address is not "no backend"
      (_debug, wrong, 'bogus', invalid),
      (_profile, none, '', invalid),
      (_profile, none, 'false', invalid),
      (_profile, none, 'true', invalid), //  local-only is debug only
      (_profile, none, 'bogus', invalid),
      (_profile, valid, '', online),
      (_profile, valid, 'false', online),
      (_profile, valid, 'true', invalid),
      (_profile, valid, 'bogus', invalid),
      (_profile, wrong, '', invalid),
      (_profile, wrong, 'false', invalid),
      (_profile, wrong, 'true', invalid),
      (_profile, wrong, 'bogus', invalid),
      (_release, none, '', invalid),
      (_release, none, 'false', invalid),
      (_release, none, 'true', invalid), //  local-only is debug only
      (_release, none, 'bogus', invalid),
      (_release, valid, '', online),
      (_release, valid, 'false', online),
      (_release, valid, 'true', invalid),
      (_release, valid, 'bogus', invalid),
      (_release, wrong, '', invalid),
      (_release, wrong, 'false', invalid),
      (_release, wrong, 'true', invalid),
      (_release, wrong, 'bogus', invalid),
    ];

    const addresses = {
      _Address.none: '',
      _Address.valid: _api,
      _Address.wrong: 'ftp://api.sample-company.io',
    };

    BackendMode? modeOf(_Verdict v) => switch (v) {
          _Verdict.online => BackendMode.online,
          _Verdict.localOnly => BackendMode.localOnlyDev,
          _Verdict.invalid => null,
        };

    test('the table covers every combination exactly once', () {
      final seen = <String>{};
      for (final (mode, address, flag, _) in table) {
        expect(seen.add('${mode.name}/${address.name}/$flag'), isTrue,
            reason: 'duplicate row: $mode $address "$flag"');
      }
      expect(seen, hasLength(3 * 3 * 4));
    });

    test('build mode x address x flag matches the truth table', () {
      for (final (mode, address, flag, want) in table) {
        final why = '${mode.name} + ${address.name} address + '
            'LOCAL_ONLY_DEV="$flag"';
        final c = _check(mode, api: addresses[address]!, flag: flag);
        expect(c.mode, modeOf(want), reason: why);
        expect(c.isValid, want != invalid, reason: why);
        expect(c.errors.isEmpty, want != invalid, reason: why);
      }
    });

    test('local-only is only ever produced by debug + no address + true', () {
      var localOnlyResults = 0;
      for (final mode in BuildMode.values) {
        for (final address in addresses.values) {
          // A superset of the table's flags: every spelling this suite knows.
          for (final flag in _flagSpellings) {
            final c = _check(mode, api: address, flag: flag);
            if (c.mode != BackendMode.localOnlyDev) continue;
            localOnlyResults++;
            expect(mode, BuildMode.debug);
            expect(address, isEmpty);
            expect(flag.trim(), 'true');
          }
        }
      }
      // Debug, no address, and the two spellings of true.
      expect(localOnlyResults, 2);
    });

    test(
        'APP_ENV does not change a verdict when the address is https or absent',
        () {
      // https is valid for all three rule sets and an absent address is absent
      // in all of them. (The local-only row is left out for staging and
      // production: the rule does not look at APP_ENV there, and this suite does
      // not pin down what a debug build marked production does.)
      for (final env in AppEnvironment.values) {
        for (final (mode, address, flag, want) in table) {
          if (address == wrong) continue;
          if (want == localOnly && env != AppEnvironment.development) continue;
          final c =
              _check(mode, api: addresses[address]!, flag: flag, env: env);
          expect(c.mode, modeOf(want),
              reason: '${env.name} ${mode.name} ${address.name} "$flag"');
        }
      }
    });
  });
}

/// Every spelling of the define that appears in this suite.
const _flagSpellings = [
  '',
  ' ',
  'false',
  ' false ',
  'true',
  ' true ',
  'TRUE',
  '1',
  'bogus',
];

enum _Address { none, valid, wrong }

enum _Verdict { online, localOnly, invalid }
