// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// The deployment a build talks to, chosen at build time:
///
///   flutter build ... --dart-define=APP_ENV=staging
///
/// Never read at run time from anything the user or the network controls.
enum AppEnvironment {
  development,
  staging,
  production;

  /// Staging and production never speak cleartext HTTP; only development may.
  bool get requiresHttps => this != AppEnvironment.development;

  /// The lowercase name as written in `APP_ENV` and in the server's `environment`.
  String get wireName => name;

  /// `null` when [raw] is not one of the three names (case and surrounding
  /// whitespace are ignored). An empty string is not a name either: see [resolve].
  static AppEnvironment? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final e in AppEnvironment.values) {
      if (e.name == value) return e;
    }
    return null;
  }

  /// Whether an `APP_ENV` define is acceptable: unset, or one of the three names.
  static bool isValidDefine(String raw) =>
      raw.trim().isEmpty || tryParse(raw) != null;

  /// Resolves an `APP_ENV` define: unset means development (a plain
  /// `flutter run`), a name means that environment, and anything else - a typo
  /// such as `prod` - means [production], the strictest rule set, so a typo can
  /// never switch cleartext HTTP on. [AppConfig.problems] reports the typo.
  static AppEnvironment resolve(String raw) {
    if (raw.trim().isEmpty) return AppEnvironment.development;
    return tryParse(raw) ?? AppEnvironment.production;
  }
}
