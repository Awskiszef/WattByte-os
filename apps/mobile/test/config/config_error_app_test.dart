import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/app.dart';
import 'package:wattbyte/config/app_config.dart';
import 'package:wattbyte/config/config_error_app.dart';
import 'package:wattbyte/config/local_only_banner.dart';
import 'package:wattbyte/ui/onboarding/setup_screen.dart';
import 'package:wattbyte/ui/onboarding/welcome_screen.dart';
import 'package:wattbyte/ui/shell.dart';

// Only the pure helpers of the harness: the error scan, the screen sizes and the
// real fonts. NOT `pumpApp` / `AppHarness`: ConfigErrorApp must work without
// preferences, database, providers or a ProviderScope, and these tests mount it
// exactly like `main()` does (`runApp(ConfigErrorApp(config: config))`).
import '../support/app_harness.dart'
    show
        ScreenSpec,
        expectNoFlutterErrors,
        kIPhone17Pro,
        kIPhoneSE,
        kTablet,
        loadRealFonts,
        semanticsNodes;

/// The development hints of `ConfigErrorScreen` (present in debug binaries only).
const _localOnlyCommand = 'flutter run --dart-define=LOCAL_ONLY_DEV=true';
const _onlineCommand = 'flutter run --dart-define=API_BASE_URL=';

