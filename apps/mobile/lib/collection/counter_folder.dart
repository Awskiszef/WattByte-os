// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../core/periods.dart';
import '../domain/models.dart';

/// Since-boot interface byte counters (iOS `getifaddrs`).
class CounterState {
  const CounterState({
    required this.wifiRx,
    required this.wifiTx,
    required this.cellRx,
    required this.cellTx,
    required this.bootTimeMs,
    required this.timeMs,
    this.bits = 32,
    this.ifaces = const {},
  });

  final int wifiRx;
  final int wifiTx;
  final int cellRx;
  final int cellTx;

  /// `kern.boottime` in ms; a change means the device rebooted.
  final int bootTimeMs;
  final int timeMs;

  /// 64 when [ifaces] holds the kernel's 64-bit per-interface counters; 32 for the summed `getifaddrs` counters
  /// (also what a state stored before the 64-bit reader existed decodes to).
  final int bits;

  /// Bytes per interface name as `[rx, tx]`, 64-bit counters only.
  final Map<String, ({int rx, int tx})> ifaces;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timeMs);

  Map<String, Object> toJson() => {
        'wifiRx': wifiRx,
        'wifiTx': wifiTx,
        'cellRx': cellRx,
        'cellTx': cellTx,
        'bootTimeMs': bootTimeMs,
        'timeMs': timeMs,
        if (bits != 32) 'bits': bits,
        if (ifaces.isNotEmpty)
          'ifaces': {
            for (final e in ifaces.entries) e.key: [e.value.rx, e.value.tx],
          },
      };

  static CounterState fromJson(Map<String, dynamic> m) {
    final raw = m['ifaces'];
    return CounterState(
      wifiRx: m['wifiRx'] as int,
      wifiTx: m['wifiTx'] as int,
      cellRx: m['cellRx'] as int,
      cellTx: m['cellTx'] as int,
      bootTimeMs: m['bootTimeMs'] as int,
      timeMs: m['timeMs'] as int,
      bits: (m['bits'] as int?) ?? 32,
      ifaces: {
        if (raw is Map)
          for (final e in raw.entries)
            e.key as String: (
              rx: (e.value as List)[0] as int,
              tx: (e.value as List)[1] as int
            ),
      },
    );
  }

  String encode() => jsonEncode(toJson());
  static CounterState? decode(String? s) =>
      s == null ? null : fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Converts two counter snapshots into per-day byte increments (iOS).
///
/// Only the bytes between two snapshots are known, so the increment is spread
/// linearly over the days it covers and flagged as estimated.
///
/// Two readings exist (see `InterfaceCounters.read` in the Swift plugin):
///  - **64-bit, per interface** (`bits == 64`): every interface is compared with ITS OWN previous value. A decrease is a
///    restart of that counter (delta = the new value), an interface that was not there before counts from zero, one
///    that vanished contributes nothing. No 32-bit wrap exists, so nothing is ever invented.
///  - **32-bit sums** (fallback, and states stored by older builds): a decrease is read as one 32-bit wrap, as before.
///
/// Whatever the reading, a delta larger than the link could have carried in the elapsed time ([maxBytesPerSecond]) is
/// dropped, not booked: a missing number is better than gigabytes that never moved.
class CounterFolder {
  const CounterFolder._();

  static const _wrap = 1 << 32;

  /// 2 Gbit/s: above any phone radio or Wi-Fi link.
  static const maxBytesPerSecond = 250 * 1000 * 1000;

  /// The clock reading of the boot time may jitter by this much without meaning a reboot.
  static const _bootTolerance = Duration(seconds: 5);

  static List<DailyData> fold(CounterState? prev, CounterState next) {
    if (prev == null || next.timeMs <= prev.timeMs) return const [];
    final elapsedSec = (next.timeMs - prev.timeMs) / 1000;
    // A little slack for the first/last second of rounding, then the physical ceiling.
    final cap = (elapsedSec * maxBytesPerSecond).ceil() + (16 << 20);
    int plausible(int bytes) => bytes > cap ? 0 : bytes;

    // The 32-bit sums and the 64-bit per-interface counters cannot be compared with each other (an app update, or the
    // kernel read failing once): the new reading is only the baseline. One interval is lost, none is invented.
    if (prev.bits != next.bits) return const [];
    final DailyData inc;
    if (next.bits == 64) {
      if (next.ifaces.isEmpty) return const [];
      inc = _fold64(prev, next, plausible);
    } else {
      inc = _fold32(prev, next, plausible);
    }
    if (inc.total == 0) return const [];
    return spread(inc, prev.time, next.time);
  }

