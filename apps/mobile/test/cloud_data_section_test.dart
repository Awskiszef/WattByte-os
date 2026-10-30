// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Data-subject rights reachable from the app (audit F-15): a copy of the cloud data, erasing it without deleting the account,
// removing a device. The API already offered all three; the Account screen now does too.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/api/api_failure.dart';
import 'package:wattbyte/cloud_providers.dart';
import 'package:wattbyte/features/auth/presentation/account_screen.dart';
import 'package:wattbyte/providers.dart';
import 'package:wattbyte/sync/sync_models.dart';
import 'package:wattbyte/sync/cloud_data_service.dart';

import 'support/app_harness.dart';

Map<String, Object?> device(String id,
        {String? model = 'Pixel 8', String platform = 'android'}) =>
    {
      'id': id,
      'installationId': 'install-$id-0000',
      'platform': platform,
      'model': model,
      'modelIdentifier': null,
      'designCapacityMah': null,
      'designCapacityWh': null,
      'designCapacitySource': null,
      'estimatedFullChargeCapacityMah': null,
      'estimatedFullChargeCapacityWh': null,
      'fullChargeCapacitySource': null,
      'fullChargeCapacityConfidence': null,
      'createdAt': '2026-10-01T10:00:00.000Z',
      'lastSeenAt': '2026-10-20T10:00:00.000Z',
    };

const erased = {
  'deleted': {
    'dailyUsage': 31,
    'chargingSummaries': 0,
    'monthlySummaries': 0,
    'aiGenerations': 12,
    'devices': 0
  }
};

