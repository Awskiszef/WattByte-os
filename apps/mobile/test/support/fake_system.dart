import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte_system/wattbyte_system.dart';

/// Distinct channel per fake: two fakes alive in one test (or one process) must
/// never overwrite each other's handler.
int _channelSeq = 0;

/// A `WattByteSystem` whose method channel answers from a script instead of
/// native code. Only the methods the setup needs are scripted; the rest throw.
///
/// For widget tests that run the whole app use [FakeSystem] instead: it answers
/// every method the app calls.
WattByteSystem fakeSystem({
  Map<String, Object?>? deviceInfo,
  Map<String, Object?>? capabilities,
}) {
  final channel = MethodChannel('wattbyte/system-fake-${_channelSeq++}');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'deviceInfo':
        return deviceInfo;
      case 'capabilities':
        return capabilities ??
            {
              'platform': 'ios',
              'dataByApp': false,
              'usageAccess': true,
              'chargeCounter': false,
              'energyCounter': false,
              'preciseDataHistory': false,
            };
      default:
        throw MissingPluginException(call.method);
    }
  });
  return WattByteSystem(channel: channel);
}

/// Which native side the fake pretends to be.
enum HarnessPlatform {
  ios(TargetPlatform.iOS),
  android(TargetPlatform.android);

  const HarnessPlatform(this.targetPlatform);

  /// What `defaultTargetPlatform` has to be for the Flutter side to agree with
  /// the fake native side (adaptive widgets, scroll physics, the sync payload).
  final TargetPlatform targetPlatform;

  bool get isIos => this == ios;
}

