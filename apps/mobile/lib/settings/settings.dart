import 'package:shared_preferences/shared_preferences.dart';

import '../calc/energy.dart';
import '../domain/battery_capacity.dart';
import 'setting_source.dart';

export 'setting_source.dart';

enum AppTheme { system, light, dark }

enum ElectricityPriceMode { automatic, manual }

/// The household price last received from the API (`GET /electricity-price`).
/// Kept separately from the effective price so switching back from a manual
/// price restores it without a network call.
class AutoPrice {
  const AutoPrice({
    required this.pricePerKwh,
    required this.currency,
    required this.countryCode,
    required this.period,
    required this.source,
    required this.updatedAt,
    this.stale = false,
  });

  final double pricePerKwh;
  final String currency;
  final String countryCode;

  /// Reporting period of the statistic, e.g. `2026-S1`.
  final String period;

  /// `eurostat`, `government`, `fallback`.
  final String source;

  /// When the app received it.
  final DateTime updatedAt;

  /// The server could not reach its source and served its last known value.
  final bool stale;
}

/// User preferences. Immutable; persisted by [SettingsStore].
class Settings {
  const Settings({
    this.currency = '',
    this.currencySource = SettingSource.detected,
    this.currencyOriginalSource,
    this.countryCode = '',
    this.regionSource = SettingSource.detected,
    this.regionDetection = '',
    this.regionOriginalSource,
    this.pricePerKwh = 0,
    this.priceMode = ElectricityPriceMode.automatic,
    this.manualPricePerKwh = 0,
    this.priceSource = SettingSource.detected,
    this.priceOriginalSource,
    this.autoPrice,
    this.efficiency = 0.85,
    this.designCapacityMah = 0,
    this.designCapacityWh = 0,
    this.designCapacitySource = DesignCapacitySource.unknown,
    this.deviceModel = '',
    this.deviceModelIdentifier = '',
    this.nominalVoltage = 3.85,
    this.binaryUnits = false,
    this.notifyMobileThreshold = false,
    this.mobileThresholdBytes = 5000000000,
    this.notifyChargingDone = false,
    this.notifyWeeklyEnergy = false,
    this.notifyAboveAverage = false,
    this.dataCollection = true,
    this.onboarded = false,
    this.theme = AppTheme.system,
    this.cloudSync = false,
    this.accountInSync = const {},
  });

  // Where the account-bound values come from. Every group has a [SettingSource]
  // and, when that is `accountSynced`, an `originalSource`: how the ACCOUNT got
  // the value (null = the account does not say). `docs/SETTING_SOURCES.md`.

  /// ISO 4217 code shown next to costs; empty until detected or chosen.
  final String currency;
  final SettingSource currencySource;
  final SettingSource? currencyOriginalSource;

  /// ISO 3166-1 alpha-2 of the user's region; empty = not known.
  final String countryCode;
  final SettingSource regionSource;

  /// How a detected region was found: `deviceRegion`, `deviceLocale` or
  /// `backendCountry`; empty for every other source.
  final String regionDetection;
  final SettingSource? regionOriginalSource;

  /// Price per kWh in [currency] used by every calculation; 0 means "none yet".
  /// Automatic mode: the household average from [autoPrice] (when its currency
  /// matches). Manual mode: [manualPricePerKwh].
  final double pricePerKwh;
  final ElectricityPriceMode priceMode;

  /// The user's own tariff, kept even while automatic mode is active.
  final double manualPricePerKwh;

  /// Who decided the price mode and the tariff (not where the household average
  /// comes from: [autoPrice] is data, refreshed by `ElectricityPriceService`,
  /// and never changes this).
  final SettingSource priceSource;
  final SettingSource? priceOriginalSource;
  final AutoPrice? autoPrice;

  /// Charging efficiency 0-1 (default 85 %): battery energy / efficiency = wall energy.
  final double efficiency;

  /// Design (nominal) capacity of this phone model; 0 = unknown. A published or
  /// typed figure, never a measurement: the estimated full-charge capacity of
  /// this particular battery lives in the collector, not here (see
  /// `docs/BATTERY_CAPACITY.md`). Read it as a [DesignCapacity] via
  /// [designCapacity]; the three fields are kept coherent by [sanitized].
  final double designCapacityMah;

  /// Published Wh of the battery when the catalog has it; 0 = unknown.
  final double designCapacityWh;

  /// Where the design capacity came from; [DesignCapacitySource.unknown] when
  /// no capacity is known.
  final DesignCapacitySource designCapacitySource;

  /// Marketing name from the catalog ("iPhone 15 Pro") or the platform model string.
  final String deviceModel;

  /// iOS `utsname.machine` / Android `Build.MODEL`; empty until detected.
  final String deviceModelIdentifier;
  final double nominalVoltage;
  final bool binaryUnits;

  final bool notifyMobileThreshold;
  final int mobileThresholdBytes;
  final bool notifyChargingDone;
  final bool notifyWeeklyEnergy;
  final bool notifyAboveAverage;