  /// A reboot restarts every counter at zero. Uptime (`time - boot time`) only moves forward, also when the user
  /// or the network steps the wall clock (which shifts `kern.boottime` with it): the uptime shrinking is a reboot, the
  /// boot time merely moving is not. An unknown boot time (0) says nothing; the counters themselves then decide.
  static bool _rebooted(CounterState prev, CounterState next) {
    if (prev.bootTimeMs <= 0 || next.bootTimeMs <= 0) return false;
    final before = prev.timeMs - prev.bootTimeMs;
    final after = next.timeMs - next.bootTimeMs;
    return after + _bootTolerance.inMilliseconds < before;
  }

  static DailyData _fold64(
      CounterState prev, CounterState next, int Function(int) plausible) {
    final rebooted = _rebooted(prev, next);
    var mobileRx = 0, mobileTx = 0, wifiRx = 0, wifiTx = 0;
    for (final e in next.ifaces.entries) {
      final isWifi = e.key == 'en0';
      final isCell = e.key.startsWith('pdp_ip');
      if (!isWifi && !isCell) continue;
      final before = rebooted ? null : prev.ifaces[e.key];
      // No previous value (new interface, or everything restarted): the counter counts from zero.
      final rx = plausible(_delta64(before?.rx, e.value.rx));
      final tx = plausible(_delta64(before?.tx, e.value.tx));
      if (isWifi) {
        wifiRx += rx;
        wifiTx += tx;
      } else {
        mobileRx += rx;
        mobileTx += tx;
      }
    }
    return DailyData(
      day: dayOf(next.time),
      mobileRx: mobileRx,
      mobileTx: mobileTx,
      wifiRx: wifiRx,
      wifiTx: wifiTx,
      estimated: true,
    );
  }

  static int _delta64(int? before, int now) {
    if (before == null || now < before) return now < 0 ? 0 : now;
    return now - before;
  }

  static DailyData _fold32(
      CounterState prev, CounterState next, int Function(int) plausible) {
    final rebooted = (next.bootTimeMs - prev.bootTimeMs).abs() > 5000;

    int delta(int a, int b) {
      if (rebooted) {
        return b; // counters restarted at 0; bytes before reboot are lost
      }
      if (b >= a) return b - a;
      // One 32-bit wrap. (More than one wrap between snapshots cannot be seen in 32-bit sums: the 64-bit reading exists for that.)
      return b + _wrap - a;
    }

    return DailyData(
      day: dayOf(next.time),
      mobileRx: plausible(delta(prev.cellRx, next.cellRx)),
      mobileTx: plausible(delta(prev.cellTx, next.cellTx)),
      wifiRx: plausible(delta(prev.wifiRx, next.wifiRx)),
      wifiTx: plausible(delta(prev.wifiTx, next.wifiTx)),
      estimated: true,
    );
  }

  /// Splits [inc] across the days between [from] and [to], proportionally to time.
  static List<DailyData> spread(DailyData inc, DateTime from, DateTime to) {
    final totalMs = to.difference(from).inMilliseconds;
    if (totalMs <= 0 || dayOf(from) == dayOf(to)) {
      return [
        DailyData(
          day: dayOf(to),
          mobileRx: inc.mobileRx,
          mobileTx: inc.mobileTx,
          wifiRx: inc.wifiRx,
          wifiTx: inc.wifiTx,
          estimated: true,
        )
      ];
    }
    final out = <DailyData>[];
    var cursor = from;
    var remaining = [inc.mobileRx, inc.mobileTx, inc.wifiRx, inc.wifiTx];
    while (cursor.isBefore(to)) {
      final day = dayOf(cursor);
      final nextMidnight = DateTime(day.year, day.month, day.day + 1);
      final segEnd = nextMidnight.isBefore(to) ? nextMidnight : to;
      final share = segEnd.difference(cursor).inMilliseconds / totalMs;
      final isLast = !segEnd.isBefore(to);
      final part = [
        for (final (i, v)
            in [inc.mobileRx, inc.mobileTx, inc.wifiRx, inc.wifiTx].indexed)
          // Never more than what is left: rounding several shares up must not leave a NEGATIVE remainder for the last day.
          (v * share).round().clamp(0, remaining[i]),
      ];
      final use = isLast ? remaining : part; // last day absorbs rounding
      out.add(DailyData(
        day: day,
        mobileRx: use[0],
        mobileTx: use[1],
        wifiRx: use[2],
        wifiTx: use[3],
        estimated: true,
      ));
      remaining = [for (var i = 0; i < 4; i++) remaining[i] - use[i]];
      cursor = segEnd;
    }
    return out;
  }
}
