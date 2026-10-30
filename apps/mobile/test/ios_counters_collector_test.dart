// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// iOS data usage as the Collector books it from the 64-bit per-interface counters (audit G-09, H-03), through the real
// Collector, a scripted native side (FakeSystem) and a real in-memory SQLite database.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wattbyte/collection/collector.dart';
import 'package:wattbyte/storage/database.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

import 'support/fake_system.dart';

const _gib = 1024 * 1024 * 1024;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final t0 = DateTime(2026, 10, 13, 9);
  late DateTime now;
  late FakeSystem fake;
  late WattByteDb db;
  late Collector collector;

  setUp(() async {
    now = t0;
    fake = FakeSystem(platform: HarnessPlatform.ios, clock: () => now);
    db = await WattByteDb.openInMemory();
    collector = Collector(system: fake.system, db: db);
  });
  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  RawInterfaceCounters reading(Map<String, ({int rx, int tx})> ifaces) =>
      RawInterfaceCounters(
        wifiRx: 0,
        wifiTx: 0,
        cellRx: 0,
        cellTx: 0,
        bootTimeMs: t0.millisecondsSinceEpoch - 20 * 24 * 3600 * 1000,
        timeMs: now.millisecondsSinceEpoch,
        bits: 64,
        ifaces: ifaces,
      );

  Future<void> refresh(
      Duration after, Map<String, ({int rx, int tx})> ifaces) async {
    now = now.add(after);
    fake.counters = reading(ifaces);
    await collector.collect(now: now);
  }

  Future<({int wifi, int mobile})> totalForToday() async {
    final rows = await db.allDaily();
    final today = rows.where((d) => d.day == DateTime(2026, 10, 13));
    return (
      wifi: today.fold<int>(0, (a, d) => a + d.wifi),
      mobile: today.fold<int>(0, (a, d) => a + d.mobile),
    );
  }

  test(
      '9 GiB over Wi-Fi in one gap is stored in full; a cellular reset is not 4 GiB',
      () async {
    await refresh(Duration.zero, {
      'en0': (rx: 1 * _gib, tx: 0),
      'pdp_ip0': (rx: 500 * 1000 * 1000, tx: 0),
    });
    // Baseline only: nothing booked yet.
    expect((await totalForToday()).wifi, 0);

    // Three hours later: 9 GiB more on Wi-Fi, and the cellular counter restarted (airplane mode) at 30 MB.
    await refresh(const Duration(hours: 3), {
      'en0': (rx: 10 * _gib, tx: 0),
      'pdp_ip0': (rx: 30 * 1000 * 1000, tx: 0),
    });
    final total = await totalForToday();
    expect(total.wifi, 9 * _gib);
    expect(total.mobile, 30 * 1000 * 1000);
  });

  test(
      'the stored baseline survives a restart of the app (JSON round trip of the 64-bit state)',
      () async {
    await refresh(Duration.zero, {'en0': (rx: 2 * _gib, tx: 0)});
    final stored = await db.meta(Collector.metaIface);
    expect(stored, contains('"bits":64'));
    expect(stored, contains('en0'));
    // A new Collector on the same database continues from that baseline.
    collector = Collector(system: fake.system, db: db);
    await refresh(
        const Duration(hours: 1), {'en0': (rx: 2 * _gib + 1234, tx: 0)});
    expect((await totalForToday()).wifi, 1234);
  });

  test(
      'a 32-bit baseline from an older build is replaced by the first 64-bit reading without booking anything',
      () async {
    now = t0;
    fake.counters = RawInterfaceCounters(
      wifiRx: 4000000000,
      wifiTx: 0,
      cellRx: 0,
      cellTx: 0,
      bootTimeMs: t0.millisecondsSinceEpoch - 20 * 24 * 3600 * 1000,
      timeMs: now.millisecondsSinceEpoch,
    );
    await collector.collect(now: now);
    await refresh(const Duration(hours: 1), {'en0': (rx: 1000, tx: 0)});
    expect((await totalForToday()).wifi, 0);
    await refresh(const Duration(hours: 1), {'en0': (rx: 3000, tx: 0)});
    expect((await totalForToday()).wifi, 2000);
  });
}
