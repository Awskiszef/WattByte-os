import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/ui/theme.dart';

/// Simulator bug 6: outlined buttons were unreadable on light cards (the
/// default foreground is the yellow primary). This measures what the buttons
/// really render with, through the real theme, against every surface a button
/// sits on, in both brightnesses:
///
/// * label text: WCAG 2.x contrast >= 4.5 : 1 (1.4.3)
/// * outline: >= 3 : 1 (1.4.11, user-interface components)
///
/// Colours are read from the rendered widgets (the label's `RichText` and the
/// button's `Material`), so it does not matter HOW the theme sets them
/// (`styleFrom`, a `WidgetStateProperty`, a colour-scheme role): what counts is
/// the colour on screen. Translucent colours are composited over the surface
/// first. Pixels are not compared, only ratios.
/// Opacity of the accent at the first stop of `accentWash` (wb_widgets.dart).
/// This file avoids importing the widgets (they pull in the whole app, which
/// other work may have half-edited); `widgets_regression_test.dart` checks
/// that this number is still what `accentWash` uses.
const accentWashAlpha = 0.16;

void main() {
  const textRatio = 4.5;
  const outlineRatio = 3.0;

  group('WCAG helpers (so the numbers below can be trusted)', () {
    test('black on white is 21:1, equal colours are 1:1', () {
      expect(contrast(Colors.black, Colors.white), closeTo(21, 1e-9));
      expect(contrast(Colors.white, Colors.black), closeTo(21, 1e-9));
      expect(contrast(Colors.red, Colors.red), closeTo(1, 1e-9));
    });

    test('known pairs: #767676 on white is the 4.54:1 AA boundary', () {
      expect(
          contrast(const Color(0xFF767676), Colors.white), closeTo(4.54, 0.01));
      expect(contrast(const Color(0xFF777777), Colors.white), lessThan(4.5));
      expect(
          contrast(const Color(0xFF949494), Colors.white), closeTo(3.04, 0.02));
    });

    test('translucent colours are composited over the surface first', () {
      const black50 = Color(0x80000000);
      final flat = Color.alphaBlend(black50, Colors.white);
      expect(contrast(flat, Colors.white), closeTo(4.0, 0.05));
    });
  });

  for (final brightness in Brightness.values) {
    group('${brightness.name} theme', () {
      /// Every background a button can be drawn on.
      Map<String, Color> backgrounds(BuildContext context) {
        final theme = Theme.of(context);
        final surface = theme.colorScheme.surface;
        return {
          'card (surface)': surface,
          'screen background': theme.scaffoldBackgroundColor,
          // The first stop of `accentWash` is the accent at low opacity over
          // the card: the top-left corner of every hero card.
          for (final accent in <String, Color>{
            'bolt': WbColors.bolt,
            'byte': WbColors.byte,
            'mobile': WbColors.mobile,
            'wifi': WbColors.wifi,
            'cost': WbColors.cost,
          }.entries)
            'card with ${accent.key} wash': Color.alphaBlend(
                accent.value.withValues(alpha: accentWashAlpha), surface),
        };
      }

      testWidgets('OutlinedButton: label >= 4.5:1 on every surface',
          (tester) async {
        final problems = <String>[];
        late Map<String, Color> surfaces;
        await tester.pumpWidget(_host(brightness, builder: (context) {
          surfaces = backgrounds(context);
          return const SizedBox.shrink();
        }));
        for (final s in surfaces.entries) {
          final m = await _measure(tester, brightness, s.value,
              (child) => OutlinedButton(onPressed: () {}, child: child));
          final text = contrast(m.label, s.value);
          if (text < textRatio) {
            problems.add('label ${_hex(m.label)} on ${s.key} ${_hex(s.value)}: '
                '${text.toStringAsFixed(2)}:1 < $textRatio');
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      testWidgets('OutlinedButton: outline >= 3:1 on every surface',
          (tester) async {
        final problems = <String>[];
        late Map<String, Color> surfaces;
        await tester.pumpWidget(_host(brightness, builder: (context) {
          surfaces = backgrounds(context);
          return const SizedBox.shrink();
        }));
        for (final s in surfaces.entries) {
          final m = await _measure(tester, brightness, s.value,
              (child) => OutlinedButton(onPressed: () {}, child: child));
          final outline =
              m.outline == null ? null : contrast(m.outline!, s.value);
          if (outline == null) {
            problems.add('no outline at all on ${s.key}');
          } else if (outline < outlineRatio) {
            problems.add('outline ${_hex(m.outline!)} on ${s.key} '
                '${_hex(s.value)}: ${outline.toStringAsFixed(2)}:1 < $outlineRatio');
          }
        }
        expect(problems, isEmpty, reason: problems.join('\n'));
      });

      testWidgets('OutlinedButton is not drawn in the yellow primary (the bug)',
          (tester) async {
        final theme = wbTheme(brightness);
        final m = await _measure(tester, brightness, theme.colorScheme.surface,
            (child) => OutlinedButton(onPressed: () {}, child: child));
        expect(m.label, isNot(theme.colorScheme.primary));
        expect(m.label, isNot(WbColors.bolt));
      });

      testWidgets('FilledButton: label on its fill >= 4.5:1', (tester) async {
        final m = await _measure(
            tester,
            brightness,
            wbTheme(brightness).colorScheme.surface,
            (child) => FilledButton(onPressed: () {}, child: child));
        expect(m.fill, isNotNull);
        expect(contrast(m.label, m.fill!), greaterThanOrEqualTo(textRatio),
            reason: '${_hex(m.label)} on ${_hex(m.fill!)}');
      });

      testWidgets('TextButton: label >= 4.5:1 on the card and the screen',
          (tester) async {
        late Map<String, Color> surfaces;
        await tester.pumpWidget(_host(brightness, builder: (context) {
          surfaces = backgrounds(context);
          return const SizedBox.shrink();
        }));
        for (final s in surfaces.entries) {
          final m = await _measure(tester, brightness, s.value,
              (child) => TextButton(onPressed: () {}, child: child));
          expect(contrast(m.label, s.value), greaterThanOrEqualTo(textRatio),
              reason: '${_hex(m.label)} on ${s.key} ${_hex(s.value)}');
        }
      });

      test('body text, captions and errors are readable on card and screen',
          () {
        final theme = wbTheme(brightness);
        final surfaces = {
          'card': theme.colorScheme.surface,
          'screen': theme.scaffoldBackgroundColor,
        };
        for (final s in surfaces.entries) {
          final onSurface = theme.colorScheme.onSurface;
          expect(contrast(onSurface, s.value), greaterThanOrEqualTo(7),
              reason: 'body text on ${s.key}');
          final caption = theme.textTheme.labelMedium!.color!;
          expect(contrast(Color.alphaBlend(caption, s.value), s.value),
              greaterThanOrEqualTo(textRatio),
              reason: 'caption ${_hex(caption)} on ${s.key}');
          expect(contrast(theme.colorScheme.error, s.value),
              greaterThanOrEqualTo(textRatio),
              reason: 'error text on ${s.key}');
        }
      });
    });
  }
}

/// The effective colours of one pumped button.
class _Measured {
  const _Measured(this.label, this.fill, this.outline);

  final Color label;
  final Color? fill;
  final Color? outline;
}

Widget _host(Brightness brightness, {required WidgetBuilder builder}) =>
    MaterialApp(
      theme: wbTheme(brightness),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: Builder(builder: builder)),
    );

Future<_Measured> _measure(
  WidgetTester tester,
  Brightness brightness,
  Color background,
  Widget Function(Widget label) button,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: wbTheme(brightness),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: Center(
        child: ColoredBox(
          color: background,
          child: button(const Text('Sync now')),
        ),
      ),
    ),
  ));
  await tester.pump();
  final finder = find.byWidgetPredicate((w) => w is ButtonStyleButton);
  expect(finder, findsOneWidget);
  final richText = tester.widget<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)));
  final raw = richText.text.style?.color;
  expect(raw, isNotNull, reason: 'the label has an explicit colour');
  final material = tester.widget<Material>(
      find.descendant(of: finder, matching: find.byType(Material)).first);
  final shape = material.shape;
  final side = shape is OutlinedBorder ? shape.side : BorderSide.none;
  final fill = material.color;
  final fillOpaque =
      (fill == null || fill.a == 0) ? null : Color.alphaBlend(fill, background);
  final base = fillOpaque ?? background;
  return _Measured(
    Color.alphaBlend(raw!, base),
    fillOpaque,
    side.style == BorderStyle.none || side.width == 0
        ? null
        : Color.alphaBlend(side.color, background),
  );
}

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'
    '${c.a < 1 ? '@${(c.a * 100).round()}%' : ''}';

/// WCAG 2.x relative luminance of an opaque colour.
double luminance(Color c) {
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

/// WCAG 2.x contrast ratio of two opaque colours, 1..21.
double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