  /// Master switch for reading system statistics.
  final bool dataCollection;

  /// The automatic setup (account -> detection -> review -> permissions) finished.
  final bool onboarded;
  final AppTheme theme;

  /// A VIEW of the cloud-sync switch, not the consent. Cloud sync is a per-account
  /// opt-in recorded in the sync ledger (`SyncOwnership`, `sync_account:<accountKey>`
  /// in the database): the truth. While an account is signed in, `settingsProvider`
  /// sets this field from that record (so a second user of the phone sees it OFF);
  /// with nobody known it is the last value shown. [SettingsStore] keeps it only so
  /// the switch is right on the first frame after a restart. NEVER decide to upload
  /// from this field: `SyncService` reads the ledger itself, and so must anything
  /// else that sends data. Off by default: WattByte is local-first.
  final bool cloudSync;

  /// The groups whose current value this phone knows to be on the account: the
  /// value came from it, or the account acknowledged an upload. A conscious local
  /// value that is NOT in this set has never reached the account (an offline edit,
  /// an upgrade) and wins over what the account holds; one that is in it is only
  /// as new as the last time the account agreed, so a later change from another
  /// device wins (see `mergeAccountSettings`).
  final Set<SettingGroup> accountInSync;

  bool get hasPrice => pricePerKwh > 0;
  bool get hasCurrency => currency.isNotEmpty;

  /// Costs derived from a national average are estimates by nature.
  bool get priceIsAverage =>
      priceMode == ElectricityPriceMode.automatic && hasPrice;

  /// The automatic price can only be applied when it is in the display currency.
  bool get autoPriceMatchesCurrency =>
      autoPrice != null && autoPrice!.currency == currency;

  SettingSource sourceOf(SettingGroup g) => switch (g) {
        SettingGroup.region => regionSource,
        SettingGroup.currency => currencySource,
        SettingGroup.price => priceSource,
      };

  SettingSource? originalSourceOf(SettingGroup g) => switch (g) {
        SettingGroup.region => regionOriginalSource,
        SettingGroup.currency => currencyOriginalSource,
        SettingGroup.price => priceOriginalSource,
      };

  /// The user decided this value, on this phone or (a synced value whose origin
  /// is a manual choice) on another one. Detection never replaces it silently.
  bool isCustom(SettingGroup g) {
    final source = sourceOf(g);
    return source.isConscious ||
        (source == SettingSource.accountSynced &&
            (originalSourceOf(g)?.isConscious ?? false));
  }

  /// Whether this group has something to say at all (an empty region or
  /// currency, and a price still at its default, have not been decided).
  bool hasValue(SettingGroup g) => switch (g) {
        SettingGroup.region => countryCode.isNotEmpty,
        SettingGroup.currency => currency.isNotEmpty,
        SettingGroup.price => priceMode == ElectricityPriceMode.manual ||
            priceSource != SettingSource.detected,
      };

  Settings _inSync(SettingGroup g, bool value) => copyWith(
      accountInSync:
          value ? {...accountInSync, g} : ({...accountInSync}..remove(g)));

  /// Records that the account now holds [groups] as they were in [uploaded]: a
  /// group that was edited while the upload was on its way is not acknowledged,
  /// because the account has never seen its new value.
  Settings markInSyncFrom(Settings uploaded, Iterable<SettingGroup> groups) =>
      copyWith(accountInSync: {
        ...accountInSync,
        for (final g in groups)
          if (_sameDecision(uploaded, g)) g
      });

  bool _sameDecision(Settings o, SettingGroup g) => switch (g) {
        SettingGroup.region =>
          countryCode == o.countryCode && regionSource == o.regionSource,
        SettingGroup.currency =>
          currency == o.currency && currencySource == o.currencySource,
        SettingGroup.price => priceMode == o.priceMode &&
            manualPricePerKwh == o.manualPricePerKwh &&
            priceSource == o.priceSource,
      };

  // ---- region

  Settings withManualRegion(String code) => copyWith(
          countryCode: code.trim().toUpperCase(),
          regionSource: SettingSource.manual,
          regionDetection: '',
          clearRegionOriginalSource: true)
      ._inSync(SettingGroup.region, false);

  Settings withDetectedRegion(String code, {String detection = ''}) => copyWith(
          countryCode: code,
          regionSource: SettingSource.detected,
          regionDetection: detection,
          clearRegionOriginalSource: true)
      ._inSync(SettingGroup.region, false);

  /// A region that came from the account; [original] is how the account got it.
  Settings withAccountRegion(String code, {SettingSource? original}) =>
      copyWith(
              countryCode: code,
              regionSource: SettingSource.accountSynced,
              regionDetection: '',
              regionOriginalSource: original,
              clearRegionOriginalSource: original == null)
          ._inSync(SettingGroup.region, true);

  /// The design capacity as a value object (unknown when no mAh is stored).
  DesignCapacity get designCapacity => DesignCapacity(
        mah: designCapacityMah,
        wh: designCapacityWh,
        source: designCapacitySource,
      );

