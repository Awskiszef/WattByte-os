// The whole first run on a fresh install, through the real app, with every
// native and network edge faked:
//
//   signed out -> Welcome -> Create account (fake auth) -> "Setting up
//   WattByte..." -> ONE review screen with a single Continue -> Permissions
//   (explanation first, system prompt only after a tap) -> Dashboard
//
// at text scale 1.0 and 2.0, in English and Polish.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
import 'package:wattbyte/l10n/generated/app_localizations.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/onboarding/setup_screen.dart';
import 'package:wattbyte/ui/widgets/wb_widgets.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// Scrolls [finder] into view (a form or a list at a large text size does not
/// show everything) and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Brings [finder] fully on screen (the list builds rows beyond the viewport,
/// so "built" is not "visible").
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Welcome -> Create account -> submit; returns once "Setting up..." was seen
/// (or the review is already there).
Future<bool> _createAccount(WidgetTester tester, AppLocalizations l) async {
  expect(find.text(l.welcomeTagline), findsOneWidget, reason: 'Welcome first');
  expect(find.byType(NavigationDestination), findsNothing,
      reason: 'no dashboard before an account exists');
  await _tap(tester, find.widgetWithText(FilledButton, l.signUp));
  await settle(tester);
  expect(find.text(l.authCreateTitle), findsOneWidget);
  expectNoFlutterErrors(tester, screen: 'Create account');

  await tester.enterText(find.byType(TextField).first, 'new.user@example.com');
  await tester.enterText(find.byType(TextField).last, 'password');
  await _tap(tester, find.widgetWithText(FilledButton, l.signUp));
  // Frame by frame: the progress screen is short-lived.
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    if (find.text(l.setupDetectingTitle).evaluate().isNotEmpty) {
      expectNoFlutterErrors(tester, screen: 'Setting up WattByte');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      return true;
    }
  }
  return false;
}

Future<void> _flow(WidgetTester tester,
    {required double scale, required Locale locale}) async {
  final l = locale.languageCode == 'pl' ? _pl : _en;
  final h = await pumpApp(tester,
      signedIn: false,
      onboarded: false,
      historyDays: 0,
      textScale: scale,
      locale: locale,
      semantics: true);
  expectNoFlutterErrors(tester, screen: 'Welcome');
  // The app really runs at this size (no cap in WattByteApp): 10 sp -> 10*scale.
  expect(
      MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
          .scale(10),
      closeTo(10 * scale, 0.01),
      reason: 'the system text size must reach the screens uncapped');

  final sawProgress = await _createAccount(tester, l);
  expect(sawProgress, isTrue, reason: '"Setting up WattByte..." is shown');
  await settle(tester);

  // ---- the review: one screen, one Continue, Edit per value
  expect(find.text(l.setupReviewTitle), findsOneWidget);
  expectNoFlutterErrors(tester, screen: 'Setup review');
  expectNoBrokenText(tester, screen: 'Setup review');
  expect(find.byType(FilledButton), findsOneWidget,
      reason: 'a single Continue');
  expect(find.text(l.continueLabel), findsOneWidget);
  // Region, Currency, Battery, Electricity price and Efficiency are editable
  // (one "Edit" inside each card); the device is information.
  for (final (label, editable) in [
    (l.setupRegion, true),
    (l.currency, true),
    (l.setupDevice, false),
    (l.setupBattery, true),
    (l.setupElectricity, true),
    (l.chargingEfficiency, true),
  ]) {
    await tester.scrollUntilVisible(find.text(label), 120,
        scrollable: find.byType(Scrollable).first);
    final card = find.ancestor(
        of: find.text(label), matching: find.byType(SetupValueTile));
    expect(card, findsOneWidget, reason: label);
    expect(find.descendant(of: card, matching: find.text(l.edit)),
        editable ? findsOneWidget : findsNothing,
        reason: label);
  }
  expect(find.byType(EstimatedBadge), findsOneWidget,
      reason: 'the automatic price is an estimate');
  expect(find.textContaining(l.priceSourceAutomatic), findsOneWidget);
  await expectAccessibleTargets(tester, screen: 'Setup review');

  // ---- nothing was requested from the system yet
  expect(h.notifier.permissionRequests, 0);
  expect(h.system.callsTo('openUsageAccessSettings'), isEmpty);
  expect(h.container(tester).read(settingsProvider).onboarded, isFalse,
      reason: 'setup is not finished before Permissions');

  // ---- Continue -> Permissions (an explanation, not a system prompt)
  await _tap(tester, find.text(l.continueLabel));
  await settle(tester);
  expect(find.text(l.permissionsTitle), findsOneWidget);
  await _reveal(tester, find.text(l.permNotificationsBody));
  expect(find.text(l.permNotificationsBody), findsOneWidget);
  expect(h.notifier.permissionRequests, 0,
      reason: 'the system prompt appears only after a tap');
  expectNoFlutterErrors(tester, screen: 'Permissions');
  expectNoBrokenText(tester, screen: 'Permissions');
  await expectAccessibleTargets(tester, screen: 'Permissions');

  await _tap(tester, find.text(l.enableNotifications));
  await settle(tester);
  expect(h.notifier.permissionRequests, 1);
  expect(find.text(l.granted), findsOneWidget);

  // ---- Get started -> Dashboard
  await _tap(tester, find.text(l.getStarted));
  await settle(tester);
  expect(find.byType(NavigationDestination), findsNWidgets(4));
  expect(h.container(tester).read(settingsProvider).onboarded, isTrue);
  expectNoFlutterErrors(tester, screen: 'Dashboard after setup');

  // What the setup wrote.
  final s = h.container(tester).read(settingsProvider);
  expect(s.countryCode, 'PL');
  expect(s.currency, 'PLN');
  expect(s.priceMode, ElectricityPriceMode.automatic);
  expect(s.pricePerKwh, 1.15);
  // The nominal capacity of the iPhone 17 Pro from the bundled catalog.
  expect(s.designCapacityMah, 3988);
  expect(s.designCapacitySource, DesignCapacitySource.localDeviceDatabase);
  expect(h.backend.where('POST', '/api/v1/devices'), isNotEmpty);
}

