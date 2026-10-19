import '../analytics/dashboard_model.dart';
import '../analytics/notification_rules.dart';
import '../calc/energy.dart';
import '../collection/collector.dart';
import '../core/error_log.dart';
import '../core/units.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings/settings.dart';
import '../storage/database.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_service.dart';
import 'app_notifier.dart';
import 'widget_publisher.dart';

/// One refresh cycle: collect -> store -> widgets -> queue -> sync -> notifications.
///
/// Shared by the foreground app (resume, pull-to-refresh, 60 s timer) and the
/// background task, so both paths behave identically (the background one has no
/// [sync]).
class RefreshService {
  RefreshService({
    required this.collector,
    required this.db,
    required this.widgets,
    required this.notifier,
    this.sync,
  });

  final Collector collector;
  final WattByteDb db;
  final WidgetPublisher widgets;
  final AppNotifier notifier;

  /// Cloud uploader; null in the background isolate and in the local-only development mode.
  final SyncService? sync;

  Future<CollectResult?> run({
    required Settings settings,
    required SettingsStore store,
    required AppLocalizations l10n,
    required Units units,
    required DateTime now,
  }) async {
    if (!settings.dataCollection) return null;
    await store.reload(); // see SettingsStore.reload
    final result = await collector.collect(now: now);
    final days = await db.allDaily();
    final sessions = await db.allSessions();
    final calc = await energyCalcFor(settings, collector);

    final model = DashboardModel.build(
      days: days,
      sessions: sessions,
      open: result.open,
      chargingNow: result.chargingNow,
      calc: calc,
      now: now,
    );
    try {
      await widgets.publish(
        model: model,
        units: units,
        l10n: l10n,
        currency: settings.currency,
        hasPrice: settings.hasPrice,
      );
    } catch (e, st) {
      // Widgets are optional; a missing extension must not break collection, but
      // the failure is recorded.
      reportError(e, st, 'widget publish');
    }

    // Keep the latest per-day aggregates ready for cloud sync. Device-local: no
    // account owns them and nothing is sent here.
    await SyncQueue(db).enqueueRecent(
      days: days,
      sessions: sessions,
      calc: calc,
      currency: settings.currency,
      now: now,
    );

    // Upload only from the foreground (the background isolate has no sync service)
    // and only what the SIGNED-IN ACCOUNT opted into: `syncIfDue` reads that
    // consent from the per-account ledger itself, never from a UI flag, uploads at
    // most every 5 minutes and honours the backoff of a failed attempt. A changing
    // current day therefore cannot turn this 60-second pass into a request loop.
    if (sync != null) {
      try {
        await sync!.syncIfDue();
      } catch (e, st) {
        // The queue keeps the data; collection must never fail because of the network.
        reportError(e, st, 'cloud sync');
      }
    }

    final pending = evaluateNotifications(
      settings: settings,
      days: days,
      sessions: sessions,
      newlyClosed: result.newSessions,
      calc: calc,
      now: now,
      alreadySent: store.sentNotifications,
      nativeChargingAlerts: result.capabilities.isAndroid,
    );
    await notifier.showAll(pending,
        store: store, l10n: l10n, units: units, currency: settings.currency);
    return result;
  }
}

/// Same calculator as the UI (see `Settings.energyCalc`): the design capacity
/// when known, otherwise the estimated full-charge capacity when there is one.
Future<EnergyCalc> energyCalcFor(Settings s, Collector c) async {
  final fullCharge = await c.fullChargeCapacity();
  return s.energyCalc(
      estimatedFullChargeCapacityMah:
          fullCharge.isAvailable ? fullCharge.mah ?? 0 : 0);
}
