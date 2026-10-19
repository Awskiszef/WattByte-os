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
  });

  final int wifiRx;
  final int wifiTx;
  final int cellRx;
  final int cellTx;

  /// `kern.boottime` in ms; a change means the device rebooted.
  final int bootTimeMs;
  final int timeMs;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timeMs);

  Map<String, int> toJson() => {
        'wifiRx': wifiRx,
        'wifiTx': wifiTx,
        'cellRx': cellRx,
        'cellTx': cellTx,
        'bootTimeMs': bootTimeMs,
        'timeMs': timeMs,
      };

  static CounterState fromJson(Map<String, dynamic> m) => CounterState(
        wifiRx: m['wifiRx'] as int,
        wifiTx: m['wifiTx'] as int,
        cellRx: m['cellRx'] as int,
        cellTx: m['cellTx'] as int,
        bootTimeMs: m['bootTimeMs'] as int,
        timeMs: m['timeMs'] as int,
      );

  String encode() => jsonEncode(toJson());
  static CounterState? decode(String? s) =>
      s == null ? null : fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Converts two counter snapshots into per-day byte increments (iOS).
///
/// Only the bytes between two snapshots are known, so the increment is spread
/// linearly over the days it covers and flagged as estimated.
class CounterFolder {
  const CounterFolder._();

  static const _wrap = 1 << 32;

  static List<DailyData> fold(CounterState? prev, CounterState next) {
    if (prev == null || next.timeMs <= prev.timeMs) return const [];
    final rebooted = (next.bootTimeMs - prev.bootTimeMs).abs() > 5000;

    int delta(int a, int b) {
      if (rebooted) {
        return b; // counters restarted at 0; bytes before reboot are lost
      }
      if (b >= a) return b - a;
      // ponytail: handles a single 32-bit wrap; sysctl(NET_RT_IFLIST2) gives 64-bit counters.
      return b + _wrap - a;
    }

    final inc = DailyData(
      day: dayOf(next.time),
      mobileRx: delta(prev.cellRx, next.cellRx),
      mobileTx: delta(prev.cellTx, next.cellTx),
      wifiRx: delta(prev.wifiRx, next.wifiRx),
      wifiTx: delta(prev.wifiTx, next.wifiTx),
      estimated: true,
    );
    if (inc.total == 0) return const [];
    return spread(inc, prev.time, next.time);
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
        for (final v in [inc.mobileRx, inc.mobileTx, inc.wifiRx, inc.wifiTx])
          (v * share).round(),
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
