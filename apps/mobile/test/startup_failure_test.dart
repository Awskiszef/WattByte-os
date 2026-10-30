// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// A storage failure before the first frame ends in a recovery screen, not a blank launch screen (audit F-07).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/config/startup_failure.dart';
import 'package:wattbyte/storage/database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('startGuarded', () {
    test('runs the app when the storage opens', () async {
      final ran = <Widget>[];
      await startGuarded(
        build: () async => const SizedBox(key: Key('app')),
        resetLocalData: () async => fail('no reset expected'),
        run: ran.add,
      );
      expect(ran, hasLength(1));
      expect(ran.single.key, const Key('app'));
    });

    test(
        'shows the recovery app when the storage fails, and retries into the real app',
        () async {
      final ran = <Widget>[];
      var attempts = 0;
      await startGuarded(
        build: () async {
          attempts++;
          if (attempts == 1) {
            throw const FormatException('file is not a database');
          }
          return const SizedBox(key: Key('app'));
        },
        resetLocalData: () async => fail('no reset expected'),
        run: ran.add,
      );
      expect(ran.single, isA<StartupFailureApp>());
      await (ran.single as StartupFailureApp).onRetry();
      expect(attempts, 2);
      expect(ran.last.key, const Key('app'));
    });

    test('a failing retry shows the recovery app again instead of throwing',
        () async {
      final ran = <Widget>[];
      await startGuarded(
        build: () async => throw StateError('disk full'),
        resetLocalData: () async {},
        run: ran.add,
      );
      await (ran.single as StartupFailureApp).onRetry();
      expect(ran, hasLength(2));
      expect(ran.every((w) => w is StartupFailureApp), isTrue);
    });

    test('the reset moves the data aside first, then starts again', () async {
      final order = <String>[];
      final ran = <Widget>[];
      var failing = true;
      await startGuarded(
        build: () async {
          order.add('build');
          if (failing) throw StateError('corrupt');
          return const SizedBox(key: Key('app'));
        },
        resetLocalData: () async {
          order.add('reset');
          failing = false;
        },
        run: ran.add,
      );
      await (ran.single as StartupFailureApp).onResetLocalData();
      expect(order, ['build', 'reset', 'build']);
      expect(ran.last.key, const Key('app'));
    });
  });

  group('the recovery screen', () {
    Future<void> pump(WidgetTester tester,
        {required Future<void> Function() retry,
        required Future<void> Function() reset,
        String lang = 'en'}) async {
      await tester.pumpWidget(StartupFailureApp(
          onRetry: retry, onResetLocalData: reset, languageCode: lang));
    }

    testWidgets(
        'says what happened in plain words and offers retry; no error details',
        (tester) async {
      await pump(tester, retry: () async {}, reset: () async {});
      expect(find.text(StartupTexts.en.title), findsOneWidget);
      expect(find.text(StartupTexts.en.retry), findsOneWidget);
      expect(find.textContaining('not deleted'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('Polish phone: Polish text', (tester) async {
      await pump(tester, retry: () async {}, reset: () async {}, lang: 'pl');
      expect(find.text(StartupTexts.pl.title), findsOneWidget);
    });

    testWidgets(
        'retry calls back; the reset asks first and does nothing on Cancel',
        (tester) async {
      var retries = 0, resets = 0;
      await pump(tester,
          retry: () async => retries++, reset: () async => resets++);
      await tester.tap(find.text(StartupTexts.en.retry));
      await tester.pump();
      expect(retries, 1);

      await tester.tap(find.text(StartupTexts.en.reset));
      await tester.pumpAndSettle();
      expect(find.text(StartupTexts.en.confirmTitle), findsOneWidget);
      await tester.tap(find.text(StartupTexts.en.cancel));
      await tester.pumpAndSettle();
      expect(resets, 0);

      await tester.tap(find.text(StartupTexts.en.reset));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StartupTexts.en.confirmReset));
      await tester.pumpAndSettle();
      expect(resets, 1);
    });
  });

  group('moveBrokenFileAside', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wb-broken-db'));
    tearDown(() => dir.deleteSync(recursive: true));

    test(
        'a corrupt database: open fails, the file is moved (not deleted), the next open is a fresh database',
        () async {
      final path = '${dir.path}/wattbyte.db';
      File(path).writeAsStringSync('this is not a sqlite file at all' * 20);
      File('$path-wal').writeAsStringSync('stale wal');
      await expectLater(WattByteDb.open(path: path), throwsA(anything));

      // (SQLite may remove a stale log itself while the failed open runs)
      final walExisted = File('$path-wal').existsSync();
      final moved = await WattByteDb.moveBrokenFileAside(
          path: path, at: DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(moved, '$path.broken-1700000000000');
      expect(File(path).existsSync(), isFalse);
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File(moved!).readAsStringSync(),
          startsWith('this is not a sqlite file'),
          reason: 'kept, not deleted');
      expect(File('$path-wal.broken-1700000000000').existsSync(), walExisted);

      final db = await WattByteDb.open(path: path);
      addTearDown(db.close);
      expect(await db.allDaily(), isEmpty);
    });

    test('nothing to move is not an error', () async {
      expect(await WattByteDb.moveBrokenFileAside(path: '${dir.path}/none.db'),
          isNull);
    });
  });
}
