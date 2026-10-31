// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:wattbyte/core/units.dart';

/// Locale-aware money formatting, table driven. Every string below is exact.
///
/// `intl` separates number and currency (pl: `12,50 zł`) and groups thousands
/// (pl: `1 234,50`) with a NO-BREAK SPACE, U+00A0, never with a plain space.
/// The tables spell it `$nb` so a plain-space regression fails visibly.
const nb = '\u00A0';

/// The amounts every table covers: zero, a sub-grosz cost that must not
/// collapse (0.021, 0.004), a half, ordinary and large values, negatives.
/// 0.0004 is the one amount too small for three decimals.
const amounts = <double>[
  0.0,
  0.0004,
  0.004,
  0.021,
  0.5,
  1.23,
  12.5,
  1234.5,
  123456.789,
  -0.021,
  -12.5,
];

/// (locale tag, currency) -> the text for each of [amounts].
final money = <(String, String), List<String>>{
  ('pl_PL', 'PLN'): [
    '0,00${nb}zł',
    '<0,001${nb}zł',
    '0,004${nb}zł',
    '0,021${nb}zł',
    '0,50${nb}zł',
    '1,23${nb}zł',
    '12,50${nb}zł',
    '1${nb}234,50${nb}zł',
    '123${nb}456,79${nb}zł',
    '-0,021${nb}zł',
    '-12,50${nb}zł',
  ],
  ('en_US', 'USD'): [
    '\$0.00',
    '<\$0.001',
    '\$0.004',
    '\$0.021',
    '\$0.50',
    '\$1.23',
    '\$12.50',
    '\$1,234.50',
    '\$123,456.79',
    '-\$0.021',
    '-\$12.50',
  ],
  ('en_PL', 'PLN'): [
    'zł${nb}0.00',
    '<zł${nb}0.001',
    'zł${nb}0.004',
    'zł${nb}0.021',
    'zł${nb}0.50',
    'zł${nb}1.23',
    'zł${nb}12.50',
    'zł${nb}1,234.50',
    'zł${nb}123,456.79',
    '-zł${nb}0.021',
    '-zł${nb}12.50',
  ],
  ('pl_PL', 'USD'): [
    '0,00$nb\$',
    '<0,001$nb\$',
    '0,004$nb\$',
    '0,021$nb\$',
    '0,50$nb\$',
    '1,23$nb\$',
    '12,50$nb\$',
    '1${nb}234,50$nb\$',
    '123${nb}456,79$nb\$',
    '-0,021$nb\$',
    '-12,50$nb\$',
  ],
  ('en_US', 'PLN'): [
    'zł${nb}0.00',
    '<zł${nb}0.001',
    'zł${nb}0.004',
    'zł${nb}0.021',
    'zł${nb}0.50',
    'zł${nb}1.23',
    'zł${nb}12.50',
    'zł${nb}1,234.50',
    'zł${nb}123,456.79',
    '-zł${nb}0.021',
    '-zł${nb}12.50',
  ],
  ('de_DE', 'EUR'): [
    '0,00$nb€',
    '<0,001$nb€',
    '0,004$nb€',
    '0,021$nb€',
    '0,50$nb€',
    '1,23$nb€',
    '12,50$nb€',
    '1.234,50$nb€',
    '123.456,79$nb€',
    '-0,021$nb€',
    '-12,50$nb€',
  ],
  ('en_GB', 'GBP'): [
    '£0.00',
    '<£0.001',
    '£0.004',
    '£0.021',
    '£0.50',
    '£1.23',
    '£12.50',
    '£1,234.50',
    '£123,456.79',
    '-£0.021',
    '-£12.50',
  ],
  ('cs_CZ', 'CZK'): [
    '0,00${nb}Kč',
    '<0,001${nb}Kč',
    '0,004${nb}Kč',
    '0,021${nb}Kč',
    '0,50${nb}Kč',
    '1,23${nb}Kč',
    '12,50${nb}Kč',
    '1${nb}234,50${nb}Kč',
    '123${nb}456,79${nb}Kč',
    '-0,021${nb}Kč',
    '-12,50${nb}Kč',
  ],
  ('en', 'CHF'): [
    'CHF${nb}0.00',
    '<CHF${nb}0.001',
    'CHF${nb}0.004',
    'CHF${nb}0.021',
    'CHF${nb}0.50',
    'CHF${nb}1.23',
    'CHF${nb}12.50',
    'CHF${nb}1,234.50',
    'CHF${nb}123,456.79',
    '-CHF${nb}0.021',
    '-CHF${nb}12.50',
  ],
  ('pl', 'CAD'): [
    '0,00${nb}CAD',
    '<0,001${nb}CAD',
    '0,004${nb}CAD',
    '0,021${nb}CAD',
    '0,50${nb}CAD',
    '1,23${nb}CAD',
    '12,50${nb}CAD',
    '1${nb}234,50${nb}CAD',
    '123${nb}456,79${nb}CAD',
    '-0,021${nb}CAD',
    '-12,50${nb}CAD',
  ],
  ('en', 'JPY'): [
    '¥0',
    '<¥0.001',
    '¥0.004',
    '¥0.021',
    '¥0.5',
    '¥1',
    '¥13',
    '¥1,235',
    '¥123,457',
    '-¥0.021',
    '-¥13',
  ],
  ('pl', 'pln'): [
    '0,00${nb}zł',
    '<0,001${nb}zł',
    '0,004${nb}zł',
    '0,021${nb}zł',
    '0,50${nb}zł',
    '1,23${nb}zł',
    '12,50${nb}zł',
    '1${nb}234,50${nb}zł',
    '123${nb}456,79${nb}zł',
    '-0,021${nb}zł',
    '-12,50${nb}zł',
  ],
  ('en', 'ZZZ'): [
    'ZZZ${nb}0.00',
    '<ZZZ${nb}0.001',
    'ZZZ${nb}0.004',
    'ZZZ${nb}0.021',
    'ZZZ${nb}0.50',
    'ZZZ${nb}1.23',
    'ZZZ${nb}12.50',
    'ZZZ${nb}1,234.50',
    'ZZZ${nb}123,456.79',
    '-ZZZ${nb}0.021',
    '-ZZZ${nb}12.50',
  ],
  ('pl', 'ZZZ'): [
    '0,00${nb}ZZZ',
    '<0,001${nb}ZZZ',
    '0,004${nb}ZZZ',
    '0,021${nb}ZZZ',
    '0,50${nb}ZZZ',
    '1,23${nb}ZZZ',
    '12,50${nb}ZZZ',
    '1${nb}234,50${nb}ZZZ',
    '123${nb}456,79${nb}ZZZ',
    '-0,021${nb}ZZZ',
    '-12,50${nb}ZZZ',
  ],
  ('en', ''): [
    '0.00',
    '<0.001',
    '0.004',
    '0.021',
    '0.50',
    '1.23',
    '12.50',
    '1,234.50',
    '123,456.79',
    '-0.021',
    '-12.50',
  ],
  ('pl', ''): [
    '0,00',
    '<0,001',
    '0,004',
    '0,021',
    '0,50',
    '1,23',
    '12,50',
    '1${nb}234,50',
    '123${nb}456,79',
    '-0,021',
    '-12,50',
  ],
  ('xx_YY', 'PLN'): [
    'zł${nb}0.00',
    '<zł${nb}0.001',
    'zł${nb}0.004',
    'zł${nb}0.021',
    'zł${nb}0.50',
    'zł${nb}1.23',
    'zł${nb}12.50',
    'zł${nb}1,234.50',
    'zł${nb}123,456.79',
    '-zł${nb}0.021',
    '-zł${nb}12.50',
  ],
};

