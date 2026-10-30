// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/collection/counter_folder.dart';

CounterState c(DateTime t, {int wifiRx = 0, int cellRx = 0, int boot = 1000}) =>
    CounterState(
      wifiRx: wifiRx,
      wifiTx: 0,
      cellRx: cellRx,
      cellTx: 0,
      bootTimeMs: boot,
      timeMs: t.millisecondsSinceEpoch,
    );

void main() {
  test('same-day delta lands on that day, flagged estimated', () {
    final out = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 100),
      c(DateTime(2026, 10, 13, 12), wifiRx: 700, cellRx: 50),
    );
    expect(out, hasLength(1));
    expect(out.single.day, DateTime(2026, 10, 13));
    expect(out.single.wifiRx, 600);
    expect(out.single.mobileRx, 50);
    expect(out.single.estimated, isTrue);
  });

  test('spreads across midnight proportionally to time', () {
    final out = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 18), wifiRx: 0),
      c(DateTime(2026, 10, 14, 6), wifiRx: 1200),
    );
    expect(out.map((d) => d.day),
        [DateTime(2026, 10, 13), DateTime(2026, 10, 14)]);
    expect(out[0].wifiRx, 600);
    expect(out[1].wifiRx, 600);
  });

  test('handles a 32-bit wrap and a reboot', () {
    final wrapped = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 4294967000),
      c(DateTime(2026, 10, 13, 11), wifiRx: 1000),
    );
    expect(wrapped.single.wifiRx, 1296);

    final rebooted = CounterFolder.fold(
      c(DateTime(2026, 10, 13, 10), wifiRx: 5000, boot: 1000),
      c(DateTime(2026, 10, 13, 11), wifiRx: 300, boot: 999000),
    );
    expect(rebooted.single.wifiRx, 300);
  });

  test('first sample is a baseline only', () {
    expect(CounterFolder.fold(null, c(DateTime(2026, 10, 13), wifiRx: 10)),
        isEmpty);
  });

  group('64-bit per-interface counters (G-09, H-03)', () {
    const gib = 1024 * 1024 * 1024;
    CounterState c64(
      DateTime t,
      Map<String, ({int rx, int tx})> ifaces, {
      int? boot,
    }) =>
        CounterState(
          wifiRx: 0,
          wifiTx: 0,
          cellRx: 0,
          cellTx: 0,
          // A boot time far in the past by default: uptime is large and only grows.
          bootTimeMs: boot ?? t.millisecondsSinceEpoch - 30 * 24 * 3600 * 1000,
          timeMs: t.millisecondsSinceEpoch,
          bits: 64,
          ifaces: ifaces,
        );
    final t0 = DateTime(2026, 10, 13, 10);
    final t1 = DateTime(2026, 10, 13, 14);

    test('9 GiB over Wi-Fi between two samples is booked in full', () {
      final out = CounterFolder.fold(
        c64(t0, {'en0': (rx: 1 * gib, tx: 0)}, boot: 1),
        c64(t1, {'en0': (rx: 10 * gib, tx: 5)}, boot: 1),
      );
      expect(out.single.wifiRx, 9 * gib);
      expect(out.single.wifiTx, 5);
    });

    test(
        'a counter that restarts without a reboot books the new value, not 4 GiB',
        () {
      final out = CounterFolder.fold(
        c64(t0, {'pdp_ip0': (rx: 500 * 1000 * 1000, tx: 0)}),
        c64(t1, {'pdp_ip0': (rx: 40 * 1000 * 1000, tx: 0)}),
      );
      expect(out.single.mobileRx, 40 * 1000 * 1000);
    });

    test(
        'an interface that disappears does not change the others (no phantom decrease)',
        () {
      final out = CounterFolder.fold(
        c64(t0, {
          'pdp_ip0': (rx: 700 * 1000 * 1000, tx: 0),
          'pdp_ip1': (rx: 300 * 1000 * 1000, tx: 0),
        }),
        c64(t1, {'pdp_ip0': (rx: 710 * 1000 * 1000, tx: 0)}),
      );
      expect(out.single.mobileRx, 10 * 1000 * 1000);
    });

    test('an interface that appears counts from zero', () {
      final out = CounterFolder.fold(
        c64(t0, {'pdp_ip0': (rx: 10, tx: 0)}),
        c64(t1, {'pdp_ip0': (rx: 15, tx: 0), 'pdp_ip1': (rx: 2000, tx: 100)}),
      );
      expect(out.single.mobileRx, 2005);
      expect(out.single.mobileTx, 100);
    });

    test('interfaces other than en0 and pdp_ip* are not counted', () {
      final out = CounterFolder.fold(
        c64(t0, {'lo0': (rx: 0, tx: 0), 'en0': (rx: 0, tx: 0)}),
        c64(t1, {'lo0': (rx: 99 * gib, tx: 0), 'en0': (rx: 7, tx: 0)}),
      );
      expect(out.single.wifiRx, 7);
      expect(out.single.mobile, 0);
    });

    test(
        'a clock step moves the boot time but is not a reboot: counters keep their baseline',
        () {
      // Wall clock stepped back 40 s between the samples; kern.boottime moved with it. Uptime did not shrink.
      final boot0 = t0.millisecondsSinceEpoch - 1000 * 3600;
      final out = CounterFolder.fold(
        c64(t0, {'en0': (rx: 1000, tx: 0)}, boot: boot0),
        c64(t1, {'en0': (rx: 3000, tx: 0)}, boot: boot0 - 40000),
      );
      expect(out.single.wifiRx, 2000);
    });

    test(
        'a reboot (uptime shrinks) books everything the counters hold since boot',
        () {
      final out = CounterFolder.fold(
        c64(t0, {'en0': (rx: 5000, tx: 0)},
            boot: t0.millisecondsSinceEpoch - 10 * 3600 * 1000),
        c64(t1, {'en0': (rx: 9000, tx: 0)},
            boot: t1.millisecondsSinceEpoch - 600 * 1000),
      );
      // 9000 since the reboot 10 minutes ago, although 9000 > 5000 would otherwise read as +4000.
      expect(out.single.wifiRx, 9000);
    });

    test(
        'an unknown boot time (0) says nothing about a reboot; the counters decide',
        () {
      final out = CounterFolder.fold(
        c64(t0, {'en0': (rx: 5000, tx: 0)}, boot: 0),
        c64(t1, {'en0': (rx: 9000, tx: 0)}, boot: 0),
      );
      expect(out.single.wifiRx, 4000);
    });

    test('a delta no link could carry in that time is dropped, not booked', () {
      // 1 TB in four hours is 69 MB/s; 1 TB in ten seconds is impossible.
      final fast = CounterFolder.fold(
        c64(t0, {'en0': (rx: 0, tx: 0)}),
        c64(t0.add(const Duration(seconds: 10)),
            {'en0': (rx: 1000 * gib, tx: 0)}),
      );
      expect(fast, isEmpty);
      final plausible = CounterFolder.fold(
        c64(t0, {'en0': (rx: 0, tx: 0)}),
        c64(t1, {'en0': (rx: 1000 * gib, tx: 0)}),
      );
      expect(plausible.single.wifiRx, 1000 * gib);
    });

    test(
        '32-bit and 64-bit readings are never compared: the first 64-bit one is a baseline',
        () {
      expect(
        CounterFolder.fold(
          c(t0, wifiRx: 4000000000),
          c64(t1, {'en0': (rx: 1, tx: 0)}),
        ),
        isEmpty,
      );
      expect(
        CounterFolder.fold(
          c64(t0, {'en0': (rx: 6 * gib, tx: 0)}),
          c(t1, wifiRx: 500),
        ),
        isEmpty,
      );
    });

    test('spread over midnight still adds up', () {
      final out = CounterFolder.fold(
        c64(DateTime(2026, 10, 13, 22), {'en0': (rx: 0, tx: 0)}),
        c64(DateTime(2026, 10, 14, 2), {'en0': (rx: 8 * gib, tx: 0)}),
      );
      expect(out, hasLength(2));
      expect(out.fold<int>(0, (a, d) => a + d.wifiRx), 8 * gib);
    });

    test(
        'state round-trips through JSON; a state stored by an older build decodes as 32-bit',
        () {
      final state =
          c64(t0, {'en0': (rx: 7 * gib, tx: 3), 'pdp_ip0': (rx: 1, tx: 2)});
      final back = CounterState.decode(state.encode())!;
      expect(back.bits, 64);
      expect(back.ifaces, state.ifaces);
      final legacy = CounterState.decode(
          '{"wifiRx":1,"wifiTx":2,"cellRx":3,"cellTx":4,"bootTimeMs":5,"timeMs":6}')!;
      expect(legacy.bits, 32);
      expect(legacy.ifaces, isEmpty);
    });
  });
}
