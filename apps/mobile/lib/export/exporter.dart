// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import '../settings/settings.dart';

/// Serializes the user's own data. Nothing here touches the network.
///
/// Format decisions (all pinned by `test/export_csv_test.dart` and
/// `test/export_json_test.dart`, summarised in `docs/REGRESSION_TESTS.md`):
///
/// * **Encoding.** The functions return Dart strings; the caller writes them
///   with `File.writeAsString`, which is UTF-8 **without a byte-order mark**.
///   No BOM is written on purpose: every field the exporter produces today is
///   ASCII (numbers, ISO dates, `true`/`false`, a currency code), so a BOM would
///   only put a stray `﻿` in front of the first header for tools that do not
///   strip it. If free text (names, notes) is ever exported, revisit this:
///   Excel needs the BOM to read non-ASCII UTF-8.
/// * **Line endings.** CSV rows end with `\n`. A cell containing a CR or LF is
///   quoted (RFC 4180), so a newline inside a value can never split a row.
/// * **Numbers.** Always a dot as decimal separator, never grouped, never in the
///   device locale. CSV uses fixed decimals (`toStringAsFixed`, so no exponent
///   below 1e21); JSON writes the shortest round-trip form of the double, which
///   Dart prints without exponent between 1e-6 and 1e21 (outside that range the
///   exponent form is still valid JSON). Negative zero is written as zero.
/// * **Not a number.** `NaN` and the infinities have no JSON representation (and
///   `jsonEncode` throws on them), and the text `NaN` in a spreadsheet is worse
///   than a gap. They are written as an **empty CSV cell** and JSON **`null`**.
/// * **Unknown is not zero.** A design capacity or electricity price of 0 means
///   "not known" in [Settings]; the energy and cost of a session that has no
///   measurement and no capacity to estimate from are empty / `null` instead of
///   a made-up `0`.
/// * **Two capacities, never one.** The JSON `settings` block keeps the design
///   capacity of the phone model (`designCapacityMah`, `designCapacitySource`)
///   apart from the capacity the `% -> mAh` energy estimate used
///   (`estimateCapacityMah`, with its `estimateCapacityBasis`): that is the
///   design capacity when one is known and otherwise the estimated full-charge
///   capacity of this battery, which is not the nominal one.
/// * **Time.** Instants are UTC ISO-8601 with a `Z`; calendar days are the local
///   `yyyy-MM-dd` key the app shows.
/// * **Text.** The only free-form text is the currency code. A CSV text cell is
///   quoted when it holds a comma, quote, CR or LF, and a cell that starts with
///   `=`, `+`, `-`, `@`, a tab or a CR gets a leading `'` so a spreadsheet cannot
///   read it as a formula. Numbers and dates are generated here and never start
///   with those characters (a negative number's `-` is a sign, not text).
class Exporter {
  const Exporter._();

  /// Header of [dataCsv] (also the column order).
  static const dataCsvHeader = 'day,mobile_rx_bytes,mobile_tx_bytes,'
      'wifi_rx_bytes,wifi_tx_bytes,total_bytes,estimated';

  /// Header of [chargingCsv] (also the column order).
  static const chargingCsvHeader =
      'start,end,start_level,end_level,duration_min,mah,mah_estimated,'
      'battery_wh,wh_estimated,wall_wh,wall_kwh,cost,currency,sparse';

  static String dataCsv(List<DailyData> days) {
    final b = StringBuffer('$dataCsvHeader\n');
    for (final d in days) {
      b.writeln(
          '${dayKey(d.day)},${d.mobileRx},${d.mobileTx},${d.wifiRx},${d.wifiTx},'
          '${d.total},${d.estimated}');
    }
    return b.toString();
  }

  static String chargingCsv(
      List<ChargingSession> sessions, EnergyCalc calc, String currency) {
    final b = StringBuffer('$chargingCsvHeader\n');
    final currencyCell = _csvText(currency);
    for (final s in sessions) {
      final e = calc.session(s);
      final known = _energyIsKnown(e, calc);
      final priced = known && calc.pricePerKwh > 0;
      b.writeln([
        s.start.toUtc().toIso8601String(),
        s.end.toUtc().toIso8601String(),
        '${s.startLevel}',
        '${s.endLevel}',
        '${s.duration.inMinutes}',
        if (known) _fixed(e.mah, 0) else '',
        '${e.mahEstimated}',
        if (known) _fixed(e.batteryWh, 2) else '',
        '${e.whEstimated}',
        if (known) _fixed(e.wallWh, 2) else '',
        if (known) _fixed(e.wallKwh, 5) else '',
        if (priced) _fixed(e.cost, 4) else '',
        currencyCell,
        '${s.sparse}',
      ].join(','));
    }
    return b.toString();
  }