  /// Replaces the three design-capacity fields together, so they stay
  /// coherent: [DesignCapacity.unknown] becomes 0 / 0 / unknown.
  Settings withDesignCapacity(DesignCapacity capacity) => copyWith(
        designCapacityMah: capacity.mah ?? 0,
        designCapacityWh: capacity.wh ?? 0,
        designCapacitySource: capacity.source,
      );

  /// The one place that builds the calculator from settings. The design
  /// capacity wins; only when none is known is the estimated full-charge
  /// capacity of this battery used as the `% -> mAh` basis (0 = unknown). The
  /// calculator's capacity is therefore not always a design capacity.
  EnergyCalc energyCalc({double estimatedFullChargeCapacityMah = 0}) =>
      EnergyCalc(
        batteryCapacityMah: designCapacity.isKnown
            ? designCapacityMah
            : estimatedFullChargeCapacityMah,
        nominalVoltage: nominalVoltage,
        efficiency: efficiency,
        pricePerKwh: pricePerKwh,
      );

  /// Stores a freshly fetched household price and applies it when the user did
  /// not choose a manual tariff (and the currencies agree).
  Settings withAutoPrice(AutoPrice price) {
    final next = copyWith(autoPrice: price);
    return next.priceMode == ElectricityPriceMode.manual
        ? next
        : next.copyWith(pricePerKwh: next._effectiveAutoPrice);
  }

  /// The user typed a tariff on this phone.
  Settings withManualPrice(double value) => copyWith(
          priceMode: ElectricityPriceMode.manual,
          manualPricePerKwh: value,
          pricePerKwh: value,
          priceSource: SettingSource.manual,
          clearPriceOriginalSource: true)
      ._inSync(SettingGroup.price, false);

  /// The household average from [autoPrice] is used from now on. Called by the
  /// user's own "Use automatic price" ([source] manual: a decision), and with
  /// [SettingSource.detected] when the mode only follows a changed currency.
  /// The manual tariff is kept for the way back.
  Settings withAutomaticPrice({SettingSource source = SettingSource.manual}) =>
      copyWith(
              priceMode: ElectricityPriceMode.automatic,
              pricePerKwh: _effectiveAutoPrice,
              priceSource: source,
              clearPriceOriginalSource: true)
          ._inSync(SettingGroup.price, false);

  /// The price decision of the account (another phone, or an earlier install):
  /// the mode and the tariff it holds. An automatic mode stays automatic, with the
  /// tariff only kept for the way back; the effective price is then the household
  /// average of THIS phone's [autoPrice], which the account never stores.
  Settings withAccountPrice({
    required ElectricityPriceMode mode,
    double? manualPrice,
    SettingSource? original,
  }) {
    final tariff = manualPrice ?? manualPricePerKwh;
    return copyWith(
            priceMode: mode,
            manualPricePerKwh: tariff,
            pricePerKwh: mode == ElectricityPriceMode.manual
                ? tariff
                : _effectiveAutoPrice,
            priceSource: SettingSource.accountSynced,
            priceOriginalSource: original,
            clearPriceOriginalSource: original == null)
        ._inSync(SettingGroup.price, true);
  }

  double get _effectiveAutoPrice =>
      autoPriceMatchesCurrency ? autoPrice!.pricePerKwh : 0;

  /// A currency chosen by the user; an automatic price in another currency no longer applies.
  Settings withManualCurrency(String code) => copyWith(
          currency: code.trim().toUpperCase(),
          currencySource: SettingSource.manual,
          clearCurrencyOriginalSource: true)
      ._inSync(SettingGroup.currency, false)
      ._reapplyPrice();

  /// A currency WattByte worked out from the region.
  Settings withDetectedCurrency(String code) => copyWith(
          currency: code,
          currencySource: SettingSource.detected,
          clearCurrencyOriginalSource: true)
      ._inSync(SettingGroup.currency, false)
      ._reapplyPrice();

  /// A currency that came from the account; [original] is how the account got it.
  Settings withAccountCurrency(String code, {SettingSource? original}) =>
      copyWith(
              currency: code,
              currencySource: SettingSource.accountSynced,
              currencyOriginalSource: original,
              clearCurrencyOriginalSource: original == null)
          ._inSync(SettingGroup.currency, true)
          ._reapplyPrice();

  Settings _reapplyPrice() => priceMode == ElectricityPriceMode.manual
      ? this
      : copyWith(pricePerKwh: _effectiveAutoPrice);

