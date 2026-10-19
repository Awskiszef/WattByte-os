import '../domain/models.dart';

/// Thrown when an energy calculation receives a value that cannot be physical:
/// NaN, infinity, negative amounts, or an efficiency outside (0, 1].
///
/// The calculations never turn bad input into a quiet `NaN` or `Infinity`.
class EnergyInputError extends ArgumentError {
  EnergyInputError(String name, Object? value, String rule)
      : super.value(value, name, 'must be $rule');
}

void _requireFinite(String name, double v) {
  if (!v.isFinite) throw EnergyInputError(name, v, 'a finite number');
}

void _requireNonNegative(String name, double v) {
  _requireFinite(name, v);
  if (v < 0) throw EnergyInputError(name, v, 'zero or positive');
}

/// Energy mathematics. Pure functions, no I/O.
///
/// Wh  = mAh x V / 1000
/// kWh = Wh / 1000
/// wall energy = battery energy / charging efficiency
/// cost = wall kWh x price per kWh
class EnergyCalc {
  /// Validates every input and throws [EnergyInputError] instead of producing
  /// `NaN`/`Infinity`/negative energy later.
  factory EnergyCalc({
    required double batteryCapacityMah,
    required double nominalVoltage,
    required double efficiency,
    required double pricePerKwh,
  }) {
    _requireNonNegative('batteryCapacityMah', batteryCapacityMah);
    if (batteryCapacityMah > maxCapacityMah) {
      throw EnergyInputError(
          'batteryCapacityMah', batteryCapacityMah, 'at most $maxCapacityMah');
    }
    _requireFinite('nominalVoltage', nominalVoltage);
    if (nominalVoltage < minVoltage || nominalVoltage > maxVoltage) {
      throw EnergyInputError('nominalVoltage', nominalVoltage,
          'between $minVoltage and $maxVoltage V');
    }
    _requireFinite('efficiency', efficiency);
    if (efficiency <= 0 || efficiency > 1) {
      throw EnergyInputError('efficiency', efficiency, 'in (0, 1]');
    }
    _requireNonNegative('pricePerKwh', pricePerKwh);
    return EnergyCalc._(
      batteryCapacityMah: batteryCapacityMah,
      nominalVoltage: nominalVoltage,
      efficiency: efficiency,
      pricePerKwh: pricePerKwh,
    );
  }

  const EnergyCalc._({
    required this.batteryCapacityMah,
    required this.nominalVoltage,
    required this.efficiency,
    required this.pricePerKwh,
  });

  /// Sanity bounds: far beyond any phone, tight enough to catch unit mistakes.
  static const maxCapacityMah = 30000.0;
  static const maxCapacityWh = 200.0;
  static const minVoltage = 2.5;
  static const maxVoltage = 5.0;

  /// One charging session cannot add more than this (a laptop battery is ~100 Wh).
  static const maxSessionChargeUah = 30000 * 1000; // 30 Ah
  static const maxSessionEnergyNwh = 200 * 1000000000; // 200 Wh

  /// Capacity used for the `% -> mAh` estimate (0 = unknown).
  final double batteryCapacityMah;

  /// Fallback cell voltage when the system reports none (typical Li-ion: 3.85 V).
  final double nominalVoltage;

  /// 0-1. Battery energy / efficiency = energy drawn from the wall.
  final double efficiency;
  final double pricePerKwh;

  static double whFromMah(double mah, double volts) {
    _requireNonNegative('mah', mah);
    _requireFinite('volts', volts);
    if (volts <= 0) throw EnergyInputError('volts', volts, 'positive');
    return mah * volts / 1000;
  }

  static double kwhFromWh(double wh) {
    _requireNonNegative('wh', wh);
    return wh / 1000;
  }

  static double wallFromBattery(double wh, double efficiency) {
    _requireNonNegative('wh', wh);
    _requireFinite('efficiency', efficiency);
    if (efficiency <= 0 || efficiency > 1) {
      throw EnergyInputError('efficiency', efficiency, 'in (0, 1]');
    }
    return wh / efficiency;
  }

  static double costOf(double kwh, double pricePerKwh) {
    _requireNonNegative('kwh', kwh);
    _requireNonNegative('pricePerKwh', pricePerKwh);
    return kwh * pricePerKwh;
  }

  /// Prefers measured counters, falls back to a capacity-based estimate.
  ///
  /// 1. Energy counter delta (nWh)     -> measured Wh.
  /// 2. Charge counter delta (uAh)     -> measured mAh; Wh = mAh x V (estimated).
  /// 3. Capacity x added percent       -> estimated mAh and Wh.
  SessionEnergy session(ChargingSession s) {
    double? mah;
    var mahEstimated = true;
    final cd = s.chargeDeltaUah;
    if (cd != null && cd > 0 && cd <= maxSessionChargeUah) {
      mah = cd / 1000;
      mahEstimated = false;
    }
    // A counter delta that is <= 0 (reset/unsupported) or absurdly large (glitch)
    // is not trusted and falls back to the estimate.
    mah ??= batteryCapacityMah * s.addedPercent / 100;

    final mv = s.avgVoltageMv;
    final volts =
        (mv != null && mv >= minVoltage * 1000 && mv <= maxVoltage * 1000)
            ? mv / 1000
            : nominalVoltage;

    double wh;
    var whEstimated = true;
    final ed = s.energyDeltaNwh;
    if (ed != null && ed > 0 && ed <= maxSessionEnergyNwh) {
      wh = ed / 1e9;
      whEstimated = false;
    } else {
      wh = whFromMah(mah, volts);
    }
    final wall = wallFromBattery(wh, efficiency);
    return SessionEnergy(
      mah: mah,
      mahEstimated: mahEstimated,
      batteryWh: wh,
      whEstimated: whEstimated,
      wallWh: wall,
      cost: costOf(kwhFromWh(wall), pricePerKwh),
    );
  }

  SessionEnergy total(Iterable<ChargingSession> sessions) =>
      sessions.fold(SessionEnergy.zero, (acc, s) => acc.plus(session(s)));

  /// Does the `% -> mAh` path have the input it needs?
  bool get canEstimateFromPercent => batteryCapacityMah > 0;
}
