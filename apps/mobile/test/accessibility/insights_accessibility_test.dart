// Insights and its AI card at every text size, phone, theme and language;
// what a screen reader says; touch targets; contrast.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_factory.dart';
import 'package:wattbyte/api/session_manager.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/features/ai/ai_input_builder.dart';
import 'package:wattbyte/features/ai/ai_service.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/insights/insights_screen.dart';

import '../support/app_harness.dart';
import 'shared_widgets_checks.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// An AI service the test controls: [generate] waits for [gate].
class _ControlledAi implements AiService {
  Completer<AiResult>? gate;
  int calls = 0;

  @override
  ApiFactory get apis => throw UnimplementedError();

  @override
  SessionManager get sessions => throw UnimplementedError();

  @override
  Future<AiResult> generate(AiKind kind, AiPeriodStats stats,
      {required String languageCode}) {
    calls++;
    return (gate = Completer<AiResult>()).future;
  }
}

const _longResult = AiResult(
  title: 'Wi-Fi robi robotę',
  message: 'Ten miesiąc: najwięcej danych zużyłeś przez Wi-Fi, a ładowanie '
      'odbywało się głównie w nocy. Przy takim tempie w tym miesiącu '
      'zapłacisz za prąd niecałe dwa złote. Nieźle jak na telefon, który '
      'nigdy nie odpoczywa!',
  emoji: '⚡',
  severity: 'info',
  provider: 'mock',
  model: 'mock',
  remainingToday: 3,
);

Future<(AppHarness, _ControlledAi)> _pump(
  WidgetTester tester, {
  int historyDays = 45,
  bool signedIn = true,
  bool apiConfigured = true,
  Locale locale = const Locale('en'),
  bool semantics = false,
  bool andSettle = true,
  bool tall = false,
  HarnessPlatform platform = HarnessPlatform.ios,
  FakeAccessibilityFeatures accessibilityFeatures =
      const FakeAccessibilityFeatures(),
}) async {
  final ai = _ControlledAi();
  final h = await pumpScreen(
    tester,
    // A nested scope swaps ONE provider for the whole screen.
    ProviderScope(
      overrides: [aiServiceProvider.overrideWith((ref) => ai)],
      child: const InsightsScreen(),
    ),
    scaffold: true,
    platform: platform,
    historyDays: historyDays,
    signedIn: signedIn,
    apiConfigured: apiConfigured,
    locale: locale,
    semantics: semantics,
    andSettle: andSettle,
    accessibilityFeatures: accessibilityFeatures,
    size: tall ? const Size(402, 3000) : null,
  );
  return (h, ai);
}

Future<void> _check(WidgetTester tester, String screen) =>
    expectLayoutHealthy(tester, screen);

