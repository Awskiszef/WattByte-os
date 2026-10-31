// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// The one place that decides whether a build may start, and how it reaches its
/// backend. Pure Dart (no Flutter import) so the same function runs in the unit
/// tests, in `tool/check_backend_config.dart` (CI and the release workflow) and,
/// through [AppConfig], in the app itself.
///
/// | build mode | `API_BASE_URL` | `LOCAL_ONLY_DEV` | result                            |
/// |------------|----------------|------------------|-----------------------------------|
/// | any        | valid          | unset / false    | [BackendMode.online]              |
/// | debug      | missing        | `true`           | [BackendMode.localOnlyDev]        |
/// | debug      | missing        | unset / false    | invalid                           |
/// | profile    | missing        | any              | invalid                           |
/// | release    | missing        | any              | invalid                           |
/// | profile / release | any     | `true`           | invalid                           |
/// | any        | present, wrong | any              | invalid (never "local-only")      |
/// | debug      | valid          | `true`           | invalid (contradiction)           |
/// | debug      | missing        | `true`, APP_ENV staging / production | invalid       |
/// | profile / release | any     | APP_ENV=development, or a non-public host (localhost, IP, `.local`, `example.com`) | invalid |
///
/// Without `APP_ENV` a profile or release build is validated as `production`
/// (https only), see [effectiveEnvironment].
///
/// Nothing else in the app may decide "this build has no backend": screens and
/// providers read [AppConfig.backendMode] (or [AppConfig.isLocalOnlyDev]) and
/// never test `API_BASE_URL` themselves.
library;

import '../api/api_config.dart';
import 'app_environment.dart';
import 'url_rules.dart';

/// Flutter's three build modes (`flutter run --debug|--profile|--release`).
/// [kBuildMode] in `app_config.dart` is the mode this binary was compiled in.
enum BuildMode {
  debug,
  profile,
  release;

  /// The lowercase name, as used in messages and in `tool/check_backend_config.dart`.
  String get wireName => name;

  static BuildMode? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final m in BuildMode.values) {
      if (m.name == value) return m;
    }
    return null;
  }
}

/// How a valid build reaches its backend.
enum BackendMode {
  /// `API_BASE_URL` is valid: sign-in is required before anything is configured.
  /// This is the only mode a profile or release build can have.
  online,

  /// Development only (`debug` + `--dart-define=LOCAL_ONLY_DEV=true`): no
  /// backend and no account; the app starts at the local setup. Shows the
  /// `LOCAL ONLY DEVELOPMENT MODE` banner.
  localOnlyDev,
}

/// The accepted spellings of the `LOCAL_ONLY_DEV` define.
const String kLocalOnlyDevDefine = 'LOCAL_ONLY_DEV';

/// What [validateBackendConfig] decided. Either [mode] is set and [errors] is
/// empty, or the build is invalid: [mode] is null and [errors] says why.
class BackendConfigCheck {
  const BackendConfigCheck._(this.mode, this.errors);

  const BackendConfigCheck.valid(BackendMode mode) : this._(mode, const []);

  const BackendConfigCheck.invalid(List<String> errors) : this._(null, errors);

  /// `null` when the build is invalid.
  final BackendMode? mode;

  /// One line per violated rule. Never contains a define's value: an address
  /// could carry credentials.
  final List<String> errors;

  bool get isValid => mode != null;

  @override
  String toString() => isValid
      ? 'BackendConfigCheck(${mode!.name})'
      : 'BackendConfigCheck($errors)';
}

/// The build mode a binary must be validated for. [compiled] is what the
/// `dart.vm.*` constants say ([kBuildMode]); [assertsEnabled] is whether
/// `assert` statements run in this process.
///
/// Flutter runs `assert` only in debug (JIT) builds, and `dart.vm.product` /
/// `dart.vm.profile` can be overridden on the command line (a `--dart-define`
/// or `--extra-front-end-options` that names them), so a profile or release
/// AOT binary could otherwise claim to be a debug build and unlock
/// [BackendMode.localOnlyDev]. A binary that says "debug" but does not run
/// assertions is therefore validated as a release build (fail closed).
BuildMode effectiveBuildMode({
  required BuildMode compiled,
  required bool assertsEnabled,
}) =>
    compiled == BuildMode.debug && !assertsEnabled
        ? BuildMode.release
        : compiled;

