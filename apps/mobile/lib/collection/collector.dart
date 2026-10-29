import 'package:wattbyte_system/wattbyte_system.dart';

import '../core/error_log.dart';
import '../core/periods.dart';
import '../domain/battery_capacity.dart';
import '../domain/models.dart';
import '../storage/database.dart';
import 'counter_folder.dart';
import 'session_builder.dart';

/// Outcome of one collection pass.
class CollectResult {
  const CollectResult({
    required this.capabilities,
    required this.newSessions,
    required this.open,
    required this.latest,
  });

  final SystemCapabilities capabilities;

  /// Sessions closed during this pass (used for "charging completed" alerts).
  final List<ChargingSession> newSessions;

  /// Samples of a session still in progress.
  final List<BatterySample> open;
  final BatterySample? latest;

  bool get chargingNow => latest?.plugged ?? false;
}

/// Moves raw system readings into local storage.
///
/// Platform differences stop here: everything above this layer works with the
/// shared models only.
class Collector {
  Collector({required this.system, required this.db});

  final WattByteSystem system;
  final WattByteDb db;

  /// NetworkStatsManager keeps roughly this much history by default; older
  /// days survive only in our own table.
  static const androidHistoryDays = 90;
  static const metaIface = 'iface_counters';

  /// An open charge with more samples than this is thinned after every pass (see [SessionBuilder.redundantSamples]).
  static const thinOpenRunAbove = 180;

  // The estimated full-charge capacity of this battery
  // ([EstimatedFullChargeCapacity]) is kept in the meta table. The key strings
  // still say "calibrated capacity" so existing installs keep their reading;
  // what they hold is an estimate extrapolated from the charge counter, never a
  // design capacity (see docs/BATTERY_CAPACITY.md).
  static const metaFullChargeCapacityMah =
      EstimatedFullChargeCapacity.metaMahKey;
  static const metaFullChargeCapacityLevel =
      EstimatedFullChargeCapacity.metaLevelKey;
  static const metaFullChargeCapacityWh = EstimatedFullChargeCapacity.metaWhKey;
  static const metaFullChargeCapacityMeasuredAt =
      EstimatedFullChargeCapacity.metaMeasuredAtKey;
  static const _fullChargeMetaKeys = [
    metaFullChargeCapacityMah,
    metaFullChargeCapacityLevel,
    metaFullChargeCapacityWh,
    metaFullChargeCapacityMeasuredAt,
  ];

  Future<CollectResult> collect({required DateTime now}) async {
    final caps = await system.capabilities();
    // The data step and the battery step are independent: a failing network-statistics query (revoked usage access, an
    // OS error) must not stop the charging samples from being stored, and the other way round. The failure is
    // recorded; the battery step's own failure still propagates as before.
    try {
      await _collectData(caps, now);
    } catch (e, st) {
      reportError(e, st, 'data collection');
    }
    return _collectBattery(caps, now);
  }