  /// Replaces every physically impossible value (NaN, negative, out of range)
  /// with its default. Applied when reading storage, so one corrupt preference
  /// can never make the calculations throw.
  Settings sanitized() {
    const d = Settings();
    bool ok(double v, double lo, double hi) => v.isFinite && v >= lo && v <= hi;
    final currencyOk = RegExp(r'^[A-Z]{3}$').hasMatch(currency);
    final countryOk = RegExp(r'^[A-Z]{2}$').hasMatch(countryCode);
    final a = autoPrice;
    // A stored household price that is not a plausible number must never become the
    // effective price (NaN, negative or absurd would make every cost wrong).
    final autoPriceOk = a == null ||
        (a.pricePerKwh.isFinite &&
            a.pricePerKwh > 0 &&
            a.pricePerKwh <= maxPricePerKwh);
    // The design capacity is one coherent group: a usable mAh and a known
    // source go together, "unknown" carries no numbers, and Wh needs the mAh.
    final designKnown = designCapacitySource != DesignCapacitySource.unknown &&
        designCapacityMah.isFinite &&
        designCapacityMah > 0 &&
        designCapacityMah <= EnergyCalc.maxCapacityMah;
    final designWhOk = designKnown &&
        designCapacityWh.isFinite &&
        designCapacityWh > 0 &&
        designCapacityWh <= EnergyCalc.maxCapacityWh;
    // An original source only exists next to an account value, and is one of the
    // three origins the account can hold.
    bool originalOk(SettingSource source, SettingSource? original) =>
        source == SettingSource.accountSynced &&
        original != null &&
        original.canBeOriginal;
    return copyWith(
      clearAutoPrice: !autoPriceOk,
      clearCurrencyOriginalSource:
          !originalOk(currencySource, currencyOriginalSource),
      clearRegionOriginalSource:
          !originalOk(regionSource, regionOriginalSource),
      clearPriceOriginalSource: !originalOk(priceSource, priceOriginalSource),
      currency: currencyOk ? currency : d.currency,
      countryCode: countryOk ? countryCode : d.countryCode,
      pricePerKwh: ok(pricePerKwh, 0, maxPricePerKwh) ? pricePerKwh : 0,
      manualPricePerKwh:
          ok(manualPricePerKwh, 0, maxPricePerKwh) ? manualPricePerKwh : 0,
      efficiency: efficiency.isFinite && efficiency > 0 && efficiency <= 1
          ? efficiency
          : d.efficiency,
      designCapacityMah: designKnown ? designCapacityMah : d.designCapacityMah,
      designCapacityWh: designWhOk ? designCapacityWh : d.designCapacityWh,
      designCapacitySource:
          designKnown ? designCapacitySource : DesignCapacitySource.unknown,
      nominalVoltage:
          ok(nominalVoltage, EnergyCalc.minVoltage, EnergyCalc.maxVoltage)
              ? nominalVoltage
              : d.nominalVoltage,
      mobileThresholdBytes: mobileThresholdBytes > 0
          ? mobileThresholdBytes
          : d.mobileThresholdBytes,
    );
  }

  static const maxPricePerKwh = 1000.0;

  Settings copyWith({
    String? currency,
    SettingSource? currencySource,
    SettingSource? currencyOriginalSource,
    bool clearCurrencyOriginalSource = false,
    String? countryCode,
    SettingSource? regionSource,
    String? regionDetection,
    SettingSource? regionOriginalSource,
    bool clearRegionOriginalSource = false,
    double? pricePerKwh,
    ElectricityPriceMode? priceMode,
    double? manualPricePerKwh,
    SettingSource? priceSource,
    SettingSource? priceOriginalSource,
    bool clearPriceOriginalSource = false,
    AutoPrice? autoPrice,
    bool clearAutoPrice = false,
    double? efficiency,
    double? designCapacityMah,
    double? designCapacityWh,
    DesignCapacitySource? designCapacitySource,
    String? deviceModel,
    String? deviceModelIdentifier,
    double? nominalVoltage,
    bool? binaryUnits,
    bool? notifyMobileThreshold,
    int? mobileThresholdBytes,
    bool? notifyChargingDone,
    bool? notifyWeeklyEnergy,
    bool? notifyAboveAverage,
    bool? dataCollection,
    bool? onboarded,
    AppTheme? theme,
    bool? cloudSync,
    Set<SettingGroup>? accountInSync,
  }) =>
      Settings(
        currency: currency ?? this.currency,
        currencySource: currencySource ?? this.currencySource,
        currencyOriginalSource: clearCurrencyOriginalSource
            ? null
            : (currencyOriginalSource ?? this.currencyOriginalSource),
        countryCode: countryCode ?? this.countryCode,
        regionSource: regionSource ?? this.regionSource,
        regionDetection: regionDetection ?? this.regionDetection,
        regionOriginalSource: clearRegionOriginalSource
            ? null
            : (regionOriginalSource ?? this.regionOriginalSource),
        pricePerKwh: pricePerKwh ?? this.pricePerKwh,
        priceMode: priceMode ?? this.priceMode,
        manualPricePerKwh: manualPricePerKwh ?? this.manualPricePerKwh,
        priceSource: priceSource ?? this.priceSource,
        priceOriginalSource: clearPriceOriginalSource
            ? null
            : (priceOriginalSource ?? this.priceOriginalSource),
        autoPrice: clearAutoPrice ? null : (autoPrice ?? this.autoPrice),
        efficiency: efficiency ?? this.efficiency,
        designCapacityMah: designCapacityMah ?? this.designCapacityMah,
        designCapacityWh: designCapacityWh ?? this.designCapacityWh,
        designCapacitySource: designCapacitySource ?? this.designCapacitySource,
        deviceModel: deviceModel ?? this.deviceModel,
        deviceModelIdentifier:
            deviceModelIdentifier ?? this.deviceModelIdentifier,
        nominalVoltage: nominalVoltage ?? this.nominalVoltage,
        binaryUnits: binaryUnits ?? this.binaryUnits,
        notifyMobileThreshold:
            notifyMobileThreshold ?? this.notifyMobileThreshold,
        mobileThresholdBytes: mobileThresholdBytes ?? this.mobileThresholdBytes,
        notifyChargingDone: notifyChargingDone ?? this.notifyChargingDone,
        notifyWeeklyEnergy: notifyWeeklyEnergy ?? this.notifyWeeklyEnergy,
        notifyAboveAverage: notifyAboveAverage ?? this.notifyAboveAverage,
        dataCollection: dataCollection ?? this.dataCollection,
        onboarded: onboarded ?? this.onboarded,
        theme: theme ?? this.theme,
        cloudSync: cloudSync ?? this.cloudSync,
        accountInSync: accountInSync ?? this.accountInSync,
      );
}

