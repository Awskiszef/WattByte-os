// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/export/exporter.dart';

import 'export_csv_support.dart';

/// CSV export (`Exporter.dataCsv`, `Exporter.chargingCsv`): pure functions, so
/// every case is exact. Format decisions are documented on `Exporter` and in
/// `docs/REGRESSION_TESTS.md`.
void main() {
  final calc = calcWith();
  final start = DateTime.utc(2026, 10, 12, 22, 30);
  final plainNumber = RegExp(r'^\d+(\.\d+)?$');

  group('data CSV', () {
    test('an empty database exports only the header', () {
      final csv = Exporter.dataCsv(const []);
      expect(csv, '${Exporter.dataCsvHeader}\n');
      final rows = parseCsv(csv);
      expect(rows, hasLength(1));
      expect(rows.single, hasLength(7));
    });

    test('one record: exact line, total is the sum, flags are true/false', () {
      final csv = Exporter.dataCsv([
        DailyData(
            day: DateTime(2026, 10, 12),
            mobileRx: 1000,
            mobileTx: 200,
            wifiRx: 30000,
            wifiTx: 4000,
            estimated: true),
        DailyData(day: DateTime(2026, 10, 13)),
      ]);
      expect(csv.split('\n'), [
        Exporter.dataCsvHeader,
        '2026-10-12,1000,200,30000,4000,35200,true',
        '2026-10-13,0,0,0,0,0,false',
        '',
      ]);
    });

    test('many records keep their order and one row each (10 years of days)',
        () {
      final days = [
        for (var i = 0; i < 3650; i++)
          DailyData(
              day: DateTime(2016, 10, 13 + i),
              mobileRx: i * 1000,
              wifiRx: i * 7,
              estimated: i.isEven),
      ];
      final rows = parseCsv(Exporter.dataCsv(days));
      expect(rows, hasLength(3651));
      expect(rows.skip(1).map((r) => r.length).toSet(), {7});
      expect(rows[1][0], '2016-10-13');
      expect(rows.last[0], dayKeyOf(DateTime(2016, 10, 13 + 3649)));
      expect({for (final r in rows.skip(1)) r[0]}, hasLength(3650),
          reason: 'one distinct local day per row, DST changes included');
      expect(int.parse(rows[2][5]), 1000 + 7);
    });

    test('day keys are the local calendar day, also across daylight saving',
        () {
      // Local midnights of the European and US clock changes: whatever zone the
      // test runs in, the key is the calendar date, never shifted by 23/25 hours.
      for (final d in [
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
        DateTime(2026, 3, 8),
        DateTime(2026, 11, 1),
        DateTime(2024, 2, 29),
      ]) {
        final key = parseCsv(Exporter.dataCsv([DailyData(day: d)]))[1][0];
        expect(key,
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      }
    });

    test('very large counters are written in full, without exponent', () {
      const big = 9007199254740993; // 2^53 + 1: not representable as a double
      final csv = Exporter.dataCsv([
        DailyData(day: DateTime(2026, 10, 12), mobileRx: big, wifiRx: 1),
      ]);
      final row = parseCsv(csv)[1];
      expect(row[1], '$big');
      expect(row[5], '${big + 1}');
      expect(csv, isNot(matches(RegExp(r'\de[+-]?\d'))));
    });

    test('every cell is a date, a plain integer or true/false - no free text',
        () {
      final days = [
        for (var i = 0; i < 50; i++)
          DailyData(
              day: DateTime(2026, 1, 1 + i),
              mobileRx: i * 12345,
              mobileTx: i,
              wifiRx: i * 999999,
              wifiTx: i * 3,
              estimated: i % 3 == 0),
      ];
      for (final row in parseCsv(Exporter.dataCsv(days)).skip(1)) {
        expect(row[0], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
        for (final cell in row.sublist(1, 6)) {
          expect(cell, matches(RegExp(r'^\d+$')));
        }
        expect(row[6], anyOf('true', 'false'));
      }
    });
  });

  group('charging CSV', () {
    test('an empty database exports only the header', () {
      final csv = Exporter.chargingCsv(const [], calc, 'PLN');
      expect(csv, '${Exporter.chargingCsvHeader}\n');
      expect(parseCsv(csv).single, hasLength(14));
    });

    test('one estimated session: exact values, dot decimals, fixed digits', () {
      // 4000 mAh x 60 % = 2400 mAh; x 3.85 V = 9.24 Wh; / 0.85 = 10.8706 Wh;
      // x 1.15 PLN/kWh = 0.0125 PLN.
      final row =
          chargingRow(Exporter.chargingCsv([sessionAt(start)], calc, 'PLN'));
      expect(row, {
        'start': '2026-10-12T22:30:00.000Z',
        'end': '2026-10-12T23:30:00.000Z',
        'start_level': '20',
        'end_level': '80',
        'duration_min': '60',
        'mah': '2400',
        'mah_estimated': 'true',
        'battery_wh': '9.24',
        'wh_estimated': 'true',
        'wall_wh': '10.87',
        'wall_kwh': '0.01087',
        'cost': '0.0125',
        'currency': 'PLN',
        'sparse': 'false',
      });
    });

    test('a measured session is flagged as measured', () {
      final row = chargingRow(Exporter.chargingCsv([
        sessionAt(start,
            chargeUah: 2500000, energyNwh: 9500000000, voltageMv: 3900),
      ], calc, 'EUR'));
      expect(row['mah'], '2500');
      expect(row['mah_estimated'], 'false');
      expect(row['battery_wh'], '9.50');
      expect(row['wh_estimated'], 'false');
      expect(row['currency'], 'EUR');
    });

    test('sparse sessions keep their flag', () {
      expect(
          chargingRow(Exporter.chargingCsv(
              [sessionAt(start, sparse: true)], calc, 'PLN'))['sparse'],
          'true');
    });

    test('timestamps are UTC with Z whatever zone the session was built in',
        () {
      final local = DateTime(2026, 3, 29, 1, 30); // inside the EU clock change
      final csv = Exporter.chargingCsv(
          [sessionAt(local, length: const Duration(hours: 3))], calc, 'PLN');
      final row = chargingRow(csv);
      expect(row['start'], endsWith('Z'));
      expect(row['end'], endsWith('Z'));
      expect(DateTime.parse(row['start']!).isAtSameMomentAs(local), isTrue);
      expect(
          DateTime.parse(row['end']!)
              .isAtSameMomentAs(local.add(const Duration(hours: 3))),
          isTrue);
      expect(row['duration_min'], '180',
          reason: 'the duration is elapsed time, not wall-clock time');
      expect(csv, isNot(contains('+0')),
          reason: 'no local offset suffix such as +01:00');
    });

    test('many sessions: one row each, every row as wide as the header', () {
      final sessions = [
        for (var i = 0; i < 5000; i++)
          sessionAt(start.add(Duration(hours: i * 7)),
              from: i % 90,
              to: (i % 90) + 10,
              chargeUah: i.isEven ? (i + 1) * 1000 : null,
              sparse: i % 11 == 0),
      ];
      final rows = parseCsv(Exporter.chargingCsv(sessions, calc, 'PLN'));
      expect(rows, hasLength(5001));
      expect({for (final r in rows) r.length}, {14});
      expect(rows[1][0], '2026-10-12T22:30:00.000Z');
    });

    test('numbers never use a decimal comma, grouping or exponent', () {
      final previous = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = previous);
      for (final locale in ['pl_PL', 'de_DE', 'ar_EG', 'en_US']) {
        Intl.defaultLocale = locale;
        final csv = Exporter.chargingCsv([
          sessionAt(start, to: 90),
          sessionAt(start, from: 0, to: 100),
        ], calcWith(capacityMah: 30000, voltage: 5, efficiency: 0.01), 'PLN');
        for (final row in parseCsv(csv).skip(1)) {
          for (final i in [2, 3, 4, 5, 7, 9, 10, 11]) {
            expect(row[i], matches(plainNumber), reason: '$locale: ${row[i]}');
          }
        }
      }
    });

    test('very large and very small values stay plain decimals', () {
      // Largest physically accepted values: 30 000 mAh at 5 V and 1 % efficiency.
      final big = chargingRow(Exporter.chargingCsv(
          [sessionAt(start, from: 0, to: 100)],
          calcWith(
              capacityMah: 30000, voltage: 5, efficiency: 0.01, price: 1000),
          'PLN'));
      expect(big['mah'], '30000');
      expect(big['battery_wh'], '150.00');
      expect(big['wall_wh'], '15000.00');
      expect(big['wall_kwh'], '15.00000');
      expect(big['cost'], '15000.0000');

      // A thousandth of a percent of a tiny battery rounds to zero, not to 1e-9.
      final small = chargingRow(Exporter.chargingCsv(
          [sessionAt(start, from: 0, to: 1)],
          calcWith(capacityMah: 0.001, price: 0.0001),
          'PLN'));
      for (final column in [
        'mah',
        'battery_wh',
        'wall_wh',
        'wall_kwh',
        'cost'
      ]) {
        expect(small[column], matches(plainNumber), reason: column);
        expect(double.parse(small[column]!), 0, reason: column);
      }
    });

    test('no value is NaN or Infinity: such numbers become empty cells', () {
      final csv = Exporter.chargingCsv(
          [sessionAt(start)],
          _FixedCalc(const SessionEnergy(
              mah: double.nan,
              mahEstimated: true,
              batteryWh: double.infinity,
              whEstimated: true,
              wallWh: double.negativeInfinity,
              cost: double.nan)),
          'PLN');
      final row = chargingRow(csv);
      for (final column in [
        'mah',
        'battery_wh',
        'wall_wh',
        'wall_kwh',
        'cost'
      ]) {
        expect(row[column], '', reason: column);
      }
      expect(csv.toLowerCase(), isNot(contains('nan')));
      expect(csv.toLowerCase(), isNot(contains('inf')));
      expect(row['currency'], 'PLN', reason: 'the rest of the row is intact');
    });

    test('negative zero and tiny negative values are written as plain zero',
        () {
      for (final v in [-0.0, -0.0000001, -0.00004]) {
        final row = chargingRow(Exporter.chargingCsv(
            [sessionAt(start)],
            _FixedCalc(SessionEnergy(
                mah: v,
                mahEstimated: true,
                batteryWh: v,
                whEstimated: true,
                wallWh: v,
                cost: v)),
            'PLN'));
        expect(row['mah'], '0', reason: '$v');
        expect(row['battery_wh'], '0.00', reason: '$v');
        expect(row['wall_wh'], '0.00', reason: '$v');
        expect(row['wall_kwh'], '0.00000', reason: '$v');
        expect(row['cost'], '0.0000', reason: '$v');
      }
    });

    test('a real negative amount keeps its sign (nothing is hidden)', () {
      final row = chargingRow(Exporter.chargingCsv(
          [sessionAt(start)],
          _FixedCalc(const SessionEnergy(
              mah: -5,
              mahEstimated: true,
              batteryWh: -1.5,
              whEstimated: true,
              wallWh: -2,
              cost: -0.5)),
          'PLN'));
      expect(row['mah'], '-5');
      expect(row['cost'], '-0.5000');
    });

    test('unknown capacity and no counters: the energy is empty, not 0', () {
      final unknown = EnergyCalc(
          batteryCapacityMah: 0,
          nominalVoltage: 3.85,
          efficiency: 0.85,
          pricePerKwh: 1.15);
      final row =
          chargingRow(Exporter.chargingCsv([sessionAt(start)], unknown, 'PLN'));
      for (final column in [
        'mah',
        'battery_wh',
        'wall_wh',
        'wall_kwh',
        'cost'
      ]) {
        expect(row[column], '', reason: column);
      }
      expect(row['mah_estimated'], 'true');
      expect(row['duration_min'], '60', reason: 'what is known is still there');

      // ... but a measured session needs no capacity.
      final measured = chargingRow(Exporter.chargingCsv(
          [sessionAt(start, chargeUah: 2400000)], unknown, 'PLN'));
      expect(measured['mah'], '2400');
      expect(measured['mah_estimated'], 'false');
      expect(measured['cost'], isNotEmpty);
    });

    test('unknown price: the cost is empty, the energy is still exported', () {
      final noPrice = calcWith(price: 0);
      final row =
          chargingRow(Exporter.chargingCsv([sessionAt(start)], noPrice, 'PLN'));
      expect(row['cost'], '');
      expect(row['wall_kwh'], '0.01087');
    });

    test('a session that added 0 % is a real zero, not unknown', () {
      final row = chargingRow(Exporter.chargingCsv(
          [sessionAt(start, from: 50, to: 50)], calc, 'PLN'));
      expect(row['mah'], '0');
      expect(row['cost'], '0.0000');
    });
  });

  group('text cells (the currency) and CSV injection', () {
    String currencyCell(String currency) {
      final csv = Exporter.chargingCsv([sessionAt(start)], calc, currency);
      final rows = parseCsv(csv);
      expect(rows, hasLength(2), reason: 'a value must never split the file');
      expect(rows[1], hasLength(14),
          reason: 'a value must never shift the columns');
      expect(rows[1][13], 'false', reason: 'the column after it is intact');
      return rows[1][12];
    }

    test('ordinary codes are written as they are', () {
      for (final code in ['PLN', 'EUR', 'USD', 'CZK', '']) {
        expect(currencyCell(code), code);
        expect(Exporter.chargingCsv([sessionAt(start)], calc, code),
            contains(',$code,false\n'),
            reason: 'no needless quotes');
      }
    });

    test('commas, quotes and newlines are quoted per RFC 4180 and survive', () {
      for (final value in [
        'P,LN',
        'P"LN',
        '"',
        '""',
        'P\nLN',
        'P\r\nLN',
        'P\rLN',
        ',',
        '\n',
        'a,"b"\r\nc',
      ]) {
        expect(currencyCell(value), value, reason: _show(value));
      }
    });

    test('a LF or CRLF inside a text field does not add a record', () {
      for (final nl in ['\n', '\r\n']) {
        final csv = Exporter.chargingCsv([sessionAt(start)], calc, 'A${nl}B');
        expect(csv, contains('"A${nl}B"'));
        expect(parseCsv(csv), hasLength(2));
      }
    });

    test('Polish letters, emoji and other Unicode round-trip unchanged', () {
      for (final value in [
        'ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ',
        'zł',
        '€',
        '💶',
        '👨‍👩‍👧 \u{1F1F5}\u{1F1F1}',
        'ß ç ñ ü',
        '日本語',
        'ا',
        'é', // e + combining accent
        '​', // zero-width space
      ]) {
        expect(currencyCell(value), value, reason: _show(value));
      }
    });

    test('cells that a spreadsheet would read as a formula are neutralised',
        () {
      for (final value in [
        '=1+1',
        '+1+1',
        '-1+1',
        '@SUM(A1)',
        '=HYPERLINK("http://example.invalid","x")',
        '\t=1',
        '\r=1',
      ]) {
        final cell = currencyCell(value);
        expect(cell, startsWith("'"), reason: _show(value));
        expect(cell.substring(1), value);
      }
      // Only a LEADING character matters; inside a value the text is unchanged.
      expect(currencyCell('A=B'), 'A=B');
      expect(currencyCell('P-LN'), 'P-LN');
    });

    test(
        'the exporter writes no other free text: every other cell is a number, '
        'a timestamp or a flag, so none can start with = + - @', () {
      final sessions = [
        for (var i = 0; i < 200; i++)
          sessionAt(start.add(Duration(days: i)),
              from: i % 100,
              to: (i * 7) % 100,
              chargeUah: i % 3 == 0 ? i * 100000 : null,
              energyNwh: i % 5 == 0 ? i * 100000000000 : null,
              voltageMv: i % 4 == 0 ? 3700 + i : null,
              sparse: i.isOdd),
      ];
      final rows = parseCsv(Exporter.chargingCsv(sessions, calc, 'PLN'));
      final timestamp =
          RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
      for (final row in rows.skip(1)) {
        expect(row[0], matches(timestamp));
        expect(row[1], matches(timestamp));
        for (final i in [2, 3, 4, 5, 7, 9, 10, 11]) {
          // Integers and fixed decimals; a leading '-' would be a sign, and
          // none of these can be negative for a valid session.
          expect(row[i], matches(plainNumber), reason: 'column $i: ${row[i]}');
        }
        for (final i in [6, 8, 13]) {
          expect(row[i], anyOf('true', 'false'));
        }
        expect(row[12], 'PLN');
      }
      final data = parseCsv(Exporter.dataCsv([
        for (var i = 0; i < 50; i++) DailyData(day: DateTime(2026, 1, 1 + i)),
      ]));
      for (final row in data.skip(1)) {
        for (final cell in row) {
          expect(cell, isNot(matches(RegExp(r'^[=+\-@\t\r]'))));
        }
      }
    });
  });

  group('encoding of the final bytes', () {
    final csvs = <String, String>{
      'data': Exporter.dataCsv([
        DailyData(day: DateTime(2026, 10, 12), mobileRx: 5, estimated: true),
      ]),
      'charging': Exporter.chargingCsv(
          [sessionAt(start)], calc, 'zł ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ 💶, "x"\nz'),
    };

    for (final e in csvs.entries) {
      test('${e.key}: UTF-8 round trip, and no byte-order mark', () {
        final bytes = utf8.encode(e.value);
        expect(utf8.decode(bytes), e.value);
        expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
        expect(e.value.codeUnitAt(0), isNot(0xFEFF));
        expect(e.value, startsWith(e.key == 'data' ? 'day,' : 'start,'),
            reason: 'the first header is not prefixed by an invisible char');
      });
    }

    test('what the app writes to disk (File.writeAsString) is that UTF-8',
        () async {
      final dir = await Directory.systemTemp.createTemp('wb_export_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/wattbyte-charging.csv');
      await file.writeAsString(csvs['charging']!);
      final bytes = await file.readAsBytes();
      expect(bytes, utf8.encode(csvs['charging']!));
      expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), csvs['charging']);
      // Polish letters take two bytes each in UTF-8: the file is not Latin-2.
      expect(utf8.encode('ą'), [0xC4, 0x85]);
    });

    test('rows end with LF only (no stray CR outside quoted text)', () {
      final csv = Exporter.chargingCsv([sessionAt(start)], calc, 'PLN');
      expect(csv, isNot(contains('\r')));
      expect(csv.endsWith('\n'), isTrue);
      expect(csv.endsWith('\n\n'), isFalse);
    });
  });
}

String _show(String s) => jsonEncode(s);

/// A calculator whose session energy is whatever the test says, to reach the
/// exporter's own guards (the real [EnergyCalc] validates and throws long
/// before a NaN could get this far).
class _FixedCalc extends Fake implements EnergyCalc {
  _FixedCalc(this.energy);

  final SessionEnergy energy;

  @override
  SessionEnergy session(ChargingSession s) => energy;

  @override
  double get pricePerKwh => 1.15;

  @override
  double get batteryCapacityMah => 4000;

  @override
  double get nominalVoltage => 3.85;

  @override
  double get efficiency => 0.85;

  @override
  bool get canEstimateFromPercent => true;
}

String dayKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
