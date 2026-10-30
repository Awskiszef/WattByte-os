// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/export/exporter.dart';
import 'package:wattbyte/settings/settings.dart';

void main() {
  _extra();
  final calc = EnergyCalc(
      batteryCapacityMah: 4000,
      nominalVoltage: 3.85,
      efficiency: 0.85,
      pricePerKwh: 1.15);

  test('an empty database exports a valid header-only CSV and valid JSON', () {
    expect(Exporter.dataCsv(const []).trim().split('\n'), hasLength(1));
    expect(Exporter.chargingCsv(const [], calc, 'PLN').trim().split('\n'),
        hasLength(1));
    final j = jsonDecode(Exporter.json(
        days: const [],
        sessions: const [],
        calc: calc,
        settings: const Settings(),
        now: DateTime(2026, 10, 13))) as Map;
    expect(j['data'], isEmpty);
    expect(j['charging'], isEmpty);
  });

  test('timestamps are UTC with a Z suffix, numbers use a dot, no value is NaN',
      () {
    final s = ChargingSession(
        start: DateTime(2026, 3, 29, 1, 30),
        end: DateTime(2026, 3, 29, 4, 30),
        startLevel: 20,
        endLevel: 80);
    final csv = Exporter.chargingCsv([s], calc, 'PLN');
    final row = csv.trim().split('\n')[1].split(',');
    expect(row[0], endsWith('Z'));
    expect(row[1], endsWith('Z'));
    expect(csv, isNot(contains('NaN')));
    expect(csv, isNot(contains('Infinity')));
    expect(row[13], 'false');
    final json = jsonDecode(Exporter.json(
        days: [
          DailyData(day: DateTime(2026, 10, 1), mobileRx: 5, estimated: true)
        ],
        sessions: [
          s
        ],
        calc: calc,
        settings: const Settings(currency: 'PLN'),
        now: DateTime(2026, 10, 13, 12))) as Map;
    expect((json['charging'] as List).single['start'], endsWith('Z'));
    expect(json['exportedAt'], endsWith('Z'));
  });
}

/// Bug 4 of the simulator report (export): the share-sheet anchor and the error
/// handling live in the Settings screen; what is testable here is that the
/// data itself is well formed. The detailed cases are in
/// `export_csv_test.dart` and `export_json_test.dart`.
void _extra() {
  final calc = EnergyCalc(
      batteryCapacityMah: 4000,
      nominalVoltage: 3.85,
      efficiency: 0.85,
      pricePerKwh: 1.15);

  test('one record each: CSV rows match the header, JSON decodes, no BOM', () {
    final s = ChargingSession(
        start: DateTime.utc(2026, 10, 12, 22),
        end: DateTime.utc(2026, 10, 12, 23),
        startLevel: 10,
        endLevel: 60);
    final day = DailyData(day: DateTime(2026, 10, 12), mobileRx: 1);
    final csvs = [
      Exporter.dataCsv([day]),
      Exporter.chargingCsv([s], calc, 'PLN'),
    ];
    for (final csv in csvs) {
      final rows = csv.trim().split('\n');
      expect(rows, hasLength(2));
      expect(rows[1].split(',').length, rows[0].split(',').length);
      expect(utf8.encode(csv).take(3), isNot([0xEF, 0xBB, 0xBF]));
    }
    final json = Exporter.json(
        days: [day],
        sessions: [s],
        calc: calc,
        settings: const Settings(currency: 'PLN'),
        now: DateTime.utc(2026, 10, 13));
    expect(jsonDecode(json), isA<Map>());
    expect(utf8.encode(json).first, 0x7B);
  });

  test('the exporter is pure: it imports no I/O, network or API client', () {
    final source = File('lib/export/exporter.dart').readAsStringSync();
    final imports = RegExp(r'''^import\s+['"]([^'"]+)['"]''', multiLine: true)
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toList();
    expect(imports, isNotEmpty);
    for (final i in imports) {
      expect(i, isNot(startsWith('dart:io')));
      expect(i, isNot(startsWith('dart:html')));
      expect(i, isNot(contains('package:http')));
      expect(i, isNot(contains('generated/api')));
      expect(i, isNot(contains('api_factory')));
    }
  });
}