/// Persists [Settings] and small bookkeeping flags in SharedPreferences.
class SettingsStore {
  SettingsStore(this._p) {
    legacyCloudSync = _b(_cloudSync);
  }

  final SharedPreferences _p;

  // Typed reads that treat a value of the wrong type as absent. SharedPreferences'
  // own getters throw a TypeError for it, and one damaged preference must not stop
  // the app from starting (see `Settings.sanitized` for out-of-range values).
  bool? _b(String key) {
    final v = _p.get(key);
    return v is bool ? v : null;
  }

  double? _d(String key) {
    final v = _p.get(key);
    return v is double ? v : null;
  }

  int? _i(String key) {
    final v = _p.get(key);
    return v is int ? v : null;
  }

  String? _s(String key) {
    final v = _p.get(key);
    return v is String ? v : null;
  }

  List<String> _list(String key) {
    final v = _p.get(key);
    return v is List ? v.whereType<String>().toList() : const [];
  }

  /// The value of `wb.cloudSync` when this store was created, i.e. before this run
  /// could overwrite it with a view. After the v5 upgrade it is still the old global
  /// consent; `SyncOwnership.adoptLegacyPreference` moves it to the legacy queue's
  /// owner (once: the database holds the marker). Null when it was never stored.
  late final bool? legacyCloudSync;

  static const _currency = 'wb.currency';
  static const _currencySource = 'wb.currencySource';
  static const _currencyOriginal = 'wb.currencyOriginalSource';
  static const _country = 'wb.countryCode';
  static const _regionSource = 'wb.regionSource';
  static const _regionDetection = 'wb.regionDetection';
  static const _regionOriginal = 'wb.regionOriginalSource';
  static const _price = 'wb.pricePerKwh';
  static const _priceMode = 'wb.priceMode';
  static const _manualPrice = 'wb.manualPricePerKwh';
  static const _priceSource = 'wb.priceSource';
  static const _priceOriginal = 'wb.priceOriginalSource';
  static const _accountInSync = 'wb.accountInSync';
  static const _autoPrice = 'wb.autoPrice.value';
  static const _autoPriceCurrency = 'wb.autoPrice.currency';
  static const _autoPriceCountry = 'wb.autoPrice.country';
  static const _autoPricePeriod = 'wb.autoPrice.period';
  static const _autoPriceSource = 'wb.autoPrice.source';
  static const _autoPriceUpdated = 'wb.autoPrice.updatedMs';
  static const _autoPriceStale = 'wb.autoPrice.stale';
  static const _efficiency = 'wb.efficiency';
  static const _designCapacity = 'wb.designCapacityMah';
  static const _designCapacityWh = 'wb.designCapacityWh';
  static const _designCapacitySource = 'wb.designCapacitySource';

  // Keys of builds before the design / estimated full-charge split. Read once
  // by [_loadDesignCapacity], removed by [save].
  static const _legacyCapacity = 'wb.batteryCapacityMah';
  static const _legacyCapacityWh = 'wb.batteryCapacityWh';
  static const _legacyCapacitySource = 'wb.capacitySource';
  static const _deviceModel = 'wb.deviceModel';
  static const _deviceModelId = 'wb.deviceModelIdentifier';
  static const _voltage = 'wb.nominalVoltage';
  static const _binary = 'wb.binaryUnits';
  static const _nMobile = 'wb.notifyMobileThreshold';
  static const _nMobileBytes = 'wb.mobileThresholdBytes';
  static const _nCharging = 'wb.notifyChargingDone';
  static const _nWeekly = 'wb.notifyWeeklyEnergy';
  static const _nAvg = 'wb.notifyAboveAverage';
  static const _collect = 'wb.dataCollection';
  static const _onboarded = 'wb.onboarded';
  static const _theme = 'wb.theme';

