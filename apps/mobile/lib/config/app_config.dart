// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;

import '../api/api_config.dart';
import 'app_environment.dart';
import 'backend_config.dart';
import 'feature_flags.dart';
import 'url_rules.dart';

export 'app_environment.dart';
export 'backend_config.dart';

/// The mode this binary was compiled in (a compile-time constant, so code
/// behind `kBuildMode == BuildMode.debug` is removed from profile and release).
const BuildMode kBuildMode = kReleaseMode
    ? BuildMode.release
    : kProfileMode
        ? BuildMode.profile
        : BuildMode.debug;

/// The build-time half of the release guard: a profile or release build that
/// lacks `API_BASE_URL` or carries `LOCAL_ONLY_DEV=true` does not compile.
///
/// The compiler evaluates this constant while it compiles the library, in
/// every build, and a failed `assert` in a constant constructor is a
/// compile-time error (whether or not assertions are enabled at run time):
///
///   flutter build apk --release
///   Error: Constant evaluation error: ... This assertion failed with message:
///   [WB-CONFIG-001] ...
///
/// Debug builds are not stopped here (`flutter test` and `flutter analyze`
/// compile without defines): they are validated at start-up by
/// [validateBackendConfig], where `main()` shows [ConfigErrorApp] instead of
/// the app. Strings cannot be parsed in a constant, so this layer covers the
/// two mistakes that matter most (missing address, `LOCAL_ONLY_DEV`); the
/// start-up check covers everything else (address syntax, https, ...) in every
/// mode. Both call the same rules, see `docs/CONFIGURATION_MOBILE.md`.
const BuildConfigurationGuard kBuildConfigurationGuard =
    BuildConfigurationGuard(
  optimizedBuild: kReleaseMode || kProfileMode,
  apiBaseUrl: String.fromEnvironment('API_BASE_URL'),
  localOnlyDev: String.fromEnvironment(kLocalOnlyDevDefine),
);

/// Whether `assert` statements run in this process: true in a debug (JIT)
/// build and in `flutter test`, false in profile and release (AOT). A second,
/// independent signal for the build mode, see [effectiveBuildMode].
bool _assertsEnabled() {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}

/// See [kBuildConfigurationGuard]. Only its constant constructor matters.
class BuildConfigurationGuard {
  const BuildConfigurationGuard({
    required bool optimizedBuild,
    required String apiBaseUrl,
    required String localOnlyDev,
  })  : assert(
          !optimizedBuild || apiBaseUrl != '',
          '[WB-CONFIG-001] INVALID BUILD CONFIGURATION: a profile or release '
          'build needs --dart-define=API_BASE_URL=<https address of the API>. '
          'Building without a backend is a debug-only mode '
          '(flutter run --dart-define=LOCAL_ONLY_DEV=true)',
        ),
        assert(
          !optimizedBuild || localOnlyDev == '' || localOnlyDev == 'false',
          '[WB-CONFIG-002] INVALID BUILD CONFIGURATION: in a profile or '
          'release build LOCAL_ONLY_DEV must be unset or exactly false '
          '(LOCAL_ONLY_DEV=true is a debug-only mode). Remove it from this '
          'build',
        );
}

/// Diagnostic status while no public privacy-policy URL is configured. Used in
/// the docs and in the debug-only startup log line; never shown to users.
const String kPrivacyPolicyBlockedStatus = 'BLOCKED — PUBLIC URL REQUIRED';

/// Diagnostic status once a valid public https URL is configured.
const String kPrivacyPolicyConfiguredStatus = 'CONFIGURED';

/// Everything that differs between development, staging and production builds,
/// decided at build time with `--dart-define` (or `--dart-define-from-file`,
/// see `config/*.example.json` and `docs/CONFIGURATION_MOBILE.md`):
///
/// | define               | meaning                                                    |
/// |----------------------|------------------------------------------------------------|
/// | `APP_ENV`            | `development` (default), `staging`, `production`           |
/// | `API_BASE_URL`       | the API; required (see below); https outside development   |
/// | `LOCAL_ONLY_DEV`     | `true` only in a debug build without `API_BASE_URL`; default false |
/// | `PRIVACY_POLICY_URL` | public https page of the privacy policy                    |
/// | `FEATURE_AI`, `FEATURE_SUBSCRIPTIONS`, `FEATURE_CLOUD_SYNC` | build flag defaults |
///
/// `API_BASE_URL` is required unless the build is a debug build with
/// `LOCAL_ONLY_DEV=true`; the whole decision is [validateBackendConfig] and its
/// result is [backendMode] / [isValid]. An invalid build must not run: `main()`
/// shows the configuration error instead of the app, and no other code may
/// treat a missing address as "no backend" ([isLocalOnlyDev] is the only way
/// to ask).
///
/// No production or staging address lives in the source tree. Nothing here is
/// a secret: dart-defines end up in the shipped binary.
class AppConfig {
  const AppConfig._({
    required this.environment,
    required this.buildMode,
    required this.api,
    required this.backend,
    required this.privacyPolicyUrl,
    required this.featureDefaults,
    required this.problems,
  });

