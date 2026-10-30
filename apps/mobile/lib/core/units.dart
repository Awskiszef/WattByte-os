// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:intl/intl.dart';

/// Display formatting for bytes, energy, charge, money, percent and durations.
///
/// Pure Dart (no Flutter) so it is unit-testable and usable from the
/// background isolate that renders widget and notification text.
///
/// Everything here is for people. API payloads, JSON, CSV exports and sync
/// bodies are NEVER formatted with [Units]: they use a decimal point and ISO
/// codes whatever the language of the phone.
///
/// Guarantees:
///  * the separators, grouping and currency layout come from `intl` for
///    [locale] (`pl`: `1 234,50`, `en`: `1,234.50`);
///  * an unknown or malformed locale tag falls back to English instead of
///    throwing;
///  * NaN and +/-Infinity never reach the screen: every method returns
///    [placeholder] for them;
///  * a negative number that rounds to zero is printed as zero, never `-0,00`.
class Units {
  const Units({required this.locale, this.binary = false});

  /// Locale tag (e.g. `pl`, `pl_PL`, `en-GB`) used for digit grouping, decimal
  /// separators and currency layout. See [formatLocaleFor] for the fallback.
  final String locale;

  /// `true` -> KiB/MiB/GiB (1024), `false` -> KB/MB/GB (1000).
  final bool binary;

  /// Shown instead of a number that does not exist (NaN, infinity). The same
  /// dash the widgets use for "no price".
  static const placeholder = '—';

  /// Languages the app ships text for. The first is the fallback.
  static const supportedLanguages = ['en', 'pl'];

  /// No-break space (U+00A0): between a letter- or digit-ending currency label
  /// and the number that follows it (`PLN 0.02`, see [_spaceLabel]).
  static const nbsp = '\u00A0';

  /// Beyond this `intl` prints wrong digits (it converts through a 64-bit
  /// integer) and a double no longer holds whole units anyway, so such values
  /// print as [placeholder]. Real inputs (bytes, Wh, money) are many orders of
  /// magnitude smaller.
  static const _maxMagnitude = 1e15;

  static bool _showable(double v) => v.isFinite && v.abs() < _maxMagnitude;