/// The `APP_ENV` rule set a build is validated against. A debug build without
/// `APP_ENV` is `development` (a plain `flutter run`); a profile or release
/// build without `APP_ENV` gets the strictest set, `production` (https only,
/// no placeholder hosts), because a build that ships must never accept
/// cleartext just because a define was forgotten. A typo is `production` in
/// every mode (see [AppEnvironment.resolve]).
AppEnvironment effectiveEnvironment({
  required BuildMode buildMode,
  required String appEnv,
}) =>
    appEnv.trim().isEmpty && buildMode != BuildMode.debug
        ? AppEnvironment.production
        : AppEnvironment.resolve(appEnv);

/// Validates the backend configuration of a build. Pure: the compiled-in
/// values are fed in by [AppConfig.fromEnvironment]; tests, the CI tool and
/// the release workflow feed in their own.
///
/// * [apiBaseUrl] the raw `API_BASE_URL` define ('' when unset).
/// * [localOnlyDev] the raw `LOCAL_ONLY_DEV` define: '' (unset), `true` or
///   `false`; any other spelling is an error (a safety switch is never guessed).
/// * [environment] the `APP_ENV` rule set the address is validated against.
BackendConfigCheck validateBackendConfig({
  required BuildMode buildMode,
  String apiBaseUrl = '',
  String localOnlyDev = '',
  AppEnvironment? environment,
}) {
  // Not given: the rule set the build would get without APP_ENV (development for debug, production otherwise).
  final env =
      environment ?? effectiveEnvironment(buildMode: buildMode, appEnv: '');
  environment = env;
  final errors = <String>[];

  final flagRaw = localOnlyDev.trim();
  final flagMalformed =
      flagRaw.isNotEmpty && flagRaw != 'true' && flagRaw != 'false';
  final flagOn = flagRaw == 'true';
  if (flagMalformed) {
    errors.add('$kLocalOnlyDevDefine must be true or false');
  }
  if (flagOn && buildMode != BuildMode.debug) {
    errors.add('$kLocalOnlyDevDefine=true is only allowed in debug builds '
        '(this is a ${buildMode.wireName} build)');
  }
  if (flagOn && environment != AppEnvironment.development) {
    errors.add('$kLocalOnlyDevDefine=true is only allowed in the development '
        'environment (APP_ENV is ${environment.wireName})');
  }

  // An address that is present but wrong is an error of its own: it must never
  // degrade into "no backend", which is exactly the local-only behaviour.
  final api = ApiConfig(apiBaseUrl, environment: environment);
  final apiProblem = api.problem;
  final apiPresent = api.isConfigured || apiProblem != null;
  if (apiProblem != null) errors.add(apiProblem);

  // A build that ships is not a development build (F-14): `APP_ENV=development` relaxes https and placeholder-host rules for a
  // laptop, and a release carrying it would talk cleartext to whatever the address says. The address must also be a name a
  // stranger's phone can resolve: localhost, an IP literal, a single-label name or a reserved domain (`.local`, `example.com`)
  // is a development address whatever APP_ENV says.
  if (buildMode != BuildMode.debug) {
    if (environment == AppEnvironment.development) {
      errors.add(
          'APP_ENV=development is not allowed in ${buildMode.wireName} builds '
          '(use staging or production)');
    }
    final host = Uri.tryParse(apiBaseUrl.trim())?.host ?? '';
    if (apiProblem == null && api.isConfigured && isNonPublicHost(host)) {
      errors.add(
          'API_BASE_URL must be a public host in ${buildMode.wireName} builds '
          '(not localhost, an IP address, a single-label name or a reserved domain)');
    }
  }

  if (apiPresent) {
    if (flagOn && buildMode == BuildMode.debug) {
      errors.add('$kLocalOnlyDevDefine=true cannot be combined with '
          'API_BASE_URL: remove one of them');
    }
  } else if (buildMode == BuildMode.debug) {
    if (!flagOn) {
      errors.add('API_BASE_URL is required. For development without a '
          'backend build with --dart-define=$kLocalOnlyDevDefine=true');
    }
  } else {
    errors.add('API_BASE_URL is required in ${buildMode.wireName} builds '
        '($kLocalOnlyDevDefine is not available there)');
  }

  if (errors.isNotEmpty) {
    return BackendConfigCheck.invalid(List.unmodifiable(errors));
  }
  return BackendConfigCheck.valid(
      apiPresent ? BackendMode.online : BackendMode.localOnlyDev);
}