  /// Cached view of the sync switch (see [Settings.cloudSync]). Before schema v5 it
  /// WAS the consent (one global flag): [legacyCloudSync] is that value, read once to
  /// move the choice to the account that owned the legacy queue.
  static const _cloudSync = 'wb.cloudSync';
  static const _locale = 'wb.locale';
  static const _sent = 'wb.sentNotifications';
  static const _deviceSpecCache = 'wb.deviceSpecCache';

  /// The three design-capacity fields as stored.
  ///
  /// The current layout is read as is. Builds before the split stored
  /// `wb.batteryCapacityMah` / `wb.batteryCapacityWh` / `wb.capacitySource`,
  /// which are read when the new source key is absent: `localDatabase` and
  /// `backendDatabase` map to their `...DeviceDatabase` names, `manual` stays,
  /// and a number with no or an unparsable source was typed by the user before
  /// sources existed, so it becomes `manual`. `system` and `estimated` were
  /// measurements (a charge-counter extrapolation), which are not a design
  /// capacity: they become unknown and their numbers are dropped.
  ({double mah, double wh, DesignCapacitySource source}) _loadDesignCapacity() {
    final storedSource = _s(_designCapacitySource);
    final legacy = storedSource == null &&
        (_p.containsKey(_legacyCapacity) ||
            _p.containsKey(_legacyCapacitySource));
    final mah = _d(legacy ? _legacyCapacity : _designCapacity) ?? 0.0;
    final wh = _d(legacy ? _legacyCapacityWh : _designCapacityWh) ?? 0.0;
    final typed =
        mah > 0 ? DesignCapacitySource.manual : DesignCapacitySource.unknown;
    if (!legacy) {
      // Measurements were never design capacities, whichever key they sit under.
      if (storedSource == 'system' || storedSource == 'estimated') {
        return (mah: 0.0, wh: 0.0, source: DesignCapacitySource.unknown);
      }
      return (
        mah: mah,
        wh: wh,
        source: DesignCapacitySource.tryParse(storedSource) ?? typed,
      );
    }
    final source = switch (_s(_legacyCapacitySource)) {
      'localDatabase' => DesignCapacitySource.localDeviceDatabase,
      'backendDatabase' => DesignCapacitySource.backendDeviceDatabase,
      'manual' => DesignCapacitySource.manual,
      'system' || 'estimated' || 'unknown' => DesignCapacitySource.unknown,
      _ => typed,
    };
    return source == DesignCapacitySource.unknown
        ? (mah: 0.0, wh: 0.0, source: source)
        : (mah: mah, wh: wh, source: source);
  }