  /// Builds a configuration from raw define values. Pure, so tests can feed
  /// any combination; [fromEnvironment] feeds it the compiled-in values.
  /// [buildMode] defaults to the compiled mode ([kBuildMode]); [fromEnvironment]
  /// passes the effective one explicitly. Without `APP_ENV`, a profile or
  /// release build is validated as production ([effectiveEnvironment]).
  factory AppConfig.fromDefines({
    String appEnv = '',
    String apiBaseUrl = '',
    String localOnlyDev = '',
    String privacyPolicyUrl = '',
    FlagDefines flags = const FlagDefines(),
    BuildMode buildMode = kBuildMode,
  }) {
    final environment =
        effectiveEnvironment(buildMode: buildMode, appEnv: appEnv);
    final backend = validateBackendConfig(
      buildMode: buildMode,
      apiBaseUrl: apiBaseUrl,
      localOnlyDev: localOnlyDev,
      environment: environment,
    );
    final api = ApiConfig(apiBaseUrl, environment: environment);
    final policyRaw = privacyPolicyUrl.trim();
    final policyProblem =
        policyRaw.isEmpty ? null : publicHttpsUrlProblem(policyRaw);
    final problems = <String>[
      if (!AppEnvironment.isValidDefine(appEnv))
        'APP_ENV is not development, staging or production; '
            'the strictest rules (production) apply',
      ...backend.errors,
      if (policyProblem != null) 'PRIVACY_POLICY_URL $policyProblem',
      ...flags.problems,
    ];
    return AppConfig._(
      environment: environment,
      buildMode: buildMode,
      api: api,
      backend: backend,
      privacyPolicyUrl: policyRaw.isNotEmpty && policyProblem == null
          ? Uri.parse(policyRaw)
          : null,
      featureDefaults: flags.flags,
      problems: List.unmodifiable(problems),
    );
  }

  /// The configuration this binary was compiled with, validated for the build
  /// mode it really runs in ([effectiveBuildMode]: `dart.vm.*` constants plus
  /// whether assertions run).
  static final AppConfig fromEnvironment = AppConfig.fromDefines(
    buildMode: effectiveBuildMode(
      compiled: kBuildMode,
      assertsEnabled: _assertsEnabled(),
    ),
    appEnv: const String.fromEnvironment('APP_ENV'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    localOnlyDev: const String.fromEnvironment(kLocalOnlyDevDefine),
    privacyPolicyUrl: const String.fromEnvironment('PRIVACY_POLICY_URL'),
    flags: FlagDefines.fromEnvironment,
  );

  final AppEnvironment environment;

  /// The mode this configuration was validated for.
  final BuildMode buildMode;

  /// The validated API address ([ApiConfig.isConfigured] is false without one,
  /// and always in [BackendMode.localOnlyDev]).
  final ApiConfig api;

  /// The verdict of [validateBackendConfig] for this build.
  final BackendConfigCheck backend;

  /// How the build reaches its backend; `null` when the configuration is
  /// invalid and the app must not start.
  BackendMode? get backendMode => backend.mode;

  /// Whether the build may run at all. `main()` refuses to start otherwise.
  bool get isValid => backend.isValid;

  /// The explicit development mode without a backend and without an account.
  /// True only for a validated debug build with `LOCAL_ONLY_DEV=true`; this is
  /// the only way to skip the account and is never inferred from a missing or
  /// broken `API_BASE_URL`.
  bool get isLocalOnlyDev => backend.mode == BackendMode.localOnlyDev;

  /// The validated public https privacy-policy URL, `null` when none is
  /// configured or the configured one is not a public https URL.
  final Uri? privacyPolicyUrl;

  bool get hasPrivacyPolicyUrl => privacyPolicyUrl != null;

  /// [kPrivacyPolicyBlockedStatus] until a valid URL is configured.
  String get privacyPolicyStatus => hasPrivacyPolicyUrl
      ? kPrivacyPolicyConfiguredStatus
      : kPrivacyPolicyBlockedStatus;

  /// The build-time flag defaults, before the server's configuration is merged
  /// in (see `featureFlagsProvider`).
  final FeatureFlags featureDefaults;

  /// What is wrong with the build's defines, one line each. Never contains a
  /// define's value (it could be a credential pasted into the wrong place).
  final List<String> problems;

  bool get isProduction => environment == AppEnvironment.production;

  /// Value-free summary for the debug-only startup log.
  String get diagnostics {
    final apiState = api.isConfigured
        ? 'configured (${Uri.parse(api.baseUrl).host})'
        : 'not configured';
    return 'build=${buildMode.wireName} env=${environment.wireName} '
        'backend=${backendMode?.name ?? 'INVALID'} api=$apiState '
        'privacyPolicy=$privacyPolicyStatus '
        'flags=ai:${featureDefaults.ai} subscriptions:${featureDefaults.subscriptions} '
        'cloudSync:${featureDefaults.cloudSync}'
        '${problems.isEmpty ? '' : ' problems=${problems.length}'}';
  }
}
