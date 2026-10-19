import '../calc/energy.dart';
import '../core/periods.dart';
import '../domain/models.dart';
import '../storage/database.dart';
import 'daily_aggregate.dart';
import 'sync_models.dart';

/// Keeps the latest per-day aggregates that cloud sync can upload.
///
/// Nothing here touches the network and nothing here knows an account: the queue
/// is DEVICE-LOCAL data (it survives sign-out and account switches). Whether a day
/// has been uploaded, and to whom, is a [SyncReceipt]; whether an account may
/// upload it at all is that account's sync scope. Queueing is idempotent: a row is
/// rewritten only when its aggregate actually changed, and a rewrite never touches
/// any account's schedule (backoff, last success), so a day that changes every
/// minute cannot defeat the retry policy.
class SyncQueue {
  SyncQueue(this._db);

  final WattByteDb _db;

  /// Days to re-aggregate on every pass; later stats for older days are rare.
  static const lookbackDays = 3;

  /// The backend accepts at most this many days per request.
  static const batchSize = 92;

  Future<void> enqueueRecent({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
    required DateTime now,
    int? lookback,
  }) async {
    final today = LocalDate.of(dayOf(now));
    final span = lookback ?? lookbackDays;
    final existing = {
      for (final i
          in await _db.syncItems(sinceDay: today.plusDays(-(span - 1)).key))
        dayKey(i.day): i
    };
    for (var i = 0; i < span; i++) {
      final agg = _aggregate(today.plusDays(-i).midnight,
          days: days, sessions: sessions, calc: calc, currency: currency);
      if (agg == null) continue;
      final prev = existing[agg.date];
      if (prev != null && prev.payload == agg) continue;
      await _db.upsertSyncItem(SyncQueueItem(
        day: parseDayKey(agg.date),
        payload: agg,
        updatedAt: now,
      ));
    }
  }

  /// The aggregate of every local day that has data, oldest first: the same days
  /// [enqueueAll] queues. Pure (no database access): used to count how much history
  /// an account does not have yet before anything is queued or enabled.
  static List<DailyAggregate> buildAll({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
    required DateTime now,
  }) {
    final span = _spanDays(days, sessions, now);
    if (span == 0) return const [];
    final today = LocalDate.of(dayOf(now));
    final all = <DailyAggregate>[];
    for (var i = span - 1; i >= 0; i--) {
      final agg = _aggregate(today.plusDays(-i).midnight,
          days: days, sessions: sessions, calc: calc, currency: currency);
      if (agg != null) all.add(agg);
    }
    return all;
  }

  /// Queues every day that has data (used when history is enabled for an account,
  /// so history that predates the switch is eligible too).
  Future<void> enqueueAll({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
    required DateTime now,
  }) {
    final span = _spanDays(days, sessions, now);
    if (span == 0) return Future.value();
    return enqueueRecent(
        days: days,
        sessions: sessions,
        calc: calc,
        currency: currency,
        now: now,
        lookback: span);
  }

  /// Local days from the first one with data to today, inclusive; 0 without data.
  static int _spanDays(
      List<DailyData> days, List<ChargingSession> sessions, DateTime now) {
    if (days.isEmpty && sessions.isEmpty) return 0;
    final first = [
      ...days.map((d) => d.day),
      ...sessions.map((s) => dayOf(s.start)),
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    return LocalDate.of(first).daysUntil(LocalDate.of(dayOf(now))) + 1;
  }

  /// The aggregate of [day], or null when it is empty or outside the API contract
  /// (such a day is never queued: the server would answer 400).
  static DailyAggregate? _aggregate(
    DateTime day, {
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
  }) {
    final agg = DailyAggregate.build(
      day: day,
      days: days,
      sessions: sessions,
      calc: calc,
      currency: currency,
    );
    return agg.isEmpty || !agg.isWithinContract ? null : agg;
  }
}
