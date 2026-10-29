// "Reset statistics" is not undone by the next collection on Android (audit G-17).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/storage/database.dart';

import 'support/fake_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final t0 = DateTime(2026, 10, 20, 9);
  late DateTime now;
  late FakeSystem fake;
  late WattByteDb db;
  late Collector collector;

  setUp(() async {
    now = t0;
    fake = FakeSystem(
        platform: HarnessPlatform.android, batteryLevel: 50, clock: () => now);
    db = await WattByteDb.openInMemory();
    collector = Collector(system: fake.system, db: db);
  });
  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  int fromMsOfLastQuery() =>
      (fake.callsTo('queryDataDaily').last.arguments as Map)['fromMs'] as int;

  Map<String, Object?> workerSample(DateTime at, int level) => {
        'timeMs': at.millisecondsSinceEpoch,
        'level': level,
        'plugged': true,
        'chargeUah': null,
        'energyNwh': null,
        'voltageMv': null,
        'source': 'worker',
      };

  test('before any reset the Android collector reads the system\'s 90 days',
      () async {
    await collector.collect(now: now);
    expect(DateTime.fromMillisecondsSinceEpoch(fromMsOfLastQuery()),
        DateTime(2026, 10, 20 - Collector.androidHistoryDays));
  });

  test('after a reset it never reads behind the reset day, also on later days',
      () async {
    await collector.collect(now: now);
    await db.resetAll(at: now);
    expect(await db.resetAt(), now);

    now = t0.add(const Duration(hours: 2));
    await collector.collect(now: now);
    expect(DateTime.fromMillisecondsSinceEpoch(fromMsOfLastQuery()),
        DateTime(2026, 10, 20));

    now = DateTime(2026, 10, 23, 8);
    await collector.collect(now: now);
    expect(DateTime.fromMillisecondsSinceEpoch(fromMsOfLastQuery()),
        isNot(DateTime(2026, 10, 20 - Collector.androidHistoryDays)));
    expect(
        DateTime.fromMillisecondsSinceEpoch(fromMsOfLastQuery())
            .isBefore(DateTime(2026, 10, 20)),
        isFalse);
  });

  test(
      'worker samples recorded before the reset are discarded (and acknowledged), later ones are kept',
      () async {
    await db.resetAll(at: t0);
    fake.plugged = true; // an open charge: its samples stay in the table
    fake.pendingSamples = [
      workerSample(t0.subtract(const Duration(hours: 3)), 40),
      workerSample(t0.subtract(const Duration(minutes: 1)), 41),
      workerSample(t0.add(const Duration(minutes: 5)), 45),
    ];
    now = t0.add(const Duration(minutes: 10));
    await collector.collect(now: now);
    final stored = (await db.samples())
        .where((s) => s.source == 'worker')
        .map((s) => s.level)
        .toList();
    expect(stored, [45]);
    expect(fake.pendingSamples, isEmpty,
        reason: 'acknowledged, so not delivered again');
  });

  test(
      'the reset instant survives a second reset and the wipe keeps nothing else',
      () async {
    await db.setMeta('some_other_key', 'x');
    await db.resetAll(at: t0);
    expect(await db.meta('some_other_key'), isNull);
    final later = t0.add(const Duration(days: 1));
    await db.resetAll(at: later);
    expect(await db.resetAt(), later);
  });
}