  static String json({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required Settings settings,
    required DateTime now,
  }) {
    final hasDesign = settings.designCapacity.isKnown;
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'WattByte',
      'exportedAt': now.toUtc().toIso8601String(),
      // Only what the numbers above were computed from. No account data:
      // no e-mail, no tokens, no ids.
      'settings': {
        'currency': settings.currency,
        'pricePerKwh': settings.hasPrice ? _number(settings.pricePerKwh) : null,
        'chargingEfficiency': _number(settings.efficiency),
        // The nominal capacity of the phone model (null when unknown) ...
        'designCapacityMah':
            hasDesign ? _number(settings.designCapacityMah) : null,
        'designCapacitySource':
            hasDesign ? settings.designCapacitySource.name : 'unknown',
        // ... versus the capacity the `% -> mAh` estimate used, which is the
        // design capacity or, when none is known, the estimated full-charge
        // capacity of this battery (an estimate, never the nominal value).
        'estimateCapacityMah': calc.canEstimateFromPercent
            ? _number(calc.batteryCapacityMah)
            : null,
        'estimateCapacityBasis': hasDesign
            ? 'design'
            : calc.canEstimateFromPercent
                ? 'estimatedFullCharge'
                : null,
        'nominalVoltage': _number(calc.nominalVoltage),
      },
      'data': [
        for (final d in days)
          {
            'day': dayKey(d.day),
            'mobileRxBytes': d.mobileRx,
            'mobileTxBytes': d.mobileTx,
            'wifiRxBytes': d.wifiRx,
            'wifiTxBytes': d.wifiTx,
            'estimated': d.estimated,
          },
      ],
      'charging': [
        for (final s in sessions)
          {
            'start': s.start.toUtc().toIso8601String(),
            'end': s.end.toUtc().toIso8601String(),
            'startLevel': s.startLevel,
            'endLevel': s.endLevel,
            'chargeDeltaUah': s.chargeDeltaUah,
            'energyDeltaNwh': s.energyDeltaNwh,
            'avgVoltageMv': s.avgVoltageMv,
            'sparse': s.sparse,
            'energy': _energy(calc.session(s), calc),
          },
      ],
    });
  }

  static Map<String, Object?> _energy(SessionEnergy e, EnergyCalc calc) {
    final known = _energyIsKnown(e, calc);
    final priced = known && calc.pricePerKwh > 0;
    return {
      'mah': known ? _number(e.mah) : null,
      'mahEstimated': e.mahEstimated,
      'batteryWh': known ? _number(e.batteryWh) : null,
      'whEstimated': e.whEstimated,
      'wallWh': known ? _number(e.wallWh) : null,
      'wallKwh': known ? _number(e.wallKwh) : null,
      'cost': priced ? _number(e.cost) : null,
    };
  }

  /// Whether [e] rests on a measurement or on a capacity to estimate from. A
  /// session with neither has no energy at all, which is not the same as 0 Wh.
  static bool _energyIsKnown(SessionEnergy e, EnergyCalc calc) => !e.isUnknown;

  /// A finite double for JSON, `null` otherwise; `-0.0` becomes `0.0`.
  static double? _number(double v) => v.isFinite ? (v == 0 ? 0.0 : v) : null;

  /// A CSV number with [digits] decimals; empty for NaN / infinity; never `-0.00`.
  static String _fixed(double v, int digits) {
    if (!v.isFinite) return '';
    final text = v.toStringAsFixed(digits);
    // `(-0.0).toStringAsFixed(2)` is "-0.00", and so is a tiny negative number.
    return text.startsWith('-') && !text.contains(RegExp('[1-9]'))
        ? text.substring(1)
        : text;
  }

  /// One CSV text cell (RFC 4180 quoting plus spreadsheet-formula hygiene).
  static String _csvText(String value) {
    var text = value;
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
    if (text.contains(RegExp('[",\r\n]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