  Settings load() {
    const d = Settings();
    final price = _d(_price) ?? d.pricePerKwh;
    final design = _loadDesignCapacity();
    final storedCurrency = _s(_currency);

    // Installs from before the automatic setup (the old onboarding asked for a
    // currency and a price; there were no sources): what is stored was given by
    // the user, so it is kept as a conscious choice, `migratedManual`, and
    // detection never replaces it. Nothing more is guessed: a build that wrote a
    // source (every build since the automatic setup) is read as it wrote it.
    final storedPriceMode =
        ElectricityPriceMode.values.asNameMap()[_s(_priceMode)];
    final priceMode = storedPriceMode ??
        (price > 0
            ? ElectricityPriceMode.manual
            : ElectricityPriceMode.automatic);
    final priceSource = SettingSource.tryParse(_s(_priceSource)) ??
        (storedPriceMode != null
            // A mode without a source: written by the first automatic setup. A
            // manual tariff there was typed by the user or copied from the
            // account (the old code could not tell); it stays a local choice.
            ? (priceMode == ElectricityPriceMode.manual
                ? SettingSource.manual
                : SettingSource.detected)
            : (price > 0
                ? SettingSource.migratedManual
                : SettingSource.detected));
    final currencySource = SettingSource.tryParse(_s(_currencySource)) ??
        (storedCurrency != null && storedCurrency.isNotEmpty
            ? SettingSource.migratedManual
            : SettingSource.detected);

    // `wb.regionSource` used to hold how a region was found (`deviceRegion`,
    // `deviceLocale`, `backendCountry`) or `manual`.
    final storedRegion = _s(_regionSource);
    final legacyDetection = const {
      'deviceRegion',
      'deviceLocale',
      'backendCountry'
    }.contains(storedRegion)
        ? storedRegion!
        : '';
    final regionSource = legacyDetection.isNotEmpty
        ? SettingSource.detected
        : (SettingSource.tryParse(storedRegion) ?? SettingSource.detected);

    final autoValue = _d(_autoPrice);
    final autoPrice = autoValue == null
        ? null
        : AutoPrice(
            pricePerKwh: autoValue,
            currency: _s(_autoPriceCurrency) ?? '',
            countryCode: _s(_autoPriceCountry) ?? '',
            period: _s(_autoPricePeriod) ?? '',
            source: _s(_autoPriceSource) ?? '',
            updatedAt:
                DateTime.fromMillisecondsSinceEpoch(_i(_autoPriceUpdated) ?? 0),
            stale: _b(_autoPriceStale) ?? false,
          );

    return Settings(
      currency: storedCurrency ?? d.currency,
      currencySource: currencySource,
      currencyOriginalSource:
          SettingSource.tryParseOriginal(_s(_currencyOriginal)),
      countryCode: _s(_country) ?? d.countryCode,
      regionSource: regionSource,
      regionDetection: _s(_regionDetection) ?? legacyDetection,
      regionOriginalSource: SettingSource.tryParseOriginal(_s(_regionOriginal)),
      pricePerKwh: price,
      priceMode: priceMode,
      manualPricePerKwh: _d(_manualPrice) ??
          (priceMode == ElectricityPriceMode.manual ? price : 0),
      priceSource: priceSource,
      priceOriginalSource: SettingSource.tryParseOriginal(_s(_priceOriginal)),
      accountInSync: {
        for (final name in _list(_accountInSync))
          if (SettingGroup.tryParse(name) case final g?) g
      },
      autoPrice: autoPrice,
      efficiency: _d(_efficiency) ?? d.efficiency,
      designCapacityMah: design.mah,
      designCapacityWh: design.wh,
      designCapacitySource: design.source,
      deviceModel: _s(_deviceModel) ?? d.deviceModel,
      deviceModelIdentifier: _s(_deviceModelId) ?? d.deviceModelIdentifier,
      nominalVoltage: _d(_voltage) ?? d.nominalVoltage,
      binaryUnits: _b(_binary) ?? d.binaryUnits,
      notifyMobileThreshold: _b(_nMobile) ?? d.notifyMobileThreshold,
      mobileThresholdBytes: _i(_nMobileBytes) ?? d.mobileThresholdBytes,
      notifyChargingDone: _b(_nCharging) ?? d.notifyChargingDone,
      notifyWeeklyEnergy: _b(_nWeekly) ?? d.notifyWeeklyEnergy,
      notifyAboveAverage: _b(_nAvg) ?? d.notifyAboveAverage,
      dataCollection: _b(_collect) ?? d.dataCollection,
      onboarded: _b(_onboarded) ?? d.onboarded,
      theme: AppTheme.values.asNameMap()[_s(_theme)] ?? d.theme,
      cloudSync: _b(_cloudSync) ?? d.cloudSync,
    ).sanitized();
  }

  Future<void> save(Settings input) {
    final s = input.sanitized();
    final a = s.autoPrice;
    return Future.wait([
      _p.setString(_currency, s.currency),
      _p.setString(_currencySource, s.currencySource.wire),
      _setOrRemove(_currencyOriginal, s.currencyOriginalSource?.wire),
      _p.setString(_country, s.countryCode),
      _p.setString(_regionSource, s.regionSource.wire),
      _p.setString(_regionDetection, s.regionDetection),
      _setOrRemove(_regionOriginal, s.regionOriginalSource?.wire),
      _p.setDouble(_price, s.pricePerKwh),
      _p.setString(_priceMode, s.priceMode.name),
      _p.setDouble(_manualPrice, s.manualPricePerKwh),
      _p.setString(_priceSource, s.priceSource.wire),
      _setOrRemove(_priceOriginal, s.priceOriginalSource?.wire),
      _p.setStringList(_accountInSync, [
        for (final g in SettingGroup.values)
          if (s.accountInSync.contains(g)) g.name
      ]),
      if (a == null) ...[
        _p.remove(_autoPrice),
        _p.remove(_autoPriceCurrency),
        _p.remove(_autoPriceCountry),
        _p.remove(_autoPricePeriod),
        _p.remove(_autoPriceSource),
        _p.remove(_autoPriceUpdated),
        _p.remove(_autoPriceStale),
      ] else ...[
        _p.setDouble(_autoPrice, a.pricePerKwh),
        _p.setString(_autoPriceCurrency, a.currency),
        _p.setString(_autoPriceCountry, a.countryCode),
        _p.setString(_autoPricePeriod, a.period),
        _p.setString(_autoPriceSource, a.source),
        _p.setInt(_autoPriceUpdated, a.updatedAt.millisecondsSinceEpoch),
        _p.setBool(_autoPriceStale, a.stale),
      ],
      _p.setDouble(_efficiency, s.efficiency),
      _p.setDouble(_designCapacity, s.designCapacityMah),
      _p.setDouble(_designCapacityWh, s.designCapacityWh),
      _p.setString(_designCapacitySource, s.designCapacitySource.name),
      _p.remove(_legacyCapacity),
      _p.remove(_legacyCapacityWh),
      _p.remove(_legacyCapacitySource),
      _p.setString(_deviceModel, s.deviceModel),
      _p.setString(_deviceModelId, s.deviceModelIdentifier),
      _p.setDouble(_voltage, s.nominalVoltage),
      _p.setBool(_binary, s.binaryUnits),
      _p.setBool(_nMobile, s.notifyMobileThreshold),
      _p.setInt(_nMobileBytes, s.mobileThresholdBytes),
      _p.setBool(_nCharging, s.notifyChargingDone),
      _p.setBool(_nWeekly, s.notifyWeeklyEnergy),
      _p.setBool(_nAvg, s.notifyAboveAverage),
      _p.setBool(_collect, s.dataCollection),
      _p.setBool(_onboarded, s.onboarded),
      _p.setString(_theme, s.theme.name),
      _p.setBool(_cloudSync, s.cloudSync),
    ]);
  }

