// G-01: on Android the WorkManager task runs in its own FlutterEngine inside the
// SAME process as the UI. sqflite_android keeps its single-instance registry in JVM
// statics shared by every engine, answers a second `singleInstance` open of a path with
// the SAME native database id, and `close` has no reference count: the background
// engine's `db.close()` closed the connection the UI isolate kept using, and every
// later UI read failed with `database_closed` until Android killed the process.
//
// [_AndroidRegistryFactory] models exactly that sharing on top of real SQLite files, so
// the tests below fail on the old code (background path = `WattByteDb.open()` + close)
// and pass when the background isolate owns its connection.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/background/background_tasks.dart';
import 'package:wattbyte/domain/models.dart';
import 'package:wattbyte/storage/database.dart';

BatterySample _sample(int ms, {String source = 'app'}) => BatterySample(
    time: DateTime.fromMillisecondsSinceEpoch(ms),
    level: 50,
    plugged: true,
    source: source);

/// Runs in a separate isolate: the background connection, writing as the worker does.
/// Returns "journal mode/busy timeout/foreign keys" as the connection saw them.
Future<String> _workerPass(String path) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  return withBackgroundDb(path: path, (db) async {
    for (var batch = 0; batch < 60; batch++) {
      await db.insertSamples([
        for (var i = 0; i < 25; i++) _sample(batch * 1000 + i, source: 'worker')
      ]);
    }
    Future<Object?> pragma(String name) async =>
        (await db.rawDatabase.rawQuery('PRAGMA $name')).single.values.single;
    return '${(await pragma('journal_mode')).toString().toLowerCase()}/'
        '${await pragma('busy_timeout')}/${await pragma('foreign_keys')}';
  });
}

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wb_g01_');
    path = '${dir.path}/wattbyte.db';
    databaseFactory = databaseFactoryFfi;
  });
  tearDown(() async {
    databaseFactory = databaseFactoryFfi;
    await dir.delete(recursive: true);
  });

  test(
      'model check: a second holder of the shared handle that closes it kills the first (the G-01 mechanism)',
      () async {
    final ui = await WattByteDb.open(path: path);
    final background = await WattByteDb.open(path: path);
    await ui.insertSamples([_sample(1000)]);

    await background.close();

    await expectLater(ui.samples(), throwsA(isA<DatabaseException>()),
        reason:
            'if this model stopped reproducing the bug, the tests below prove nothing');
  });

  test('the background refresh path leaves the UI connection open and working',
      () async {
    final ui = await WattByteDb.open(path: path);
    addTearDown(ui.close);
    await ui.insertSamples([_sample(1000)]);

    await withBackgroundDb(path: path, (db) async {
      // The background isolate sees what the UI wrote and writes its own reading.
      expect(await db.samples(), hasLength(1));
      await db.insertSamples([_sample(2000, source: 'worker')]);
    });

    expect(ui.rawDatabase.isOpen, isTrue);
    expect((await ui.samples()).map((s) => s.time.millisecondsSinceEpoch),
        [1000, 2000],
        reason: 'the UI keeps reading, and sees the background write');
    await ui.insertSamples([_sample(3000)]); // and keeps writing
    expect(await ui.samples(), hasLength(3));
  });

  test('the background connection is closed again, also when the work throws',
      () async {
    final ui = await WattByteDb.open(path: path);
    addTearDown(ui.close);
    late WattByteDb seen;
    await expectLater(
        withBackgroundDb(path: path, (db) async {
          seen = db;
          throw StateError('refresh failed');
        }),
        throwsStateError);
    expect(seen.rawDatabase.isOpen, isFalse);
    expect(ui.rawDatabase.isOpen, isTrue);
    expect(await ui.samples(), isEmpty);
  });

  test(
      'a worker pass in another isolate and a foreground pass wait for each other instead of failing with "database is locked"',
      () async {
    final ui = await WattByteDb.open(path: path);
    addTearDown(ui.close);

    // The real topology: the WorkManager task runs in its own isolate (its own
    // thread, its own sqlite) beside the UI isolate.
    final worker = Isolate.run(() => _workerPass(path));
    for (var batch = 0; batch < 60; batch++) {
      await ui.insertSamples([
        for (var i = 0; i < 25; i++) _sample(batch * 1000 + i, source: 'app')
      ]);
    }
    expect(await worker, 'wal/5000/1');

    final journal = await ui.rawDatabase.rawQuery('PRAGMA journal_mode');
    expect(journal.single.values.single.toString().toLowerCase(), 'wal');
    final busy = await ui.rawDatabase.rawQuery('PRAGMA busy_timeout');
    expect(busy.single.values.single, WattByteDb.busyTimeoutMs);

    final all = await ui.samples();
    expect(all.where((s) => s.source == 'app'), hasLength(60 * 25));
    expect(all.where((s) => s.source == 'worker'), hasLength(60 * 25));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('an in-memory database is not put in WAL mode (it has no file)',
      () async {
    final db = await WattByteDb.openInMemory();
    addTearDown(db.close);
    final journal = await db.rawDatabase.rawQuery('PRAGMA journal_mode');
    expect(journal.single.values.single.toString().toLowerCase(), 'memory');
  });
}
