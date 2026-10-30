// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';

/// Locale-aware bytes, energy, charge, percent, duration and plain numbers, for
/// the two languages the app ships (pl, en) plus the locale-tag handling.
///
/// pl groups thousands with a NO-BREAK SPACE (U+00A0), written `$nb` below.
const nb = '\u00A0';

void main() {
  const pl = Units(locale: 'pl');
  const en = Units(locale: 'en');
  const plBinary = Units(locale: 'pl', binary: true);
  const enBinary = Units(locale: 'en', binary: true);

  /// One row: the input and what Polish and English must print.
  void table<T>(
    String name,
    String Function(Units, T) format,
    List<(T, String, String)> rows,
  ) {
    test(name, () {
      for (final (input, expectedPl, expectedEn) in rows) {
        expect(format(pl, input), expectedPl, reason: 'pl: $input');
        expect(format(en, input), expectedEn, reason: 'en: $input');
      }
    });
  }

  group('bytes (decimal)', () {
    table<num>('picks MB / GB / TB, never below MB', (u, v) => u.bytes(v), [
      (0, '0,00 MB', '0.00 MB'),
      (12, '0,00 MB', '0.00 MB'),
      (1500000, '1,50 MB', '1.50 MB'),
      (999000000, '999,0 MB', '999.0 MB'),
      (2840000000, '2,84 GB', '2.84 GB'),
      (21440000000, '21,44 GB', '21.44 GB'),
      (123456000000, '123,5 GB', '123.5 GB'),
      (1234000000000, '1,23 TB', '1.23 TB'),
      (-5000000, '-5,00 MB', '-5.00 MB'),
    ]);

    table<num>('a value that rounds up to the next unit moves to it', (u, v) {
      return u.bytes(v);
    }, [
      (999996000, '1,00 GB', '1.00 GB'),
      (999996000000, '1,00 TB', '1.00 TB'),
    ]);

    table<num>('thousands of TB are grouped by the locale', (u, v) {
      return u.bytes(v);
    }, [
      (999999999999999, '1${nb}000,0 TB', '1,000.0 TB'),
    ]);
  });

  group('bytes (binary)', () {
    test('KiB/MiB/GiB with 1024 steps and the same separators', () {
      expect(plBinary.bytes(1073741824), '1,00 GiB');
      expect(enBinary.bytes(1073741824), '1.00 GiB');
      expect(plBinary.bytes(1572864), '1,50 MiB');
      expect(enBinary.bytes(1572864), '1.50 MiB');
      expect(enBinary.bytes(1024 * 1024 * 1024 * 1024 * 3), '3.00 TiB');
      // 1,000,000 bytes are 0.95 MiB but 1.00 MB: the setting decides.
      expect(enBinary.bytes(1000000), '0.95 MiB');
      expect(en.bytes(1000000), '1.00 MB');
    });

    test('rounding up into the next binary unit', () {
      // 1023.996 MiB prints as 1,024.0 MiB without the carry.
      expect(enBinary.bytes((1023.996 * 1024 * 1024).round()), '1.00 GiB');
    });
  });

  group('energy and charge', () {
    table<double>('Wh: one decimal below 100, none from 100', (u, v) {
      return u.wh(v);
    }, [
      (0.0, '0,0 Wh', '0.0 Wh'),
      (5.0, '5,0 Wh', '5.0 Wh'),
      (15.2, '15,2 Wh', '15.2 Wh'),
      (99.96, '100 Wh', '100 Wh'),
      (100.0, '100 Wh', '100 Wh'),
      (1234.5, '1${nb}235 Wh', '1,235 Wh'),
      (-0.04, '0,0 Wh', '0.0 Wh'),
    ]);

    table<double>('kWh from Wh: two to four decimals by magnitude', (u, v) {
      return u.kwh(v);
    }, [
      (0.0, '0,00 kWh', '0.00 kWh'),
      (0.04, '<0,0001 kWh', '<0.0001 kWh'),
      (0.06, '0,0001 kWh', '0.0001 kWh'),
      (15.2, '0,0152 kWh', '0.0152 kWh'),
      (152.0, '0,152 kWh', '0.152 kWh'),
      (999.9, '0,9999 kWh', '0.9999 kWh'),
      (999.96, '1,00 kWh', '1.00 kWh'),
      (1200.0, '1,20 kWh', '1.20 kWh'),
      (1230.0, '1,23 kWh', '1.23 kWh'),
      (12345.6, '12,35 kWh', '12.35 kWh'),
      (123456.0, '123,46 kWh', '123.46 kWh'),
      (1234567.0, '1${nb}234,57 kWh', '1,234.57 kWh'),
      (-1230.0, '-1,23 kWh', '-1.23 kWh'),
    ]);

    table<double>('mAh: whole numbers, grouped', (u, v) => u.mah(v), [
      (0.0, '0 mAh', '0 mAh'),
      (850.0, '850 mAh', '850 mAh'),
      (3920.4, '3${nb}920 mAh', '3,920 mAh'),
      (12345.0, '12${nb}345 mAh', '12,345 mAh'),
      (-0.2, '0 mAh', '0 mAh'),
    ]);
  });

  group('percent, duration, plain numbers', () {
    table<num>('percent follows the locale pattern', (u, v) => u.percent(v), [
      (0, '0%', '0%'),
      (0.4, '0%', '0%'),
      (85, '85%', '85%'),
      (85.5, '86%', '86%'),
      (100, '100%', '100%'),
      (123456, '123${nb}456%', '123,456%'),
      (-3, '-3%', '-3%'),
    ]);

    test('percent spacing is the locale\'s, not a hardcoded "%"', () {
      // German writes "85 %" with a no-break space; the same code path serves it.
      expect(const Units(locale: 'de_DE').percent(85), '85$nb%');
    });

    table<Duration>('duration: h and min symbols, localized numbers',
        (u, v) => u.duration(v), [
      (Duration.zero, '0 min', '0 min'),
      (const Duration(seconds: 59), '0 min', '0 min'),
      (const Duration(minutes: 45), '45 min', '45 min'),
      (const Duration(minutes: 81), '1 h 21 min', '1 h 21 min'),
      (const Duration(minutes: -81), '-1 h 21 min', '-1 h 21 min'),
      (
        const Duration(hours: 1234, minutes: 5),
        '1${nb}234 h 5 min',
        '1,234 h 5 min'
      ),
    ]);

    table<(num, int)>('number(value, decimals)', (u, v) {
      return u.number(v.$1, v.$2);
    }, [
      ((1234.5, 2), '1${nb}234,50', '1,234.50'),
      ((1.15, 2), '1,15', '1.15'),
      ((3, 0), '3', '3'),
      ((3, -1), '3', '3'),
      ((-0.001, 2), '0,00', '0.00'),
      ((-0.0, 1), '0,0', '0.0'),
    ]);

    test('approx marks estimates and leaves non-numbers alone', () {
      expect(en.approx('15.2 Wh', estimated: true), '~15.2 Wh');
      expect(en.approx('15.2 Wh', estimated: false), '15.2 Wh');
      expect(en.approx(Units.placeholder, estimated: true), Units.placeholder);
      expect(en.approx('<0.001', estimated: true), '<0.001');
    });
  });

  group('non-finite and absurd input never reaches the screen', () {
    final bad = <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e300,
      -1e300,
    ];

    test('every formatter returns the placeholder', () {
      for (final locale in ['pl_PL', 'en_US', 'xx_YY', '']) {
        final u = Units(locale: locale);
        for (final v in bad) {
          expect(u.bytes(v), Units.placeholder, reason: '$locale bytes $v');
          expect(u.wh(v), Units.placeholder, reason: '$locale wh $v');
          expect(u.kwh(v), Units.placeholder, reason: '$locale kwh $v');
          expect(u.mah(v), Units.placeholder, reason: '$locale mah $v');
          expect(u.percent(v), Units.placeholder, reason: '$locale % $v');
          expect(u.number(v, 2), Units.placeholder, reason: '$locale n $v');
          expect(u.money(v, 'PLN'), Units.placeholder, reason: '$locale \$ $v');
        }
      }
    });

    test('no output contains NaN, Infinity or null', () {
      final all = <String>[
        for (final u in [pl, en, plBinary, enBinary])
          for (final v in bad) ...[
            u.bytes(v),
            u.wh(v),
            u.kwh(v),
            u.mah(v),
            u.percent(v),
            u.number(v, 3),
            u.money(v, 'PLN'),
            u.money(v, ''),
          ],
      ];
      for (final s in all) {
        expect(s, isNot(contains('NaN')));
        expect(s, isNot(contains('Infinity')));
        expect(s, isNot(contains('∞')));
        expect(s, isNot(contains('null')));
      }
    });

    test('a large but real value still prints', () {
      expect(en.bytes(5e14), '500.0 TB');
      expect(en.money(999999999999.0, 'USD'), '\$999,999,999,999.00');
    });
  });

  group('locale tags', () {
    test('formatLocaleFor keeps what intl knows and falls back to English', () {
      expect(Units.formatLocaleFor('pl_PL'), 'pl');
      expect(Units.formatLocaleFor('pl-PL'), 'pl');
      expect(Units.formatLocaleFor('pl'), 'pl');
      expect(Units.formatLocaleFor('en_PL'), 'en');
      expect(Units.formatLocaleFor('en-GB'), 'en_GB');
      expect(Units.formatLocaleFor('de_DE'),
          'de'); // intl has no de_DE data, de is it
      for (final bad in [null, '', '   ', 'xx_YY', 'x', '!!', 'zz-ZZ']) {
        expect(Units.formatLocaleFor(bad), 'en', reason: '"$bad"');
      }
    });

    test('an invalid locale formats in English instead of throwing', () {
      for (final bad in ['xx_YY', '', 'x', '!!', ' ']) {
        final u = Units(locale: bad);
        expect(u.bytes(1500000), '1.50 MB', reason: '"$bad"');
        expect(u.kwh(1230), '1.23 kWh', reason: '"$bad"');
        expect(u.percent(85), '85%', reason: '"$bad"');
        expect(u.duration(const Duration(minutes: 81)), '1 h 21 min');
        expect(u.money(12.5, 'USD'), '\$12.50', reason: '"$bad"');
      }
    });

    test('Polish with any region and English with a Polish region', () {
      // pl_PL is Polish; en_PL is English with Polish *region*: intl has no
      // en_PL data and the app has no English-Poland text, so it reads as en.
      for (final v in [0.5, 1234.5, 987654.321]) {
        expect(const Units(locale: 'pl_PL').number(v, 2), pl.number(v, 2));
        expect(const Units(locale: 'pl-PL').number(v, 2), pl.number(v, 2));
        expect(const Units(locale: 'en_PL').number(v, 2), en.number(v, 2));
        expect(
            const Units(locale: 'en_PL').money(v, 'PLN'), en.money(v, 'PLN'));
      }
      expect(const Units(locale: 'en_PL').bytes(2840000000), '2.84 GB');
      expect(const Units(locale: 'pl_PL').bytes(2840000000), '2,84 GB');
    });

    test('resolveAppLocale: the language the UI resolves a device tag to', () {
      const expected = {
        'pl': 'pl',
        'pl_PL': 'pl',
        'pl-PL': 'pl',
        'PL': 'pl',
        'pl_US': 'pl',
        'en': 'en',
        'en_PL': 'en',
        'en-GB': 'en',
        'EN_us': 'en',
        'de_DE': 'en',
        'fr': 'en',
        'zh_Hant_TW': 'en',
        '': 'en',
        '  ': 'en',
        '!!': 'en',
      };
      expected.forEach((tag, language) {
        expect(Units.resolveAppLocale(tag), language, reason: '"$tag"');
      });
      expect(Units.resolveAppLocale(null), 'en');
      expect(Units.supportedLanguages, ['en', 'pl']);
    });
  });
}
