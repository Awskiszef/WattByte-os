// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wattbyte/calc/energy.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/export/exporter.dart';
import 'package:wattbyte/settings/settings.dart';

import 'export_csv_support.dart';

/// JSON export (`Exporter.json`). Pure, so every case is exact. The format
/// decisions are documented on `Exporter` and in `docs/REGRESSION_TESTS.md`.
void main() {
  final calc = calcWith();
  final now = DateTime.utc(2026, 10, 13, 10, 30, 15);
  final start = DateTime.utc(2026, 10, 12, 22, 30);

  const settings = Settings(
    currency: 'PLN',
    pricePerKwh: 1.15,
    efficiency: 0.85,
    designCapacityMah: 4000,
    designCapacitySource: DesignCapacitySource.localDeviceDatabase,
  );

  String export({
    List<DailyData> days = const [],
    List<ChargingSession> sessions = const [],
    EnergyCalc? useCalc,
    Settings s = settings,
    DateTime? at,
  }) =>
      Exporter.json(
          days: days,
          sessions: sessions,
          calc: useCalc ?? calc,
          settings: s,
          now: at ?? now);

  Map<String, dynamic> decode(String text) =>
      jsonDecode(text) as Map<String, dynamic>;

  group('structure and validity', () {
    test('an empty export is valid JSON with empty collections', () {
      final text = export();
      final j = decode(text);
      expect(j.keys, ['app', 'exportedAt', 'settings', 'data', 'charging']);
      expect(j['app'], 'WattByte');
      expect(j['data'], isEmpty);
      expect(j['charging'], isEmpty);
      expect(j['settings'], isNotEmpty,
          reason: 'the settings block is there even without data');
    });

    test('one day and one session decode to exactly what was exported', () {
      final j = decode(export(days: [
        DailyData(
            day: DateTime(2026, 10, 12),
            mobileRx: 1000,
            mobileTx: 200,
            wifiRx: 30000,
            wifiTx: 4000,
            estimated: true),
      ], sessions: [
        sessionAt(start, chargeUah: 2500000, energyNwh: 9500000000)
      ]));
      expect(j['data'], [
        {
          'day': '2026-10-12',
          'mobileRxBytes': 1000,
          'mobileTxBytes': 200,
          'wifiRxBytes': 30000,
          'wifiTxBytes': 4000,
          'estimated': true,
        }
      ]);
      final session = (j['charging'] as List).single as Map<String, dynamic>;
      expect(session['start'], '2026-10-12T22:30:00.000Z');
      expect(session['end'], '2026-10-12T23:30:00.000Z');
      expect(session['startLevel'], 20);
      expect(session['endLevel'], 80);
      expect(session['chargeDeltaUah'], 2500000);
      expect(session['energyDeltaNwh'], 9500000000);
      expect(session['avgVoltageMv'], isNull);
      expect(session['sparse'], false);
      final energy = session['energy'] as Map<String, dynamic>;
      expect(energy['mah'], 2500);
      expect(energy['mahEstimated'], false);
      expect(energy['batteryWh'], 9.5);
      expect(energy['whEstimated'], false);
      expect(energy['wallWh'], closeTo(9.5 / 0.85, 1e-12));
      expect(energy['wallKwh'], closeTo(9.5 / 0.85 / 1000, 1e-15));
      expect(energy['cost'], closeTo(9.5 / 0.85 / 1000 * 1.15, 1e-15));
    });

    test('many records: 4000 days and 4000 sessions decode, in order', () {
      final text = export(days: [
        for (var i = 0; i < 4000; i++)
          DailyData(day: DateTime(2015, 1, 1 + i), mobileRx: i)
      ], sessions: [
        for (var i = 0; i < 4000; i++)
          sessionAt(start.add(Duration(hours: i)), from: i % 50, to: 50)
      ]);
      final j = decode(text);
      expect(j['data'], hasLength(4000));
      expect(j['charging'], hasLength(4000));
      expect(((j['data'] as List).last as Map)['mobileRxBytes'], 3999);
      expect(((j['charging'] as List)[1] as Map)['start'],
          '2026-10-12T23:30:00.000Z');
    });

    test('the document is stable: exporting twice gives the same text', () {
      final days = [DailyData(day: DateTime(2026, 10, 12), mobileRx: 7)];
      final sessions = [sessionAt(start)];
      expect(export(days: days, sessions: sessions),
          export(days: days, sessions: sessions));
    });
  });

  group('number types', () {
    test('ints stay ints, doubles stay doubles, null stays null', () {
      final j = decode(export(
          days: [DailyData(day: DateTime(2026, 10, 12), wifiRx: 5)],
          sessions: [sessionAt(start)]));
      final day = (j['data'] as List).single as Map;
      for (final k in ['mobileRxBytes', 'mobileTxBytes', 'wifiRxBytes']) {
        expect(day[k], isA<int>(), reason: k);
      }
      final s = (j['charging'] as List).single as Map;
      expect(s['startLevel'], isA<int>());
      expect(s['endLevel'], isA<int>());
      expect(s.containsKey('chargeDeltaUah'), isTrue,
          reason: 'null is written, not omitted');
      expect(s['chargeDeltaUah'], isNull);
      expect(s['energyDeltaNwh'], isNull);
      expect(s['avgVoltageMv'], isNull);
      final energy = s['energy'] as Map;
      for (final k in ['mah', 'batteryWh', 'wallWh', 'wallKwh', 'cost']) {
        expect(energy[k], isA<double>(), reason: k);
      }
      expect(energy['mahEstimated'], isA<bool>());
      final settings = j['settings'] as Map;
      expect(settings['pricePerKwh'], isA<double>());
      expect(settings['designCapacityMah'], isA<double>());
      expect(settings['estimateCapacityMah'], isA<double>());
      expect(settings['currency'], isA<String>());
    });

    test('64-bit counters are written as exact integers', () {
      const big = 9007199254740993; // 2^53 + 1
      final j = decode(export(
          days: [DailyData(day: DateTime(2026, 10, 12), mobileRx: big)]));
      expect(((j['data'] as List).single as Map)['mobileRxBytes'], big);
    });

    test('plain decimals for every realistic value, whatever the locale', () {
      final previous = Intl.defaultLocale;
      addTearDown(() => Intl.defaultLocale = previous);
      for (final locale in ['pl_PL', 'de_DE', 'en_US']) {
        Intl.defaultLocale = locale;
        final text = export(sessions: [
          for (var i = 0; i < 300; i++)
            sessionAt(start.add(Duration(days: i)),
                from: i % 90, to: (i % 90) + 1 + i % 9)
        ]);
        expect(text, isNot(matches(RegExp(r'\d[eE][+-]?\d'))),
            reason: 'no exponent notation ($locale)');
        expect(text, isNot(matches(RegExp(r'\d,\d'))),
            reason: 'no decimal comma ($locale)');
        expect(text.toLowerCase(), isNot(contains('nan')));
        expect(text.toLowerCase(), isNot(contains('infinity')));
        decode(text);
      }
    });

    test('very large values stay plain numbers and valid JSON', () {
      final j = decode(export(
          sessions: [sessionAt(start, from: 0, to: 100)],
          useCalc: calcWith(
              capacityMah: 30000, voltage: 5, efficiency: 0.01, price: 1000)));
      final energy = ((j['charging'] as List).single as Map)['energy'] as Map;
      expect(energy['wallWh'], closeTo(15000, 1e-6));
      expect(energy['cost'], closeTo(15000, 1e-6));
    });

    test(
        'a vanishingly small value is still valid JSON (exponent form is '
        'only possible below 1e-6)', () {
      final text = export(
          sessions: [sessionAt(start, from: 0, to: 1)],
          useCalc: calcWith(capacityMah: 0.001, price: 0.0001));
      final energy =
          ((decode(text)['charging'] as List).single as Map)['energy'] as Map;
      expect(energy['wallKwh'], isA<double>());
      expect(energy['wallKwh'] as double, lessThan(1e-6));
      expect(energy['wallKwh'] as double, greaterThan(0));
    });

    test('NaN and Infinity become null instead of making the export fail', () {
      final text = export(
          sessions: [sessionAt(start)],
          useCalc: _FixedCalc(const SessionEnergy(
              mah: double.nan,
              mahEstimated: true,
              batteryWh: double.infinity,
              whEstimated: true,
              wallWh: double.negativeInfinity,
              cost: double.nan)));
      final energy =
          ((decode(text)['charging'] as List).single as Map)['energy'] as Map;
      for (final k in ['mah', 'batteryWh', 'wallWh', 'wallKwh', 'cost']) {
        expect(energy.containsKey(k), isTrue, reason: k);
        expect(energy[k], isNull, reason: k);
      }
      expect(energy['mahEstimated'], true, reason: 'flags are untouched');
      expect(text.toLowerCase(), isNot(contains('nan')));
      expect(text.toLowerCase(), isNot(contains('infinity')));
    });

    test('negative zero is written as 0.0', () {
      final text = export(
          sessions: [sessionAt(start)],
          useCalc: _FixedCalc(const SessionEnergy(
              mah: -0.0,
              mahEstimated: true,
              batteryWh: -0.0,
              whEstimated: true,
              wallWh: -0.0,
              cost: -0.0)));
      expect(text, isNot(contains(': -0')));
      final energy =
          ((decode(text)['charging'] as List).single as Map)['energy'] as Map;
      for (final k in ['mah', 'batteryWh', 'wallWh', 'wallKwh', 'cost']) {
        expect(energy[k], 0.0, reason: k);
        expect((energy[k] as double).isNegative, isFalse, reason: k);
      }
    });

    test('settings that are 0 because they are unknown are null, not 0', () {
      final unknownCalc = EnergyCalc(
          batteryCapacityMah: 0,
          nominalVoltage: 3.85,
          efficiency: 0.85,
          pricePerKwh: 0);
      final j = decode(export(
          s: const Settings(currency: 'PLN'),
          useCalc: unknownCalc,
          sessions: [sessionAt(start)]));
      final s = j['settings'] as Map;
      expect(s['pricePerKwh'], isNull);
      expect(s['designCapacityMah'], isNull);
      expect(s['designCapacitySource'], 'unknown');
      expect(s['estimateCapacityMah'], isNull);
      expect(s['estimateCapacityBasis'], isNull);
      expect(s['chargingEfficiency'], 0.85);
      expect(s['nominalVoltage'], 3.85);
      final energy = ((j['charging'] as List).single as Map)['energy'] as Map;
      for (final k in ['mah', 'batteryWh', 'wallWh', 'wallKwh', 'cost']) {
        expect(energy[k], isNull, reason: '$k is unknown, not 0');
      }
      expect(energy['mahEstimated'], true);
    });
  });

  group('two capacities, never one: design versus the estimate basis', () {
    Map<String, dynamic> settingsOf(String text) =>
        decode(text)['settings'] as Map<String, dynamic>;

    /// The export of [s] with the calculator the app builds from it.
    String exportOf(Settings s, {double estimatedFullChargeMah = 0}) => export(
        s: s,
        useCalc: s.energyCalc(
            estimatedFullChargeCapacityMah: estimatedFullChargeMah),
        sessions: [sessionAt(start)]);

    test('a known design capacity is the design and the estimate basis', () {
      for (final source in [
        DesignCapacitySource.manufacturerSpecification,
        DesignCapacitySource.localDeviceDatabase,
        DesignCapacitySource.backendDeviceDatabase,
        DesignCapacitySource.manual,
      ]) {
        final s = settingsOf(exportOf(Settings(
            currency: 'PLN',
            designCapacityMah: 4575,
            designCapacitySource: source)));
        expect(s['designCapacityMah'], 4575.0, reason: source.name);
        expect(s['designCapacitySource'], source.name);
        expect(s['estimateCapacityMah'], 4575.0, reason: source.name);
        expect(s['estimateCapacityBasis'], 'design', reason: source.name);
      }
    });

    test('a design capacity always wins over the estimate for the basis', () {
      final s = settingsOf(exportOf(
          const Settings(
              currency: 'PLN',
              designCapacityMah: 4000,
              designCapacitySource: DesignCapacitySource.localDeviceDatabase),
          estimatedFullChargeMah: 3600));
      expect(s['designCapacityMah'], 4000.0);
      expect(s['estimateCapacityMah'], 4000.0);
      expect(s['estimateCapacityBasis'], 'design');
      expect(s.values, isNot(contains(3600.0)),
          reason: 'the estimate that was not used is not exported at all');
    });

    test(
        'only an estimate: the basis says estimatedFullCharge and the design '
        'capacity stays null, it is never labelled as design', () {
      final s = settingsOf(exportOf(const Settings(currency: 'PLN'),
          estimatedFullChargeMah: 3600));
      expect(s['designCapacityMah'], isNull);
      expect(s['designCapacitySource'], 'unknown');
      expect(s['estimateCapacityMah'], 3600.0);
      expect(s['estimateCapacityBasis'], 'estimatedFullCharge');
    });

    test(
        'Android charge counter != design capacity: a reliable reading is an '
        'estimate in the export, never the design capacity', () {
      // 100 % full with 4321 mAh stored: the most trustworthy reading there is.
      final estimate =
          FullChargeCapacityEstimator.estimate(chargeUah: 4321000, level: 100);
      expect(estimate.confidence, FullChargeCapacityConfidence.high);
      final text = exportOf(const Settings(currency: 'PLN'),
          estimatedFullChargeMah: estimate.mah!);
      final s = settingsOf(text);
      expect(s['designCapacityMah'], isNull);
      expect(s['designCapacitySource'], 'unknown');
      expect(s['estimateCapacityMah'], 4321.0);
      expect(s['estimateCapacityBasis'], 'estimatedFullCharge');
      expect([
        for (final e in s.entries)
          if (e.value == 4321.0) e.key
      ], [
        'estimateCapacityMah'
      ]);
      for (final key in s.keys.where((k) => k.startsWith('design'))) {
        expect(s[key], anyOf(isNull, 'unknown'), reason: key);
      }
    });

    test('nothing known: the design is unknown and no estimate basis is named',
        () {
      for (final s in [
        settingsOf(exportOf(const Settings())),
        settingsOf(export(
            s: const Settings(),
            useCalc: const Settings().energyCalc(),
            sessions: [sessionAt(start)])),
      ]) {
        expect(s['designCapacityMah'], isNull);
        expect(s['designCapacitySource'], 'unknown');
        expect(s['estimateCapacityMah'], isNull);
        expect(s['estimateCapacityBasis'], isNull);
      }
    });

    test('the retired capacity keys are gone from the export', () {
      final s = settingsOf(exportOf(settings));
      for (final key in [
        'batteryCapacityMah',
        'batteryCapacityWh',
        'capacitySource',
        'batterySpecificationSource',
      ]) {
        expect(s.containsKey(key), isFalse, reason: key);
      }
      expect(s.keys.where((k) => k.contains('apacity')).toList(), [
        'designCapacityMah',
        'designCapacitySource',
        'estimateCapacityMah',
        'estimateCapacityBasis',
      ]);
    });

    test('the design source is always one of the design sources', () {
      final names = {for (final v in DesignCapacitySource.values) v.name};
      for (final source in DesignCapacitySource.values) {
        final s = settingsOf(exportOf(Settings(
            currency: 'PLN',
            designCapacityMah:
                source == DesignCapacitySource.unknown ? 0 : 4000,
            designCapacitySource: source)));
        expect(names, contains(s['designCapacitySource']));
        expect(s['designCapacitySource'], isNot('androidChargeCounter'));
        expect(s['designCapacitySource'], isNot('estimatedFullCharge'));
      }
    });

    test('NaN, Infinity and negative capacities are null, never exported', () {
      // Settings are sanitized when the app loads them; the exporter must hold
      // up even when handed one that was not (the calculator is built apart:
      // a real EnergyCalc refuses these values).
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -4000.0,
        0.0,
        -0.0,
      ]) {
        final text = export(
            s: Settings(
                currency: 'PLN',
                designCapacityMah: bad,
                designCapacityWh: bad,
                designCapacitySource: DesignCapacitySource.localDeviceDatabase),
            sessions: [sessionAt(start)]);
        final s = settingsOf(text);
        expect(s['designCapacityMah'], isNull, reason: '$bad');
        expect(s['designCapacitySource'], 'unknown', reason: '$bad');
        expect(s['estimateCapacityBasis'], isNot('design'),
            reason: '$bad is no design capacity');
        expect(text.toLowerCase(), isNot(contains('nan')), reason: '$bad');
        expect(text.toLowerCase(), isNot(contains('infinity')), reason: '$bad');
      }
    });

    test('a calculator capacity that is not a number is null, not NaN', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity
      ]) {
        final text = export(
            s: const Settings(currency: 'PLN'),
            useCalc: _FixedCalc(
                const SessionEnergy(
                    mah: 1,
                    mahEstimated: true,
                    batteryWh: 1,
                    whEstimated: true,
                    wallWh: 1,
                    cost: 1),
                capacityMah: bad),
            sessions: [sessionAt(start)]);
        final s = settingsOf(text);
        expect(s['estimateCapacityMah'], isNull, reason: '$bad');
        expect(s['designCapacityMah'], isNull, reason: '$bad');
        expect(text.toLowerCase(), isNot(contains('nan')), reason: '$bad');
        expect(text.toLowerCase(), isNot(contains('infinity')), reason: '$bad');
      }
    });
  });

  group('dates and times', () {
    test('exportedAt is UTC ISO-8601 with Z, from a UTC or a local instant',
        () {
      expect(decode(export(at: now))['exportedAt'], '2026-10-13T10:30:15.000Z');
      final local = DateTime(2026, 3, 29, 1, 30, 15); // clock-change night
      final stamp = decode(export(at: local))['exportedAt'] as String;
      expect(stamp, endsWith('Z'));
      expect(DateTime.parse(stamp).isAtSameMomentAs(local), isTrue);
    });

    test('session instants are UTC with Z; days are local calendar keys', () {
      final local = DateTime(2026, 10, 25, 2, 30); // ambiguous local hour
      final j = decode(export(days: [
        DailyData(day: DateTime(2026, 10, 25)),
        DailyData(day: DateTime(2026, 3, 29)),
      ], sessions: [
        sessionAt(local, length: const Duration(hours: 2)),
      ]));
      expect((j['data'] as List).map((d) => (d as Map)['day']),
          ['2026-10-25', '2026-03-29']);
      final s = (j['charging'] as List).single as Map;
      expect(s['start'], endsWith('Z'));
      expect(s['end'], endsWith('Z'));
      expect(DateTime.parse(s['start']).isAtSameMomentAs(local), isTrue);
      expect(
          DateTime.parse(s['end'])
              .difference(DateTime.parse(s['start']))
              .inMinutes,
          120);
    });
  });

  group('settings block: no account data', () {
    const everything = Settings(
      currency: 'PLN',
      currencySource: SettingSource.manual,
      countryCode: 'PL',
      regionSource: SettingSource.detected,
      pricePerKwh: 1.15,
      priceMode: ElectricityPriceMode.manual,
      manualPricePerKwh: 1.15,
      efficiency: 0.9,
      designCapacityMah: 4000,
      designCapacityWh: 15.4,
      designCapacitySource: DesignCapacitySource.localDeviceDatabase,
      deviceModel: 'iPhone 17 Pro',
      deviceModelIdentifier: 'iPhone18,1',
      cloudSync: true,
      onboarded: true,
    );

    test('exactly the values the numbers were computed from', () {
      final j =
          decode(export(s: everything, useCalc: calcWith(efficiency: 0.9)));
      expect(j['settings'], {
        'currency': 'PLN',
        'pricePerKwh': 1.15,
        'chargingEfficiency': 0.9,
        // The nominal capacity of the phone model and where it came from ...
        'designCapacityMah': 4000.0,
        'designCapacitySource': 'localDeviceDatabase',
        // ... apart from the capacity the `% -> mAh` estimate used.
        'estimateCapacityMah': 4000.0,
        'estimateCapacityBasis': 'design',
        'nominalVoltage': 3.85,
      });
    });

    test('no e-mail, token, id, device, region or sync state is exported', () {
      final text = export(
          s: everything,
          days: [DailyData(day: DateTime(2026, 10, 12))],
          sessions: [sessionAt(start)]);
      for (final forbidden in [
        '@',
        'mail',
        'token',
        'password',
        'secret',
        'bearer',
        'refresh',
        'access',
        'session_id',
        'userId',
        'installation',
        'iPhone',
        'deviceModel',
        'countryCode',
        'cloudSync',
        'regionSource',
      ]) {
        expect(text.toLowerCase(), isNot(contains(forbidden.toLowerCase())),
            reason: forbidden);
      }
      // The only top-level keys: nothing account-shaped can sneak in.
      expect(decode(text).keys,
          ['app', 'exportedAt', 'settings', 'data', 'charging']);
    });
  });

  group('text and encoding', () {
    test('quotes, backslashes, newlines and control characters are escaped',
        () {
      for (final currency in [
        'P"LN',
        r'P\LN',
        'P\nLN',
        'P\r\nLN',
        'P\tLN',
        'P\u0000LN',
        'P\u001fLN',
        '</script>',
        '{"a":1}',
      ]) {
        final j = decode(export(s: Settings(currency: currency)));
        expect((j['settings'] as Map)['currency'], currency);
      }
    });

    test('Polish letters, emoji and other Unicode round-trip unchanged', () {
      for (final currency in [
        'ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ',
        'zł',
        '€',
        '💶',
        '👨‍👩‍👧',
        '日本語',
        'é',
      ]) {
        final text = export(s: Settings(currency: currency));
        expect(decode(text)['settings']['currency'], currency);
        final bytes = utf8.encode(text);
        expect(utf8.decode(bytes), text);
        expect(decode(utf8.decode(bytes))['settings']['currency'], currency);
      }
    });

    test('the bytes are UTF-8 without a byte-order mark', () {
      final text = export(s: const Settings(currency: 'zł'));
      final bytes = utf8.encode(text);
      expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
      expect(text.codeUnitAt(0), 0x7B, reason: 'starts with {');
      // jsonDecode of the raw bytes works the way a consumer would read the file.
      expect(jsonDecode(utf8.decode(bytes)), isA<Map>());
    });

    test('what the app writes to disk (File.writeAsString) reads back',
        () async {
      final dir = await Directory.systemTemp.createTemp('wb_export_json_');
      addTearDown(() => dir.delete(recursive: true));
      final text = export(
          s: const Settings(currency: 'zł 💶'),
          days: [DailyData(day: DateTime(2026, 10, 12), mobileRx: 1)],
          sessions: [sessionAt(start)]);
      final file = File('${dir.path}/wattbyte.json');
      await file.writeAsString(text);
      final bytes = await file.readAsBytes();
      expect(bytes, utf8.encode(text));
      expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
      final j = decode(utf8.decode(bytes));
      expect((j['settings'] as Map)['currency'], 'zł 💶');
    });
  });
}

/// A calculator whose session energy is whatever the test says, to reach the
/// exporter's own guards (the real [EnergyCalc] validates and throws long
/// before a NaN could get this far).
class _FixedCalc extends Fake implements EnergyCalc {
  _FixedCalc(this.energy, {this.capacityMah = 4000});

  final SessionEnergy energy;
  final double capacityMah;

  @override
  SessionEnergy session(ChargingSession s) => energy;

  @override
  double get pricePerKwh => 1.15;

  @override
  double get batteryCapacityMah => capacityMah;

  @override
  double get nominalVoltage => 3.85;

  @override
  double get efficiency => 0.85;

  @override
  bool get canEstimateFromPercent => true;
}
