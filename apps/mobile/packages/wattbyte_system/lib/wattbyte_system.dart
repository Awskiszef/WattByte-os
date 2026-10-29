/// Dart side of the WattByte platform bridge.
///
/// Every method maps 1:1 to an official system API on Android or iOS; see the
/// Kotlin and Swift sources for the exact calls. Values the platform cannot
/// provide come back as `null`, never as made-up numbers.
library;

import 'package:flutter/services.dart';

/// What the running platform can measure directly.
class SystemCapabilities {
  const SystemCapabilities({
    required this.platform,
    required this.dataByApp,
    required this.usageAccessGranted,
    this.usageAccessState = 'granted',
    required this.chargeCounter,
    required this.energyCounter,
    required this.preciseDataHistory,
  });

  /// `android` or `ios`.
  final String platform;

  /// Per-app usage is readable (Android NetworkStatsManager only).
  final bool dataByApp;

  /// Android "Usage access" special permission state (always true on iOS).
  final bool usageAccessGranted;

  /// `granted`, `denied` or `unavailable` (no stats service / no system screen).
  final String usageAccessState;

  /// `BATTERY_PROPERTY_CHARGE_COUNTER` reports a value. It is the charge
  /// currently stored in the battery (a measurement), not the battery capacity.
  final bool chargeCounter;

  /// `BATTERY_PROPERTY_ENERGY_COUNTER` reports a value (Wh is measured).
  final bool energyCounter;

  /// Day-level history comes from the system (Android) rather than from our
  /// own sampling of since-boot counters (iOS).
  final bool preciseDataHistory;

  bool get isAndroid => platform == 'android';

  static SystemCapabilities fromMap(Map<Object?, Object?> m) =>
      SystemCapabilities(
        platform: m['platform'] as String,
        dataByApp: m['dataByApp'] as bool,
        usageAccessGranted: m['usageAccess'] as bool,
        usageAccessState: (m['usageAccessState'] as String?) ??
            ((m['usageAccess'] as bool) ? 'granted' : 'denied'),
        chargeCounter: m['chargeCounter'] as bool,
        energyCounter: m['energyCounter'] as bool,
        preciseDataHistory: m['preciseDataHistory'] as bool,
      );
}

class RawDailyData {
  const RawDailyData(
      this.day, this.mobileRx, this.mobileTx, this.wifiRx, this.wifiTx);

  /// `yyyy-MM-dd` in the device time zone.
  final String day;
  final int mobileRx;
  final int mobileTx;
  final int wifiRx;
  final int wifiTx;

  static RawDailyData fromMap(Map<Object?, Object?> m) => RawDailyData(
        m['day'] as String,
        m['mobileRx'] as int,
        m['mobileTx'] as int,
        m['wifiRx'] as int,
        m['wifiTx'] as int,
      );
}

class RawAppData {
  const RawAppData({
    required this.uid,
    required this.name,
    this.package,
    required this.mobile,
    required this.wifi,
    this.icon,
    this.kind = 'app',
  });

  final int uid;
  final String name;
  final String? package;
  final int mobile;
  final int wifi;
  final Uint8List? icon;

  /// `app`, `system`, `tethering`, `removed` or `unknown` (uid not resolvable).
  final String kind;

  static RawAppData fromMap(Map<Object?, Object?> m) => RawAppData(
        uid: m['uid'] as int,
        name: m['name'] as String,
        package: m['package'] as String?,
        mobile: m['mobile'] as int,
        wifi: m['wifi'] as int,
        icon: m['icon'] as Uint8List?,
        kind: (m['kind'] as String?) ?? 'app',
      );
}

class RawBatterySnapshot {
  const RawBatterySnapshot({
    required this.timeMs,
    required this.level,
    required this.plugged,
    this.chargeUah,
    this.energyNwh,
    this.voltageMv,
    this.source = 'app',
  });

  final int timeMs;

  /// 0-100, or -1 when the platform reports "unknown".
  final int level;
  final bool plugged;

  /// Android `BATTERY_PROPERTY_CHARGE_COUNTER` in microampere-hours: the charge
  /// currently stored in the battery, NOT its capacity (null when unsupported).
  final int? chargeUah;
  final int? energyNwh;
  final int? voltageMv;
  final String source;

  static RawBatterySnapshot fromMap(Map<Object?, Object?> m) =>
      RawBatterySnapshot(
        timeMs: m['timeMs'] as int,
        level: m['level'] as int,
        plugged: m['plugged'] as bool,
        chargeUah: m['chargeUah'] as int?,
        energyNwh: m['energyNwh'] as int?,
        voltageMv: m['voltageMv'] as int?,
        source: (m['source'] as String?) ?? 'app',
      );
}

/// Since-boot byte counters of the Wi-Fi and cellular interfaces (iOS).
class RawInterfaceCounters {
  const RawInterfaceCounters({
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
  final int bootTimeMs;
  final int timeMs;

  /// Width of the counters: 64 when the kernel's `if_data64` could be read, 32 for the `getifaddrs` fallback
  /// (and for a native side from before the 64-bit reader existed, which does not send the field).
  final int bits;

  /// Bytes per interface name (`en0`, `pdp_ip0`, ...) as `[rx, tx]`. Empty with 32-bit counters.
  final Map<String, ({int rx, int tx})> ifaces;

  static RawInterfaceCounters fromMap(Map<Object?, Object?> m) {
    final raw = m['ifaces'];
    return RawInterfaceCounters(
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
            if (e.key is String &&
                e.value is List &&
                (e.value as List).length == 2)
              e.key as String: (
                rx: (e.value as List)[0] as int,
                tx: (e.value as List)[1] as int
              ),
      },
    );
  }
}

/// Public model and region facts (see `deviceInfo` in the Swift/Kotlin sources).
///
/// Everything here is non-identifying: a model code shared by millions of
/// phones and the Region/locale setting. Used by the automatic setup to look the
/// battery up in the device catalog and to pick the default currency.
class DeviceInfo {
  const DeviceInfo({
    required this.manufacturer,
    required this.model,
    required this.modelIdentifier,
    this.regionCode,
    this.localeTag,
    this.isSimulator = false,
  });

