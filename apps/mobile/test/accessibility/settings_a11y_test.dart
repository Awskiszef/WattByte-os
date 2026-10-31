// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Settings: every row readable and reachable at every text scale, the editors
// (bottom sheets) and dialogs scrollable with the keyboard up, one merged,
// named node per row for a screen reader.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/settings/settings.dart';
import 'package:wattbyte/ui/settings/settings_screen.dart';
import 'package:wattbyte/ui/theme.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

/// Brings [finder] fully on screen: the list builds rows beyond the viewport
/// (its cache extent), so "built" is not "visible".
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// 300 logical px of keyboard (the view is 3x).
void _keyboard(WidgetTester tester, {double height = 300}) {
  tester.view.viewInsets = FakeViewPadding(bottom: height * 3);
  addTearDown(tester.view.resetViewInsets);
}

void main() {
  setUp(resetAssetCache);

  testWidgets('fits every phone, scale, brightness and language',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await sweepFlow(tester, h, screen: 'Settings', scroll: true);
  });

  testWidgets('does not throw on wide layouts', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(), scaffold: true);
    await sweepFlow(tester, h,
        screen: 'Settings (wide)',
        devices: kWide,
        scales: const [1.0, 2.0, 3.0],
        scroll: true,
        targets: false);
  });

  testWidgets('fits with no region, currency, price or battery',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true, onboarded: false);
    await sweepFlow(tester, h, screen: 'Settings (nothing set)', scroll: true);
  });

  testWidgets('fits with a custom price, a manual currency and binary units',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        semantics: true,
        settings: const Settings(
            countryCode: 'PL',
            regionSource: SettingSource.manual,
            currency: 'EUR',
            currencySource: SettingSource.manual,
            priceMode: ElectricityPriceMode.manual,
            manualPricePerKwh: 0.31,
            pricePerKwh: 0.31,
            binaryUnits: true,
            notifyMobileThreshold: true,
            onboarded: true));
    await sweepFlow(tester, h, screen: 'Settings (custom)', scroll: true);
  });

  testWidgets(
      'Settings say why a value is set, in words, never with an enum name',
      (tester) async {
    const synced = Settings(
        countryCode: 'PL',
        regionSource: SettingSource.accountSynced,
        regionOriginalSource: SettingSource.detected,
        currency: 'EUR',
        currencySource: SettingSource.accountSynced,
        currencyOriginalSource: SettingSource.manual,
        priceMode: ElectricityPriceMode.manual,
        manualPricePerKwh: 0.31,
        pricePerKwh: 0.31,
        priceSource: SettingSource.accountSynced,
        priceOriginalSource: SettingSource.manual,
        onboarded: true);
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, settings: synced);
    // Region: the account held a detected value.
    expect(find.text(_en.sourceAccountSynced), findsOneWidget);
    // Currency: the user chose it on another device.
    expect(find.text('${_en.sourceAccountSynced} · ${_en.regionManual}'),
        findsOneWidget);
    // Price: a custom tariff that came from the account.
    expect(find.text('${_en.priceSourceManual} · ${_en.sourceAccountSynced}'),
        findsOneWidget);
    // The detected-currency shortcut is offered: the currency was a choice.
    expect(find.text(_en.useDetectedCurrency('PLN')), findsOneWidget);
    for (final technical in [
      'accountSynced',
      'migratedManual',
      'SettingSource'
    ]) {
      expect(find.textContaining(technical), findsNothing, reason: technical);
    }
    expect(find.text('detected'), findsNothing);
    expect(find.text('manual'), findsNothing);
  });

  testWidgets('Settings: a migrated choice reads as chosen by the user',
      (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        settings: const Settings(
            countryCode: 'PL',
            currency: 'EUR',
            currencySource: SettingSource.migratedManual,
            onboarded: true));
    expect(find.text(_en.currencyManualNote), findsOneWidget);
    expect(find.textContaining('migrated'), findsNothing);
  });

  testWidgets('Settings: the account label is translated', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        settings: const Settings(
            countryCode: 'PL',
            regionSource: SettingSource.accountSynced,
            currency: 'PLN',
            currencySource: SettingSource.accountSynced,
            onboarded: true));
    await h.configure(tester, locale: const Locale('pl'));
    expect(find.text(_pl.sourceAccountSynced), findsWidgets);
    expect(find.text(_en.sourceAccountSynced), findsNothing);
  });

  // ------------------------------------------------------------ semantics

  testWidgets(
      'semantics: sections are headings, rows are one named button '
      'each', (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    for (final heading in [
      _en.tabSettings,
      _en.settingsGeneral,
    ]) {
      expect(tester.getSemantics(find.text(heading).first),
          isSemantics(isHeader: true, label: heading),
          reason: heading);
    }
    expect(
        semanticsNode(
            tester,
            exactly('${_en.setupRegion}, Poland (PL), '
                '${_en.detectedAutomatically}')),
        isSemantics(isButton: true, hasTapAction: true));
    final price = semanticsNode(tester, RegExp('^${_en.electricityPrice}, '));
    expect(price.label, contains('1.15 PLN / kWh'));
    expect(price.label, contains(_en.priceSourceAutomatic));
    expect(price, isSemantics(isButton: true, hasTapAction: true));

    await _scrollTo(tester, find.text(_en.resetStatistics));
    for (final heading in [_en.notifications, _en.privacy]) {
      expect(tester.getSemantics(find.text(heading).first),
          isSemantics(isHeader: true, label: heading),
          reason: heading);
    }
    expect(semanticsNode(tester, exactly(_en.resetStatistics)),
        isSemantics(isButton: true, hasTapAction: true),
        reason: 'the destructive action is a named button');
  });

  testWidgets(
      'semantics: a switch is one node with its name, state and '
      'action - the name is not doubled', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.notifChargingDone));

    final node = semanticsNode(tester, exactly(_en.notifChargingDone));
    expect(
        node,
        isSemantics(
            hasToggledState: true, isToggled: false, hasTapAction: true));
    expect(semanticsCount(tester, RegExp(_en.notifChargingDone)), 1);

    await tester.tap(find.text(_en.notifChargingDone));
    await settle(tester);
    expect(h.notifier.permissionRequests, 1,
        reason: 'turning a notification on asks for permission');
    expect(
        h.container(tester).read(settingsProvider).notifyChargingDone, isTrue);
    expect(semanticsNode(tester, exactly(_en.notifChargingDone)),
        isSemantics(isToggled: true));
  });

  testWidgets('text contrast', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(), scaffold: true);
    await expectReadableContrast(tester, h, screen: 'Settings');
  });

  testWidgets('the contrast check can fail: the plain accent blue on white',
      (tester) async {
    // What "Use custom price" looked like before it got its darker blue.
    final h = await pumpScreen(
        tester,
        const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
                child: Text('Use custom price',
                    style: TextStyle(
                        color: WbColors.byte,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)))));
    var failed = false;
    try {
      await expectReadableContrast(tester, h, screen: 'probe');
    } on TestFailure catch (e) {
      failed = true;
      expect(e.message, contains('Expected contrast ratio'));
    }
    expect(failed, isTrue, reason: 'the check must be able to fail');
  });

  testWidgets('a notification stays off when the permission is refused',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    h.notifier.permissionGranted = false;
    await _scrollTo(tester, find.text(_en.notifWeeklyEnergy));
    await tester.tap(find.text(_en.notifWeeklyEnergy));
    await settle(tester);
    expect(
        h.container(tester).read(settingsProvider).notifyWeeklyEnergy, isFalse);
    expect(semanticsNode(tester, exactly(_en.notifWeeklyEnergy)),
        isSemantics(isToggled: false));
  });

  testWidgets(
      'semantics: the mobile-data amount is its own row, not a link '
      'hidden in a subtitle', (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.notifThresholdChange));
    final change =
        semanticsNode(tester, exactly('${_en.notifThresholdChange}, 5.00 GB'));
    expect(change, isSemantics(isButton: true, hasTapAction: true));
    final toggle =
        semanticsNode(tester, RegExp('^${_en.notifMobileThreshold}'));
    expect(toggle, isSemantics(hasToggledState: true));
  });

  testWidgets('"Units" and "Appearance" are named groups of options',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.appearance));
    expect(semanticsNode(tester, exactly(_en.appearance)),
        isSemantics(label: _en.appearance));
    await tester.tap(find.text(_en.themeDark));
    await settle(tester);
    expect(h.container(tester).read(settingsProvider).theme, AppTheme.dark);
    await _scrollTo(tester, find.text(_en.unitsBinary));
    await tester.tap(find.text(_en.unitsBinary));
    await settle(tester);
    expect(h.container(tester).read(settingsProvider).binaryUnits, isTrue);
  });

  // ---------------------------------------------------------- localisation

  testWidgets('the region is named in the app language', (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, locale: const Locale('pl'), semantics: true);
    expect(find.text('Polska (PL)'), findsOneWidget);
    expect(find.text('Poland (PL)'), findsNothing);
    expect(
        semanticsNode(
            tester,
            exactly('${_pl.setupRegion}, Polska (PL), '
                '${_pl.detectedAutomatically}')),
        isSemantics(isButton: true));
    await _scrollTo(tester, find.text(_pl.resetStatistics));
  });

  testWidgets('a country without a name shows as its code', (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        settings: const Settings(
            countryCode: 'XK',
            regionSource: SettingSource.manual,
            currency: 'EUR',
            onboarded: true));
    expect(find.text('XK'), findsOneWidget);
  });

  // ------------------------------------------------------------- editors

  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets(
        'price editor at ${scale}x on an SE with the keyboard up: '
        'scrollable, Save stays visible', (tester) async {
      await pumpScreen(tester, const SettingsScreen(),
          scaffold: true, semantics: true, device: kIPhoneSE, textScale: scale);
      await _scrollTo(tester, find.text(_en.electricityPrice));
      await tester.tap(find.text(_en.electricityPrice));
      await settle(tester);
      expect(find.text(_en.save), findsOneWidget);
      _keyboard(tester);
      await settle(tester);

      expectNoFlutterErrors(tester, screen: 'Price editor with keyboard');
      expectNoBrokenText(tester, screen: 'Price editor with keyboard');
      expect(find.text(_en.save).hitTestable(), findsOneWidget,
          reason: 'Save must be reachable above the keyboard');
      final save = tester.getRect(find.text(_en.save));
      expect(save.bottom, lessThanOrEqualTo(667 - 300));
      await expectAccessibleTargets(tester, screen: 'Price editor');
    });
  }

  testWidgets('the editor names its field, refuses nonsense and says why',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.electricityPrice));
    await tester.tap(find.text(_en.electricityPrice));
    await settle(tester);

    final field = tester.getSemantics(find.byType(TextField));
    expect(field.label, contains(_en.electricityPrice));
    expect(field, isSemantics(isTextField: true));
    final sheetTitle = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(_en.electricityPrice));
    expect(tester.getSemantics(sheetTitle), isSemantics(isHeader: true));

    for (final bad in ['', '5000', '0,0,1', '.']) {
      await tester.enterText(find.byType(TextField), bad);
      await tester.tap(find.text(_en.save));
      await settle(tester);
      expect(find.text(_en.save), findsOneWidget,
          reason: '"$bad" must not close the sheet');
      expect(find.text(_en.editorInvalidNumber('1000')), findsOneWidget,
          reason: 'and the reason is shown for "$bad"');
    }
    expect(h.container(tester).read(settingsProvider).priceMode,
        ElectricityPriceMode.automatic);

    await tester.enterText(find.byType(TextField), '0,95');
    await tester.tap(find.text(_en.save));
    await settle(tester);
    final s = h.container(tester).read(settingsProvider);
    expect(s.priceMode, ElectricityPriceMode.manual);
    expect(s.manualPricePerKwh, 0.95);
    expect(find.text(_en.save), findsNothing);
    expect(find.textContaining('0.95 PLN'), findsOneWidget);
    expect(find.textContaining(_en.priceSourceManual), findsWidgets);
  });

  testWidgets('the keyboard action "done" saves a valid value', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.chargingEfficiency));
    await tester.tap(find.text(_en.chargingEfficiency));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(h.container(tester).read(settingsProvider).efficiency, 0.9);
  });

  testWidgets('the threshold editor uses the unit the user reads everywhere',
      (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        settings: const Settings(binaryUnits: true, onboarded: true));
    await _scrollTo(tester, find.text(_en.notifThresholdChange));
    await tester.tap(find.text(_en.notifThresholdChange));
    await settle(tester);
    expect(find.text('GiB'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text(_en.save));
    await settle(tester);
    expect(h.container(tester).read(settingsProvider).mobileThresholdBytes,
        2 * 1024 * 1024 * 1024);
  });

  testWidgets('a text editor sheet at 3x in landscape stays usable',
      (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true,
        semantics: true,
        device: kIPhone17ProLandscape,
        textScale: 3.0);
    await _scrollTo(tester, find.text(_en.currency));
    await tester.tap(find.text(_en.currency));
    await settle(tester);
    expect(find.text(_en.save), findsOneWidget);
    _keyboard(tester, height: 160);
    await settle(tester);
    expectNoFlutterErrors(tester, screen: 'Currency editor, landscape 3x');
    expect(find.text(_en.save).hitTestable(), findsOneWidget);
  });

  // --------------------------------------------------------------- dialogs

  for (final scale in [1.0, 2.0, 3.0]) {
    for (final locale in kLocales) {
      testWidgets(
          'reset dialog at ${scale}x (${locale.languageCode}) on an '
          'SE scrolls and keeps both buttons', (tester) async {
        final l = locale.languageCode == 'pl' ? _pl : _en;
        await pumpScreen(tester, const SettingsScreen(),
            scaffold: true,
            semantics: true,
            device: kIPhoneSE,
            textScale: scale,
            locale: locale);
        await _scrollTo(tester, find.text(l.resetStatistics));
        await tester.tap(find.text(l.resetStatistics));
        await settle(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expectNoFlutterErrors(tester, screen: 'Reset dialog');
        expectNoBrokenText(tester, screen: 'Reset dialog');
        expect(tester.getSemantics(find.text(l.resetConfirmTitle)),
            isSemantics(isHeader: true, label: l.resetConfirmTitle));
        await tester.ensureVisible(find.text(l.reset));
        await tester.ensureVisible(find.text(l.cancel));
        expect(find.text(l.reset).hitTestable(), findsOneWidget);
        expect(find.text(l.cancel).hitTestable(), findsOneWidget);
        await expectAccessibleTargets(tester, screen: 'Reset dialog');
        await tester.tap(find.text(l.cancel));
        await settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  }

  testWidgets('confirming the reset wipes the statistics', (tester) async {
    final h = await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    expect((await h.db.allSessions()), isNotEmpty);
    await _scrollTo(tester, find.text(_en.resetStatistics));
    await tester.tap(find.text(_en.resetStatistics));
    await settle(tester);
    await tester.tap(find.text(_en.reset));
    await settle(tester);
    expect(await h.db.allSessions(), isEmpty);
  });

  testWidgets('semantics: the confirm button of the dialog is red and named',
      (tester) async {
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, semantics: true);
    await _scrollTo(tester, find.text(_en.resetStatistics));
    await tester.tap(find.text(_en.resetStatistics));
    await settle(tester);
    expect(semanticsNode(tester, exactly(_en.reset)),
        isSemantics(isButton: true, hasTapAction: true));
    final red = tester.widget<Text>(find.text(_en.reset)).style?.color;
    expect(red, WbColors.lightError,
        reason: 'the theme\'s accessible red (4.5:1 on the dialog), not the '
            'plain 3.8:1 red');
  });
}
