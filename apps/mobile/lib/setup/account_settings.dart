import '../api/api_factory.dart';
import '../api/api_failure.dart';
import '../api/session_manager.dart';
import '../generated/api/api.dart' as api;
import '../settings/settings.dart';

// What the account holds is region, currency and the price decision, each with
// the origin of the value (`detected`, `manual`, `migratedManual`: how the device
// that saved it got it). A device that reads a value records it as
// `SettingSource.accountSynced` and keeps that origin as its `originalSource`.
// Rules: `docs/SETTING_SOURCES.md`.

ElectricityPriceMode _mode(api.UserSettingsDtoElectricityPriceModeEnum m) =>
    m == api.UserSettingsDtoElectricityPriceModeEnum.manual
        ? ElectricityPriceMode.manual
        : ElectricityPriceMode.automatic;

/// The account's answer in the app's own terms.
extension AccountSettingsView on api.UserSettingsDto {
  SettingSource? get countryOrigin =>
      SettingSource.tryParseOriginal(countryCodeSource?.toJson());
  SettingSource? get currencyOrigin =>
      SettingSource.tryParseOriginal(currencyCodeSource?.toJson());
  SettingSource? get priceOrigin =>
      SettingSource.tryParseOriginal(electricityPriceSource?.toJson());
  ElectricityPriceMode get priceMode => _mode(electricityPriceMode);

  /// The account holds a price DECISION: a manual tariff, or an explicit choice
  /// of the mode. A fresh account answers "automatic" because the column has to
  /// say something, which decides nothing.
  bool get hasPriceDecision =>
      priceMode == ElectricityPriceMode.manual ||
      electricityPriceSource != null;
}

/// Whether this phone's own value of [g] wins over what the account holds.
///
/// A conscious local value (manual here, or migrated from an older version) that
/// the account has not acknowledged yet is the user's latest explicit decision
/// and wins. Once the account has acknowledged it, the account is the newer
/// word if it says something else: another device changed it since.
bool _localWins(Settings s, SettingGroup g) =>
    s.sourceOf(g).isConscious && !s.accountInSync.contains(g);

/// This phone wrote (or already took) exactly what the account holds: reading
/// it back changes nothing, and above all not its source. Device A's manual EUR
/// stays manual when A reads EUR from the account.
bool _alreadyThere(Settings s, SettingGroup g, api.UserSettingsDto a) {
  // An account value is read again every time, so that its origin stays current.
  if (!s.accountInSync.contains(g) ||
      s.sourceOf(g) == SettingSource.accountSynced) {
    return false;
  }
  return switch (g) {
    SettingGroup.region => s.countryCode == a.countryCode,
    SettingGroup.currency => s.currency == a.currencyCode,
    SettingGroup.price => s.priceMode == a.priceMode &&
        (a.manualElectricityPrice == null ||
            s.manualPricePerKwh == a.manualElectricityPrice!.toDouble()),
  };
}

/// Merges what the account holds into [s]: the account half of the setting
/// priorities,
///
///   1. an explicit local choice, until the account has acknowledged it
///   2. the account's value (source `accountSynced`, the account's origin kept
///      as `originalSource`)
///
/// Detection (3) and the fallback (4) are applied by `AutoSetup.apply` to what
/// is still undecided. A null [account] means "unreachable": nothing changes,
/// not even a source, so the last value this phone knows keeps working offline.
Settings mergeAccountSettings(Settings s, api.UserSettingsDto? account) {
  if (account == null) return s;
  var next = s;
  final country = account.countryCode;
  if (country != null &&
      !_localWins(next, SettingGroup.region) &&
      !_alreadyThere(next, SettingGroup.region, account)) {
    next = next.withAccountRegion(country, original: account.countryOrigin);
  }
  final currency = account.currencyCode;
  if (currency != null &&
      !_localWins(next, SettingGroup.currency) &&
      !_alreadyThere(next, SettingGroup.currency, account)) {
    next = next.withAccountCurrency(currency, original: account.currencyOrigin);
  }
  if (account.hasPriceDecision &&
      !_localWins(next, SettingGroup.price) &&
      !_alreadyThere(next, SettingGroup.price, account)) {
    next = next.withAccountPrice(
      mode: account.priceMode,
      manualPrice: account.manualElectricityPrice?.toDouble(),
      original: account.priceOrigin,
    );
  }
  return next;
}