/// A scriptable stand-in for the native platform bridge (`wattbyte/system`).
///
/// Everything the app asks the native side is answered from plain fields, so a
/// test can change the world between pumps:
///
/// ```dart
/// final fake = FakeSystem(platform: HarnessPlatform.android);
/// fake.batteryLevel = 12;
/// fake.usageAccessGranted = false;     // the permission card appears
/// expect(fake.callsTo('openUsageAccessSettings'), isEmpty);
/// ```
///
/// Defaults describe a plausible, healthy device of the chosen platform (an
/// iPhone 17 Pro in Poland, or a Pixel 8 in Poland). Unknown methods throw
/// `MissingPluginException`, exactly like a missing native implementation, so
/// a new native call in `lib/` is noticed instead of silently answered.
///
/// Call [dispose] (or let `AppHarness` do it) to remove the channel handler.
class FakeSystem {
  FakeSystem({
    this.platform = HarnessPlatform.ios,
    this.usageAccessGranted = true,
    this.batteryLevel = 78,
    this.plugged = false,
    this.chargeCounterMah,
    Map<String, Object?>? deviceInfo,
    this.appGroupId,
    DateTime Function()? clock,
  })  : deviceInfo = deviceInfo ?? defaultDeviceInfo(platform),
        _clock = clock ?? DateTime.now {
    _channel = MethodChannel('wattbyte/system-fake-${_channelSeq++}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
    system = WattByteSystem(channel: _channel);
    appGroupId ??= platform.isIos ? 'group.pl.wattbyte.app' : null;
    appRows = platform.isIos ? const [] : sampleApps();
  }

  final HarnessPlatform platform;
  final DateTime Function() _clock;
  late final MethodChannel _channel;

  /// The object to inject (`systemProvider.overrideWithValue(fake.system)`).
  late final WattByteSystem system;

  /// Android: the "Usage access" special permission. Always true on iOS.
  bool usageAccessGranted;

  /// Answer of `capabilities`; null = derived from [platform] and
  /// [usageAccessGranted].
  Map<String, Object?>? capabilitiesOverride;

  /// Answer of `deviceInfo`; null makes the call return null (old native side).
  Map<String, Object?>? deviceInfo;

  /// iOS App Group id (`appGroupId`); null on Android.
  String? appGroupId;

  int batteryLevel;
  bool plugged;

  /// Android only: `BATTERY_PROPERTY_CHARGE_COUNTER` in mAh (null = counter
  /// unsupported). This is the charge currently STORED in the battery at
  /// [batteryLevel], not its capacity: a full battery of 3600 mAh at 78 % reads
  /// 2808. The app only turns it into an estimated full-charge capacity. Also
  /// switches `capabilities.chargeCounter` on (zero and negative values are
  /// passed through, like a broken native counter would).
  double? chargeCounterMah;

  /// Android only: `BATTERY_PROPERTY_ENERGY_COUNTER` in nWh (null = unsupported).
  int? energyCounterNwh;
  int voltageMv = 3950;

  /// iOS since-boot interface counters. Static by default (every refresh
  /// measures zero new bytes); change them between refreshes to simulate usage.
  RawInterfaceCounters? counters;

  /// Android: rows returned by `queryDataDaily` (empty = nothing new).
  List<Map<String, Object?>> dailyRows = [];

  /// Android: rows returned by `queryAppData` (defaults to [sampleApps] on
  /// Android; iOS has no per-app data).
  late List<Map<String, Object?>> appRows;

  /// Samples the charging worker "recorded while the app slept"; returned once
  /// by `drainSamples`, then cleared (the real native side clears its queue).
  List<Map<String, Object?>> pendingSamples = [];
  int _sampleToken = 0;

  /// Every token the app acknowledged through `ackSamples`.
  final List<int> ackedTokens = [];

  /// Every method call the app made, in order.
  final List<MethodCall> calls = [];

  List<MethodCall> callsTo(String method) =>
      calls.where((c) => c.method == method).toList();

  /// Calls the test made on purpose can be forgotten with this.
  void clearCalls() => calls.clear();

  /// The next battery reading: [level] percent with [storedMah] currently
  /// stored in the battery (the charge counter; null = unsupported) and the
  /// optional [energyNwh] counter. Always the full set, so a previous
  /// reading's counters never leak into the next one.
  void setReading(int level, {double? storedMah, int? energyNwh}) {
    batteryLevel = level;
    chargeCounterMah = storedMah;
    energyCounterNwh = energyNwh;
  }

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Map<String, Object?> get capabilities =>
      capabilitiesOverride ??
      {
        'platform': platform.name,
        'dataByApp': !platform.isIos,
        'usageAccess': platform.isIos || usageAccessGranted,
        'usageAccessState':
            platform.isIos || usageAccessGranted ? 'granted' : 'denied',
        'chargeCounter': !platform.isIos && chargeCounterMah != null,
        'energyCounter': !platform.isIos && energyCounterNwh != null,
        'preciseDataHistory': !platform.isIos,
      };

  Map<String, Object?> get batterySnapshot => {
        'timeMs': _clock().millisecondsSinceEpoch,
        'level': batteryLevel,
        'plugged': plugged,
        if (!platform.isIos && chargeCounterMah != null)
          'chargeUah': (chargeCounterMah! * 1000).round(),
        if (!platform.isIos && energyCounterNwh != null)
          'energyNwh': energyCounterNwh,
        if (!platform.isIos) 'voltageMv': voltageMv,
        'source': 'app',
      };

  Map<String, Object?> get interfaceCounters {
    final c = counters;
    return {
      'wifiRx': c?.wifiRx ?? 48 * 1024 * 1024 * 1024,
      'wifiTx': c?.wifiTx ?? 6 * 1024 * 1024 * 1024,
      'cellRx': c?.cellRx ?? 9 * 1024 * 1024 * 1024,
      'cellTx': c?.cellTx ?? 1024 * 1024 * 1024,
      // A stable boot time: a changing one would look like a reboot to the folder.
      'bootTimeMs':
          c?.bootTimeMs ?? DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
      'timeMs': c?.timeMs ?? _clock().millisecondsSinceEpoch,
      if (c != null && c.bits != 32) 'bits': c.bits,
      if (c != null && c.ifaces.isNotEmpty)
        'ifaces': {
          for (final e in c.ifaces.entries) e.key: [e.value.rx, e.value.tx],
        },
    };
  }

  /// Methods that fail with a PlatformException while they are listed here (a tool for failure-path tests).
  final Set<String> failing = {};

  /// Methods an older native side does not implement: they throw MissingPluginException, as the real channel does.
  final Set<String> unsupported = {};

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    if (unsupported.contains(call.method)) {
      throw MissingPluginException(call.method);
    }
    if (failing.contains(call.method)) {
      throw PlatformException(code: 'injected', message: call.method);
    }
    switch (call.method) {
      case 'capabilities':
        return capabilities;
      case 'deviceInfo':
        return deviceInfo;
      case 'batterySnapshot':
        return batterySnapshot;
      case 'interfaceCounters':
        if (!platform.isIos) throw PlatformException(code: 'unsupported');
        return interfaceCounters;
      case 'drainSamples':
        final rows = List<Map<String, Object?>>.of(pendingSamples);
        pendingSamples = [];
        return rows;
      case 'peekSamples':
        // Two-step hand-over like the real SampleStore: the rows stay until they are acknowledged.
        return {
          'token': pendingSamples.isEmpty ? 0 : ++_sampleToken,
          'samples': List<Map<String, Object?>>.of(pendingSamples),
        };
      case 'ackSamples':
        final token = (call.arguments as Map)['token'] as int;
        if (token == _sampleToken) pendingSamples = [];
        ackedTokens.add(token);
        return null;
      case 'queryDataDaily':
        return dailyRows;
      case 'queryAppData':
        return appRows;
      case 'appGroupId':
        return appGroupId;
      case 'openUsageAccessSettings':
        return true;
      case 'ensureChargingWorker':
      case 'cancelChargingWorker':
      case 'setChargingNotification':
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }

  /// A plausible `deviceInfo` answer: iPhone 17 Pro or Pixel 8, region Poland.
  static Map<String, Object?> defaultDeviceInfo(HarnessPlatform platform) =>
      platform.isIos
          ? {
              'manufacturer': 'Apple',
              'model': 'iPhone',
              'modelIdentifier': 'iPhone18,1',
              'regionCode': 'PL',
              'localeTag': 'en-PL',
              'isSimulator': false,
            }
          : {
              'manufacturer': 'Google',
              'model': 'Pixel 8',
              'modelIdentifier': 'Pixel 8',
              'regionCode': 'PL',
              'localeTag': 'en-PL',
              'isSimulator': false,
            };

  /// A believable "Data by app" list for Android (largest first).
  static List<Map<String, Object?>> sampleApps() => [
        for (final (i, a) in const [
          ('YouTube', 'com.google.android.youtube', 1840, 220),
          ('Instagram', 'com.instagram.android', 920, 610),
          ('Chrome', 'com.android.chrome', 410, 960),
          ('Spotify', 'com.spotify.music', 380, 240),
          ('Google Maps', 'com.google.android.apps.maps', 150, 20),
          ('Messenger', 'com.facebook.orca', 95, 120),
        ].indexed)
          {
            'uid': 10100 + i,
            'name': a.$1,
            'package': a.$2,
            'mobile': a.$3 * 1024 * 1024,
            'wifi': a.$4 * 1024 * 1024,
            'icon': null,
            'kind': 'app',
          },
      ];
}
