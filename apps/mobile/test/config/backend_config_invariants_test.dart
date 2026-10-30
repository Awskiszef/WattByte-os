// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Source-level guards for the backend-configuration rules.
//
// `validateBackendConfig` (lib/config/backend_config.dart) is unit-tested on its
// own, and test/config/local_only_ui_test.dart shows what the user sees. What
// neither can show is that nobody quietly goes AROUND the decision later: reads
// a define somewhere else, prints the development banner outside a debug
// build, does storage work before the configuration is checked, or feeds
// `startDestination` from the API address again. These tests read the sources
// (like "no environment address is hardcoded in lib/" in test/app_config_test.dart
// does) and fail with the rule that broke and where to look.
//
// A guard that cannot fail is worth nothing, so every rule is a function over a
// set of sources: the first group runs it over the real lib/, the last group
// runs it over lib/ with ONE deliberate breakage applied in memory and expects
// that exact rule to fail.
//
// They are deliberately text-level and therefore a little strict about the shape
// of the code; when one fails after a legitimate refactor, update the guard in
// the same change - the message says which file and rule.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/config/app_config.dart';

const _bannerText = 'LOCAL ONLY DEVELOPMENT MODE';
const _bannerFile = 'lib/config/local_only_banner.dart';

/// Files outside `lib/config/` and `lib/api/` that may read a `--dart-define`
/// directly. Derived by grepping lib/ when this guard was written (rule E): none.
/// Adding one here is a decision to spread the configuration over the app; the
/// rule is to read `AppConfig` (through `appConfigProvider`) instead.
const _mayReadDefinesDirectly = <String>{};

/// Directories that own the build's defines.
const _definesOwners = <String>['lib/config/', 'lib/api/'];

