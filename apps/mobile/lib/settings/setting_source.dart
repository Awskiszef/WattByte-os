// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Why a setting has the value it has (see `docs/SETTING_SOURCES.md`).
///
/// One model for every setting that can come from more than one place: the
/// region, the currency and the electricity price decision. It answers two
/// different questions that used to be mixed into one word, "manual":
///
///  * *was it chosen on this device?* ([manual], [migratedManual])
///  * *did it come from the user's account?* ([accountSynced])
enum SettingSource {
  /// Found by WattByte: the device region, the catalog, a default.
  detected,

  /// The user set it on this device on purpose.
  manual,

  /// It came from the user's account (another device, or an earlier install).
  /// How the account got it is the setting's `originalSource`; this value alone
  /// says nothing about a choice made here, and must never become [manual] just
  /// because an account value outranks a fresh detection.
  accountSynced,

  /// A value from an older version of the app that the user gave on purpose
  /// (the old onboarding asked for it). The migration cannot tell more about it,
  /// so it is kept and treated like [manual].
  migratedManual;

  /// A choice of the user, here or (as [migratedManual]) in an older version:
  /// automatic detection never replaces it.
  bool get isConscious => this == manual || this == migratedManual;

  /// A source a value can have on the account (the first place it was decided).
  /// [accountSynced] is how a value reaches a device, never how the account got it.
  bool get canBeOriginal => this != accountSynced;

  /// The name stored in preferences and sent to the API.
  String get wire => name;

  /// Parses a stored or received name. `automatic` is the name the first version
  /// of the model used for [detected]. Null for anything else.
  static SettingSource? tryParse(Object? name) {
    if (name == 'automatic') return detected;
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// The origin of an account value from its wire name: only the three origins
  /// the API accepts; null = unknown (never guessed).
  static SettingSource? tryParseOriginal(Object? name) {
    final s = tryParse(name);
    return s != null && s.canBeOriginal ? s : null;
  }
}

/// The settings that follow the account (everything else is local to the phone,
/// or device-bound and sent with the device registration).
enum SettingGroup {
  /// `countryCode`.
  region,

  /// `currency`.
  currency,

  /// The price decision as a whole: the mode and the manual tariff. The
  /// household average itself is data from `ElectricityPriceService`, not a setting.
  price;

  static SettingGroup? tryParse(Object? name) {
    for (final g in values) {
      if (g.name == name) return g;
    }
    return null;
  }
}