  final String manufacturer;

  /// Marketing family ("iPhone") on iOS, `Build.MODEL` ("Pixel 8") on Android.
  final String model;

  /// iOS `utsname.machine` ("iPhone16,1") or Android `Build.MODEL`.
  final String modelIdentifier;

  /// ISO 3166-1 alpha-2 of the device Region setting; null when not set.
  final String? regionCode;

  /// BCP 47 tag of the preferred language, e.g. `en-PL`.
  final String? localeTag;
  final bool isSimulator;

  static DeviceInfo fromMap(Map<Object?, Object?> m) => DeviceInfo(
        manufacturer: (m['manufacturer'] as String?) ?? '',
        model: (m['model'] as String?) ?? '',
        modelIdentifier: (m['modelIdentifier'] as String?) ?? '',
        regionCode: _upper2(m['regionCode'] as String?),
        localeTag: m['localeTag'] as String?,
        isSimulator: (m['isSimulator'] as bool?) ?? false,
      );

  static String? _upper2(String? v) {
    final s = v?.trim().toUpperCase();
    return s != null && RegExp(r'^[A-Z]{2}$').hasMatch(s) ? s : null;
  }
}

class WattByteSystem {
  WattByteSystem({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('wattbyte/system');

  final MethodChannel _ch;

  Future<SystemCapabilities> capabilities() async => SystemCapabilities.fromMap(
      (await _ch.invokeMethod('capabilities')) as Map);

  /// Android: opens the system "Usage access" screen. No-op on iOS.
  Future<bool> openUsageAccessSettings() async =>
      (await _ch.invokeMethod<bool>('openUsageAccessSettings')) ?? false;

  /// Android: one row per local day in `[from, to)` from NetworkStatsManager.
  Future<List<RawDailyData>> queryDataDaily(DateTime from, DateTime to) async {
    final rows =
        await _ch.invokeListMethod<Map<Object?, Object?>>('queryDataDaily', {
      'fromMs': from.millisecondsSinceEpoch,
      'toMs': to.millisecondsSinceEpoch,
    });
    return [for (final r in rows ?? const []) RawDailyData.fromMap(r)];
  }

  /// Android: per-app totals in `[from, to)`, largest first.
  Future<List<RawAppData>> queryAppData(DateTime from, DateTime to) async {
    final rows =
        await _ch.invokeListMethod<Map<Object?, Object?>>('queryAppData', {
      'fromMs': from.millisecondsSinceEpoch,
      'toMs': to.millisecondsSinceEpoch,
    });
    return [for (final r in rows ?? const []) RawAppData.fromMap(r)];
  }

  Future<RawBatterySnapshot> batterySnapshot() async =>
      RawBatterySnapshot.fromMap(
          (await _ch.invokeMethod('batterySnapshot')) as Map);

  /// iOS: `getifaddrs` counters. Throws `MissingPluginException`-style error on Android.
  Future<RawInterfaceCounters> interfaceCounters() async =>
      RawInterfaceCounters.fromMap(
          (await _ch.invokeMethod('interfaceCounters')) as Map);

  /// Android: samples recorded by the charging worker while the app slept.
  Future<List<RawBatterySnapshot>> drainSamples() async {
    final rows =
        await _ch.invokeListMethod<Map<Object?, Object?>>('drainSamples');
    return [for (final r in rows ?? const []) RawBatterySnapshot.fromMap(r)];
  }

  /// iOS: the App Group shared with the widget extension (build setting
  /// `WB_APP_GROUP`, read from Info.plist). `null` on Android or when not configured.
  Future<String?> appGroupId() async {
    try {
      return await _ch.invokeMethod<String>('appGroupId');
    } on MissingPluginException {
      return null;
    }
  }

  /// Model code and Region setting for the automatic setup; null when the
  /// platform side is missing (tests, unsupported platform).
  Future<DeviceInfo?> deviceInfo() async {
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('deviceInfo');
      return m == null ? null : DeviceInfo.fromMap(m);
    } on MissingPluginException {
      return null;
    }
  }

  /// Android: (re)schedules the WorkManager job that samples while charging.
  Future<void> ensureChargingWorker() =>
      _ch.invokeMethod('ensureChargingWorker');

  /// Android: stops the charging sampler (data collection switched off). iOS: no-op.
  Future<void> cancelChargingWorker() =>
      _ch.invokeMethod('cancelChargingWorker');

  /// Android: text and switch for the native "charging completed" notification.
  ///
  /// The user-visible channel name and description (shown in the system's
  /// notification settings) come from the app's localization, like the title and
  /// body: the native side holds no text of its own.
  Future<void> setChargingNotification({
    required bool enabled,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) =>
      _ch.invokeMethod('setChargingNotification', {
        'enabled': enabled,
        'title': title,
        'body': body,
        'channelName': channelName,
        'channelDescription': channelDescription,
      });
}