void main() {
  late final _Lib lib = _Lib.load();

  group('the source scanner (so the guards below cannot rot silently)', () {
    test('blanks comments, keeps offsets and line numbers', () {
      const text = 'a // x\nb /* y\nz */ c\n/// doc\nd';
      final s = _Source('t.dart', text);
      expect(s.code.length, text.length);
      expect(s.code, 'a     \nb     \n     c\n       \nd');
      expect(s.lineOf(s.code.indexOf('d')), 5);
    });

    test('keeps "//" inside strings, blanks string contents in the skeleton',
        () {
      const text = "final a = 'x // not a comment'; // real comment\n"
          'final b = "q\\"//"; final c = r\'raw // \\\';\n'
          "final d = '''\nmulti // line\n'''; final e = '\${f('g')} // h';";
      final s = _Source('t.dart', text);
      expect(s.code, contains("'x // not a comment'"));
      expect(s.code, isNot(contains('real comment')));
      expect(s.code, contains('"q\\"//"'));
      expect(s.code, contains("r'raw // \\'"));
      expect(s.code, contains('multi // line'));
      expect(s.code, contains("'\${f('g')} // h'"));
      expect(s.skeleton, isNot(contains('not a comment')));
      expect(s.skeleton, isNot(contains('multi')));
      expect(s.skeleton.length, text.length);
      expect(s.skeleton, contains("final a = '"));
    });

    test('balanced() finds the matching closer', () {
      final s = _Source('t.dart', 'f(a, g(b), "(") + h(c)');
      final range = s.balanced(s.skeleton.indexOf('('));
      expect(s.code.substring(range.$1, range.$2), 'a, g(b), "("');
    });
  });

  group('the rules hold for lib/', () {
    test('A1: the banner text is spelled out in exactly one file, once',
        () => _a1(lib));
    test('A2: only the debug start-up log uses the constant besides the widget',
        () => _a2(lib));
    test('A3: LocalOnlyDevBanner is built in lib/app.dart and nowhere else',
        () => _a3(lib));
    test('B1: lib/app.dart builds the banner only behind kBuildMode == debug',
        () => _b1(lib));
    test('B2: the start-up log prints it only behind the same condition',
        () => _b2(lib));
    test('B3: kBuildMode is a compile-time constant', () {
      _b3(lib);
      expect(kBuildMode, BuildMode.debug,
          reason: 'flutter test runs in debug mode');
    });
    test(
        'C1: main() checks config.isValid, then ConfigErrorApp, then return, '
        'before any other work',
        () => _c1(lib));
    test(
        'D1: StartGate feeds startDestination(localOnlyDev:) from '
        'isLocalOnlyDev only',
        () => _d1(lib));
    test('D2: startDestination itself takes a flag, not an address',
        () => _d2(lib));
    test('D3: the StartGate does not look at the API address', () => _d3(lib));
    test(
        'E1: no String/bool/int.fromEnvironment or bool.hasEnvironment '
        'outside lib/config/ and lib/api/',
        () => _e1(lib));
    test('E2: LOCAL_ONLY_DEV is read only by lib/config/app_config.dart',
        () => _e2(lib));
    test('E3: the API address of the app is AppConfig.api, not a second read',
        () => _e3(lib));
    test('F1: both guard codes are declared and the guard is a const',
        () => _f1(lib));

    test('F2: the build guard constant evaluates in a debug test run', () {
      // Referencing it forces its evaluation. Under `flutter test` there are no
      // dart-defines and the build is not optimised, so no assert fires; a
      // profile/release build without API_BASE_URL fails to COMPILE instead.
      expect(kBuildConfigurationGuard, isA<BuildConfigurationGuard>());
      expect(kBuildMode, BuildMode.debug);
    });

    // `assert` is compiled out when assertions are off (flutter test and debug
    // builds have them on; a release build never reaches this code).
    var assertsOn = false;
    assert(assertsOn = true);
    final skipWithoutAsserts = assertsOn ? false : 'assertions are disabled';

    BuildConfigurationGuard guard(
            {required bool optimized, String api = '', String local = ''}) =>
        BuildConfigurationGuard(
            optimizedBuild: optimized, apiBaseUrl: api, localOnlyDev: local);

    Matcher failsWith(String code) => throwsA(isA<AssertionError>().having(
        (e) => '${e.message}',
        'message',
        allOf(contains(code), contains('INVALID BUILD CONFIGURATION'))));

    test('F3: the guard fires with the right code for each mistake', () {
      expect(() => guard(optimized: true), failsWith('[WB-CONFIG-001]'),
          reason: 'release/profile without API_BASE_URL');
      expect(() => guard(optimized: true, local: 'true'),
          failsWith('[WB-CONFIG-001]'),
          reason: 'no address wins over the flag: the first problem is named');
      expect(() => guard(optimized: true, api: 'https://x.test', local: 'true'),
          failsWith('[WB-CONFIG-002]'),
          reason: 'release/profile with LOCAL_ONLY_DEV=true');
      expect(() => guard(optimized: true, api: 'https://x.test', local: 'yes'),
          failsWith('[WB-CONFIG-002]'),
          reason: 'any spelling but unset/false is refused in release');
    }, skip: skipWithoutAsserts);

    test('F4: the guard lets valid builds through', () {
      guard(optimized: true, api: 'https://x.test'); // release, online
      guard(optimized: true, api: 'https://x.test', local: 'false');
      guard(optimized: false); // debug is checked at start-up, not here
      guard(optimized: false, local: 'true'); // debug local-only
      guard(optimized: false, api: 'https://x.test');
    }, skip: skipWithoutAsserts);
  });

  // Each case breaks lib/ in ONE way, in memory, and the named rule must notice.
  group('the rules can fail (lib/ with one deliberate breakage)', () {
    /// Appended to a file: code that mentions the banner, reads a define, ...
    String Function(String) append(String code) => (raw) => '$raw\n$code\n';

    /// Replaces the first [from] by [to]; a missing anchor fails the case
    /// loudly instead of silently testing nothing.
    String Function(String) replace(String from, String to) => (raw) {
          if (!raw.contains(from)) {
            throw TestFailure('the breakage anchor `$from` is gone from the '
                'source: update this case in '
                'backend_config_invariants_test.dart');
          }
          return raw.replaceFirst(from, to);
        };

    void broken(String rule, void Function(_Lib) check, String path,
        String Function(String) change) {
      final mutated = lib.replacing(path, change);
      Object? failure;
      try {
        check(mutated);
      } on TestFailure catch (e) {
        failure = e;
      }
      expect(failure, isA<TestFailure>(),
          reason: 'rule $rule did NOT fail although $path was broken on '
              'purpose: the guard is blind to this breakage');
      expect((failure! as TestFailure).message, contains('[rule $rule'),
          reason: 'the failure must name the rule');
    }

    void stillFine(void Function(_Lib) check, String path,
        String Function(String) change) {
      check(lib.replacing(path, change));
    }

    test('A1: a second copy of the banner text', () {
      broken(
          'A1', _a1, 'lib/ui/shell.dart', append("const _x = '$_bannerText';"));
      broken('A1', _a1, _bannerFile, append("const _y = '$_bannerText';"));
      broken('A1', _a1, _bannerFile,
          replace("'$_bannerText'", "'LOCAL ONLY DEVELOPMENT'"));
    });

    test('A1: a comment that quotes the text is not a copy', () {
      stillFine(_a1, 'lib/ui/shell.dart', append('// $_bannerText'));
      stillFine(_a1, 'lib/ui/shell.dart', append('/// `$_bannerText`'));
    });

    test('A2: another file uses kLocalOnlyDevBannerText', () {
      broken('A2', _a2, 'lib/ui/shell.dart',
          append('final _x = kLocalOnlyDevBannerText;'));
    });

    test('A3: a second place builds the banner', () {
      broken('A3', _a3, 'lib/ui/shell.dart',
          append('final _x = LocalOnlyDevBanner(child: SizedBox());'));
    });

    test('B1: the banner is built without the debug-mode condition', () {
      broken('B1', _b1, 'lib/app.dart',
          replace('kBuildMode == BuildMode.debug &&', ''));
      broken(
          'B1',
          _b1,
          'lib/app.dart',
          replace('showLocalOnlyBanner ? LocalOnlyDevBanner(',
              'LocalOnlyDevBanner('));
      broken('B1', _b1, 'lib/app.dart',
          replace('.isLocalOnlyDev;', '.api.isConfigured;'));
    });

    test('B2: the start-up log prints the text in every build mode', () {
      broken('B2', _b2, 'lib/config/startup.dart',
          replace('kBuildMode == BuildMode.debug && ', ''));
      broken(
          'B2',
          _b2,
          'lib/config/startup.dart',
          replace(
              'debugLog(kLocalOnlyDevBannerText,',
              'print(kLocalOnlyDevBannerText); '
                  'debugLog(kLocalOnlyDevBannerText,'));
    });

    test('B3: kBuildMode stops being a constant', () {
      broken('B3', _b3, 'lib/config/app_config.dart',
          replace('const BuildMode kBuildMode', 'final BuildMode kBuildMode'));
    });

    test('C1: storage work before the configuration check', () {
      broken(
          'C1',
          _c1,
          'lib/main.dart',
          replace(
              'if (!config.isValid) {',
              'final early = await SharedPreferences.getInstance();\n'
                  '  if (!config.isValid) {'));
      broken(
          'C1',
          _c1,
          'lib/main.dart',
          replace(
              'if (!config.isValid) {',
              'registerBackgroundRefresh();\n'
                  '  if (!config.isValid) {'));
    });

    test('C1: the error app does not stop main()', () {
      broken(
          'C1',
          _c1,
          'lib/main.dart',
          replace('runApp(ConfigErrorApp(config: config));\n    return;',
              'runApp(ConfigErrorApp(config: config));'));
    });

    test('C1: the guard is not (or no longer) on config.isValid', () {
      broken(
          'C1',
          _c1,
          'lib/main.dart',
          replace(
              'if (!config.isValid) {', 'if (config.problems.isNotEmpty) {'));
      broken(
          'C1',
          _c1,
          'lib/main.dart',
          replace('runApp(ConfigErrorApp(config: config));',
              'runApp(const SizedBox());'));
    });

    test('D1: the start destination is derived from the API address again', () {
      const call = 'localOnlyDev: ref.watch(appConfigProvider).isLocalOnlyDev';
      broken(
          'D1',
          _d1,
          'lib/app.dart',
          replace(call,
              'localOnlyDev: !ref.watch(apiConfigProvider).isConfigured'));
      broken(
          'D1',
          _d1,
          'lib/app.dart',
          replace(
              call,
              '$call || '
              '!ref.watch(appConfigProvider).api.isConfigured'));
    });

    test('D2: startDestination reads the address or the build mode itself', () {
      broken(
          'D2',
          _d2,
          'lib/setup/setup_controller.dart',
          replace('if (localOnlyDev) {',
              'if (localOnlyDev || kBuildMode == BuildMode.debug) {'));
      broken('D2', _d2, 'lib/setup/setup_controller.dart',
          replace('required bool localOnlyDev,', 'required bool apiMissing,'));
    });

    test('D3: StartGate looks at the API address', () {
      broken(
          'D3',
          _d3,
          'lib/app.dart',
          replace(
              'final destination = startDestination(',
              'final _ = ref.watch(apiConfigProvider).isConfigured;\n'
                  '    final destination = startDestination('));
    });

    test('E1: a screen reads a define itself', () {
      broken('E1', _e1, 'lib/ui/shell.dart',
          append("const _x = bool.fromEnvironment('SKIP_LOGIN');"));
      broken('E1', _e1, 'lib/features/auth/presentation/auth_controller.dart',
          append("const _x = String.fromEnvironment('API_BASE_URL');"));
      broken('E1', _e1, 'lib/ui/shell.dart',
          append("final _x = bool.hasEnvironment('LOCAL_ONLY_DEV');"));
    });

    test(
        'E1: reading a define in lib/config/ or lib/api/ is allowed, and a '
        'comment about it is nothing', () {
      stillFine(_e1, 'lib/config/startup.dart',
          append("const _x = String.fromEnvironment('X');"));
      stillFine(_e1, 'lib/ui/shell.dart',
          append("// const _x = String.fromEnvironment('X');"));
    });

    test('E2: LOCAL_ONLY_DEV is read from a second place', () {
      broken('E2', _e2, 'lib/config/startup.dart',
          append('const _x = String.fromEnvironment(kLocalOnlyDevDefine);'));
      broken('E2', _e2, 'lib/ui/shell.dart',
          append("const _x = 'LOCAL_ONLY_DEV';"));
    });

    test('E3: a second, unvalidated read of the API address', () {
      broken('E3', _e3, 'lib/ui/shell.dart',
          append('final _x = ApiConfig.fromEnvironment;'));
      broken('E3', _e3, 'lib/config/startup.dart',
          append("const _x = String.fromEnvironment('API_BASE_URL');"));
    });

    test('F1: a guard code or the const-ness of the guard is lost', () {
      broken('F1', _f1, 'lib/config/app_config.dart',
          replace('[WB-CONFIG-002]', '[WB-CONFIG-9]'));
      broken(
          'F1',
          _f1,
          'lib/config/app_config.dart',
          replace('const BuildConfigurationGuard kBuildConfigurationGuard',
              'final BuildConfigurationGuard kBuildConfigurationGuard'));
      broken(
          'F1',
          _f1,
          'lib/config/app_config.dart',
          replace('optimizedBuild: kReleaseMode || kProfileMode,',
              'optimizedBuild: kReleaseMode,'));
    });
  });
}