/// The groups this phone has decided itself and the account does not hold yet:
/// what is uploaded. A value that came FROM the account is never sent back
/// (it could only undo a newer change made elsewhere), and neither is a price
/// that nobody decided.
Set<SettingGroup> groupsToPush(Settings s) => {
      for (final g in SettingGroup.values)
        if (s.sourceOf(g) != SettingSource.accountSynced &&
            !s.accountInSync.contains(g) &&
            s.hasValue(g) &&
            (g != SettingGroup.price ||
                s.priceSource.isConscious ||
                s.priceMode == ElectricityPriceMode.manual))
          g
    };

/// The outcome of one upload: the account as it is now, and the groups it took.
class AccountPush {
  const AccountPush(this.settings, this.groups, this.pushed);

  final api.UserSettingsDto settings;
  final Set<SettingGroup> groups;

  /// The local settings the upload was made from: a group is "in sync" only if
  /// it still has this value when the answer arrives.
  final Settings pushed;
}

/// Account-level preferences (`/me/settings`): country, currency and the price
/// decision follow the account; everything device-bound stays local.
class AccountSettingsSync {
  AccountSettingsSync({required this.apis, required this.sessions});

  final ApiFactory apis;
  final SessionManager sessions;

  /// Uploads the groups [s] decided itself ([groupsToPush]); for every other
  /// group the account's own current value is sent back unchanged (the generated
  /// client sends an unset field as `null`, which would clear it). Best effort:
  /// null when the account cannot be reached, never an exception into the UI.
  ///
  /// [current] is the account as just read; without it the account is read
  /// first, so nothing is ever written from a stale copy.
  Future<AccountPush?> push(Settings s, {api.UserSettingsDto? current}) async {
    try {
      final account = current ?? await pull();
      if (account == null) return null;
      final groups = groupsToPush(s);
      if (groups.isEmpty) return AccountPush(account, groups, s);
      final region = groups.contains(SettingGroup.region);
      final currency = groups.contains(SettingGroup.currency);
      final price = groups.contains(SettingGroup.price);
      final request = api.UpdateUserSettingsRequest(
        countryCode: region ? s.countryCode : account.countryCode,
        countryCodeSource: _countrySource(
            region ? s.regionSource.wire : account.countryCodeSource?.toJson()),
        currencyCode: currency ? s.currency : account.currencyCode,
        currencyCodeSource: _currencySource(currency
            ? s.currencySource.wire
            : account.currencyCodeSource?.toJson()),
        electricityPriceMode:
            _requestMode(price ? s.priceMode : account.priceMode),
        // A manual mode needs its price, zero included; in automatic mode the
        // tariff is only kept for the way back.
        manualElectricityPrice: price
            ? (s.priceMode == ElectricityPriceMode.manual ||
                    s.manualPricePerKwh > 0
                ? s.manualPricePerKwh
                : null)
            : account.manualElectricityPrice,
        electricityPriceSource: _priceSource(price
            ? s.priceSource.wire
            : account.electricityPriceSource?.toJson()),
      );
      final saved = await sessions.authorized((token) => guarded(() =>
          api.AccountApi(apis.bearer(token)).apiV1MeSettingsPut(request)));
      return saved == null ? null : AccountPush(saved, groups, s);
    } on ApiFailure {
      return null;
    } on Exception {
      return null;
    }
  }

  /// What the account holds (possibly nothing: every field null); null when the
  /// API cannot be reached or nobody is signed in.
  Future<api.UserSettingsDto?> pull() async {
    try {
      return await sessions.authorized((token) => guarded(
          () => api.AccountApi(apis.bearer(token)).apiV1MeSettingsGet()));
    } on ApiFailure {
      return null;
    } on Exception {
      return null;
    }
  }
}

api.UpdateUserSettingsRequestElectricityPriceModeEnum _requestMode(
        ElectricityPriceMode m) =>
    m == ElectricityPriceMode.manual
        ? api.UpdateUserSettingsRequestElectricityPriceModeEnum.manual
        : api.UpdateUserSettingsRequestElectricityPriceModeEnum.automatic;

// The generated client has one enum per field; the wire names are the same.
// A name the API does not accept (`accountSynced`) decodes to null = "not given".
api.UpdateUserSettingsRequestCountryCodeSourceEnum? _countrySource(
        String? wire) =>
    api.UpdateUserSettingsRequestCountryCodeSourceEnum.fromJson(wire);
api.UpdateUserSettingsRequestCurrencyCodeSourceEnum? _currencySource(
        String? wire) =>
    api.UpdateUserSettingsRequestCurrencyCodeSourceEnum.fromJson(wire);
api.UpdateUserSettingsRequestElectricityPriceSourceEnum? _priceSource(
        String? wire) =>
    api.UpdateUserSettingsRequestElectricityPriceSourceEnum.fromJson(wire);
