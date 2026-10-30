// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../analytics/stats.dart';
import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import 'sha256.dart';

/// The only shape a future cloud sync would upload: one row per local day.
///
/// Raw samples, per-app usage and session timestamps never leave the device.
/// All numbers are computed locally and deterministically; a backend or an AI
/// only ever reads them.
class DailyAggregate {
  const DailyAggregate({
    required this.date,
    required this.mobileBytes,
    required this.wifiBytes,
    required this.chargedWh,
    required this.wallWh,
    required this.chargingSessions,
    required this.estimatedCost,
    required this.currency,
    this.dataEstimated = false,
    this.energyEstimated = true,
  });

  /// Local `yyyy-MM-dd`.
  final String date;
  final int mobileBytes;
  final int wifiBytes;

  /// Energy stored in the battery.
  final double chargedWh;

  /// Energy drawn from the outlet (battery energy / efficiency).
  final double wallWh;
  final int chargingSessions;
  final double estimatedCost;
  final String currency;
  final bool dataEstimated;
  final bool energyEstimated;

  static DailyAggregate build({
    required DateTime day,
    required Iterable<DailyData> days,
    required Iterable<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
  }) {
    final d = dayOf(day);
    final range = DateRange(d, DateTime(d.year, d.month, d.day + 1));
    final data = DailyData.sum(daysIn(days, range), day: d);
    final daySessions = sessionsIn(sessions, range);
    final e = calc.total(daySessions);
    return DailyAggregate(
      date: dayKey(d),
      mobileBytes: data.mobile,
      wifiBytes: data.wifi,
      chargedWh: _round(e.batteryWh, 3),
      wallWh: _round(e.wallWh, 3),
      chargingSessions: daySessions.length,
      estimatedCost: _round(e.cost, 4),
      currency: currency,
      dataEstimated: data.estimated,
      energyEstimated: e.whEstimated || daySessions.isNotEmpty,
    );
  }

  /// Within the API contract (finite, non-negative, physically possible, ISO currency).
  /// A day outside it is never queued or sent: the server would answer 400.
  bool get isWithinContract {
    bool ok(double v) => v.isFinite && v >= 0 && v <= 100000;
    return mobileBytes >= 0 &&
        mobileBytes <= 10000000000000 &&
        wifiBytes >= 0 &&
        wifiBytes <= 10000000000000 &&
        ok(chargedWh) &&
        ok(wallWh) &&
        ok(estimatedCost) &&
        chargingSessions >= 0 &&
        chargingSessions <= 1000 &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency) &&
        date.compareTo('2015-01-01') >= 0;
  }

  bool get isEmpty =>
      mobileBytes == 0 && wifiBytes == 0 && chargingSessions == 0;

  /// The aggregate as one canonical string: every field, keys sorted, no
  /// whitespace. Two equal aggregates always produce the same text, whatever order
  /// the map was built in, and it survives the JSON round trip through SQLite.
  String get canonicalJson {
    final m = toJson();
    final keys = m.keys.toList()..sort();
    return jsonEncode({for (final k in keys) k: m[k]});
  }

  /// SHA-256 of [canonicalJson] (hex). A cloud receipt records the fingerprint of
  /// what was uploaded; a day needs uploading again exactly when the fingerprint of
  /// the current aggregate differs (see `docs/SYNC_OWNERSHIP.md`).
  String get fingerprint => sha256Hex(canonicalJson);

  Map<String, Object?> toJson() => {
        'date': date,
        'mobileBytes': mobileBytes,
        'wifiBytes': wifiBytes,
        'chargedWh': chargedWh,
        'wallWh': wallWh,
        'chargingSessions': chargingSessions,
        'estimatedCost': estimatedCost,
        'currency': currency,
        'dataEstimated': dataEstimated,
        'energyEstimated': energyEstimated,
      };

  static DailyAggregate fromJson(Map<String, dynamic> m) => DailyAggregate(
        date: m['date'] as String,
        mobileBytes: m['mobileBytes'] as int,
        wifiBytes: m['wifiBytes'] as int,
        chargedWh: (m['chargedWh'] as num).toDouble(),
        wallWh: (m['wallWh'] as num).toDouble(),
        chargingSessions: m['chargingSessions'] as int,
        estimatedCost: (m['estimatedCost'] as num).toDouble(),
        currency: m['currency'] as String,
        dataEstimated: m['dataEstimated'] as bool? ?? false,
        energyEstimated: m['energyEstimated'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is DailyAggregate &&
      date == other.date &&
      mobileBytes == other.mobileBytes &&
      wifiBytes == other.wifiBytes &&
      chargedWh == other.chargedWh &&
      wallWh == other.wallWh &&
      chargingSessions == other.chargingSessions &&
      estimatedCost == other.estimatedCost &&
      currency == other.currency &&
      dataEstimated == other.dataEstimated &&
      energyEstimated == other.energyEstimated;

  @override
  int get hashCode => Object.hash(
      date,
      mobileBytes,
      wifiBytes,
      chargedWh,
      wallWh,
      chargingSessions,
      estimatedCost,
      currency,
      dataEstimated,
      energyEstimated);

  static double _round(double v, int decimals) {
    final f = [1, 10, 100, 1000, 10000][decimals];
    return (v * f).roundToDouble() / f;
  }
}
