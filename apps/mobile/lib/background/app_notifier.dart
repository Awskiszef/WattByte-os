import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../analytics/notification_rules.dart';
import '../core/units.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings/settings.dart';

/// Shows the optional, locally generated notifications.
class AppNotifier {
  AppNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(const InitializationSettings(
      // The monochrome status-bar icon shipped by the wattbyte_system plugin
      // (`android/src/main/res/drawable/ic_wb_bolt.xml`); the launcher icon is a
      // coloured bitmap and renders as a solid white square in the status bar.
      android: AndroidInitializationSettings('@drawable/ic_wb_bolt'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: false, sound: true) ??
          false;
    }
    return false;
  }

  Future<void> showAll(
    List<PendingNotification> pending, {
    required SettingsStore store,
    required AppLocalizations l10n,
    required Units units,
    required String currency,
  }) async {
    if (pending.isEmpty) return;
    await _init();
    for (final n in pending) {
      final text = textFor(n, l10n, units);
      // No number to talk about: nothing is shown and, unlike a shown one, the
      // key is not marked as sent.
      if (text == null) continue;
      final (title, body) = text;
      await _plugin.show(
        n.key.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
              'wattbyte.summary', l10n.notifChannelName,
              channelDescription: l10n.notifChannelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority),
          iOS: const DarwinNotificationDetails(),
        ),
      );
      await store.markSent(n.key);
    }
  }

  /// Title and body of [n], localized and formatted with [u] exactly like the
  /// app screens (the background isolate passes the same locale logic, see
  /// `runBackgroundRefresh`). Null when the notification would have to print a
  /// number that does not exist (NaN or infinity), so a "You've used — of
  /// mobile data" never reaches the lock screen.
  static (String, String)? textFor(
      PendingNotification n, AppLocalizations l, Units u) {
    final printsNumber = n.kind != NotificationKind.chargingDone;
    if (printsNumber && !n.value.isFinite) return null;
    switch (n.kind) {
      case NotificationKind.mobileThreshold:
        return (l.notifMobileTitle, l.notifMobileBody(u.bytes(n.value)));
      case NotificationKind.chargingDone:
        return (l.notifChargingTitle, l.notifChargingBody);
      case NotificationKind.weeklyEnergy:
        return (l.notifWeeklyTitle, l.notifWeeklyBody(u.kwh(n.value * 1000)));
      case NotificationKind.aboveWeeklyAverage:
        // Percent is formatted by the localization (`decimalPattern`).
        return (l.notifAboveAvgTitle, l.notifAboveAvgBody(n.value.round()));
    }
  }
}