void main() {
  group('Units.money table', () {
    money.forEach((key, expected) {
      final (locale, currency) = key;
      test('$locale / ${currency.isEmpty ? '(no currency)' : currency}', () {
        final u = Units(locale: locale);
        expect(expected, hasLength(amounts.length));
        for (var i = 0; i < amounts.length; i++) {
          expect(u.money(amounts[i], currency), expected[i],
              reason: 'money(${amounts[i]}, "$currency") in $locale');
        }
      });
    });
  });

  group('issue examples', () {
    test('Polish zloty in Polish and US dollars in English', () {
      expect(const Units(locale: 'pl_PL').money(0.02, 'PLN'), '0,02${nb}zł');
      expect(const Units(locale: 'en_US').money(0.02, 'USD'), '\$0.02');
    });

    test('a charging cost of 0.021 PLN is not rounded to 0.02', () {
      expect(const Units(locale: 'pl_PL').money(0.021, 'PLN'), '0,021${nb}zł');
      expect(const Units(locale: 'en_US').money(0.021, 'USD'), '\$0.021');
    });

    test('kWh follows the locale: 1,23 in Polish, 1.23 in English', () {
      expect(const Units(locale: 'pl_PL').kwh(1230), '1,23 kWh');
      expect(const Units(locale: 'en_US').kwh(1230), '1.23 kWh');
    });
  });

  group('precision rule', () {
    const pl = Units(locale: 'pl');

    test('currency decimals from 1 up, up to three below 1', () {
      expect(pl.money(1, 'PLN'), '1,00${nb}zł');
      expect(pl.money(0.9996, 'PLN'), '1,00${nb}zł');
      expect(pl.money(0.999, 'PLN'), '0,999${nb}zł');
      expect(pl.money(0.5, 'PLN'), '0,50${nb}zł'); // not 0,500
      expect(pl.money(0.1234, 'PLN'), '0,123${nb}zł');
    });

    test('a non-zero amount never prints as zero', () {
      expect(pl.money(0.0005, 'PLN'), '0,001${nb}zł');
      expect(pl.money(0.00049, 'PLN'), '<0,001${nb}zł');
      expect(pl.money(1e-9, 'PLN'), '<0,001${nb}zł');
      expect(pl.money(-1e-9, 'PLN'), '>-0,001${nb}zł');
      expect(pl.money(0, 'PLN'), '0,00${nb}zł');
      expect(pl.money(-0.0, 'PLN'), '0,00${nb}zł');
    });

    test('approx() leaves "less than" text alone', () {
      expect(pl.approx(pl.money(0.00001, 'PLN'), estimated: true),
          '<0,001${nb}zł');
      expect(
          pl.approx(pl.money(0.021, 'PLN'), estimated: true), '~0,021${nb}zł');
      expect(pl.approx(pl.money(double.nan, 'PLN'), estimated: true),
          Units.placeholder);
    });

    test('a currency without minor units keeps 0 decimals from 1 up', () {
      expect(const Units(locale: 'en').money(1234.5, 'JPY'), '¥1,235');
      expect(const Units(locale: 'en').money(0.3, 'JPY'), '¥0.3');
    });

    test('a three-decimal currency keeps its three decimals', () {
      expect(const Units(locale: 'en').money(12.5, 'KWD'), 'KWD${nb}12.500');
    });
  });

  group('symbols', () {
    const en = Units(locale: 'en');

    test('intl symbols are used for unambiguous currencies only', () {
      const symbol = {
        'USD': '\$1.00',
        'EUR': '€1.00',
        'GBP': '£1.00',
        'PLN': 'zł${nb}1.00',
        'CZK': 'Kč${nb}1.00',
        'JPY': '¥1',
        'KRW': '₩1',
        'INR': '₹1.00',
        'UAH': '₴1.00',
        'RUB': '₽1.00',
      };
      symbol.forEach((code, text) => expect(en.money(1, code), text));
    });

    test('ambiguous or odd intl symbols are replaced by the ISO code', () {
      // intl says `\$` for all of these, `kr` for the Nordics, `din` for the
      // dinars and `lev` for BGN: none of that is safe to show next to a price.
      for (final code in [
        'CAD',
        'AUD',
        'NZD',
        'MXN',
        'HKD',
        'SEK',
        'NOK',
        'DKK',
        'KWD',
        'BHD',
        'BGN',
        'CNY',
        'TRY',
        'CHF',
      ]) {
        expect(en.money(1, code), startsWith('$code$nb'), reason: code);
        expect(const Units(locale: 'pl').money(1, code), endsWith('$nb$code'),
            reason: code);
      }
    });

    test('lower-case and padded ISO codes are normalized', () {
      expect(en.money(1, ' pln '), 'zł${nb}1.00');
      expect(en.money(1, 'usd'), '\$1.00');
    });

    test('an unknown code is printed as it is, a bad one cannot break it', () {
      expect(en.money(1, 'ZZZ'), 'ZZZ${nb}1.00');
      expect(en.money(1, "A'B"), "A'B${nb}1.00");
      expect(en.money(1, 'Złoty'), 'Złoty${nb}1.00');
      expect(en.money(1, r'$$'), r'$$1.00');
    });

    test('an empty or blank currency prints the number only', () {
      expect(en.money(1234.5, ''), '1,234.50');
      expect(en.money(1234.5, '   '), '1,234.50');
    });

    test('intl facts this design rests on', () {
      // NumberFormat.currency never localizes the symbol: it prints the code.
      expect(NumberFormat.currency(locale: 'pl_PL', name: 'PLN').format(1),
          '1,00${nb}PLN');
      // simpleCurrency does: that is where the symbols come from.
      expect(
          NumberFormat.simpleCurrency(locale: 'pl_PL', name: 'PLN').format(1),
          '1,00${nb}zł');
      // ...but it has no spacing rule for a letter symbol before the digits.
      expect(NumberFormat.simpleCurrency(locale: 'en', name: 'PLN').format(1),
          'zł1.00');
    });
  });

  group('never NaN / Infinity', () {
    test('every currency and locale answers with the placeholder', () {
      for (final locale in ['pl_PL', 'en_US', 'xx_YY', '']) {
        for (final currency in ['PLN', 'USD', 'ZZZ', '']) {
          for (final bad in [
            double.nan,
            double.infinity,
            double.negativeInfinity,
            1e300,
          ]) {
            expect(
                Units(locale: locale).money(bad, currency), Units.placeholder);
          }
        }
      }
    });
  });
}
