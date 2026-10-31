// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Text-level guards for the links the behavioural tests cannot reach in a
// debug-only `flutter test` run (same approach as backend_config_invariants_test.dart).
String _read(String path) => File(path).readAsStringSync();

String _fromEnvironmentArguments() {
  final m = RegExp(
          r'static final AppConfig fromEnvironment = AppConfig\.fromDefines\((.*?)\n  \);',
          dotAll: true)
      .firstMatch(_read('lib/config/app_config.dart'));
  expect(m, isNotNull,
      reason: 'AppConfig.fromEnvironment moved or changed shape');
  return m!.group(1)!;
}

void main() {
  test(
      'G1: AppConfig.fromEnvironment reads every define into the right argument',
      () {
    final args = _fromEnvironmentArguments();
    for (final wanted in [
      "appEnv: const String.fromEnvironment('APP_ENV')",
      "apiBaseUrl: const String.fromEnvironment('API_BASE_URL')",
      'localOnlyDev: const String.fromEnvironment(kLocalOnlyDevDefine)',
      "privacyPolicyUrl: const String.fromEnvironment('PRIVACY_POLICY_URL')",
    ]) {
      expect(args, contains(wanted), reason: wanted);
    }
  });

  test(
      'G2: AppConfig.fromEnvironment validates for the EFFECTIVE build mode '
      '(dart.vm constants and whether assertions run), not for a default', () {
    final args = _fromEnvironmentArguments();
    expect(
        args.replaceAll(RegExp(r'\s+'), ' '),
        contains('buildMode: effectiveBuildMode( compiled: kBuildMode, '
            'assertsEnabled: _assertsEnabled(), )'),
        reason: 'a profile/release AOT binary that overrides dart.vm.* must '
            'not be validated as a debug build');
  });

  test('G3: the developer hints of the error screen exist only in debug builds',
      () {
    final src = _read('lib/config/config_error_app.dart');
    final hint = src.indexOf('flutter run --dart-define=LOCAL_ONLY_DEV=true');
    expect(hint, isNonNegative);
    final guard = RegExp(r'if \(kBuildMode == BuildMode\.debug\) \.\.\.\[')
        .firstMatch(src);
    expect(guard, isNotNull);
    expect(guard!.start, lessThan(hint));
  });

  test('G4: main() logs the startup configuration before the validity guard',
      () {
    final src = _read('lib/main.dart');
    final log = src.indexOf('logStartupConfiguration(config);');
    final guard = src.indexOf('if (!config.isValid)');
    expect(log, isNonNegative);
    expect(log, lessThan(guard));
  });

  test('G5: the wrapper turns the verdict of the checker into the exit code',
      () {
    expect(_read('tool/check_backend_config.dart'),
        contains('exit(runBackendConfigCheck(args))'));
  });
}