void main() {
  setUp(resetAssetCache);

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'fresh install -> account -> setup -> permissions -> '
        'dashboard at ${scale}x (English)', (tester) async {
      await _flow(tester, scale: scale, locale: const Locale('en'));
    });
  }

  testWidgets('the same flow in Polish at 2.0x', (tester) async {
    await _flow(tester, scale: 2.0, locale: const Locale('pl'));
  });

  // ---------------------------------------------------------- price states

  Future<AppHarness> reachReview(WidgetTester tester,
      {double scale = 1.0,
      void Function(AppHarness h)? backend,
      Locale locale = const Locale('en')}) async {
    final l = locale.languageCode == 'pl' ? _pl : _en;
    final h = await AppHarness.create(tester,
        signedIn: false, onboarded: false, historyDays: 0, locale: locale);
    backend?.call(h);
    await pumpApp(tester,
        harness: h, textScale: scale, locale: locale, semantics: true);
    await _createAccount(tester, l);
    await settle(tester);
    expect(find.text(l.setupReviewTitle), findsOneWidget);
    await _reveal(tester, find.text(l.setupElectricity));
    return h;
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'price row, automatic average: "Estimated" and the source '
        'at ${scale}x', (tester) async {
      await reachReview(tester, scale: scale);
      expect(find.byType(EstimatedBadge), findsOneWidget);
      final price = semanticsNode(tester, RegExp('^${_en.setupElectricity}, '));
      expect(price.label, contains('1.15 PLN / kWh'));
      expect(price.label, contains(_en.estimated));
      expect(
          price.label,
          contains(
              '${_en.priceSourceAutomatic} · ${_en.householdAverage('Poland (PL)')}'));
    });

    testWidgets(
        'price row, custom: the user\'s own tariff is labelled '
        '"Custom price" at ${scale}x', (tester) async {
      final h = await reachReview(tester, scale: scale);
      await _tap(tester, find.text(_en.setupElectricity));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '0.95');
      await _tap(tester, find.text(_en.save));
      await settle(tester);

      expect(h.container(tester).read(settingsProvider).priceMode,
          ElectricityPriceMode.manual);
      final price = semanticsNode(tester, RegExp('^${_en.setupElectricity}, '));
      expect(price.label, contains('0.95 PLN / kWh'));
      expect(price.label, contains(_en.priceSourceManual));
      expect(price.label, isNot(contains(_en.estimated)));
      expect(find.byType(EstimatedBadge), findsNothing);
      // The household average is remembered but not shown as the price.
      expect(find.textContaining(_en.householdAverage('Poland (PL)')),
          findsNothing);
      expectNoFlutterErrors(tester, screen: 'Custom price');
    });

    testWidgets(
        'price row, unavailable: says so and offers "Enter '
        'manually" at ${scale}x', (tester) async {
      final h = await reachReview(tester,
          scale: scale,
          backend: (h) => h.backend.routes['GET /api/v1/electricity-price'] =
              (r) => FakeBackend.error(404, 'electricity_price_unavailable'));
      expect(find.text(_en.priceUnavailable), findsOneWidget);
      expect(find.byType(EstimatedBadge), findsNothing);
      expect(h.container(tester).read(settingsProvider).hasPrice, isFalse,
          reason: 'no price is invented');
      final price = semanticsNode(tester, RegExp('^${_en.setupElectricity}, '));
      expect(price.label, endsWith(_en.enterManually));
      expect(find.text(_en.enterManually), findsOneWidget);

      // The manual route out works and the review still has one Continue.
      await _tap(tester, find.text(_en.enterManually));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '0,89');
      await _tap(tester, find.text(_en.save));
      await settle(tester);
      expect(h.container(tester).read(settingsProvider).pricePerKwh, 0.89);
      expect(find.text(_en.priceUnavailable), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  }

  testWidgets('offline: the price waits for the network and none is invented',
      (tester) async {
    final h = await reachReview(tester,
        backend: (h) => h.backend.offline = true, scale: 2.0);
    expect(find.text(_en.priceOfflineBody), findsOneWidget);
    expect(find.byType(EstimatedBadge), findsNothing);
    expect(h.container(tester).read(settingsProvider).hasPrice, isFalse);
    expectNoFlutterErrors(tester, screen: 'Review offline');
    expectNoBrokenText(tester, screen: 'Review offline');
  });
}