  Future<void> _collectData(SystemCapabilities caps, DateTime now) async {
    final today = dayOf(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    if (caps.isAndroid) {
      if (!caps.usageAccessGranted) return;
      final latest = await db.latestDay();
      var floor =
          DateTime(today.year, today.month, today.day - androidHistoryDays);
      // "Reset statistics" is not undone by the next pass: the system's history before it stays out (G-17).
      final resetAt = await db.resetAt();
      if (resetAt != null) {
        final resetDay = dayOf(resetAt);
        if (resetDay.isAfter(floor)) floor = resetDay;
      }
      // Re-read the last two stored days: the system flushes stats with a delay.
      var from = latest == null
          ? floor
          : DateTime(latest.year, latest.month, latest.day - 1);
      if (from.isBefore(floor)) from = floor;
      final rows = await system.queryDataDaily(from, tomorrow);
      await db.replaceDaily(rows.map((r) => DailyData(
            day: parseDayKey(r.day),
            mobileRx: r.mobileRx,
            mobileTx: r.mobileTx,
            wifiRx: r.wifiRx,
            wifiTx: r.wifiTx,
          )));
    } else {
      final raw = await system.interfaceCounters();
      final next = CounterState(
        wifiRx: raw.wifiRx,
        wifiTx: raw.wifiTx,
        cellRx: raw.cellRx,
        cellTx: raw.cellTx,
        bootTimeMs: raw.bootTimeMs,
        timeMs: raw.timeMs,
        bits: raw.bits,
        ifaces: raw.ifaces,
      );
      final prev = CounterState.decode(await db.meta(metaIface));
      // One transaction: the increment and the baseline it was measured against. Separate writes double-counted the
      // interval when the process died between them.
      await db.addDailyAndSetMeta(
          CounterFolder.fold(prev, next), metaIface, next.encode());
    }
  }

  Future<CollectResult> _collectBattery(
      SystemCapabilities caps, DateTime now) async {
    // The charging worker's samples are the only copy of what happened while the app slept. They are stored FIRST,
    // before any other call that can fail, and the native side deletes them only after that succeeded (H-05, G-11). If
    // anything here throws, the next pass receives the same batch again; storing a sample twice is a no-op.
    final batch = await system.peekSamples();
    // Samples taken before the last "Reset statistics" belong to what the user erased: acknowledged below, not stored.
    final resetAtMs = (await db.resetAt())?.millisecondsSinceEpoch ?? 0;
    final kept = [
      for (final r in batch.samples)
        if (r.timeMs >= resetAtMs) _sample(r),
    ];
    if (kept.isNotEmpty) await db.insertSamples(kept);
    try {
      await system.ackSamples(batch.token);
    } catch (e, st) {
      // Not acknowledged = delivered again next time, which is harmless.
      reportError(e, st, 'acknowledge worker samples');
    }
    final snap = await system.batterySnapshot();
    if (snap.level >= 0) await db.insertSamples([_sample(snap)]);

    await _updateFullChargeCapacity(snap, now);

    final builder = SessionBuilder(
      maxGap: caps.isAndroid
          ? const Duration(minutes: 30)
          : const Duration(hours: 8),
    );
    final all = await db.samples();
    final res = builder.build(all);
    await db.insertSessions(res.closed);
    if (all.isNotEmpty) {
      final keepFrom =
          res.open.isNotEmpty ? res.open.first.time : all.last.time;
      await db.deleteSamplesBefore(keepFrom);
      // A long charge in progress: thin out what a session no longer needs (the 'open' list returned is the full one).
      if (res.open.length > thinOpenRunAbove) {
        await db.deleteSamples(SessionBuilder.redundantSamples(res.open));
      }
    }
    return CollectResult(
      capabilities: caps,
      newSessions: res.closed,
      open: res.open,
      latest: all.isEmpty ? null : all.last,
    );
  }

  /// Cheap foreground sample (timer / resume) without rebuilding sessions.
  Future<void> sampleBattery() async {
    final snap = await system.batterySnapshot();
    if (snap.level >= 0) await db.insertSamples([_sample(snap)]);
  }

  /// The best estimate of this battery's full-charge capacity seen so far, or
  /// [EstimatedFullChargeCapacity.unavailable]. An estimate, never the nominal
  /// capacity of the phone model.
  Future<EstimatedFullChargeCapacity> fullChargeCapacity() async =>
      EstimatedFullChargeCapacity.fromMeta({
        for (final key in _fullChargeMetaKeys) key: await db.meta(key),
      });

  /// Extrapolates the charge counter of [snap] to a full-charge estimate and
  /// keeps it when it beats the stored one
  /// ([FullChargeCapacityEstimator.prefer]): a 45 % reading does not overwrite
  /// a 100 % reading from last week. An unsupported, zero, negative or
  /// implausible counter, or an unknown or too low level, leaves the stored
  /// estimate untouched.
  Future<void> _updateFullChargeCapacity(
      RawBatterySnapshot snap, DateTime now) async {
    final candidate = FullChargeCapacityEstimator.estimate(
      chargeUah: snap.chargeUah,
      energyNwh: snap.energyNwh,
      level: snap.level,
      measuredAt: now,
    );
    if (!candidate.isAvailable) return;
    final stored = await fullChargeCapacity();
    final winner =
        FullChargeCapacityEstimator.prefer(stored, candidate, now: now);
    if (winner == stored) return;
    final meta = winner.toMeta();
    for (final key in _fullChargeMetaKeys) {
      final value = meta[key];
      // A key the new estimate lacks (e.g. Wh) must not keep an older reading's value.
      if (value == null) {
        await db.deleteMeta(key);
      } else {
        await db.setMeta(key, value);
      }
    }
  }

  static BatterySample _sample(RawBatterySnapshot r) => BatterySample(
        time: DateTime.fromMillisecondsSinceEpoch(r.timeMs),
        level: r.level,
        plugged: r.plugged,
        chargeUah: r.chargeUah,
        energyNwh: r.energyNwh,
        voltageMv: r.voltageMv,
        source: r.source,
      );
}
