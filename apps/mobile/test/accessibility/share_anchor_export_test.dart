// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Regression for the iOS 26+ share-sheet crash ("sharePositionOrigin must be
// non-zero"): the Export rows of Settings hand the real share channel a
// non-empty anchor, a localized subject, and a failure becomes a message.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/l10n/generated/app_localizations_en.dart';
import 'package:wattbyte/l10n/generated/app_localizations_pl.dart';
import 'package:wattbyte/ui/settings/settings_screen.dart';

import '../support/app_harness.dart';

final _en = AppLocalizationsEn();
final _pl = AppLocalizationsPl();

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

/// Mocks the two plugin channels the export touches; returns the calls the
/// share channel received.
List<MethodCall> _mockChannels(WidgetTester tester, {bool shareFails = false}) {
  final tmp = Directory.systemTemp.createTempSync('wb_export_test');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final shared = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_pathChannel, (call) async {
    if (call.method == 'getTemporaryDirectory') return tmp.path;
    return null;
  });
  messenger.setMockMethodCallHandler(_shareChannel, (call) async {
    shared.add(call);
    if (shareFails) {
      throw PlatformException(
          code: 'error',
          message: 'sharePositionOrigin: argument must be set, '
              '{{0, 0}, {0, 0}} must be non-zero and within coordinate space');
    }
    return 'dev.fluttercommunity.plus/share/success';
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(_pathChannel, null);
    messenger.setMockMethodCallHandler(_shareChannel, null);
  });
  return shared;
}

/// Taps [label] and waits (in real time: the export writes real files) until
/// [done] is true.
Future<void> _tapAndWait(
    WidgetTester tester, String label, bool Function() done,
    {int millis = 5000}) async {
  await tester.scrollUntilVisible(find.text(label), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  // The export reads the database (fake-async microtasks: pump) and writes
  // real files (real I/O: let real time pass).
  final deadline = DateTime.now().add(Duration(milliseconds: millis));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump();
}

Rect _anchorOf(MethodCall call) {
  final a = call.arguments as Map<Object?, Object?>;
  return Rect.fromLTWH(
      (a['originX']! as num).toDouble(),
      (a['originY']! as num).toDouble(),
      (a['originWidth']! as num).toDouble(),
      (a['originHeight']! as num).toDouble());
}

void main() {
  for (final (label, json) in [
    (_en.exportCsv, false),
    (_en.exportJson, true)
  ]) {
    testWidgets('"$label" shares with the tapped row as a non-empty anchor',
        (tester) async {
      final shared = _mockChannels(tester);
      await pumpScreen(tester, const SettingsScreen(), scaffold: true);

      await _tapAndWait(tester, label, () => shared.isNotEmpty);

      expect(shared, hasLength(1), reason: 'the share sheet was opened once');
      final call = shared.single;
      expect(call.method, 'shareFiles');
      final anchor = _anchorOf(call);
      expect(anchor.width, greaterThan(0));
      expect(anchor.height, greaterThan(0));
      expect(anchor.isFinite, isTrue);

      // Anchored to the row that was tapped, not to the whole list.
      final row = tester.getRect(find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first);
      expect(anchor.left, closeTo(row.left, 0.5));
      expect(anchor.top, closeTo(row.top, 0.5));
      expect(anchor.width, closeTo(row.width, 0.5));
      expect(anchor.height, closeTo(row.height, 0.5));

      final paths = (call.arguments as Map)['paths'] as List;
      expect(paths, hasLength(json ? 1 : 2));
      expect(paths.every((p) => File(p as String).existsSync()), isTrue);
      expect(find.text(_en.exportFailed), findsNothing);
    });
  }

  testWidgets('the subject follows the app language', (tester) async {
    final shared = _mockChannels(tester);
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, locale: const Locale('pl'));
    await _tapAndWait(tester, _pl.exportJson, () => shared.isNotEmpty);
    expect((shared.single.arguments as Map)['subject'], _pl.shareSubject);
    expect(_pl.shareSubject, isNot(_en.shareSubject));
  });

  testWidgets('a refusing share sheet becomes a message, not a crash',
      (tester) async {
    final shared = _mockChannels(tester, shareFails: true);
    await pumpScreen(tester, const SettingsScreen(), scaffold: true);
    await _tapAndWait(tester, _en.exportCsv, () => shared.isNotEmpty);
    await settle(tester);
    expect(find.text(_en.exportFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the anchor is non-empty at 3x on a small phone too',
      (tester) async {
    final shared = _mockChannels(tester);
    await pumpScreen(tester, const SettingsScreen(),
        scaffold: true, device: kIPhoneSE, textScale: 3.0);
    await _tapAndWait(tester, _en.exportCsv, () => shared.isNotEmpty);
    final anchor = _anchorOf(shared.single);
    expect(anchor.width, greaterThan(0));
    expect(anchor.height, greaterThan(0));
  });
}