void main() {
  group('CloudDataService', () {
    testWidgets(
        'lists devices, removes one, erases with devices=false and exports the bytes untouched',
        (tester) async {
      final h = await pumpScreen(tester, const SizedBox());
      h.backend.routes['GET /api/v1/devices'] = (_) => FakeBackend.json({
            'devices': [
              device('d1'),
              device('d2', model: null, platform: 'ios')
            ]
          });
      h.backend.routes['DELETE /api/v1/devices/d2'] =
          (_) => FakeBackend.json({'ok': true});
      h.backend.routes['DELETE /api/v1/me/cloud-data'] =
          (_) => FakeBackend.json(erased);
      const body =
          '{"schemaVersion":1,"fromTheFuture":{"kept":true},"dailyUsage":[]}';
      h.backend.routes['GET /api/v1/me/export'] =
          (_) => FakeBackend.json(jsonDecode(body));
      final service = h.container(tester).read(cloudDataServiceProvider)!;

      await tester.runAsync(() async {
        expect((await service.devices()).map((d) => d.id), ['d1', 'd2']);
        await service.removeDevice('d2');
        final deleted = await service.eraseCloudData();
        expect(deleted.deleted.dailyUsage, 31);
        final bytes = await service.exportDocument();
        expect(jsonDecode(utf8.decode(bytes)), jsonDecode(body),
            reason: 'including keys this client does not know');
      });
      expect(
          h.backend
              .where('DELETE', '/api/v1/devices/d2')
              .single
              .headers['authorization'],
          startsWith('Bearer '));
      final erase = h.backend.where('DELETE', '/api/v1/me/cloud-data').single;
      expect(erase.query, isNot(contains('devices=true')),
          reason: 'the devices stay unless asked');
    });

    testWidgets('a server failure is an ApiFailure', (tester) async {
      final h = await pumpScreen(tester, const SizedBox());
      h.backend.routes['DELETE /api/v1/me/cloud-data'] =
          (_) => FakeBackend.error(500, 'internal');
      final service = h.container(tester).read(cloudDataServiceProvider)!;
      await tester.runAsync(() async {
        await expectLater(
            service.eraseCloudData(),
            throwsA(isA<ApiFailure>()
                .having((f) => f.kind, 'kind', ApiFailureKind.server)));
      });
    });

    test('the export file is named after the local date', () {
      expect(CloudDataService.exportFileName(DateTime(2026, 3, 5, 23, 59)),
          'wattbyte-cloud-export-2026-03-05.json');
    });
  });

  group('Account screen', () {
    /// The account screen of a signed-in user whose account has cloud sync switched ON (the ledger, not a flag).
    Future<AppHarness> open(WidgetTester tester) async {
      final h = await pumpScreen(tester, const AccountScreen());
      final c = h.container(tester);
      await tester.runAsync(() async {
        await c.read(syncServiceProvider)!.enable(SyncScope.fromNow);
        await c.read(syncAccountProvider.notifier).refresh();
      });
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).cloudSync, isTrue,
          reason: 'the precondition: sync is on');
      return h;
    }

    Future<void> tapButton(WidgetTester tester, String label) async {
      final finder = find.widgetWithText(OutlinedButton, label);
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the section with its three actions', (tester) async {
      await open(tester);
      expect(find.text('Your data in the cloud'), findsOneWidget);
      for (final label in [
        'Download a copy',
        'Devices in the cloud',
        'Erase my cloud data'
      ]) {
        expect(find.widgetWithText(OutlinedButton, label), findsOneWidget,
            reason: label);
      }
    });

    testWidgets('erasing asks first; cancel sends nothing', (tester) async {
      final h = await open(tester);
      h.backend.routes['DELETE /api/v1/me/cloud-data'] =
          (_) => FakeBackend.json(erased);
      await tapButton(tester, 'Erase my cloud data');
      expect(
          find.textContaining(
              'Your account, your settings and the data on this phone stay'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.backend.where('DELETE', '/api/v1/me/cloud-data'), isEmpty);
    });

    testWidgets('confirming erases, switches cloud sync off and says so',
        (tester) async {
      final h = await open(tester);
      h.backend.routes['DELETE /api/v1/me/cloud-data'] =
          (_) => FakeBackend.json(erased);
      await tapButton(tester, 'Erase my cloud data');
      await tester.tap(find.widgetWithText(TextButton, 'Erase my cloud data'));
      await tester.pumpAndSettle();
      expect(h.backend.where('DELETE', '/api/v1/me/cloud-data'), hasLength(1));
      expect(
          find.text('Cloud data erased. Cloud sync is off.'), findsOneWidget);
      expect(h.container(tester).read(settingsProvider).cloudSync, isFalse);
    });

    testWidgets(
        'a failed erase says nothing was changed and leaves cloud sync as it was',
        (tester) async {
      final h = await open(tester);
      h.backend.routes['DELETE /api/v1/me/cloud-data'] =
          (_) => FakeBackend.error(500, 'internal');
      await tapButton(tester, 'Erase my cloud data');
      await tester.tap(find.widgetWithText(TextButton, 'Erase my cloud data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(find.text('Cloud data erased. Cloud sync is off.'), findsNothing);
      expect(h.container(tester).read(settingsProvider).cloudSync, isTrue);
    });

    testWidgets(
        'the device list shows the devices, removing one asks first and then drops the row',
        (tester) async {
      final h = await open(tester);
      h.backend.routes['GET /api/v1/devices'] = (_) => FakeBackend.json({
            'devices': [
              device('d1'),
              device('d2', model: null, platform: 'ios')
            ]
          });
      h.backend.routes['DELETE /api/v1/devices/d2'] =
          (_) => FakeBackend.json({'ok': true});
      await tapButton(tester, 'Devices in the cloud');
      expect(find.text('Pixel 8 (android)'), findsOneWidget);
      expect(find.text('Unnamed device (ios)'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('The data on the phone itself is not touched'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.backend.where('DELETE', '/api/v1/devices/d2'), isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(h.backend.where('DELETE', '/api/v1/devices/d2'), hasLength(1));
      expect(find.text('Unnamed device (ios)'), findsNothing);
      expect(find.text('Pixel 8 (android)'), findsOneWidget);
      expect(find.text('Device removed.'), findsOneWidget);
    });

    testWidgets(
        'a device that cannot be removed stays in the list with a message',
        (tester) async {
      final h = await open(tester);
      h.backend.routes['GET /api/v1/devices'] = (_) => FakeBackend.json({
            'devices': [device('d1')]
          });
      h.backend.routes['DELETE /api/v1/devices/d1'] =
          (_) => FakeBackend.error(500, 'internal');
      await tapButton(tester, 'Devices in the cloud');
      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove').last);
      await tester.pumpAndSettle();
      expect(find.text('Pixel 8 (android)'), findsOneWidget);
      expect(find.text('Could not remove the device. Nothing was changed.'),
          findsOneWidget);
    });

    testWidgets(
        'an unreachable server while loading the devices is a message, not a crash',
        (tester) async {
      final h = await open(tester);
      h.backend.offline = true;
      await tapButton(tester, 'Devices in the cloud');
      expect(
          find.textContaining('Could not load your devices'), findsOneWidget);
    });

    testWidgets(
        'the copy is downloaded as received and handed to the share sheet under a dated name',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('wb_cloud_export');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final shared = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getTemporaryDirectory' ? tmp.path : null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'), (call) async {
        shared.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'), null);
      });
      final h = await open(tester);
      h.backend.routes['GET /api/v1/me/export'] =
          (_) => FakeBackend.json({'schemaVersion': 1, 'dailyUsage': []});
      await tester.scrollUntilVisible(
          find.widgetWithText(OutlinedButton, 'Download a copy'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Download a copy'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (shared.isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      expect(h.backend.where('GET', '/api/v1/me/export'), hasLength(1));
      expect(shared, hasLength(1));
      final files = (shared.single.arguments as Map)['paths'] as List;
      expect(files.single as String,
          matches(RegExp(r'wattbyte-cloud-export-\d{4}-\d{2}-\d{2}\.json$')));
      expect(jsonDecode(File(files.single as String).readAsStringSync()),
          {'schemaVersion': 1, 'dailyUsage': []});
    });

    testWidgets('a failed download says so', (tester) async {
      final h = await open(tester);
      h.backend.routes['GET /api/v1/me/export'] =
          (_) => FakeBackend.error(500, 'internal');
      await tapButton(tester, 'Download a copy');
      expect(
          find.textContaining('Could not download your data'), findsOneWidget);
    });
  });
}
