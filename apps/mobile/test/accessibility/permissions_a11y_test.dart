// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Permissions: explanation first, system prompt only after a tap; responsive
// on iOS and Android.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/ui/onboarding/permissions_screen.dart';

import '../support/app_harness.dart';
import 'flow_matrix_support.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

void main() {
  for (final platform in HarnessPlatform.values) {
    testWidgets(
        'fits every phone, scale, brightness and language '
        '(${platform.name})', (tester) async {
      final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
          platform: platform, historyDays: 0, semantics: true);
      await sweepFlow(tester, h,
          screen: 'Permissions ${platform.name}', scroll: true);
    });

    testWidgets('does not throw on wide layouts (${platform.name})',
        (tester) async {
      final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
          platform: platform, historyDays: 0);
      await sweepFlow(tester, h,
          screen: 'Permissions ${platform.name} (wide)',
          devices: kWide,
          scales: const [1.0, 2.0, 3.0],
          scroll: true,
          targets: false);
    });
  }

  testWidgets('Android with usage access denied still fits', (tester) async {
    final system = FakeSystem(
        platform: HarnessPlatform.android, usageAccessGranted: false);
    final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
        platform: HarnessPlatform.android,
        historyDays: 0,
        semantics: true,
        harness: await AppHarness.create(tester,
            platform: HarnessPlatform.android, historyDays: 0, system: system));
    await sweepFlow(tester, h,
        screen: 'Permissions Android (denied)', scroll: true);
    await h.setTextScale(tester, 1.0);
    expect(find.byType(OutlinedButton), findsWidgets);
  });

  testWidgets('text contrast', (tester) async {
    final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
        historyDays: 0);
    await expectReadableContrast(tester, h, screen: 'Permissions');
  });

  testWidgets('the explanation comes first: nothing is requested until a tap',
      (tester) async {
    var done = 0;
    final h = await pumpScreen(tester, PermissionsScreen(onDone: () => done++),
        historyDays: 0, semantics: true);
    expect(find.text(_en.permNotificationsBody), findsOneWidget);
    expect(find.text(_en.permIosTitle), findsOneWidget);
    expect(h.notifier.permissionRequests, 0,
        reason: 'no system prompt just for showing the screen');
    expect(find.text(_en.granted), findsNothing);

    await tester.tap(find.text(_en.enableNotifications));
    await settle(tester);
    expect(h.notifier.permissionRequests, 1);
    expect(find.text(_en.granted), findsOneWidget);
    expect(
        h.container(tester).read(settingsProvider).notifyChargingDone, isTrue);

    expect(done, 0, reason: 'granting does not leave the screen');
    await tester.tap(find.text(_en.getStarted));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('declining the system prompt keeps the button and the setting',
      (tester) async {
    final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
        historyDays: 0);
    h.notifier.permissionGranted = false;
    await tester.tap(find.text(_en.enableNotifications));
    await settle(tester);
    expect(h.notifier.permissionRequests, 1);
    expect(find.text(_en.granted), findsNothing);
    expect(find.text(_en.enableNotifications), findsOneWidget);
    expect(
        h.container(tester).read(settingsProvider).notifyChargingDone, isFalse);
  });

  testWidgets('Android: the usage-access settings open only after a tap',
      (tester) async {
    final system = FakeSystem(
        platform: HarnessPlatform.android, usageAccessGranted: false);
    final h = await pumpScreen(tester, PermissionsScreen(onDone: () {}),
        platform: HarnessPlatform.android,
        historyDays: 0,
        harness: await AppHarness.create(tester,
            platform: HarnessPlatform.android, historyDays: 0, system: system));
    expect(system.callsTo('openUsageAccessSettings'), isEmpty);
    expect(find.text(_en.permUsageBody), findsOneWidget);
    expect(h.notifier.permissionRequests, 0);
    await tester.tap(find.text(_en.usageAccessButton));
    await settle(tester);
    expect(system.callsTo('openUsageAccessSettings'), hasLength(1));
  });

  for (final (name, l, locale) in [
    ('English', _en, const Locale('en')),
    ('Polish', _pl, const Locale('pl')),
  ]) {
    testWidgets(
        'semantics ($name): headings, named buttons, and "Granted" is '
        'announced', (tester) async {
      await pumpScreen(tester, PermissionsScreen(onDone: () {}),
          historyDays: 0, semantics: true, locale: locale);
      for (final heading in [l.permissionsTitle, l.permNotificationsTitle]) {
        expect(tester.getSemantics(find.text(heading)),
            isSemantics(isHeader: true, label: heading));
      }
      expect(semanticsNode(tester, exactly(l.enableNotifications)),
          isSemantics(isButton: true, hasTapAction: true));
      expect(semanticsNode(tester, exactly(l.getStarted)),
          isSemantics(isButton: true, hasTapAction: true));

      await tester.tap(find.text(l.enableNotifications));
      await settle(tester);
      expect(semanticsNode(tester, exactly(l.granted)),
          isSemantics(isLiveRegion: true));
      expect(semanticsCount(tester, exactly(l.enableNotifications)), 0);
    });
  }
}