/// Taps "Generate insight" and lets the card react.
Future<void> _generate(WidgetTester tester, {bool pl = false}) async {
  await tester.tap(find.text((pl ? _pl : _en).aiGenerateInsight));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('layout: every text scale x phone x theme x language', () {
    testWidgets('insights and the idle AI card', (tester) async {
      final (h, _) = await _pump(tester);
      expect(find.text(_en.aiGenerateInsight), findsOneWidget);
      expect(find.text(_en.aiGenerateRoast), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (idle)',
          positions: 4,
          check: () => _check(tester, 'Insights (idle)'));
    });

    testWidgets('a new install: the empty state and the card', (tester) async {
      final (h, _) = await _pump(tester, historyDays: 0);
      expect(find.text(_en.insightsEmpty), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (no data)',
          check: () => _check(tester, 'Insights (no data)'));
    });

    testWidgets('signed out: the sign-in hint instead of the buttons',
        (tester) async {
      final (h, _) = await _pump(tester, signedIn: false);
      expect(find.text(_en.aiSignInHint), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (signed out)',
          positions: 3,
          check: () => _check(tester, 'Insights (signed out)'));
    });

    testWidgets('a build without a server has no AI card', (tester) async {
      final h = await pumpScreen(tester, const InsightsScreen(),
          scaffold: true, apiConfigured: false);
      expect(find.text(_en.aiTitle), findsNothing);
      await sweepLayouts(tester, h,
          screen: 'Insights (no server)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'Insights (no server)'));
    });

    testWidgets('busy: the progress bar', (tester) async {
      final (h, ai) = await _pump(tester);
      await _generate(tester);
      expect(ai.calls, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (busy)',
          positions: 3,
          check: () => _check(tester, 'Insights (busy)'));
    });

    testWidgets('a long answer in Polish', (tester) async {
      final (h, ai) = await _pump(tester, locale: const Locale('pl'));
      await _generate(tester, pl: true);
      ai.gate!.complete(_longResult);
      await settle(tester);
      expect(find.text(_longResult.message), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (answer)',
          positions: 4,
          check: () => _check(tester, 'Insights (answer)'));
    });

    for (final error in [
      AiError.quotaExceeded,
      AiError.offline,
      AiError.unavailable
    ]) {
      testWidgets('error ${error.name}', (tester) async {
        final (h, ai) = await _pump(tester);
        await _generate(tester);
        ai.gate!.completeError(AiException(error));
        await settle(tester);
        await sweepLayouts(tester, h,
            screen: 'Insights (${error.name})',
            positions: 3,
            check: () => _check(tester, 'Insights (${error.name})'));
      });
    }

    testWidgets('loading and error states of the screen', (tester) async {
      var (h, _) = await _pump(tester, andSettle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (loading)',
          scales: const [1.0, 3.0],
          check: () => _check(tester, 'Insights (loading)'));

      (h, _) = await _pump(tester);
      await h.db.close();
      h.container(tester).read(refreshTickProvider.notifier).state++;
      await settle(tester);
      expect(find.text(_en.genericError), findsOneWidget);
      await sweepLayouts(tester, h,
          screen: 'Insights (error)',
          check: () => _check(tester, 'Insights (error)'));
    });
  });

  group('layout: wide screens must not throw', () {
    testWidgets('insights, answer and error', (tester) async {
      final (h, ai) = await _pump(tester);
      await _generate(tester);
      ai.gate!.complete(_longResult);
      await settle(tester);
      await sweepLayouts(tester, h,
          screen: 'Insights wide',
          devices: kWideScreens,
          scales: kWideScales,
          brightnesses: const [Brightness.light],
          positions: 3,
          check: () => _check(tester, 'Insights wide'));
    });
  });

  group('bold text (iOS "Bold Text", Android bold fonts)', () {
    testWidgets('widens every text and still fits', (tester) async {
      final (h, ai) = await _pump(tester,
          accessibilityFeatures:
              const FakeAccessibilityFeatures(boldText: true));
      await _generate(tester);
      ai.gate!.complete(_longResult);
      await settle(tester);
      await sweepLayouts(tester, h,
          screen: 'Insights bold',
          scales: const [1.0, 1.6, 3.0],
          brightnesses: const [Brightness.light],
          positions: 4,
          check: () => _check(tester, 'Insights bold'));
    });
  });

  group('semantics', () {
    testWidgets('title and AI card are headings; each insight is one node',
        (tester) async {
      final (h, _) = await _pump(tester, semantics: true, tall: true);
      final tree = semanticsTree(tester);
      expect(tree.where((n) => n.header).map((n) => n.label),
          containsAll([_en.tabInsights, _en.aiTitle]));
      final cards = tree
          .where((n) => n.tappable == false && n.label.isNotEmpty && !n.header)
          .toList();
      expect(cards, isNotEmpty);
      // The Wi-Fi share insight, with its estimate flag if it has one.
      final wifi =
          tree.firstWhere((n) => n.spoken.contains('Wi-Fi represented'));
      expect(wifi.spoken, isNot(contains('~')));
      expect(h.history.days, isNotEmpty);
    });

    testWidgets('an estimated insight says Estimated within the same node',
        (tester) async {
      await _pump(tester, semantics: true, tall: true);
      // Energy and cost insights come from estimated sessions on an iPhone.
      final tree = semanticsTree(tester);
      final energy =
          tree.firstWhere((n) => n.spoken.contains('consumed approximately'));
      expect(energy.spoken, contains(_en.estimated));
      expect(tree.where((n) => n.label == _en.estimated), isEmpty,
          reason: 'the badge never stands alone');
    });

    testWidgets('both AI buttons are labelled buttons', (tester) async {
      await _pump(tester, semantics: true, tall: true);
      final tree = semanticsTree(tester);
      for (final label in [_en.aiGenerateInsight, _en.aiGenerateRoast]) {
        final b = tree.where((n) => n.label == label).toList();
        expect(b, hasLength(1), reason: label);
        expect(b.single.tappable && b.single.button, isTrue);
      }
    });

    testWidgets('busy is labelled, the answer is announced, then an error is',
        (tester) async {
      final (_, ai) = await _pump(tester, semantics: true, tall: true);
      await _generate(tester);
      expect(
          nodesContaining(semanticsTree(tester), _en.a11yLoading), isNotEmpty);

      ai.gate!.complete(const AiResult(
          title: 'Nice',
          message: 'Wi-Fi did the heavy lifting this month.',
          emoji: '⚡',
          severity: 'info',
          provider: 'mock',
          model: 'mock',
          remainingToday: 2));
      await settle(tester);
      final answer = oneNodeWith(
          semanticsTree(tester), ['Nice', 'heavy lifting', '2 left today']);
      expect(answer.liveRegion, isTrue);

      await _generate(tester);
      ai.gate!.completeError(const AiException(AiError.quotaExceeded));
      await settle(tester);
      final error = oneNodeWith(semanticsTree(tester), [_en.aiQuotaExceeded]);
      expect(error.liveRegion, isTrue);
    });

    testWidgets('the empty state is announced', (tester) async {
      await _pump(tester, historyDays: 0, semantics: true, tall: true);
      final empty = oneNodeWith(semanticsTree(tester), [_en.insightsEmpty]);
      expect(empty.liveRegion, isTrue);
    });

    testWidgets('Polish', (tester) async {
      await _pump(tester,
          semantics: true, tall: true, locale: const Locale('pl'));
      final tree = semanticsTree(tester);
      expect(tree.where((n) => n.header).map((n) => n.label),
          containsAll([_pl.tabInsights, _pl.aiTitle]));
      expect(nodesContaining(tree, _pl.aiGenerateInsight), hasLength(1));
    });
  });

  group('touch targets (Android 48 px, iOS 44 px, labelled)', () {
    testWidgets('idle, answer and error', (tester) async {
      final (h, ai) = await _pump(tester, semantics: true);
      await sweepLayouts(tester, h,
          screen: 'Insights targets (idle)',
          brightnesses: const [Brightness.light],
          positions: 3, check: () async {
        await expectAccessibleTargets(tester, screen: 'Insights');
        final problems = tappableProblems(tester, semanticsTree(tester));
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
      // The sweep ended in the last configuration (Polish, 3.0x).
      await applyView(tester, h,
          textScale: 1.0,
          device: kIPhone17Pro,
          brightness: Brightness.light,
          locale: const Locale('en'));
      await _generate(tester);
      ai.gate!.complete(_longResult);
      await settle(tester);
      await sweepLayouts(tester, h,
          screen: 'Insights targets (answer)',
          brightnesses: const [Brightness.light],
          scales: const [1.0, 3.0],
          check: () => expectAccessibleTargets(tester, screen: 'Insights'));
    });
  });

  group('contrast (light and dark)', () {
    testWidgets('idle, answer, error', (tester) async {
      final (h, ai) = await _pump(tester, semantics: true);
      Future<void> contrast(String what) => sweepLayouts(tester, h,
          screen: 'Insights contrast ($what)',
          scales: const [1.0, 2.0],
          devices: const [kIPhoneSE],
          locales: const [Locale('en')],
          positions: 3,
          settleFully: true,
          // The pixel-histogram guideline of flutter_test mistakes the accent
          // wash behind the AI card's small caption for a 1.4:1 text, so the
          // contrast is computed from the colours instead.
          check: () async =>
              expectTextContrast(tester, screen: 'Insights ($what)'));
      await contrast('idle');

      await applyView(tester, h,
          textScale: 1.0,
          device: kIPhone17Pro,
          brightness: Brightness.light,
          locale: const Locale('en'));
      await _generate(tester);
      ai.gate!.complete(_longResult);
      await settle(tester);
      await contrast('answer');

      await applyView(tester, h,
          textScale: 1.0,
          device: kIPhone17Pro,
          brightness: Brightness.light,
          locale: const Locale('en'));
      await _generate(tester);
      ai.gate!.completeError(const AiException(AiError.quotaExceeded));
      await settle(tester);
      await contrast('error');
    });
  });
}