/// What `main()` runs instead of the app when the build's configuration is not
/// valid (see `lib/main.dart`): a controlled stop, no account flow, no local
/// setup, nothing from the app's providers.
void main() {
  /// A broken address. It has a distinctive host and a "secret" in it so that
  /// any place that echoes the value would be caught by the "no address" checks.
  const brokenAddress = 'https://user:secret-token@api.sample-company.io';

  final cases = <String, AppConfig>{
    'release, no API address':
        AppConfig.fromDefines(buildMode: BuildMode.release),
    'release, LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
        buildMode: BuildMode.release, localOnlyDev: 'true'),
    'debug, no API address, no flag':
        AppConfig.fromDefines(buildMode: BuildMode.debug),
    'debug, invalid API address': AppConfig.fromDefines(
        buildMode: BuildMode.debug, apiBaseUrl: brokenAddress),
    'profile, no API address':
        AppConfig.fromDefines(buildMode: BuildMode.profile),
    'release, API address + LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
        buildMode: BuildMode.release,
        apiBaseUrl: 'https://api.sample-company.io',
        localOnlyDev: 'true'),
    'debug, API address + LOCAL_ONLY_DEV=true': AppConfig.fromDefines(
        buildMode: BuildMode.debug,
        apiBaseUrl: 'https://api.sample-company.io',
        localOnlyDev: 'true'),
    'debug, LOCAL_ONLY_DEV=false, no API address': AppConfig.fromDefines(
        buildMode: BuildMode.debug, localOnlyDev: 'false'),
    'debug, malformed LOCAL_ONLY_DEV': AppConfig.fromDefines(
        buildMode: BuildMode.debug, localOnlyDev: 'maybe'),
  };

  /// Every string the screen shows, built or not: `Text` and the text of the
  /// `EditableText` inside every `SelectableText`.
  List<String> allTexts(WidgetTester tester) => [
        for (final w
            in tester.widgetList<Text>(find.byType(Text, skipOffstage: false)))
          w.data ?? w.textSpan?.toPlainText() ?? '',
        for (final w in tester.widgetList<EditableText>(
            find.byType(EditableText, skipOffstage: false)))
          w.controller.text,
      ];

  /// A phone-sized view at a text scale, undone when the test ends.
  void configureView(
    WidgetTester tester, {
    ScreenSpec device = kTablet,
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
  }) {
    final dpr = device.devicePixelRatio;
    tester.view
      ..devicePixelRatio = dpr
      ..physicalSize = device.physicalSize
      ..padding = FakeViewPadding(
        left: device.safeArea.left * dpr,
        top: device.safeArea.top * dpr,
        right: device.safeArea.right * dpr,
        bottom: device.safeArea.bottom * dpr,
      );
    tester.platformDispatcher
      ..textScaleFactorTestValue = textScale
      ..platformBrightnessTestValue = brightness;
  }

  Future<void> pumpError(WidgetTester tester, AppConfig config) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await loadRealFonts(tester);
    // ConfigErrorApp straight into pumpWidget: no ProviderScope, no overrides.
    await tester.pumpWidget(ConfigErrorApp(config: config));
    await tester.pump();
  }

  for (final entry in cases.entries) {
    final name = entry.key;
    final config = entry.value;

    testWidgets('$name: the controlled stop, not an app', (tester) async {
      expect(config.isValid, isFalse,
          reason: 'precondition: "$name" must be an invalid configuration');
      expect(config.backend.errors, isNotEmpty);
      configureView(tester); // tall: everything is built at once
      await pumpError(tester, config);

      // No providers needed.
      expect(find.byType(ProviderScope), findsNothing);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(ConfigErrorScreen), findsOneWidget);

      // The title, then every error line of the verdict, as the only bullets.
      expect(find.text(ConfigErrorScreen.title), findsOneWidget);
      for (final error in config.backend.errors) {
        expect(find.text('• $error'), findsOneWidget,
            reason: 'the error "$error" must be shown');
      }
      expect(find.textContaining('• '),
          findsNWidgets(config.backend.errors.length),
          reason: 'one bullet per error of config.backend.errors, no more');

      // Not the development mode, not any screen of the app.
      expect(find.text(kLocalOnlyDevBannerText), findsNothing);
      expect(
          find.textContaining('LOCAL ONLY', skipOffstage: false), findsNothing);
      expect(find.textContaining('DEVELOPMENT MODE', skipOffstage: false),
          findsNothing);
      expect(
          find.byType(LocalOnlyDevBanner, skipOffstage: false), findsNothing);
      expect(find.byType(WelcomeScreen, skipOffstage: false), findsNothing);
      expect(find.byType(SetupScreen, skipOffstage: false), findsNothing);
      expect(find.byType(ShellScreen, skipOffstage: false), findsNothing);
      expect(find.byType(StartGate, skipOffstage: false), findsNothing);
      expect(find.byType(WattByteApp, skipOffstage: false), findsNothing);
      expect(find.byType(NavigationDestination, skipOffstage: false),
          findsNothing);
      expect(find.byType(TextField, skipOffstage: false), findsNothing,
          reason: 'no sign-in form either');
      expect(find.byType(FilledButton, skipOffstage: false), findsNothing,
          reason: 'nothing to press: no way on into an app');

      // The value of the address is never shown (it could carry credentials).
      for (final text in allTexts(tester)) {
        expect(text, isNot(contains('sample-company')),
            reason: 'no address text: "$text"');
        expect(text, isNot(contains('secret-token')),
            reason: 'no credential text: "$text"');
        expect(text, isNot(contains('://')),
            reason: 'no URL of any kind on this screen: "$text"');
      }

      // Hints for the developer exist only in a debug binary; this test run is
      // one. They name the two ways out, the explicit one included.
      expect(kBuildMode, BuildMode.debug,
          reason: 'flutter test is a debug run');
      // (An error line may quote the flag too: look for the command itself.)
      expect(find.text(_localOnlyCommand), findsOneWidget,
          reason: 'the explicit development mode is offered in debug');
      expect(find.textContaining(_onlineCommand), findsOneWidget,
          reason: 'online development is offered in debug');

      expectNoFlutterErrors(tester, screen: 'ConfigErrorApp ($name)');
    });
  }

  testWidgets('semantics: the title is a header, the errors are readable',
      (tester) async {
    final config = AppConfig.fromDefines(buildMode: BuildMode.release);
    configureView(tester);
    final handle = tester.ensureSemantics();
    try {
      await pumpError(tester, config);
      expect(tester.getSemantics(find.text(ConfigErrorScreen.title)),
          isSemantics(isHeader: true, label: ConfigErrorScreen.title));
      // The error lines are selectable text: their text is the node's value.
      final nodes = semanticsNodes(tester);
      bool announces(String text) =>
          nodes.any((n) => n.label.contains(text) || n.value.contains(text));
      for (final error in config.backend.errors) {
        expect(announces(error), isTrue,
            reason: 'the error "$error" must be in the semantics tree: $nodes');
      }
      expect(announces('LOCAL ONLY'), isFalse);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('the debug hints are plain text to copy, not buttons',
      (tester) async {
    configureView(tester);
    await pumpError(tester, AppConfig.fromDefines(buildMode: BuildMode.debug));
    expect(kBuildMode, BuildMode.debug);
    for (final hint in [_localOnlyCommand, _onlineCommand]) {
      final finder = find.textContaining(hint);
      expect(finder, findsOneWidget, reason: hint);
      expect(
          find.ancestor(of: finder, matching: find.byType(ButtonStyleButton)),
          findsNothing,
          reason: 'a hint never runs anything');
    }
  });

  group('layout', () {
    /// Scrolls the screen top to bottom in steps, checking the layout at every
    /// position (a ListView builds only what is near the viewport, so a single
    /// check sees a fraction of a screen at large text). Returns every error
    /// line that was on screen at some point.
    Future<Set<String>> scrollThrough(
        WidgetTester tester, String screen, AppConfig config) async {
      final scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      final reached = <String>{};
      for (var step = 0; step < 400; step++) {
        expectNoFlutterErrors(tester, screen: '$screen, scrolled $step');
        for (final error in config.backend.errors) {
          if (find.text('• $error').evaluate().isNotEmpty) reached.add(error);
        }
        final position = scrollable.position;
        if (position.pixels >= position.maxScrollExtent - 0.5) return reached;
        position
            .jumpTo(math.min(position.pixels + 150, position.maxScrollExtent));
        await tester.pump();
      }
      fail('$screen: the screen never reached its end');
    }

    final spec = <String, AppConfig>{
      for (final name in [
        'release, no API address',
        'release, LOCAL_ONLY_DEV=true',
        'debug, no API address, no flag',
        'debug, invalid API address',
      ])
        name: cases[name]!,
    };

    for (final entry in spec.entries) {
      testWidgets(
          '${entry.key}: no overflow at 3.0x text on the smallest phone, '
          'every error reachable by scrolling', (tester) async {
        final config = entry.value;
        configureView(tester, device: kIPhoneSE, textScale: 3.0);
        await pumpError(tester, config);
        expect(
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .maxScrollExtent,
            greaterThan(0),
            reason: 'at 3.0x on the smallest phone the screen does not fit: '
                'the check below has to scroll to see all of it');
        final reached = await scrollThrough(
            tester, 'ConfigErrorApp (${entry.key})', config);
        expect(reached, config.backend.errors.toSet(),
            reason: 'every error line must be reachable at large text');
        expect(find.text(_localOnlyCommand), findsOneWidget,
            reason: 'the last hint is reachable too');
      });
    }

    testWidgets('every screen size, scale and brightness fits', (tester) async {
      final config = cases['release, LOCAL_ONLY_DEV=true']!;
      final failures = <String>[];
      for (final device in [kIPhoneSE, kIPhone17Pro, kTablet]) {
        for (final scale in [1.0, 1.35, 2.0, 3.0]) {
          for (final brightness in Brightness.values) {
            configureView(tester,
                device: device, textScale: scale, brightness: brightness);
            await pumpError(tester, config);
            try {
              await scrollThrough(tester,
                  'ConfigErrorApp $device x$scale ${brightness.name}', config);
            } on TestFailure catch (e) {
              failures.add('$device x$scale ${brightness.name}: ${e.message}');
            }
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}
