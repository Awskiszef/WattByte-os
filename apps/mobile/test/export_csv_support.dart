/// Shared helpers of the export tests (not a test itself: the name does not end
/// in `_test.dart`).
library;

import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/models.dart';

/// A strict RFC 4180 reader, written independently of the exporter so the tests
/// do not just replay the writer's own assumptions.
///
/// Accepts `\n` and `\r\n` as record separators (the exporter writes `\n`),
/// quoted fields with `""` escapes, and newlines inside quoted fields. Throws a
/// [FormatException] on anything malformed (a quote inside an unquoted field,
/// text after a closing quote, an unterminated quote).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var justClosed = false; // a quoted field just ended
  var fieldStarted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    inQuotes = false;
    justClosed = false;
    fieldStarted = false;
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
          justClosed = true;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"') {
      if (fieldStarted || justClosed) {
        throw FormatException('quote inside a field', text, i);
      }
      inQuotes = true;
      fieldStarted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      if (justClosed) throw FormatException('text after a quote', text, i);
      field.write(c);
      fieldStarted = true;
    }
  }
  if (inQuotes) throw FormatException('unterminated quote', text);
  if (fieldStarted || justClosed || row.isNotEmpty) endRow();
  return rows;
}

/// A calculator the way a configured install has one.
EnergyCalc calcWith(
        {double capacityMah = 4000,
        double voltage = 3.85,
        double efficiency = 0.85,
        double price = 1.15}) =>
    EnergyCalc(
        batteryCapacityMah: capacityMah,
        nominalVoltage: voltage,
        efficiency: efficiency,
        pricePerKwh: price);

/// A 20 % -> 80 % session with no counters (estimated from the capacity).
ChargingSession sessionAt(DateTime start,
        {Duration length = const Duration(hours: 1),
        int from = 20,
        int to = 80,
        int? chargeUah,
        int? energyNwh,
        int? voltageMv,
        bool sparse = false}) =>
    ChargingSession(
      start: start,
      end: start.add(length),
      startLevel: from,
      endLevel: to,
      chargeDeltaUah: chargeUah,
      energyDeltaNwh: energyNwh,
      avgVoltageMv: voltageMv,
      sparse: sparse,
    );

/// Column name -> value of the first data row of a charging CSV.
Map<String, String> chargingRow(String csv, [int index = 0]) {
  final rows = parseCsv(csv);
  final header = rows.first;
  final row = rows[index + 1];
  expectSameWidth(header, row);
  return {for (var i = 0; i < header.length; i++) header[i]: row[i]};
}

void expectSameWidth(List<String> header, List<String> row) {
  if (header.length != row.length) {
    throw StateError(
        'row has ${row.length} cells, the header ${header.length}: $row');
  }
}
