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
  });

  static const zero = SessionEnergy(
    mah: 0,
    mahEstimated: false,
    batteryWh: 0,
    whEstimated: false,
    wallWh: 0,
    cost: 0,
  );

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
