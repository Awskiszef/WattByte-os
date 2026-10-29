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

  /// The account whose settings (price, currency) the queued figures were computed with.
  static const metaSettingsOwner = 'sync_queue_settings_owner';

  /// The day of the last pass: older days that changed since then (a back-filled gap) are re-aggregated too.
  static const metaLastPass = 'sync_queue_last_pass';

  Future<void> enqueueRecent({
    required List<DailyData> days,
    required List<ChargingSession> sessions,
    required EnergyCalc calc,
    required String currency,
    required DateTime now,
    int? lookback,
    String? settingsOwner,
  }) async {
    final today = LocalDate.of(dayOf(now));
    final history = _spanDays(days, sessions, now);
    var span = lookback ?? lookbackDays;

    // The cost and currency of a queued day come from the settings of the account that was signed in when it was
    // computed. Rows computed under another account's price are not this account's numbers (F-18): rebuild them all.
    var rebuilt = false;
    if (settingsOwner != null &&
        await _db.meta(metaSettingsOwner) != settingsOwner) {
      await _db.clearSyncQueue();
      span = history;
      rebuilt = true;
    }
    // Days the collectors changed behind the three-day window (an Android back-fill after a gap, an iOS counter delta
    // spread over every day since the last snapshot, a late-closed session) must be queued too (F-05): the window
    // reaches back to the previous pass. The very first pass (no cursor) repairs history once.
    if (lookback == null && !rebuilt) {
      final last = await _db.meta(metaLastPass);
      if (last == null) {
        span = history;
      } else {
        final lastDay = LocalDate.of(parseDayKey(last));
        span = [span, lastDay.daysUntil(today) + lookbackDays]
            .reduce((a, b) => a > b ? a : b);
      }
    }
    if (span > history) span = history;
    // A day after today (a clock that was ahead) is not uploadable: drop it instead of keeping it for ever.
    await _db.deleteSyncItemsAfter(today.plusDays(1).key);
    if (span <= 0) {
      await _markPass(today, settingsOwner);
      return;
    }
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
    await _markPass(today, settingsOwner);
  }

  Future<void> _markPass(LocalDate today, String? settingsOwner) async {
    await _db.setMeta(metaLastPass, today.key);
    if (settingsOwner != null) {
      await _db.setMeta(metaSettingsOwner, settingsOwner);
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
    String? settingsOwner,
  }) {
    final span = _spanDays(days, sessions, now);
    if (span == 0) return Future.value();
    return enqueueRecent(
        days: days,
        sessions: sessions,
        calc: calc,
        currency: currency,
        now: now,
        lookback: span,
        settingsOwner: settingsOwner);
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
