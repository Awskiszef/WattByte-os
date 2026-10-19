// Automatic setup review ("Your setup"): responsive in every state it can be in
// (everything detected, battery unknown, price unavailable, offline, custom
// price), at every text scale, and readable by a screen reader.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/domain/battery_capacity.dart';
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

/// One way the setup can end up.
class _Scenario {
  const _Scenario(this.name, this.build);

  final String name;
  final Future<AppHarness> Function(WidgetTester tester) build;
}

Future<AppHarness> _pump(
  WidgetTester tester, {
  HarnessPlatform platform = HarnessPlatform.ios,
  FakeSystem? system,
  Settings settings = const Settings(),
  void Function(AppHarness h)? backend,
  Future<void> Function(AppHarness h)? seed,
  bool semantics = true,
}) async {
  final h = await AppHarness.create(tester,
      platform: platform,
      system: system,
      settings: settings,
      onboarded: false,
      historyDays: 0);
  backend?.call(h);
  if (seed != null) await seed(h);
  return pumpScreen(tester, const SetupScreen(),
      harness: h, platform: platform, semantics: semantics);
}

final _scenarios = <_Scenario>[
  _Scenario('everything detected', (t) => _pump(t)),
  _Scenario(
      'battery unknown',
      (t) => _pump(t,
          system: FakeSystem(deviceInfo: {
            ...FakeSystem.defaultDeviceInfo(HarnessPlatform.ios),
            'modelIdentifier': 'iPhone99,9',
          }))),
  _Scenario(
      'price unavailable for the country',
      (t) => _pump(t,
          backend: (h) => h.backend.routes['GET /api/v1/electricity-price'] =
              (r) => FakeBackend.error(404, 'electricity_price_unavailable'))),
  _Scenario(
      'offline', (t) => _pump(t, backend: (h) => h.backend.offline = true)),
  _Scenario(
      'custom price, manual region and currency',
      (t) => _pump(t,
          settings: const Settings(
              countryCode: 'PL',
              regionSource: SettingSource.manual,
              currency: 'PLN',
              currencySource: SettingSource.manual,
              priceMode: ElectricityPriceMode.manual,
              manualPricePerKwh: 0.95,
              pricePerKwh: 0.95))),
  // The model is in no catalog, so the design capacity stays unknown even
  // though the charge counter gave an (estimated) full-charge capacity: the
  // review shows the "unavailable" warning, never the estimate.
  _Scenario(
      'unlisted Android model with an estimated full charge (counter at 70 %)',
      (t) => _pump(t,
              platform: HarnessPlatform.android,
              system: _unlistedAndroid(), seed: (h) async {
            await seedFullChargeEstimate(h.db, mah: 3600, level: 70);
          })),
];

/// An Android phone that no catalog knows, whose charge counter works.
FakeSystem _unlistedAndroid() => FakeSystem(
        platform: HarnessPlatform.android,
        chargeCounterMah: 3600,
        deviceInfo: {
          ...FakeSystem.defaultDeviceInfo(HarnessPlatform.android),
          'modelIdentifier': 'Unlisted-1',
          'model': 'Unlisted 1',
        });

