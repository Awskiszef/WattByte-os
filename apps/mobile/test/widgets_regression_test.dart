import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/ui/theme.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart';

import 'support/app_harness.dart';

/// Simulator bug 5 on the REAL dashboard: card values truncated ("~0.000 ..."),
/// and "Measured" shown under an empty 0 mAh. The widget-level behaviour of
/// `BigNumber`, `Label` and `StatCard` (shrink instead of truncate, wrap
/// instead of cut off, "~" only in front of a number, count-up, screen-reader
/// text) is pinned in `test/accessibility/shared_widgets_test.dart`; the cases
/// here are the ones that need the whole app:
///
///  * no card on the dashboard cuts a value or a label off with an ellipsis, at
///    any text size on the smallest phone;
///  * "Measured" appears only under a real, non-empty measurement;
///  * the translucent accent wash is what the contrast tests assume.
///
/// Outlined-button contrast (bug 6) is `theme_contrast_test.dart`.
void main() {
  final en = AppLocalizationsEn();

  // The `rootBundle` cache keeps futures of a finished test's zone alive.
  // (Same reason as in onboarding_persistence_test.dart.)
  setUp(rootBundle.clear);

  Iterable<RenderParagraph> paragraphsIn(WidgetTester tester, Finder within) =>
      find
          .descendant(of: within, matching: find.byType(RichText))
          .evaluate()
          .map((e) => e.renderObject)
          .whereType<RenderParagraph>();

  group('no value or caption on a dashboard card is cut off', () {
    for (final scale in kTextScales) {
      testWidgets('iPhone SE, text scale $scale', (tester) async {
        final h = await pumpApp(tester, device: kIPhoneSE, textScale: scale);
        expectNoFlutterErrors(tester, screen: 'Dashboard');

        final cards = find.byType(StatCard);
        expect(cards, findsWidgets, reason: 'the dashboard has stat cards');
        for (final card in cards.evaluate()) {
          final scope = find.byElementPredicate((e) => identical(e, card));
          // Nothing asks for an ellipsis...
          for (final text in find
              .descendant(of: scope, matching: find.byType(Text))
              .evaluate()
              .map((e) => e.widget as Text)) {
            expect(text.overflow, isNot(TextOverflow.ellipsis),
                reason: 'a stat card must not ellipsize "${text.data}"');
          }
          // ... and nothing was cut: no paragraph lost lines to maxLines.
          for (final p in paragraphsIn(tester, scope)) {
            expect(p.didExceedMaxLines, isFalse,
                reason: 'text lost its end: "${p.text.toPlainText()}"');
          }
        }
        expect(h.platform, HarnessPlatform.ios);
      });
    }
  });

  group('"Measured" belongs to a real measurement only', () {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);

    /// One session today, from midnight to one minute past.
    ChargingSession session({int? chargeUah, int? energyNwh, int to = 31}) =>
        ChargingSession(
          start: midnight,
          end: midnight.add(const Duration(minutes: 1)),
          startLevel: 30,
          endLevel: to,
          chargeDeltaUah: chargeUah,
          energyDeltaNwh: energyNwh,
          avgVoltageMv: chargeUah == null ? null : 3900,
        );

    Future<AppHarness> dashboardWith(
        WidgetTester tester, List<ChargingSession> sessions,
        {HarnessPlatform platform = HarnessPlatform.android}) async {
      final h = await AppHarness.create(tester,
          platform: platform, historyDays: 0, onboarded: true);
      await h.db.insertSessions(sessions);
      await pumpApp(tester, harness: h);
      return h;
    }

    testWidgets('a measured charge under the card says "Measured"',
        (tester) async {
      // The session lies in the first minute of today: only meaningful once
      // that minute has passed.
      if (DateTime.now().difference(midnight) < const Duration(minutes: 3)) {
        markTestSkipped('too close to midnight for a session "today"');
        return;
      }
      await dashboardWith(
          tester, [session(chargeUah: 150000, energyNwh: 580000000)]);
      expect(find.text(en.measured), findsOneWidget);
    });

    testWidgets('an empty day (0 mAh) does not say "Measured"', (tester) async {
      await dashboardWith(tester, const []);
      expect(find.text(en.measured), findsNothing);
      expectNoFlutterErrors(tester, screen: 'Dashboard, empty');
    });

    testWidgets('a session that added nothing is not "Measured" either',
        (tester) async {
      if (DateTime.now().difference(midnight) < const Duration(minutes: 3)) {
        markTestSkipped('too close to midnight for a session "today"');
        return;
      }
      // Counters that read 0: the calculator falls back to the percentage, and
      // 0 % of a battery is 0 mAh.
      await dashboardWith(
          tester, [session(chargeUah: 0, energyNwh: 0, to: 30)]);
      expect(find.text(en.measured), findsNothing);
    });

    testWidgets('an estimate says "Estimated", never "Measured" (iPhone)',
        (tester) async {
      if (DateTime.now().difference(midnight) < const Duration(minutes: 3)) {
        markTestSkipped('too close to midnight for a session "today"');
        return;
      }
      await dashboardWith(tester, [session(to: 40)],
          platform: HarnessPlatform.ios);
      expect(find.text(en.measured), findsNothing);
      expect(find.text(en.estimated), findsWidgets);
    });
  });

  group('the accent wash', () {
    testWidgets('starts from the accent at 16 % over the card, fully opaque',
        (tester) async {
      // theme_contrast_test.dart measures buttons against exactly this colour.
      for (final brightness in Brightness.values) {
        late BuildContext context;
        await tester.pumpWidget(MaterialApp(
          theme: wbTheme(brightness),
          home: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          }),
        ));
        final surface = Theme.of(context).colorScheme.surface;
        for (final accent in [
          WbColors.bolt,
          WbColors.byte,
          WbColors.mobile,
          WbColors.wifi,
          WbColors.cost,
        ]) {
          final first =
              (accentWash(context, accent) as LinearGradient).colors.first;
          expect(
              first, Color.alphaBlend(accent.withValues(alpha: 0.16), surface),
              reason: '${brightness.name}: $accent');
          expect(first.a, 1.0, reason: 'a translucent stop fades too strongly');
        }
      }
    });
  });
}
