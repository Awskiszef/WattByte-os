/// Command-line front end of [validateBackendConfig]: the same rules the app
/// applies at start-up, run before a build is made. `tool/check_backend_config.dart`
/// is a thin wrapper that only turns the return value into an exit code; the
/// logic lives here so it can be unit-tested.
///
/// Used by the CI job `mobile-config-guard` (through `tool/check_release_guard.sh`)
/// and by the release workflow, which passes the same defines to this check and
/// to `flutter build`:
///
///   dart run tool/check_backend_config.dart --build-mode=release \
///       --dart-define=API_BASE_URL=<https address of the API>
///
/// The options mirror Flutter's own, so a build command can be checked by
/// copying its `--dart-define` and `--dart-define-from-file` options:
///
/// * `--build-mode=<debug|profile|release>` (required)
/// * `--dart-define=KEY=VALUE` (repeatable)
/// * `--dart-define-from-file=<json file>` (repeatable)
///
/// Only `API_BASE_URL`, `LOCAL_ONLY_DEV` and `APP_ENV` are read (a profile or
/// release build without `APP_ENV` is checked as production, like the app does);
/// every other define (and every key of a JSON file, including `_NOTE`-style
/// comments) is ignored, except that a define named `dart.vm.*` is an error: it
/// would override the build mode the app detects itself by. Precedence is Flutter's (3.41, `extractDartDefines`): all files first,
/// in the order given, then every `--dart-define` in the order given; a later
/// value replaces an earlier one, so a `--dart-define` always beats a file. A
/// file value that is not a string is stringified the way Flutter does it
/// (`true` becomes `true`, `null` becomes `null`).
///
/// Exit codes: [kBackendConfigExitOk] valid, [kBackendConfigExitInvalid] the
/// configuration is rejected (errors on stderr), [kBackendConfigExitUsage] the
/// arguments are unusable (usage on stderr). No define's value is ever printed:
/// an address may carry credentials, so neither errors nor usage messages
/// repeat anything the caller passed, except option names and file paths.
///
/// Pure Dart (no Flutter import), like [validateBackendConfig].
library;

import 'dart:convert';
import 'dart:io';

import 'backend_config.dart';

/// The configuration is valid for the given build mode.
const int kBackendConfigExitOk = 0;

/// The configuration is rejected: such a build must not be made or shipped.
const int kBackendConfigExitInvalid = 1;

/// The arguments cannot be used (`EX_USAGE` of sysexits.h).
const int kBackendConfigExitUsage = 64;

const String _usage = '''
Usage: dart run tool/check_backend_config.dart --build-mode=<debug|profile|release>
           [--dart-define=KEY=VALUE]... [--dart-define-from-file=<json file>]...

Checks the backend configuration of a build with the rules the app itself
applies at start-up. Pass the same --dart-define and --dart-define-from-file
options as the flutter build or flutter run command.

Reads API_BASE_URL, LOCAL_ONLY_DEV and APP_ENV (profile and release builds
without APP_ENV are checked as production); defines named dart.vm.* are
rejected. Later values replace earlier ones, and --dart-define options
replace values from files (like Flutter).
Only the JSON format of --dart-define-from-file is supported.

Exit codes: 0 valid, 1 invalid configuration, 64 unusable arguments.
No define's value is ever printed.
''';

const String _reservedDefinePrefix = 'dart.vm.';
const String _buildModeOption = '--build-mode';
const String _defineOption = '--dart-define';
const String _defineFromFileOption = '--dart-define-from-file';

/// Runs the check for the command line [args]; returns the exit code.
///
/// [out] and [err] default to stdout and stderr (tests pass buffers). A valid
/// configuration prints `OK: <online|localOnlyDev> (<build mode>)` to [out]; an
/// invalid one prints `INVALID BUILD CONFIGURATION (<build mode>)` and one
/// `  - <error>` line per violated rule to [err]; unusable arguments print the
/// problem and the usage to [err].
int runBackendConfigCheck(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) {
  final outSink = out ?? stdout;
  final errSink = err ?? stderr;

  if (args.length == 1 && (args.single == '--help' || args.single == '-h')) {
    outSink.write(_usage);
    return kBackendConfigExitOk;
  }

  final _Options options;
  final Map<String, String> defines;
  try {
    options = _parseArguments(args);
    defines = _collectDefines(options);
  } on _UsageError catch (e) {
    errSink
      ..writeln('check_backend_config: ${e.message}')
      ..writeln()
      ..write(_usage);
    return kBackendConfigExitUsage;
  }

  final check = validateBackendConfig(
    buildMode: options.buildMode,
    apiBaseUrl: defines['API_BASE_URL'] ?? '',
    localOnlyDev: defines[kLocalOnlyDevDefine] ?? '',
    environment: effectiveEnvironment(
      buildMode: options.buildMode,
      appEnv: defines['APP_ENV'] ?? '',
    ),
  );
  // `dart.vm.product` / `dart.vm.profile` are how the app learns its build
  // mode. Flutter lets a define override them, which would let a profile or
  // release binary pass as a debug build: no real build sets them by hand.
  final errors = [
    ...check.errors,
    if (defines.keys.any((k) => k.startsWith(_reservedDefinePrefix)))
      'defines named $_reservedDefinePrefix* override the build mode and '
          'are not allowed',
  ];

  final mode = options.buildMode.wireName;
  if (errors.isEmpty) {
    outSink.writeln('OK: ${check.mode!.name} ($mode)');
    return kBackendConfigExitOk;
  }
  errSink.writeln('INVALID BUILD CONFIGURATION ($mode)');
  for (final error in errors) {
    errSink.writeln('  - $error');
  }
  return kBackendConfigExitInvalid;
}

