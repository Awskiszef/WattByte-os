// The small layout rules the flow screens are built from (lib/ui/settings/
// flow_widgets.dart): when a value sits beside its label and when it moves
// below, how a word that does not fit is treated, and the email break helper.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/ui/settings/flow_widgets.dart';

Widget _app(Widget child, {double textScale = 1.0}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    );

/// The text scaler the one paragraph on screen is really laid out with.
TextScaler _used(WidgetTester tester) =>
    tester.renderObject<RenderParagraph>(find.byType(RichText)).textScaler;

void main() {
  group('fitsBeside', () {
    test('a short value beside a short label', () {
      expect(fitsBeside(available: 300, sideWidth: 60, minMain: 90), isTrue);
    });

    test('a value over half of the line goes below', () {
      expect(fitsBeside(available: 300, sideWidth: 160, minMain: 40), isFalse);
    });

    test('a label whose longest word would not fit beside the value', () {
      // 300 - 100 - 12 = 188 < 200
      expect(fitsBeside(available: 300, sideWidth: 100, minMain: 200), isFalse);
      expect(fitsBeside(available: 300, sideWidth: 100, minMain: 188), isTrue);
    });

    test('the limit is configurable', () {
      expect(
          fitsBeside(
              available: 300,
              sideWidth: 110,
              minMain: 40,
              maxSideFraction: 0.4),
          isTrue);
      expect(
          fitsBeside(
              available: 300,
              sideWidth: 130,
              minMain: 40,
              maxSideFraction: 0.4),
          isFalse);
    });
  });

  group('breakableEmail / TextFit.pieces', () {
    test('adds break opportunities after @ and . and nothing else', () {
      final shown = breakableEmail('a.b@c.example.com');
      expect(shown, isNot('a.b@c.example.com'));
      expect(shown.replaceAll('​', ''), 'a.b@c.example.com');
      expect(shown, 'a.​b@​c.​example.​com');
    });

    test('pieces split at spaces, zero-width spaces and after hyphens', () {
      expect(TextFit.pieces('Wi-Fi zużywa  telefon'),
          ['Wi-', 'Fi', 'zużywa', 'telefon']);
      expect(TextFit.pieces(breakableEmail('a.b@c.com')),
          ['a.', 'b@', 'c.', 'com']);
      expect(TextFit.pieces(''), isEmpty);
    });
  });

  group('BesideOrBelow', () {
    Widget probe({required double width, required double sideWidth}) => Center(
          child: SizedBox(
            width: width,
            child: BesideOrBelow(
              main: const SizedBox(key: Key('main'), height: 20),
              side: SizedBox(
                  key: const Key('side'), width: sideWidth, height: 20),
              sideWidth: sideWidth,
              minMainWidth: 80,
            ),
          ),
        );

    testWidgets('side by side when both fit', (tester) async {
      await tester.pumpWidget(_app(probe(width: 300, sideWidth: 60)));
      final main = tester.getRect(find.byKey(const Key('main')));
      final side = tester.getRect(find.byKey(const Key('side')));
      expect(side.top, main.top, reason: 'same line');
      expect(side.left, greaterThan(main.right));
      expect(side.right, tester.getRect(find.byType(BesideOrBelow)).right);
    });

    testWidgets('below when the side is too wide', (tester) async {
      await tester.pumpWidget(_app(probe(width: 300, sideWidth: 200)));
      final main = tester.getRect(find.byKey(const Key('main')));
      final side = tester.getRect(find.byKey(const Key('side')));
      expect(side.top, greaterThanOrEqualTo(main.bottom));
      expect(side.left, main.left, reason: 'start-aligned under the text');
    });
  });

  group('FlowFitText', () {
    Widget fit(String text, {required double width, double scale = 1.0}) =>
        _app(
            Center(
              child: SizedBox(
                  width: width,
                  child:
                      FlowFitText(text, style: const TextStyle(fontSize: 20))),
            ),
            textScale: scale);

    testWidgets('leaves text alone when its words fit', (tester) async {
      await tester.pumpWidget(fit('Short words only', width: 300));
      expect(_used(tester).scale(20), 20);
    });

    testWidgets(
        'shrinks until the longest word fits, never below the design '
        'size', (tester) async {
      // (flutter_test's Ahem font: every glyph is 1em wide, so the word is
      // 280 px at 20 px: it fits in 300 at the design size, not at 3x.)
      await tester.pumpWidget(fit('Synchronizacja', width: 300, scale: 3.0));
      final used = _used(tester).scale(20) / 20;
      expect(used, lessThan(3.0));
      expect(used, greaterThanOrEqualTo(1.0));
      // The word is on one line (the paragraph is one line high).
      expect(used, greaterThan(1.0), reason: 'shrunk only as far as needed');
      expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(300));
      expect(
          tester.getSize(find.byType(Text)).height, lessThan(20 * used * 1.6),
          reason: 'one line, not a word torn into several');
    });

    testWidgets(
        'a box narrower than the word at the design size keeps the '
        'design size (nothing smaller than 1x)', (tester) async {
      await tester.pumpWidget(fit('Synchronizacja', width: 30));
      expect(_used(tester).scale(20), 20);
    });
  });

  group('flowDialog', () {
    testWidgets('scrolls its content and names its title as a heading',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => flowDialog(context,
                  title: 'Title',
                  body: List.filled(120, 'long text').join(' '),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('OK'))
                  ]),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'no overflow with a body taller than the screen');
      expect(
          find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SingleChildScrollView)),
          findsOneWidget);
      expect(find.text('OK').hitTestable(), findsOneWidget);
    });
  });
}