  static const _decimalNames = ['B', 'KB', 'MB', 'GB', 'TB'];
  static const _binaryNames = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];

  /// Currencies whose `intl` symbol is unambiguous. Everything else prints its
  /// ISO 4217 code: `intl` answers `$` for CAD/AUD/MXN/..., `kr` for SEK, NOK
  /// and DKK alike, `din` for KWD and BHD, `lev` for BGN, and a code is never
  /// wrong. A test pins each symbol so an `intl` update cannot change it silently.
  static const _symbolCurrencies = {
    'USD',
    'EUR',
    'GBP',
    'PLN',
    'CZK',
    'JPY',
    'KRW',
    'INR',
    'UAH',
    'RUB',
  };

  /// The locale the app UI resolves to for a device locale tag: `pl` for any
  /// Polish tag (`pl`, `pl_PL`, `pl-PL`), `en` for any English tag (`en_PL` is
  /// English with a Polish region) and for every language the app has no text
  /// for. Flutter's default locale resolution does the same for the first
  /// preferred language, which is what `SettingsStore.locale` records, so the
  /// background isolate (widgets, notifications) formats exactly like the UI.
  static String resolveAppLocale(String? deviceTag) {
    final language = _language(deviceTag);
    return supportedLanguages.contains(language)
        ? language
        : supportedLanguages.first;
  }

  /// The `intl` locale actually used for [tag]: the tag itself when `intl`
  /// knows it (`en_GB`), its language when it does not know the region
  /// (`en_PL` -> `en`), English otherwise (`xx_YY`, empty, garbage).
  static String formatLocaleFor(String? tag) {
    final t = (tag ?? '').trim().replaceAll('-', '_');
    if (t.isEmpty) return supportedLanguages.first;
    try {
      return Intl.verifiedLocale(t, NumberFormat.localeExists,
              onFailure: (_) => supportedLanguages.first) ??
          supportedLanguages.first;
    } on ArgumentError {
      return supportedLanguages.first;
    }
  }

  /// [formatLocaleFor] of this instance's [locale].
  String get formatLocale => formatLocaleFor(locale);

  /// A plain decimal number with exactly [decimals] fraction digits.
  String number(num value, int decimals) {
    final v = value.toDouble();
    if (!_showable(v)) return placeholder;
    final d = decimals < 0 ? 0 : decimals;
    return _decimal(v, min: d, max: d);
  }

  /// Picks MB / GB / TB so the number stays readable; never goes below MB.
  String bytes(num value) {
    final x = value.toDouble();
    if (!_showable(x)) return placeholder;
    final k = binary ? 1024 : 1000;
    final names = binary ? _binaryNames : _decimalNames;
    final magnitude = x.abs();
    var i = 0;
    var scaled = magnitude;
    while (scaled >= k && i < names.length - 1) {
      scaled /= k;
      i++;
    }
    if (i < 2) {
      scaled = magnitude / (k * k);
      i = 2;
    }
    var decimals = scaled >= 100 ? 1 : 2;
    // 999.996 MB rounds to "1,000.0 MB": that is 1.00 GB.
    if (i < names.length - 1 &&
        double.parse(scaled.toStringAsFixed(decimals)) >= k) {
      scaled /= k;
      i++;
      decimals = scaled >= 100 ? 1 : 2;
    }
    return '${number(x < 0 ? -scaled : scaled, decimals)} ${names[i]}';
  }

  /// Watt-hours: no decimals from 100 Wh up, one below.
  String wh(double wh) {
    if (!_showable(wh)) return placeholder;
    // 99.96 rounds to "100.0": that already is the no-decimals range.
    final rounded = double.parse(wh.abs().toStringAsFixed(1));
    return '${number(wh, rounded >= 100 ? 0 : 1)} Wh';
  }

  /// Takes watt-hours, prints kilowatt-hours with at least two decimals and as
  /// many more as the size of the value deserves: `0,0152`, `1,23`, `12,35`.
  /// A positive amount below 0.0001 kWh prints `<0,0001 kWh`, never `0,00`.
  String kwh(double wh) {
    if (!_showable(wh)) return placeholder;
    final k = wh / 1000;
    final a = k.abs();
    final maxDecimals = a < 1 ? 4 : (a < 10 ? 3 : 2);
    final f = _decimalFormat(min: 2, max: maxDecimals);
    final text = _belowResolution(f, k, maxDecimals) ?? _format(f, k);
    return '$text kWh';
  }

  String mah(double mah) {
    if (!_showable(mah)) return placeholder;
    return '${number(mah, 0)} mAh';
  }

  /// Formats [amount] in the ISO 4217 currency [currency] for [locale]:
  /// `12,50 zł` (pl, PLN), `$12.50` (en, USD), `12,50` when [currency] is
  /// empty. Currencies without an unambiguous symbol (see [_symbolCurrencies])
  /// print their ISO code: `CHF 12.50`, `12,50 SEK`. An unknown code is printed
  /// as it is (upper-cased when it has three letters), so a mistaken setting
  /// stays visible instead of being hidden.
  ///
  /// Precision rule. A charging session costs fractions of a grosz, so the
  /// currency's own decimals (2) would turn a real 0.021 PLN into "0.02" and
  /// 0.004 PLN into "0.00". Therefore:
  ///  * |amount| >= 1: the currency's decimals (`12,50`, `1 234,50`);
  ///  * 0 < |amount| < 1: up to three decimals, at least the currency's own
  ///    (`0,021`, `0,004`, but `0,50`, not `0,500`);
  ///  * a non-zero amount that would still round to zero (|amount| < 0.0005)
  ///    prints `<0,001 zł` (negative: `>-0,001 zł`);
  ///  * exactly 0 prints `0,00 zł`.
  /// A currency without minor units (JPY) keeps 0 decimals from 1 up.
  String money(double amount, String currency) {
    if (!_showable(amount)) return placeholder;
    final v = amount == 0 ? 0.0 : amount; // -0.0 -> 0.0
    final loc = formatLocale;
    final code = _currencyLabel(currency);
    final base = code.isEmpty ? 2 : _currencyDigits(loc, code);
    final maxDecimals = v.abs() < 1 && base < 3 ? 3 : base;

    final NumberFormat f;
    String symbol = '';
    if (code.isEmpty) {
      f = _decimalFormat(min: base, max: maxDecimals);
    } else {
      symbol = _currencySymbol(loc, code);
      f = NumberFormat.currency(
          locale: loc, name: code, symbol: symbol, decimalDigits: base)
        ..minimumFractionDigits = base
        ..maximumFractionDigits = maxDecimals;
    }
    final text = _belowResolution(f, v, maxDecimals) ?? _format(f, v);
    return _spaceLabel(text, symbol);
  }

  /// Percent for a value already expressed in percent (85 -> `85%`); the
  /// sign placement and spacing come from the locale.
  String percent(num p) {
    final v = p.toDouble();
    if (!_showable(v)) return placeholder;
    final f = NumberFormat.percentPattern(formatLocale)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 0;
    return _format(f, v / 100);
  }

  /// `1 h 21 min` / `45 min`. "h" and "min" are the unit symbols of both
  /// supported languages; only the number is localized.
  String duration(Duration d) {
    final sign = d.isNegative ? _minusSign : '';
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes % 60;
    return h == 0
        ? '$sign${number(m, 0)} min'
        : '$sign${number(h, 0)} h ${number(m, 0)} min';
  }

  /// Prefixes an estimate with "~" so it never reads as a measurement. Text
  /// that already says "less than" (`<0,001 zł`) or has no number
  /// ([placeholder]) is returned as it is: `~<` and `~—` would be nonsense.
  String approx(String formatted, {required bool estimated}) {
    if (!estimated) return formatted;
    final noNumber = formatted == placeholder ||
        formatted.startsWith('<') ||
        formatted.startsWith('>');
    return noNumber ? formatted : '~$formatted';
  }

  // --------------------------------------------------------------- internals

  String get _minusSign =>
      NumberFormat.decimalPattern(formatLocale).symbols.MINUS_SIGN;

  NumberFormat _decimalFormat({required int min, required int max}) =>
      NumberFormat.decimalPattern(formatLocale)
        ..minimumFractionDigits = min
        ..maximumFractionDigits = max;

  String _decimal(double v, {required int min, required int max}) =>
      _format(_decimalFormat(min: min, max: max), v);

  /// `f.format(v)` without `-0`: a negative value that rounds to zero prints
  /// as the zero of the same format.
  String _format(NumberFormat f, double v) {
    if (v == 0) return f.format(0);
    if (v < 0 && f.format(-v) == f.format(0)) return f.format(0);
    return f.format(v);
  }

  /// `<0,001` / `>-0,001` for a non-zero [v] that [f] would print as zero, else
  /// null. [maxDecimals] is the finest step [f] can show.
  String? _belowResolution(NumberFormat f, double v, int maxDecimals) {
    if (v == 0 || f.format(v.abs()) != f.format(0)) return null;
    var step = 1.0;
    for (var i = 0; i < maxDecimals; i++) {
      step /= 10;
    }
    return v > 0 ? '<${f.format(step)}' : '>${f.format(-step)}';
  }

  /// Currency code as written by the user, normalized: ISO-shaped codes are
  /// upper-cased (`pln` -> `PLN`), anything else is shown trimmed, empty
  /// stays empty.
  static String _currencyLabel(String currency) {
    final t = currency.trim();
    return RegExp(r'^[A-Za-z]{3}$').hasMatch(t) ? t.toUpperCase() : t;
  }

  static int _currencyDigits(String loc, String code) =>
      NumberFormat.simpleCurrency(locale: loc, name: code).decimalDigits ?? 2;

  static String _currencySymbol(String loc, String code) {
    if (!_symbolCurrencies.contains(code)) return code;
    final symbol =
        NumberFormat.simpleCurrency(locale: loc, name: code).currencySymbol;
    return symbol.isEmpty ? code : symbol;
  }

  /// CLDR "currencySpacing": a currency label that ends in a letter or digit
  /// is separated from the number that follows it (`PLN 0.02`, `zł 0.02`),
  /// a symbol such as `$` is not (`$0.02`). `intl` leaves this out.
  static String _spaceLabel(String text, String label) {
    if (label.isEmpty ||
        !RegExp(r'[\p{L}\p{N}]$', unicode: true).hasMatch(label)) {
      return text;
    }
    final at = text.indexOf(label);
    if (at < 0) return text;
    final end = at + label.length;
    if (end >= text.length) return text;
    final next = text.codeUnitAt(end);
    final isDigit = next >= 0x30 && next <= 0x39;
    return isDigit
        ? '${text.substring(0, end)}$nbsp${text.substring(end)}'
        : text;
  }

  static String _language(String? tag) {
    final t = (tag ?? '').trim().replaceAll('-', '_');
    final cut = t.indexOf('_');
    return (cut < 0 ? t : t.substring(0, cut)).toLowerCase();
  }
}
