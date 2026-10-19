import '../domain/models.dart';

/// Result of folding samples into sessions.
class SessionBuildResult {
  const SessionBuildResult({required this.closed, required this.open});

  /// Sessions that ended (an unplugged sample, a long gap or a level drop followed).
  final List<ChargingSession> closed;

  /// Trailing plugged samples of a session still in progress.
  final List<BatterySample> open;
}

/// Turns a time-ordered list of [BatterySample]s into charging sessions.
///
/// Pure and deterministic, so the same samples always yield the same sessions.
class SessionBuilder {
  const SessionBuilder({
    this.maxGap = const Duration(minutes: 30),
    this.sparseGap = const Duration(minutes: 15),
    this.minDuration = const Duration(minutes: 1),
    this.levelDropTolerance = 3,
  });

  /// Two plugged samples further apart than this belong to different sessions.
  /// Android (worker samples every minute): 30 min. iOS (sparse refreshes): hours.
  final Duration maxGap;

  /// Any gap above this marks the session as [ChargingSession.sparse].
  final Duration sparseGap;
  final Duration minDuration;

  /// A level drop larger than this between plugged samples starts a new session.
  final int levelDropTolerance;

  SessionBuildResult build(List<BatterySample> samples) {
    final sorted = [...samples]..sort((a, b) => a.time.compareTo(b.time));
    final closed = <ChargingSession>[];
    var run = <BatterySample>[];

    void close() {
      final s = toSession(run);
      if (s != null) closed.add(s);
      run = [];
    }

    for (final s in sorted) {
      if (!s.plugged) {
        if (run.isNotEmpty) close();
        continue;
      }
      if (run.isNotEmpty) {
        final last = run.last;
        final gap = s.time.difference(last.time);
        if (gap > maxGap || s.level < last.level - levelDropTolerance) close();
      }
      run.add(s);
    }
    return SessionBuildResult(closed: closed, open: run);
  }

  /// Builds a session from one plugged run; `null` if it carries no information.
  ChargingSession? toSession(List<BatterySample> run) {
    if (run.length < 2) return null;
    final first = run.first;
    final last = run.last;
    if (last.time.difference(first.time) < minDuration) return null;

    var sparse = false;
    for (var i = 1; i < run.length; i++) {
      if (run[i].time.difference(run[i - 1].time) > sparseGap) sparse = true;
    }
    final voltages = run.map((s) => s.voltageMv).whereType<int>().toList();
    int? delta(int? a, int? b) => (a == null || b == null) ? null : b - a;
    return ChargingSession(
      start: first.time,
      end: last.time,
      startLevel: first.level,
      endLevel: last.level,
      chargeDeltaUah: delta(first.chargeUah, last.chargeUah),
      energyDeltaNwh: delta(first.energyNwh, last.energyNwh),
      avgVoltageMv: voltages.isEmpty
          ? null
          : voltages.reduce((a, b) => a + b) ~/ voltages.length,
      sparse: sparse,
    );
  }
}