void main() {
  setUp(resetAssetCache);

  for (final s in _scenarios) {
    testWidgets(
        'review (${s.name}) fits every phone, scale, brightness and '
        'language', (tester) async {
      final h = await s.build(tester);
      expect(find.byType(FilledButton), findsOneWidget,
          reason: 'the review screen has its single Continue');
      await sweepFlow(tester, h,
          screen: 'Setup review: ${s.name}', scroll: true);
    });
  }

  testWidgets('review does not throw on wide layouts', (tester) async {
    final h = await _pump(tester, semantics: false);
    await sweepFlow(tester, h,
        screen: 'Setup review (wide)',
        devices: kWide,
        scales: const [1.0, 2.0, 3.0],
        scroll: true,
        targets: false);
  });

  testWidgets('"Setting up WattByte..." fits every phone, scale and language',
      (tester) async {
    final h = await pumpScreen(tester, const SetupDetectingView(),
        onboarded: false, historyDays: 0, semantics: true);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await sweepFlow(tester, h, screen: 'Setup detecting', scroll: true);
    await sweepFlow(tester, h,
        screen: 'Setup detecting (wide)',
        devices: kWide,
        scales: const [1.0, 2.0, 3.0],
        scroll: true,
        targets: false);
  });

  testWidgets('"Setting up WattByte..." is a heading and the bar has a name',
      (tester) async {
    await pumpScreen(tester, const SetupDetectingView(),
        onboarded: false, historyDays: 0, semantics: true);
    expect(tester.getSemantics(find.text(_en.setupDetectingTitle)),
        isSemantics(isHeader: true, label: _en.setupDetectingTitle));
    expect(tester.getSemantics(find.byType(LinearProgressIndicator)),
        isSemantics(label: _en.setupDetectingTitle));
  });

  // ------------------------------------------------------------ semantics

  testWidgets(
      'every value is ONE node: "Region, Poland (PL), Detected '
      'automatically, Edit"', (tester) async {
    await _pump(tester);
    expect(find.byType(FilledButton), findsOneWidget, reason: 'one Continue');
    expect(find.widgetWithText(TextButton, _en.edit), findsNothing,
        reason: 'Edit is not a second button inside the card');

    for (final label in [
      '${_en.setupRegion}, Poland (PL), ${_en.detectedAutomatically}, ${_en.edit}',
      '${_en.currency}, PLN, ${_en.detectedAutomatically}, ${_en.edit}',
      '${_en.setupBattery}, 3,988 mAh, ${_en.detectedFromSpecs}, ${_en.edit}',
      '${_en.chargingEfficiency}, 85%, ${_en.estimated}, ${_en.edit}',
    ]) {
      expect(semanticsNode(tester, exactly(label)),
          isSemantics(isButton: true, hasTapAction: true),
          reason: label);
    }
    // The device is information, not an action.
    final device = semanticsNode(
        tester, exactly('${_en.setupDevice}, iPhone 17 Pro, iPhone18,1'));
    expect(device, isSemantics(hasTapAction: false, isButton: false));
    // Nothing is announced twice: each label occurs once.
    for (final word in [_en.setupRegion, _en.currency, _en.setupBattery]) {
      expect(semanticsCount(tester, RegExp('^$word, ')), 1, reason: word);
    }
  });

  testWidgets('text contrast, including the warning rows', (tester) async {
    final h = await _pump(tester,
        system: FakeSystem(deviceInfo: {
          ...FakeSystem.defaultDeviceInfo(HarnessPlatform.ios),
          'modelIdentifier': 'iPhone99,9',
        }),
        backend: (h) => h.backend.routes['GET /api/v1/electricity-price'] =
            (r) => FakeBackend.error(404, 'electricity_price_unavailable'));
    await expectReadableContrast(tester, h, screen: 'Setup review');
  });

  testWidgets('the price is an automatic average: source line + Estimated',
      (tester) async {
    await _pump(tester);
    final price = semanticsNode(tester, RegExp('^${_en.setupElectricity}, '));
    expect(price.label, contains('1.15 PLN / kWh'));
    expect(price.label, contains(_en.priceSourceAutomatic));
    expect(price.label, contains(_en.householdAverage('Poland (PL)')));
    expect(price.label, contains(_en.estimated));
    expect(price.label, endsWith(_en.edit));
    expect(find.byType(EstimatedBadge), findsOneWidget,
        reason: 'the visible hint, not only the spoken one');
  });

  testWidgets('a custom price says "Custom price" and is not "Estimated"',
      (tester) async {
    await _pump(tester,
        settings: const Settings(
            countryCode: 'PL',
            regionSource: SettingSource.manual,
            currency: 'PLN',
            currencySource: SettingSource.manual,
            priceMode: ElectricityPriceMode.manual,
            manualPricePerKwh: 0.95,
            pricePerKwh: 0.95));
    expect(
        semanticsNode(
            tester,
            exactly('${_en.setupElectricity}, 0.95 PLN / kWh, '
                '${_en.priceSourceManual}, ${_en.edit}')),
        isSemantics(isButton: true, hasTapAction: true));
    expect(find.byType(EstimatedBadge), findsNothing);
  });

  testWidgets(
      'no price: "Electricity price unavailable" is a warning with '
      '"Enter manually"', (tester) async {
    await _pump(tester,
        backend: (h) => h.backend.routes['GET /api/v1/electricity-price'] =
            (r) => FakeBackend.error(404, 'electricity_price_unavailable'));
    final price = semanticsNode(tester, RegExp('^${_en.setupElectricity}, '));
    expect(
        price.label, contains('${_en.warningLabel}: ${_en.priceUnavailable}'));
    expect(price.label, contains(_en.priceUnavailableBody('Poland (PL)')));
    expect(price.label, endsWith(_en.enterManually));
    expect(price, isSemantics(isButton: true, hasTapAction: true));
    expect(find.byType(EstimatedBadge), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget,
        reason: 'a warning is not colour alone');
  });

  testWidgets(
      'unknown battery: "Battery capacity unavailable" + "Enter '
      'manually", never an invented number', (tester) async {
    await _pump(tester,
        system: FakeSystem(deviceInfo: {
          ...FakeSystem.defaultDeviceInfo(HarnessPlatform.ios),
          'modelIdentifier': 'iPhone99,9',
        }));
    final battery = semanticsNode(tester, RegExp('^${_en.setupBattery}, '));
    expect(battery.label,
        contains('${_en.warningLabel}: ${_en.capacityUnavailable}'));
    expect(battery.label, contains(_en.capacityUnavailableBody));
    expect(battery.label, endsWith(_en.enterManually));
    expect(battery.label, isNot(contains('mAh')));
    expect(battery, isSemantics(isButton: true, hasTapAction: true));
  });

  testWidgets(
      'a charge-counter estimate is not the battery capacity: an unlisted '
      'Android model still reads "Battery capacity unavailable"',
      (tester) async {
    final h = await _pump(tester,
        platform: HarnessPlatform.android,
        system: _unlistedAndroid(), seed: (h) async {
      final estimate = await seedFullChargeEstimate(h.db, mah: 3600, level: 70);
      expect(estimate.isAvailable, isTrue,
          reason: 'the estimate really exists, so the review is not '
              'unknown for lack of data');
    });
    // The review is about the nominal capacity of the MODEL: unknown.
    final battery = semanticsNode(tester, RegExp('^${_en.setupBattery}, '));
    expect(battery.label,
        contains('${_en.warningLabel}: ${_en.capacityUnavailable}'));
    expect(battery.label, contains(_en.capacityUnavailableBody));
    expect(battery.label, endsWith(_en.enterManually));
    expect(battery.label, isNot(contains('3,600')),
        reason: 'the estimate is never read out as the capacity');
    expect(battery.label, isNot(contains('mAh')));
    expect(find.text('~3,600 mAh'), findsNothing);
    expect(find.textContaining('3,600'), findsNothing,
        reason: 'not as the value, not as the source line');
    expect(find.byType(EstimatedBadge), findsOneWidget,
        reason: 'only the household price carries "Estimated" here');

    final s = h.container(tester).read(settingsProvider);
    expect(s.designCapacityMah, 0);
    expect(s.designCapacitySource, DesignCapacitySource.unknown);
  });

  testWidgets('the Polish review reads naturally and names the country',
      (tester) async {
    final h = await _pump(tester);
    await h.setLocale(tester, const Locale('pl'));
    expect(
        semanticsNode(
            tester,
            exactly('${_pl.setupRegion}, Polska (PL), '
                '${_pl.detectedAutomatically}, ${_pl.edit}')),
        isSemantics(isButton: true, hasTapAction: true));
    expect(find.text('Polska (PL)'), findsOneWidget,
        reason: 'not the English "Poland" in a Polish UI');
    expect(find.text('Poland (PL)'), findsNothing);
  });

  testWidgets(
      'the whole card opens the editor, and a bad value is refused '
      'in the sheet', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Poland (PL)'));
    await settle(tester);
    expect(find.text(_en.save), findsOneWidget);
    // "Edit" in a card and the sheet's field is named after the value.
    expect(find.bySemanticsLabel(_en.setupRegion), findsWidgets);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text(_en.save));
    await settle(tester);
    expect(find.text(_en.save), findsOneWidget, reason: 'the sheet stays open');
    expect(find.text(_en.editorInvalidCountry), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'de');
    await tester.tap(find.text(_en.save));
    await settle(tester);
    expect(find.text(_en.save), findsNothing);
    expect(h.container(tester).read(settingsProvider).countryCode, 'DE');
    expect(h.container(tester).read(settingsProvider).regionSource,
        SettingSource.manual);
    expect(find.text('Germany (DE)'), findsOneWidget);
  });

  testWidgets(
      '"Enter manually" turns the unknown battery into the user\'s '
      'own value, which a new detection never replaces', (tester) async {
    final h = await _pump(tester,
        system: FakeSystem(deviceInfo: {
          ...FakeSystem.defaultDeviceInfo(HarnessPlatform.ios),
          'modelIdentifier': 'iPhone99,9',
        }));
    expect(h.container(tester).read(settingsProvider).designCapacityMah, 0,
        reason: 'unknown stays unknown: no "typical" capacity is invented');
    expect(h.container(tester).read(settingsProvider).designCapacitySource,
        DesignCapacitySource.unknown);

    await tester.tap(find.text(_en.enterManually).first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '5000');
    await tester.tap(find.text(_en.save));
    await settle(tester);

    var s = h.container(tester).read(settingsProvider);
    expect(s.designCapacityMah, 5000);
    expect(s.designCapacitySource, DesignCapacitySource.manual);
    // The typed figure is also what the server is told (the design group, as
    // "manual"), not only what the app shows.
    await settle(tester);
    final registered = h.backend.where('POST', '/api/v1/devices').last.body!;
    expect(registered['designCapacityMah'], 5000);
    expect(registered['designCapacitySource'], 'manual');
    expect(
        semanticsNode(
            tester,
            exactly('${_en.setupBattery}, 5,000 mAh, ${_en.regionManual}, '
                '${_en.edit}')),
        isSemantics(isButton: true));

    // "Detect again" re-runs the detection; the manual value stays.
    await tester.scrollUntilVisible(find.text(_en.detectAgain), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text(_en.detectAgain));
    await tester.pump();
    await tester.tap(find.text(_en.detectAgain));
    await settle(tester);
    s = h.container(tester).read(settingsProvider);
    expect(s.designCapacityMah, 5000);
    expect(s.designCapacitySource, DesignCapacitySource.manual);
  });
}
