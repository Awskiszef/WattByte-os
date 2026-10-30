// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/core/units.dart';

/// Core behaviour of [Units]. The per-locale tables live in
/// `formatting_units_test.dart` (bytes, energy, percent, durations, locale
/// tags) and `formatting_money_test.dart` (money, every currency).
void main() {
  const u = Units(locale: 'en_US');
  const nb = '\u00A0';

  test('bytes pick MB/GB/TB and never go below MB', () {
    expect(u.bytes(2840000000), '2.84 GB');
    expect(u.bytes(21440000000), '21.44 GB');
    expect(u.bytes(1500000), '1.50 MB');
    expect(u.bytes(12), '0.00 MB');
    expect(u.bytes(1234000000000), '1.23 TB');
    expect(const Units(locale: 'en_US', binary: true).bytes(1073741824),
        '1.00 GiB');
  });

  test('energy, charge and money', () {
    expect(u.wh(15.2), '15.2 Wh');
    expect(u.kwh(15.2), '0.0152 kWh');
    expect(u.mah(3920.4), '3,920 mAh');
    // Money is the currency's own layout for the locale (see
    // formatting_money_test.dart); it used to be "<number> <ISO code>".
    expect(u.money(0.017, 'USD'), '\$0.017');
    expect(u.money(12.5, 'USD'), '\$12.50');
    expect(u.money(0.017, 'PLN'), 'zł${nb}0.017');
    expect(u.money(12.5, 'PLN'), 'zł${nb}12.50');
    expect(u.duration(const Duration(minutes: 81)), '1 h 21 min');
    expect(u.approx('15.2 Wh', estimated: true), '~15.2 Wh');
  });

  test('Polish uses a decimal comma and a no-break space', () {
    const pl = Units(locale: 'pl_PL');
    expect(pl.bytes(2840000000), '2,84 GB');
    expect(pl.kwh(15.2), '0,0152 kWh');
    expect(pl.mah(3920.4), '3${nb}920 mAh');
    expect(pl.money(0.017, 'PLN'), '0,017${nb}zł');
    expect(pl.money(12.5, 'PLN'), '12,50${nb}zł');
    expect(pl.number(1.15, 2), '1,15');
  });

  test('number and percent', () {
    expect(u.number(1.15, 2), '1.15');
    expect(u.number(1234.5, 0), '1,235');
    expect(u.percent(85), '85%');
    expect(const Units(locale: 'pl').percent(85), '85%');
  });

  test('NaN and infinity print as a dash, never as text', () {
    expect(u.bytes(double.nan), Units.placeholder);
    expect(u.kwh(double.infinity), Units.placeholder);
    expect(u.money(double.nan, 'USD'), Units.placeholder);
    expect(u.percent(double.negativeInfinity), Units.placeholder);
  });
}
