// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Battery capacity model: design capacity versus estimated full-charge capacity.
///
/// Two different facts live here and they must never be mixed:
///
///  * [DesignCapacity] is the nominal capacity of the phone *model*. It comes
///    from a device specification database (bundled, then the API) or from the
///    user, and is "unknown" for everything else. There is no "typical" value.
///  * [EstimatedFullChargeCapacity] is an *estimate* of what this particular
///    battery holds today, extrapolated from the Android
///    `BATTERY_PROPERTY_CHARGE_COUNTER` and the battery level.
///
/// `BATTERY_PROPERTY_CHARGE_COUNTER` is the charge currently stored in the
/// battery, not a capacity. It only becomes a capacity *estimate* through
/// `charge / (level / 100)` and the result is never a [DesignCapacity]: the
/// [DesignCapacitySource] enum has no measurement member, so the types make the
/// mix-up impossible. See docs/BATTERY_CAPACITY.md.
///
/// Pure Dart: no I/O, no Flutter.
library;

import '../calc/energy.dart';

/// Where a [DesignCapacity] came from. The strings (the enum names) are
/// identical in Dart, the API, OpenAPI and PostgreSQL.
///
/// There is deliberately no member for a system measurement: a measured value
/// is an [EstimatedFullChargeCapacity], never a design capacity.
enum DesignCapacitySource {
  /// A figure taken directly from the maker's specification (reserved: no code
  /// path produces it yet, but it is accepted wherever a source is read).
  manufacturerSpecification,

  /// The bundled device specification catalog (`assets/device_specs`).
  localDeviceDatabase,

  /// The same catalog served by the backend, cached for offline launches.
  backendDeviceDatabase,

  /// Typed by the user.
  manual,

  /// Nothing is known; no number is stored.
  unknown;