/// An argument problem. The message never repeats a value the caller passed.
class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

class _Options {
  _Options(this.buildMode, this.defines, this.files);

  final BuildMode buildMode;
  final List<String> defines;
  final List<String> files;
}

_Options _parseArguments(List<String> args) {
  String? buildModeRaw;
  final defines = <String>[];
  final files = <String>[];

  var i = 0;
  while (i < args.length) {
    final arg = args[i++];
    if (!arg.startsWith('--')) {
      // Never echoed: a stray positional argument could be an address.
      throw _UsageError('unexpected argument #$i (options start with --)');
    }
    final eq = arg.indexOf('=');
    final name = eq < 0 ? arg : arg.substring(0, eq);
    if (name != _buildModeOption &&
        name != _defineOption &&
        name != _defineFromFileOption) {
      // Only a plain option name is echoed, never a stray argument that
      // happens to start with two dashes.
      final plain = RegExp(r'^--[a-z][a-z0-9-]*$').hasMatch(name);
      throw _UsageError(plain ? 'unknown option $name' : 'unknown option');
    }
    String value;
    if (eq >= 0) {
      value = arg.substring(eq + 1);
    } else if (i < args.length && !args[i].startsWith('--')) {
      value = args[i++]; // the `--option value` form
    } else {
      throw _UsageError('$name needs a value');
    }

    switch (name) {
      case _buildModeOption:
        if (buildModeRaw != null) {
          throw _UsageError('$_buildModeOption was given more than once');
        }
        buildModeRaw = value;
      case _defineOption:
        // Flutter ignores an empty --dart-define.
        if (value.isNotEmpty) defines.add(value);
      case _defineFromFileOption:
        files.add(value);
    }
  }

  if (buildModeRaw == null) {
    throw _UsageError('$_buildModeOption is required');
  }
  final buildMode = BuildMode.tryParse(buildModeRaw);
  if (buildMode == null) {
    throw _UsageError('$_buildModeOption must be debug, profile or release');
  }
  return _Options(buildMode, defines, files);
}

/// The defines the build would see, last one wins: every file in the order
/// given, then every `--dart-define` in the order given (Flutter's order).
Map<String, String> _collectDefines(_Options options) {
  final merged = <String, String>{};
  for (final path in options.files) {
    merged.addAll(_readDefineFile(path));
  }
  for (final define in options.defines) {
    final eq = define.indexOf('=');
    if (eq <= 0) {
      // The compiler refuses `-DKEY` too ("No value given to -D option").
      throw _UsageError('$_defineOption needs KEY=VALUE');
    }
    merged[define.substring(0, eq)] = define.substring(eq + 1);
  }
  return merged;
}

/// Reads a `--dart-define-from-file` JSON object the way Flutter does: every
/// value is interpolated into `KEY=$value`, so `true` becomes `true`.
Map<String, String> _readDefineFile(String path) {
  final String raw;
  try {
    raw = File(path).readAsStringSync();
  } on FileSystemException {
    throw _UsageError('cannot read the file given to $_defineFromFileOption '
        '($path)');
  } on FormatException {
    throw _UsageError('the file given to $_defineFromFileOption is not '
        'valid UTF-8 text ($path)');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    // The parser's message quotes the file's content: not repeated.
    throw _UsageError('the file given to $_defineFromFileOption is not valid '
        'JSON ($path); the .env format is not supported by this check');
  }
  if (decoded is! Map<String, dynamic>) {
    throw _UsageError('the file given to $_defineFromFileOption must contain '
        'a JSON object ($path)');
  }
  return {for (final e in decoded.entries) e.key: '${e.value}'};
}