// ---------------------------------------------------------------------------
// The rules. Each takes a set of sources and fails (TestFailure, through
// `expect`) with "[rule X] ..." naming what broke and where to look.
// ---------------------------------------------------------------------------

/// A1: the banner text is written out in exactly one place, once.
void _a1(_Lib lib) {
  final hits = <String, int>{};
  for (final s in lib.all) {
    final n = RegExp(RegExp.escape(_bannerText)).allMatches(s.code).length;
    if (n > 0) hits[s.path] = n;
  }
  // A localised copy would reach users in a normal build.
  for (final arb in Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))) {
    final n = RegExp(RegExp.escape(_bannerText))
        .allMatches(arb.readAsStringSync())
        .length;
    if (n > 0) hits[arb.path.replaceAll(r'\', '/')] = n;
  }
  expect(hits, {_bannerFile: 1},
      reason: '[rule A1] "$_bannerText" must be written in exactly one '
          'place, $_bannerFile (kLocalOnlyDevBannerText), exactly once '
          '(comments do not count). Everything else uses the constant. '
          'Found: $hits. A copy in an ARB file or another widget could '
          'show it in a normal build.');
  final banner = lib.source(_bannerFile, 'rule A1');
  expect(
      RegExp("const String kLocalOnlyDevBannerText\\s*=\\s*kDebugMode\\s*\\?\\s*'"
              "${RegExp.escape(_bannerText)}'\\s*:\\s*''\\s*;")
          .hasMatch(banner.code),
      isTrue,
      reason: '[rule A1] $_bannerFile must declare '
          "`const String kLocalOnlyDevBannerText = kDebugMode ? '$_bannerText' : '';` "
          'so that profile and release binaries do not contain the literal '
          '(tool/check_release_guard.sh --builds greps a release binary for it)');
}

/// A2: besides the widget file, only the debug start-up log uses the constant.
void _a2(_Lib lib) {
  final users = <String>[
    for (final s in lib.all)
      if (s.path != _bannerFile &&
          RegExp(r'\bkLocalOnlyDevBannerText\b').hasMatch(s.skeleton))
        s.path,
  ]..sort();
  expect(users, ['lib/config/startup.dart'],
      reason: '[rule A2] kLocalOnlyDevBannerText may be used only by '
          'logStartupConfiguration (lib/config/startup.dart), behind '
          '`kBuildMode == BuildMode.debug`. Found in: $users. The banner '
          'itself is LocalOnlyDevBanner, built only in lib/app.dart.');
}

/// A3: LocalOnlyDevBanner is constructed once, in lib/app.dart.
void _a3(_Lib lib) {
  final builds = <String>[
    for (final s in lib.all)
      if (s.path != _bannerFile)
        for (final m
            in RegExp(r'\bLocalOnlyDevBanner\s*\(').allMatches(s.skeleton))
          s.where(m.start),
  ];
  expect(builds, hasLength(1),
      reason: '[rule A3] LocalOnlyDevBanner( may be constructed exactly '
          'once, in WattByteApp (lib/app.dart). Found: $builds');
  expect(builds.single, startsWith('lib/app.dart:'),
      reason: '[rule A3] the one construction must be in lib/app.dart, '
          'found ${builds.single}');
}

/// B1: the app builds the banner only for `kBuildMode == debug && isLocalOnlyDev`.
void _b1(_Lib lib) {
  final app = lib.source('lib/app.dart', 'rule B1');
  final assign = RegExp(r'\bshowLocalOnlyBanner\s*=\s*kBuildMode\s*==\s*'
          r'BuildMode\.debug\s*&&([^;]*?)\.isLocalOnlyDev\s*;')
      .firstMatch(app.skeleton);
  expect(assign, isNotNull,
      reason: '[rule B1] lib/app.dart must define\n'
          '  final showLocalOnlyBanner = kBuildMode == BuildMode.debug &&\n'
          '      <app config>.isLocalOnlyDev;\n'
          'so profile and release builds do not even contain the banner '
          '(kBuildMode is a compile-time constant). See WattByteApp.build.');
  final config = assign!.group(1)!.trim();
  expect(config, contains('appConfigProvider'),
      reason: '[rule B1] the flag must come from appConfigProvider '
          '(AppConfig.isLocalOnlyDev), got `$config`');
  expect(
      RegExp(r'\bshowLocalOnlyBanner\b').allMatches(app.skeleton), hasLength(2),
      reason: '[rule B1] showLocalOnlyBanner must be declared once and '
          'used once, in `showLocalOnlyBanner ? LocalOnlyDevBanner(...)`');
  expect(
      RegExp(r'\bshowLocalOnlyBanner\s*\?\s*LocalOnlyDevBanner\s*\(')
          .hasMatch(app.skeleton),
      isTrue,
      reason: '[rule B1] LocalOnlyDevBanner must be built only as '
          '`showLocalOnlyBanner ? LocalOnlyDevBanner(...) : ...`');
}

/// B2: the start-up log prints the banner text only for debug + local-only.
void _b2(_Lib lib) {
  final startup = lib.source('lib/config/startup.dart', 'rule B2');
  final uses =
      RegExp(r'\bkLocalOnlyDevBannerText\b').allMatches(startup.skeleton);
  expect(uses, hasLength(1),
      reason: '[rule B2] lib/config/startup.dart must use '
          'kLocalOnlyDevBannerText exactly once (the debug log line)');
  expect(RegExp(r'\bprint\s*\(').hasMatch(startup.skeleton), isFalse,
      reason: '[rule B2] lib/config/startup.dart must log through debugLog, '
          'never print');
  final guarded = RegExp(r'\bif\s*\(([^)]*)\)\s*\{?\s*debugLog\(\s*'
          r'kLocalOnlyDevBannerText\b')
      .firstMatch(startup.skeleton);
  expect(guarded, isNotNull,
      reason: '[rule B2] the only use of kLocalOnlyDevBannerText in '
          'lib/config/startup.dart must be the body of '
          '`if (kBuildMode == BuildMode.debug && config.isLocalOnlyDev)`');
  final condition = guarded!.group(1)!;
  expect(RegExp(r'\bkBuildMode\s*==\s*BuildMode\.debug\b').hasMatch(condition),
      isTrue,
      reason: '[rule B2] the log of the banner text must be guarded by '
          '`kBuildMode == BuildMode.debug`, got `if ($condition)`');
  expect(condition, contains('isLocalOnlyDev'),
      reason: '[rule B2] ... and by AppConfig.isLocalOnlyDev, got '
          '`if ($condition)`');
}

/// B3: kBuildMode is a compile-time constant (what strips debug-only code).
void _b3(_Lib lib) {
  final config = lib.source('lib/config/app_config.dart', 'rule B3');
  expect(
      RegExp(r'const\s+BuildMode\s+kBuildMode\s*=\s*kReleaseMode\s*\?'
              r'\s*BuildMode\.release\s*:\s*kProfileMode\s*\?\s*'
              r'BuildMode\.profile\s*:\s*BuildMode\.debug\s*;')
          .hasMatch(config.skeleton),
      isTrue,
      reason: '[rule B3] kBuildMode must stay a `const` derived from '
          'kReleaseMode / kProfileMode (lib/config/app_config.dart): '
          'that is what removes the debug-only code from profile and '
          'release builds.');
}

/// C1: main() stops an invalid build before touching anything.
void _c1(_Lib lib) {
  final entry = lib.source('lib/main.dart', 'rule C1');
  final code = entry.skeleton;

  final read = RegExp(r'\bfinal\s+config\s*=\s*AppConfig\.fromEnvironment\s*;')
      .firstMatch(code);
  expect(read, isNotNull,
      reason: '[rule C1] lib/main.dart must start from '
          '`final config = AppConfig.fromEnvironment;` (the one '
          'configuration of the build)');

  final guard = RegExp(r'\bif\s*\(\s*!\s*config\.isValid\s*\)\s*\{([^}]*)\}')
      .firstMatch(code);
  expect(guard, isNotNull,
      reason: '[rule C1] lib/main.dart must contain '
          '`if (!config.isValid) { runApp(ConfigErrorApp(config: config)); '
          'return; }`');
  final body = guard!.group(1)!;
  final run = RegExp(r'\brunApp\s*\(\s*(?:const\s+)?ConfigErrorApp\s*\(\s*'
          r'config\s*:\s*config\s*\)\s*\)\s*;')
      .firstMatch(body);
  expect(run, isNotNull,
      reason: '[rule C1] the guard must run '
          '`runApp(ConfigErrorApp(config: config));` and nothing that '
          'looks like the app');
  final ret = RegExp(r'\breturn\s*;').firstMatch(body);
  expect(ret, isNotNull,
      reason: '[rule C1] the guard must `return;` after ConfigErrorApp: '
          'an invalid build must never fall through to the real app');
  expect(run!.start, lessThan(ret!.start),
      reason: '[rule C1] runApp(ConfigErrorApp(...)) comes before return');
  expect(read!.start, lessThan(guard.start),
      reason: '[rule C1] the configuration is read before it is checked');

  // Nothing with side effects before the guard.
  for (final call in const [
    'SharedPreferences.getInstance',
    'WattByteDb.open',
    'registerBackgroundRefresh',
    'lockOrientation',
  ]) {
    final at = code.indexOf(call);
    expect(at, isNonNegative,
        reason: '[rule C1] lib/main.dart no longer mentions $call. If the '
            'start-up work moved to another file, point this guard at it: '
            'it must still run after the configuration check.');
    expect(guard.start, lessThan(at),
        reason: '[rule C1] $call (${entry.where(at)}) runs BEFORE the '
            'config.isValid guard (${entry.where(guard.start)}): an '
            'invalid build would touch storage / background work');
  }
  final firstAwait = RegExp(r'\bawait\b').firstMatch(code);
  final awaitAt = firstAwait == null ? 'none' : entry.where(firstAwait.start);
  expect(firstAwait == null || guard.end <= firstAwait.start, isTrue,
      reason: '[rule C1] there is an `await` ($awaitAt) before the '
          'config.isValid guard: nothing asynchronous may run before an '
          'invalid build is stopped');

  // The first app that is started is the error app. The real app is started only through `startGuarded` (a storage
  // failure shows a recovery screen instead of leaving the launch screen, F-07), after the guard.
  final runs = RegExp(r'\brunApp\s*\(').allMatches(code).toList();
  expect(runs, hasLength(1),
      reason: '[rule C1] lib/main.dart should call runApp exactly once '
          '(ConfigErrorApp); the app starts through startGuarded; '
          'found ${runs.length}');
  final guarded = code.indexOf('startGuarded(');
  expect(guarded, isNonNegative,
      reason: '[rule C1] the app must be started through startGuarded');
  expect(guard.end, lessThan(guarded),
      reason: '[rule C1] startGuarded runs after the config.isValid guard');
  final bodyOffset = guard.start + guard.group(0)!.indexOf('{') + 1;
  expect(runs.first.start, bodyOffset + run.start,
      reason: '[rule C1] the first runApp must be the ConfigErrorApp one');
  expect(RegExp(r'\bConfigErrorApp\b').allMatches(code), hasLength(1),
      reason: '[rule C1] ConfigErrorApp is run once, by the guard');
}

/// What a start destination may never be derived from.
final _notTheAddress = RegExp(r'isConfigured|apiConfigProvider|\.api\b|'
    r'apiConfig|baseUrl|fromEnvironment|apiBaseUrl');

/// D1: the one call of `startDestination` passes only `isLocalOnlyDev`.
void _d1(_Lib lib) {
  final calls = [
    for (final s in lib.all)
      for (final m in RegExp(r'\bstartDestination\s*\(').allMatches(s.skeleton))
        if (!s.skeleton
            .substring(0, m.start)
            .trimRight()
            .endsWith('StartDestination'))
          (
            path: s.path,
            where: s.where(m.start),
            args: s.code
                .substring(s.balanced(m.end - 1).$1, s.balanced(m.end - 1).$2),
          ),
  ];
  expect([for (final c in calls) c.path], ['lib/app.dart'],
      reason: '[rule D1] startDestination must be called exactly once, '
          'by StartGate in lib/app.dart. Found: '
          '${[for (final c in calls) c.where]}');
  final args = calls.single.args;
  expect(RegExp(r'\blocalOnlyDev\s*:\s*[^,]*\.isLocalOnlyDev\b').hasMatch(args),
      isTrue,
      reason: '[rule D1] ${calls.single.where}: the call must pass '
          '`localOnlyDev: ref.watch(appConfigProvider).isLocalOnlyDev`, '
          'got: $args');
  expect(_notTheAddress.hasMatch(args), isFalse,
      reason: '[rule D1] ${calls.single.where}: the start destination '
          'must not look at the API address '
          '(${_notTheAddress.firstMatch(args)?.group(0)}); a missing or '
          'broken API_BASE_URL must never skip the account. Got: $args');
  expect(args, isNot(contains('||')),
      reason: '[rule D1] ${calls.single.where}: localOnlyDev must be '
          'isLocalOnlyDev alone, not combined with anything. Got: $args');
}

/// D2: `startDestination` takes `required bool localOnlyDev` and no address.
void _d2(_Lib lib) {
  final controller = lib.source('lib/setup/setup_controller.dart', 'rule D2');
  final code = controller.skeleton;
  final decl =
      RegExp(r'StartDestination\s+startDestination\s*\(\s*\{').firstMatch(code);
  expect(decl, isNotNull,
      reason: '[rule D2] StartDestination startDestination({...}) was '
          'not found in lib/setup/setup_controller.dart');
  final params = controller.balanced(code.indexOf('(', decl!.start));
  final signature = controller.code.substring(params.$1, params.$2);
  expect(signature, contains('required bool localOnlyDev'),
      reason: '[rule D2] startDestination must take '
          '`required bool localOnlyDev`, got: $signature');
  final body = controller.balanced(code.indexOf('{', params.$2));
  final bodyText = controller.code.substring(body.$1, body.$2);
  final bad = RegExp(r'isConfigured|apiConfig|\.api\b|baseUrl|'
          r'fromEnvironment|kBuildMode|BuildMode|AppConfig|isValid')
      .firstMatch(bodyText);
  expect(bad, isNull,
      reason: '[rule D2] startDestination (lib/setup/setup_controller.dart) '
          'must decide from `localOnlyDev`, auth and settings only; it '
          'mentions `${bad?.group(0)}`');
  expect(bodyText, contains('localOnlyDev'),
      reason: '[rule D2] startDestination must use its localOnlyDev flag');
}

/// D3: StartGate does not read the API address.
void _d3(_Lib lib) {
  // The account UI itself legitimately explains "cloud not available"
  // (ApiConfig.isConfigured); what it must never do is decide the START
  // destination. Pin the StartGate: it watches the gate inputs and nothing
  // about the address.
  final app = lib.source('lib/app.dart', 'rule D3');
  final gate = RegExp(r'class\s+StartGate\b').firstMatch(app.skeleton);
  expect(gate, isNotNull,
      reason: '[rule D3] StartGate not found in lib/app.dart');
  final range = app.balanced(app.skeleton.indexOf('{', gate!.end));
  final text = app.code.substring(range.$1, range.$2);
  expect(_notTheAddress.hasMatch(text), isFalse,
      reason: '[rule D3] StartGate (lib/app.dart) must not read the API '
          'address (${_notTheAddress.firstMatch(text)?.group(0)}): '
          'the account is skipped only through AppConfig.isLocalOnlyDev');
}

final _readsDefine = RegExp(
    r'\b(?:String|bool|int)\s*\.\s*(?:fromEnvironment|hasEnvironment)\b');

/// E1: no define is read outside the two directories that own them.
void _e1(_Lib lib) {
  final offenders = <String>[
    for (final s in lib.all)
      if (!_definesOwners.any(s.path.startsWith) &&
          !_mayReadDefinesDirectly.contains(s.path))
        for (final m in _readsDefine.allMatches(s.skeleton)) s.where(m.start),
  ];
  expect(offenders, isEmpty,
      reason: '[rule E1] a --dart-define is read outside lib/config/ and '
          'lib/api/ at: $offenders. The decision "does this build have a '
          'backend / an account" is central: add the define to '
          'AppConfig (lib/config/app_config.dart) and read it from '
          'appConfigProvider. Allow-list '
          '(_mayReadDefinesDirectly in this test) is empty on purpose.');
  final stale = [
    for (final path in _mayReadDefinesDirectly)
      if (lib[path] == null || !_readsDefine.hasMatch(lib[path]!.skeleton))
        path,
  ];
  expect(stale, isEmpty, reason: '[rule E1] stale allow-list entries: $stale');
}

/// E2: the LOCAL_ONLY_DEV define is read in exactly one file.
void _e2(_Lib lib) {
  final reads = RegExp(
      r"""fromEnvironment\s*\(\s*(?:kLocalOnlyDevDefine|['"]LOCAL_ONLY_DEV['"])\s*\)""");
  final files = {
    for (final s in lib.all)
      if (reads.hasMatch(s.code)) s.path,
  };
  expect(files, {'lib/config/app_config.dart'},
      reason: '[rule E2] the LOCAL_ONLY_DEV define may be read only in '
          'lib/config/app_config.dart (the build guard and '
          'AppConfig.fromEnvironment). Found in: $files');
  // The name of the flag is never written as a literal anywhere else in code.
  final named = {
    for (final s in lib.all)
      if (!s.path.startsWith('lib/config/') &&
          RegExp(r"""['"]LOCAL_ONLY_DEV['"]""").hasMatch(s.code))
        s.path,
  };
  expect(named, isEmpty,
      reason: '[rule E2] the name of the flag is written outside '
          'lib/config/: $named. Use AppConfig.isLocalOnlyDev.');
}

/// E3: the app's API address is `AppConfig.api`; no second read of it.
void _e3(_Lib lib) {
  final users = [
    for (final s in lib.all)
      if (s.path != 'lib/api/api_config.dart')
        for (final m in RegExp(r'\bApiConfig\s*\.\s*fromEnvironment\b')
            .allMatches(s.skeleton))
          s.where(m.start),
  ];
  expect(users, isEmpty,
      reason: '[rule E3] ApiConfig.fromEnvironment is an unvalidated '
          'second read of API_BASE_URL (it knows nothing of LOCAL_ONLY_DEV '
          'or the build mode). The app uses appConfigProvider -> '
          'AppConfig.api. Found at: $users');
  final readers = {
    for (final s in lib.all)
      if (RegExp(r"""fromEnvironment\s*\(\s*['"]API_BASE_URL['"]\s*\)""")
          .hasMatch(s.code))
        s.path,
  };
  expect(
      readers.difference(
          {'lib/config/app_config.dart', 'lib/api/api_config.dart'}),
      isEmpty,
      reason: '[rule E3] API_BASE_URL is read in $readers; allowed: '
          'lib/config/app_config.dart and lib/api/api_config.dart');
}

/// F1: the build-time guard keeps its codes and stays a constant.
void _f1(_Lib lib) {
  final config = lib.source('lib/config/app_config.dart', 'rule F1');
  for (final code in const ['[WB-CONFIG-001]', '[WB-CONFIG-002]']) {
    expect(config.code.contains(code), isTrue,
        reason: '[rule F1] lib/config/app_config.dart must still declare '
            '$code in the message of an assert of BuildConfigurationGuard '
            '(CI and docs/CONFIGURATION_MOBILE.md look for it in the '
            'build output)');
  }
  final declaration =
      RegExp(r'const\s+BuildConfigurationGuard\s+kBuildConfigurationGuard'
              r'\s*=\s*BuildConfigurationGuard\s*\(')
          .firstMatch(config.skeleton);
  expect(declaration, isNotNull,
      reason: '[rule F1] kBuildConfigurationGuard must be a `const` '
          'initialised with the const constructor: only a constant is '
          'evaluated (and its failed assert reported) while the library '
          'is compiled, in every build');
  final end = config.skeleton.indexOf(';', declaration!.end);
  final guardBody = config.code.substring(declaration.start, end + 1);
  expect(guardBody, contains('kReleaseMode || kProfileMode'),
      reason: '[rule F1] the guard must be armed for profile AND release '
          '(`optimizedBuild: kReleaseMode || kProfileMode`)');
  expect(guardBody, contains("String.fromEnvironment('API_BASE_URL')"),
      reason: '[rule F1] the guard must read API_BASE_URL');
  expect(guardBody, contains('String.fromEnvironment(kLocalOnlyDevDefine)'),
      reason: '[rule F1] the guard must read LOCAL_ONLY_DEV');
  expect(RegExp(r'\bassert\s*\(').allMatches(config.skeleton).length,
      greaterThanOrEqualTo(2),
      reason: '[rule F1] BuildConfigurationGuard needs one assert per '
          'guard code');
}

// ---------------------------------------------------------------------------
// Reading the sources
// ---------------------------------------------------------------------------

/// Every `.dart` file of lib/ (generated code included), by path like
/// `lib/app.dart`.
class _Lib {
  _Lib(this._files);

  factory _Lib.load() {
    final dir = Directory('lib');
    if (!dir.existsSync()) {
      throw TestFailure('lib/ was not found from ${Directory.current.path}: '
          'run `flutter test` from apps/mobile.');
    }
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return _Lib({
      for (final f in files)
        f.path.replaceAll(r'\', '/'):
            _Source(f.path.replaceAll(r'\', '/'), f.readAsStringSync()),
    });
  }

  final Map<String, _Source> _files;

  Iterable<_Source> get all => _files.values;

  _Source? operator [](String path) => _files[path];

  _Source source(String path, String rule) =>
      _files[path] ??
      (throw TestFailure('[$rule] $path was not found under lib/ (moved or '
          'renamed?). Update this guard in test/config/'
          'backend_config_invariants_test.dart to the new location.'));

  /// The same sources with [path] changed by [change] (in memory only).
  _Lib replacing(String path, String Function(String raw) change) {
    final original = source(path, 'test setup');
    final changed = change(original.raw);
    if (changed == original.raw) {
      throw TestFailure('the breakage of $path changed nothing: the text it '
          'targets is gone. Update the case in '
          'backend_config_invariants_test.dart');
    }
    return _Lib({..._files, path: _Source(path, changed)});
  }
}

/// One Dart file in two cleaned forms with the SAME length and line structure
/// as the original, so an offset found in one is valid in the other and maps
/// to a line number:
///
/// * [code]     comments blanked (doc comments included): what the compiler sees.
/// * [skeleton] comments blanked and the inside of every string literal blanked
///              too: for structure (balanced brackets, `if (...)`, calls)
///              without being fooled by text inside strings.
class _Source {
  _Source(this.path, this.raw)
      : code = _blank(raw, strings: false),
        skeleton = _blank(raw, strings: true);

  final String path;
  final String raw;
  final String code;
  final String skeleton;

  int lineOf(int offset) =>
      '\n'.allMatches(code.substring(0, offset)).length + 1;

  String where(int offset) => '$path:${lineOf(offset)}';

  /// The range between the bracket at [open] and its partner (the end is the
  /// partner's own index), counted on the [skeleton].
  (int, int) balanced(int open) {
    final opener = skeleton[open];
    final closer = const {'(': ')', '{': '}', '[': ']'}[opener];
    if (closer == null) {
      throw ArgumentError('$path: no bracket at offset $open ($opener)');
    }
    var depth = 0;
    for (var k = open; k < skeleton.length; k++) {
      if (skeleton[k] == opener) {
        depth++;
      } else if (skeleton[k] == closer) {
        depth--;
        if (depth == 0) return (open + 1, k);
      }
    }
    throw StateError('$path: unbalanced "$opener" at ${where(open)}');
  }
}

String _blank(String s, {required bool strings}) {
  final out = StringBuffer();
  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      out.write(s[k] == '\n' ? '\n' : ' ');
    }
  }

  bool isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
  var i = 0;
  while (i < s.length) {
    if (s.startsWith('//', i)) {
      var j = i;
      while (j < s.length && s[j] != '\n') {
        j++;
      }
      blank(i, j);
      i = j;
      continue;
    }
    if (s.startsWith('/*', i)) {
      var depth = 1;
      var j = i + 2;
      while (j < s.length && depth > 0) {
        if (s.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (s.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      blank(i, j);
      i = j;
      continue;
    }
    final ch = s[i];
    if (ch == "'" || ch == '"') {
      final raw = i > 0 && s[i - 1] == 'r' && (i < 2 || !isIdent(s[i - 2]));
      final quote = s.startsWith(ch * 3, i) ? ch * 3 : ch;
      var j = i + quote.length;
      while (j < s.length) {
        if (s.startsWith(quote, j)) break;
        if (!raw && s[j] == r'\') {
          j += 2;
          continue;
        }
        if (!raw && s.startsWith(r'${', j)) {
          var depth = 0;
          var k = j + 1;
          while (k < s.length) {
            if (s[k] == '{') depth++;
            if (s[k] == '}') {
              depth--;
              if (depth == 0) {
                k++;
                break;
              }
            }
            k++;
          }
          j = k;
          continue;
        }
        if (quote.length == 1 && s[j] == '\n') break; // unterminated
        j++;
      }
      j = math.min(j, s.length);
      out.write(quote);
      if (strings) {
        blank(i + quote.length, j);
      } else {
        out.write(s.substring(i + quote.length, j));
      }
      final close = math.min(j + quote.length, s.length);
      out.write(s.substring(j, close));
      i = close;
      continue;
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}