  /// The member called [name], or null for `null` / an unrecognised string.
  static DesignCapacitySource? tryParse(String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// How an [EstimatedFullChargeCapacity] was obtained.
enum FullChargeCapacitySource {
  /// Extrapolated from Android `BATTERY_PROPERTY_CHARGE_COUNTER` and the level.
  androidChargeCounter,

  /// No estimate.
  unknown;

  /// The member called [name], or null for `null` / an unrecognised string.
  static FullChargeCapacitySource? tryParse(String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// How far an [EstimatedFullChargeCapacity] can be trusted. Declaration order
/// is strength: `none < low < medium < high`.
enum FullChargeCapacityConfidence {
  /// "No estimate". Never sent over the wire (see [wireName]).
  none,
  low,
  medium,
  high;

  /// True when this confidence is [other] or stronger.
  bool atLeast(FullChargeCapacityConfidence other) => index >= other.index;

  /// True when this confidence is strictly stronger than [other].
  bool strongerThan(FullChargeCapacityConfidence other) => index > other.index;

  /// The wire/API value, or null for [none] (an absent estimate has no
  /// confidence on the wire).
  String? get wireName => this == none ? null : name;

  /// The member called [name] (including `none`), or null for `null` / an
  /// unrecognised string.
  static FullChargeCapacityConfidence? tryParse(String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// The nominal capacity of a phone model.
///
/// This is a published figure from a device specification (or a number the
/// user typed), never a measurement. In particular the Android charge counter,
/// which is the charge currently stored in the battery, can never end up here:
/// build one of these only from a catalog or from the user's input.
///
/// Instances are always normalised: either [isKnown] with a finite
/// `0 < mah <= EnergyCalc.maxCapacityMah` and a source other than
/// [DesignCapacitySource.unknown], or exactly [DesignCapacity.unknown].
class DesignCapacity {
  /// Builds a design capacity, normalising anything unusable to [unknown]:
  /// the result is [unknown] unless [mah] is finite, positive, within
  /// [EnergyCalc.maxCapacityMah] and [source] is not
  /// [DesignCapacitySource.unknown]. [wh] is kept only when finite, positive
  /// and within [EnergyCalc.maxCapacityWh]; otherwise it is `null` and the
  /// milliampere-hours stay.
  factory DesignCapacity({
    double? mah,
    double? wh,
    required DesignCapacitySource source,
  }) {
    if (source == DesignCapacitySource.unknown ||
        mah == null ||
        !mah.isFinite ||
        mah <= 0 ||
        mah > EnergyCalc.maxCapacityMah) {
      return unknown;
    }
    final validWh =
        wh != null && wh.isFinite && wh > 0 && wh <= EnergyCalc.maxCapacityWh;
    return DesignCapacity._(mah: mah, wh: validWh ? wh : null, source: source);
  }

  const DesignCapacity._({
    required this.mah,
    required this.wh,
    required this.source,
  });

  /// Nothing is known about the nominal capacity; carries no numbers.
  static const DesignCapacity unknown = DesignCapacity._(
    mah: null,
    wh: null,
    source: DesignCapacitySource.unknown,
  );

  /// Nominal capacity in milliampere-hours, null when unknown.
  final double? mah;

  /// Nominal capacity in watt-hours, null when the specification gives none.
  final double? wh;

  final DesignCapacitySource source;

  /// A usable nominal capacity is present.
  bool get isKnown => source != DesignCapacitySource.unknown && mah != null;

  /// The first known candidate in priority order: the local device
  /// specification database, then the backend one, then the user's manual
  /// value, otherwise [unknown]. An unknown candidate is skipped.
  static DesignCapacity resolve({
    DesignCapacity? local,
    DesignCapacity? backend,
    DesignCapacity? manual,
  }) {
    for (final c in [local, backend, manual]) {
      if (c != null && c.isKnown) return c;
    }
    return unknown;
  }

  @override
  bool operator ==(Object other) =>
      other is DesignCapacity &&
      other.mah == mah &&
      other.wh == wh &&
      other.source == source;

  @override
  int get hashCode => Object.hash(mah, wh, source);

  @override
  String toString() =>
      'DesignCapacity(mah: $mah, wh: $wh, source: ${source.name})';
}

/// An estimate of the full-charge capacity of this particular battery.
///
/// It is always an *estimate*, never the nominal capacity: the Android
/// `BATTERY_PROPERTY_CHARGE_COUNTER` is the charge currently stored in the
/// battery, and the value here is that charge extrapolated to 100 % from the
/// battery [level] of the reading ([FullChargeCapacityEstimator.estimate]). An
/// estimate is never a [DesignCapacity] and is always shown as "Estimated".
class EstimatedFullChargeCapacity {
  const EstimatedFullChargeCapacity({
    this.mah,
    this.wh,
    this.source = FullChargeCapacitySource.unknown,
    this.confidence = FullChargeCapacityConfidence.none,
    this.level,
    this.measuredAt,
  });

  /// No estimate is available.
  static const EstimatedFullChargeCapacity unavailable =
      EstimatedFullChargeCapacity();

  /// Estimated full-charge capacity in milliampere-hours.
  final double? mah;

  /// Estimated full-charge energy in watt-hours; only set from a valid energy
  /// counter, never derived from an assumed voltage.
  final double? wh;

  final FullChargeCapacitySource source;
  final FullChargeCapacityConfidence confidence;

  /// Battery level (0-100) of the reading the estimate was extrapolated from.
  final int? level;

  /// When the reading was taken.
  final DateTime? measuredAt;

  /// An estimate exists: a finite positive [mah], a known source and a
  /// confidence other than `none`.
  bool get isAvailable {
    final m = mah;
    return m != null &&
        m.isFinite &&
        m > 0 &&
        source != FullChargeCapacitySource.unknown &&
        confidence != FullChargeCapacityConfidence.none;
  }

  /// [isAvailable] and the confidence is medium or high, which is what an
  /// estimated battery health may be based on.
  bool get isReliableForHealth =>
      isAvailable && confidence.atLeast(FullChargeCapacityConfidence.medium);

  // Key-value form used by the collector's meta table. The confidence is not
  // stored: it is a function of [level] and is recomputed on load.
  static const metaMahKey = 'calibrated_capacity_mah';
  static const metaLevelKey = 'calibrated_capacity_level';
  static const metaWhKey = 'calibrated_capacity_wh';
  static const metaMeasuredAtKey = 'calibrated_capacity_at_ms';

  /// The estimate as key-value strings for the collector's meta table; empty
  /// when nothing is available.
  Map<String, String> toMeta() {
    final m = mah;
    final lvl = level;
    if (!isAvailable || m == null || lvl == null) return const {};
    final w = wh;
    final at = measuredAt;
    return {
      metaMahKey: '$m',
      metaLevelKey: '$lvl',
      if (w != null && w.isFinite) metaWhKey: '$w',
      if (at != null) metaMeasuredAtKey: '${at.millisecondsSinceEpoch}',
    };
  }

  /// Reads what [toMeta] wrote (also the older layout that stored only the
  /// milliampere-hours and the level). The confidence is derived from the
  /// stored level. Anything missing, unparsable or implausible yields
  /// [unavailable]; a stored Wh value that is implausible is dropped, the mAh
  /// stays.
  static EstimatedFullChargeCapacity fromMeta(Map<String, String?> meta) {
    final mah = double.tryParse(meta[metaMahKey] ?? '');
    final level = int.tryParse(meta[metaLevelKey] ?? '');
    if (mah == null || level == null) return unavailable;
    final confidence = FullChargeCapacityEstimator.confidenceForLevel(level);
    if (confidence == FullChargeCapacityConfidence.none ||
        !FullChargeCapacityEstimator._plausibleMah(mah)) {
      return unavailable;
    }
    final atMs = int.tryParse(meta[metaMeasuredAtKey] ?? '');
    // DateTime accepts +/- 8.64e15 ms; anything outside would throw.
    final at = atMs != null && atMs > 0 && atMs <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(atMs)
        : null;
    return EstimatedFullChargeCapacity(
      mah: mah,
      wh: FullChargeCapacityEstimator._validWh(
          double.tryParse(meta[metaWhKey] ?? ''), mah),
      source: FullChargeCapacitySource.androidChargeCounter,
      confidence: confidence,
      level: level,
      measuredAt: at,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EstimatedFullChargeCapacity &&
      other.mah == mah &&
      other.wh == wh &&
      other.source == source &&
      other.confidence == confidence &&
      other.level == level &&
      other.measuredAt == measuredAt;

  @override
  int get hashCode =>
      Object.hash(mah, wh, source, confidence, level, measuredAt);

  @override
  String toString() => 'EstimatedFullChargeCapacity(mah: $mah, wh: $wh, '
      'source: ${source.name}, confidence: ${confidence.name}, '
      'level: $level, measuredAt: $measuredAt)';
}

/// Turns an Android charge-counter reading into an
/// [EstimatedFullChargeCapacity].
///
/// The charge counter (`BATTERY_PROPERTY_CHARGE_COUNTER`, microampere-hours) is
/// the charge currently stored in the battery. Extrapolating it to a full
/// battery, `charge / (level / 100)`, yields an estimate, never a nominal
/// capacity and never a [DesignCapacity]. Invalid input never throws and never
/// leaves `NaN` or `Infinity` in a result: it yields
/// [EstimatedFullChargeCapacity.unavailable].
abstract final class FullChargeCapacityEstimator {
  /// Below this battery level the extrapolation is too far to be useful.
  static const minLevel = 40;

  /// From this level on the confidence is at least medium.
  static const mediumConfidenceLevel = 75;

  /// From this level on the confidence is high.
  static const highConfidenceLevel = 95;

  /// Smallest estimate that is a plausible battery (also rejects a counter that
  /// reports milliampere-hours instead of microampere-hours).
  static const minPlausibleMah = 100.0;

  /// A stored estimate older than this no longer outranks a newer reading.
  static const staleAfter = Duration(days: 30);

  /// Confidence of a reading taken at battery [level]: high from 95 %, medium
  /// from 75 %, low from 40 %; `none` below that and for NaN, infinite or
  /// out-of-range (above 100) levels.
  static FullChargeCapacityConfidence confidenceForLevel(num level) {
    final l = level.toDouble();
    if (!l.isFinite || l < minLevel || l > 100) {
      return FullChargeCapacityConfidence.none;
    }
    if (l >= highConfidenceLevel) return FullChargeCapacityConfidence.high;
    if (l >= mediumConfidenceLevel) return FullChargeCapacityConfidence.medium;
    return FullChargeCapacityConfidence.low;
  }

  /// Estimates the full-charge capacity from one battery reading.
  ///
  /// ```
  /// fraction = level / 100
  /// mAh      = chargeUah / 1000 / fraction
  /// Wh       = energyNwh / 1e9 / fraction   (valid energy counter only)
  /// ```
  ///
  /// [chargeUah] is `BATTERY_PROPERTY_CHARGE_COUNTER` in microampere-hours and
  /// [energyNwh] is `BATTERY_PROPERTY_ENERGY_COUNTER` in nanowatt-hours, both
  /// `null` when unsupported. The result is unavailable when the charge is
  /// null, zero, negative, NaN or infinite, when the level is below [minLevel],
  /// above 100, NaN or infinite, or when the extrapolated capacity is outside
  /// [minPlausibleMah] .. [EnergyCalc.maxCapacityMah]. Wh is `null` unless the
  /// energy counter is valid, within 0 .. [EnergyCalc.maxCapacityWh] and implies
  /// a cell voltage within [EnergyCalc.minVoltage] .. [EnergyCalc.maxVoltage];
  /// the mAh estimate stays in that case.
  static EstimatedFullChargeCapacity estimate({
    num? chargeUah,
    num? energyNwh,
    required num level,
    DateTime? measuredAt,
  }) {
    final charge = chargeUah?.toDouble();
    if (charge == null || !charge.isFinite || charge <= 0) {
      return EstimatedFullChargeCapacity.unavailable;
    }
    final lvl = level.toDouble();
    final confidence = confidenceForLevel(lvl);
    if (confidence == FullChargeCapacityConfidence.none) {
      return EstimatedFullChargeCapacity.unavailable;
    }
    final fraction = lvl / 100;
    final mah = charge / 1000 / fraction;
    if (!_plausibleMah(mah)) return EstimatedFullChargeCapacity.unavailable;

    final energy = energyNwh?.toDouble();
    final wh = energy == null || !energy.isFinite || energy <= 0
        ? null
        : _validWh(energy / 1e9 / fraction, mah);

    return EstimatedFullChargeCapacity(
      mah: mah,
      wh: wh,
      source: FullChargeCapacitySource.androidChargeCounter,
      confidence: confidence,
      level: lvl.floor(),
      measuredAt: measuredAt,
    );
  }

  /// Picks the estimate to keep: the [stored] one or the new [candidate].
  ///
  /// An unavailable candidate never replaces anything. An absent or
  /// unavailable stored value is replaced by the candidate. Otherwise the
  /// candidate wins when its confidence is at least the stored one's, so a
  /// 45 % reading does not overwrite a 100 % reading from last week; a stronger
  /// stored estimate is only replaced once it is older than [staleAfter] (or
  /// has no [EstimatedFullChargeCapacity.measuredAt]).
  static EstimatedFullChargeCapacity prefer(
    EstimatedFullChargeCapacity? stored,
    EstimatedFullChargeCapacity candidate, {
    required DateTime now,
  }) {
    if (!candidate.isAvailable) {
      return stored ?? EstimatedFullChargeCapacity.unavailable;
    }
    if (stored == null || !stored.isAvailable) return candidate;
    if (candidate.confidence.atLeast(stored.confidence)) return candidate;
    final at = stored.measuredAt;
    if (at == null || now.difference(at) > staleAfter) return candidate;
    return stored;
  }

  static bool _plausibleMah(double mah) =>
      mah.isFinite &&
      mah >= minPlausibleMah &&
      mah <= EnergyCalc.maxCapacityMah;

  /// [wh] when it is a plausible energy for a battery of [mah] (finite, within
  /// 0 .. maxCapacityWh and implying a cell voltage in the sane range),
  /// otherwise null.
  static double? _validWh(double? wh, double mah) {
    if (wh == null ||
        !wh.isFinite ||
        wh <= 0 ||
        wh > EnergyCalc.maxCapacityWh) {
      return null;
    }
    final volts = wh / (mah / 1000);
    if (!volts.isFinite ||
        volts < EnergyCalc.minVoltage ||
        volts > EnergyCalc.maxVoltage) {
      return null;
    }
    return wh;
  }
}

/// Estimated battery health: the share of the design capacity that the battery
/// is estimated to still hold. Always an estimate; there is no exact health.
class EstimatedBatteryHealth {
  const EstimatedBatteryHealth({
    required this.percent,
    required this.confidence,
  });

  /// 0-100 (a ratio above 1.0 is reported as 100).
  final double percent;

  /// Confidence of the full-charge estimate the figure is based on.
  final FullChargeCapacityConfidence confidence;

  @override
  bool operator ==(Object other) =>
      other is EstimatedBatteryHealth &&
      other.percent == percent &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(percent, confidence);

  @override
  String toString() =>
      'EstimatedBatteryHealth(percent: $percent, confidence: ${confidence.name})';
}

/// Lowest plausible ratio of full-charge estimate to design capacity.
const _minHealthRatio = 0.30;

/// Highest plausible ratio of full-charge estimate to design capacity.
const _maxHealthRatio = 1.20;

/// `fullCharge.mah / design.mah * 100`, or `null` ("no result") unless both
/// values are reliable.
///
/// The design capacity must be known (a catalog or manual figure) and the
/// estimate must be available with medium or high confidence: a low-confidence
/// extrapolation from a half-charged battery is not good enough for a health
/// figure. A ratio outside 0.30 .. 1.20 means the design figure or the reading
/// is wrong, not the battery, so it also yields `null`. A ratio above 1.0 is
/// reported as 100 %. Never throws and never returns `NaN` or `Infinity`.
EstimatedBatteryHealth? calculateEstimatedBatteryHealth(
  DesignCapacity design,
  EstimatedFullChargeCapacity fullCharge,
) {
  if (!design.isKnown || !fullCharge.isReliableForHealth) return null;
  final d = design.mah;
  final f = fullCharge.mah;
  if (d == null || f == null || !d.isFinite || !f.isFinite) return null;
  if (d <= 0 || f <= 0) return null;
  final ratio = f / d;
  if (!ratio.isFinite || ratio < _minHealthRatio || ratio > _maxHealthRatio) {
    return null;
  }
  // f * 100 / d (not ratio * 100) so that 3600 / 4000 is exactly 90.0.
  final percent = f * 100 / d;
  return EstimatedBatteryHealth(
    percent: percent > 100 ? 100 : percent,
    confidence: fullCharge.confidence,
  );
}
