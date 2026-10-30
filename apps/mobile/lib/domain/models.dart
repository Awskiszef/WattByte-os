// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/// Shared, platform-independent data models. Plain immutable classes.
library;

/// Bytes transferred on one local calendar day.
///
/// Android fills this from `NetworkStatsManager` (measured). iOS fills it
/// from interface-counter deltas spread across days (estimated).
class DailyData {
  const DailyData({
    required this.day,
    this.mobileRx = 0,
    this.mobileTx = 0,
    this.wifiRx = 0,
    this.wifiTx = 0,
    this.estimated = false,
  });

  /// Local midnight of the day.
  final DateTime day;
  final int mobileRx;
  final int mobileTx;
  final int wifiRx;
  final int wifiTx;
  final bool estimated;

  int get mobile => mobileRx + mobileTx;
  int get wifi => wifiRx + wifiTx;
  int get rx => mobileRx + wifiRx;
  int get tx => mobileTx + wifiTx;
  int get total => mobile + wifi;

  DailyData plus(DailyData o) => DailyData(
        day: day,
        mobileRx: mobileRx + o.mobileRx,
        mobileTx: mobileTx + o.mobileTx,
        wifiRx: wifiRx + o.wifiRx,
        wifiTx: wifiTx + o.wifiTx,
        estimated: estimated || o.estimated,
      );

  static DailyData sum(Iterable<DailyData> items, {DateTime? day}) {
    var acc = DailyData(day: day ?? DateTime(1970));
    for (final i in items) {
      acc = acc.plus(i);
    }
    return acc;
  }
}

/// One reading of the battery, taken in the foreground, by the Android
/// charging worker, or by an iOS background refresh.
class BatterySample {
  const BatterySample({
    required this.time,
    required this.level,
    required this.plugged,
    this.chargeUah,
    this.energyNwh,
    this.voltageMv,
    this.source = 'app',
  });

  final DateTime time;

  /// 0-100.
  final int level;
  final bool plugged;

  /// Android `BATTERY_PROPERTY_CHARGE_COUNTER` (microampere-hours), if supported.
  /// This is the charge currently stored in the battery, NOT its capacity; it is
  /// only ever extrapolated into an estimate (see `battery_capacity.dart`).
  final int? chargeUah;

  /// Android `BATTERY_PROPERTY_ENERGY_COUNTER` (nanowatt-hours), if supported.
  final int? energyNwh;

  /// Android `EXTRA_VOLTAGE` (millivolts), if present.
  final int? voltageMv;
  final String source;
}

/// A charging session reconstructed from [BatterySample]s.
///
/// Stores raw physical deltas, not money, so changing the price or
/// efficiency setting later re-prices every session consistently.
class ChargingSession {
  const ChargingSession({
    this.id,
    required this.start,
    required this.end,
    required this.startLevel,
    required this.endLevel,
    this.chargeDeltaUah,
    this.energyDeltaNwh,
    this.avgVoltageMv,
    this.sparse = false,
  });

  final int? id;
  final DateTime start;
  final DateTime end;
  final int startLevel;
  final int endLevel;

  /// Measured charge added (microampere-hours) when the charge counter exists.
  final int? chargeDeltaUah;

  /// Measured energy added (nanowatt-hours) when the energy counter exists.
  final int? energyDeltaNwh;
  final int? avgVoltageMv;

  /// `true` when samples were far apart (iOS background), so start/end are approximate.
  final bool sparse;

  Duration get duration => end.difference(start);
  int get addedPercent => (endLevel - startLevel).clamp(0, 100);
}

/// Energy figures derived from a session plus user settings.
class SessionEnergy {
  const SessionEnergy({
    required this.mah,
    required this.mahEstimated,
    required this.batteryWh,
    required this.whEstimated,
    required this.wallWh,
    required this.cost,
    this.knownSessions = 0,
    this.unknownSessions = 0,
  });

  /// Nothing charged: a real zero (no sessions), not an unknown one.
  static const zero = SessionEnergy(
    mah: 0,
    mahEstimated: false,
    batteryWh: 0,
    whEstimated: false,
    wallWh: 0,
    cost: 0,
  );

  /// One session whose energy cannot be told: no usable counter delta and no battery capacity to estimate from. The
  /// numbers are 0 only because a field has to hold something; [isUnknown] says they are not a measurement and no
  /// surface may print or send them as one (audit G-02).
  static const unknownSession = SessionEnergy(
    mah: 0,
    mahEstimated: true,
    batteryWh: 0,
    whEstimated: true,
    wallWh: 0,
    cost: 0,
    unknownSessions: 1,
  );

  /// How many of the summed sessions have a known / an unknown energy (1 and 0, or 0 and 1, for a single session).
  final int knownSessions;
  final int unknownSessions;

  /// Every session in this total has an unknown energy (and there is at least one): print [Units.placeholder] and
  /// send nothing, not 0.
  bool get isUnknown => unknownSessions > 0 && knownSessions == 0;

  /// Some sessions of the total are known, some are not: the figures are a lower bound.
  bool get isPartial => unknownSessions > 0 && knownSessions > 0;

  /// For display: NaN when [isUnknown] (every `Units` formatter prints the placeholder for a non-finite number).
  double get mahShown => isUnknown ? double.nan : mah;
  double get batteryWhShown => isUnknown ? double.nan : batteryWh;
  double get wallWhShown => isUnknown ? double.nan : wallWh;
  double get costShown => isUnknown ? double.nan : cost;

  final double mah;
  final bool mahEstimated;

  /// Energy stored in the battery.
  final double batteryWh;
  final bool whEstimated;

  /// Energy drawn from the outlet (battery energy / charging efficiency).
  final double wallWh;

  /// Cost of [wallWh] at the configured price.
  final double cost;

  double get batteryKwh => batteryWh / 1000;
  double get wallKwh => wallWh / 1000;

  SessionEnergy plus(SessionEnergy o) => SessionEnergy(
        mah: mah + o.mah,
        mahEstimated: mahEstimated || o.mahEstimated,
        batteryWh: batteryWh + o.batteryWh,
        whEstimated: whEstimated || o.whEstimated,
        wallWh: wallWh + o.wallWh,
        cost: cost + o.cost,
        knownSessions: knownSessions + o.knownSessions,
        unknownSessions: unknownSessions + o.unknownSessions,
      );
}

/// Per-app usage (Android only; iOS exposes no such API to third parties).
class AppDataUsage {
  const AppDataUsage({
    required this.name,
    this.package,
    required this.mobile,
    required this.wifi,
    this.icon,
  });

  final String name;
  final String? package;
  final int mobile;
  final int wifi;
  final List<int>? icon;

  int get total => mobile + wifi;
}