  Future<void> _setOrRemove(String key, String? value) =>
      value == null ? _p.remove(key) : _p.setString(key, value);

  // ------------------------------------------------------------ account scope

  /// The preferences that belong to ONE account: its region, currency and price
  /// decision (with their sources), the cached household price, and whether the
  /// automatic setup finished for it. Everything else (units, theme, notifications,
  /// the data switch, the phone model and its battery capacity) belongs to the phone.
  static const _accountKeys = [
    _currency,
    _currencySource,
    _currencyOriginal,
    _country,
    _regionSource,
    _regionDetection,
    _regionOriginal,
    _price,
    _priceMode,
    _manualPrice,
    _priceSource,
    _priceOriginal,
    _accountInSync,
    _autoPrice,
    _autoPriceCurrency,
    _autoPriceCountry,
    _autoPricePeriod,
    _autoPriceSource,
    _autoPriceUpdated,
    _autoPriceStale,
    _onboarded,
  ];

  static const _owner = 'wb.settingsOwner';
  static const _stash = 'wb.acct.';

  /// The one-way account key (`accountKeyFor`) whose settings are in the live
  /// preferences; null before the first account signed in. The first account to
  /// sign in adopts whatever is on the phone (the old onboarding's answers, the
  /// state of a build from before accounts were separated), see
  /// `docs/SETTING_SOURCES.md`.
  String? get accountOwner => _s(_owner);

  /// Makes [key] the account whose settings are live. Settings of the previous
  /// owner are put away under its own key, those of [key] (if it was here before)
  /// are brought back, and a new account starts from nothing: it can only
  /// inherit the phone's own values, never another account's.
  Future<void> switchAccount(String key) async {
    final from = accountOwner;
    if (from == key) return;
    if (from != null) await _move(live: true, key: from);
    if (from != null) await _move(live: false, key: key);
    await _p.setString(_owner, key);
  }

  /// Adopts what is on the phone for [key] (nobody owned it yet).
  Future<void> adoptAccount(String key) => _p.setString(_owner, key);

  /// `live: true` copies the live preferences into the stash of [key];
  /// otherwise the stash of [key] is copied back (a key the stash lacks is
  /// removed from the live preferences, so a new account starts empty).
  Future<void> _move({required bool live, required String key}) async {
    for (final k in _accountKeys) {
      final stashKey = '$_stash$key.$k';
      await (live ? _copy(k, stashKey) : _copy(stashKey, k));
    }
  }

  Future<void> _copy(String from, String to) async {
    final v = _p.get(from);
    switch (v) {
      case String():
        await _p.setString(to, v);
      case int():
        await _p.setInt(to, v);
      case double():
        await _p.setDouble(to, v);
      case bool():
        await _p.setBool(to, v);
      case List():
        await _p.setStringList(to, v.whereType<String>().toList());
      default:
        await _p.remove(to);
    }
  }

  /// Forgets the settings of [key] (its account was deleted): the ones put away
  /// and, when they are the live ones, those too, so the next account to sign in
  /// starts from what belongs to the phone, not from the deleted account.
  Future<void> forgetAccount(String key) async {
    for (final k in _accountKeys) {
      await _p.remove('$_stash$key.$k');
    }
    if (accountOwner == key) {
      for (final k in _accountKeys) {
        await _p.remove(k);
      }
      await _p.remove(_owner);
    }
  }

  /// Re-reads the file: the background isolate keeps its own copy of the preferences,
  /// so notification dedupe keys written there are invisible here until reloaded.
  Future<void> reload() => _p.reload();

  /// Locale tag recorded at app start so the background isolate can localize.
  String? get locale => _s(_locale);
  Future<void> setLocale(String tag) => _p.setString(_locale, tag);

  /// Last specification received from the API, keyed by model identifier
  /// (JSON), so a reinstall-free relaunch works offline.
  String? get deviceSpecCache => _s(_deviceSpecCache);
  Future<void> setDeviceSpecCache(String json) =>
      _p.setString(_deviceSpecCache, json);

  /// Dedupe keys of notifications already shown.
  Set<String> get sentNotifications => _list(_sent).toSet();

  Future<void> markSent(String key) {
    final list = <String>[..._list(_sent), key];
    return _p.setStringList(
        _sent, list.length > 200 ? list.sublist(list.length - 200) : list);
  }
}
