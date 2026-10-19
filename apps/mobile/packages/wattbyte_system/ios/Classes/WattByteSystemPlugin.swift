import Flutter
import UIKit

/// Method-channel entry point ("wattbyte/system") for iOS.
///
/// iOS offers no per-app data usage and no charge/energy counters to third
/// parties, so those calls answer `notImplemented` / `nil` and the Dart side
/// hides or estimates accordingly. What is public:
///  - `getifaddrs` since-boot byte counters per interface (en0 = Wi-Fi, pdp_ip* = cellular)
///  - `UIDevice` battery level and state
///  - `kern.boottime` to detect reboots between samples
public class WattByteSystemPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "wattbyte/system", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WattByteSystemPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result([
        "platform": "ios",
        "dataByApp": false,
        "usageAccess": true,
        "chargeCounter": false,
        "energyCounter": false,
        "preciseDataHistory": false,
      ])
    case "batterySnapshot":
      result(BatteryReader.snapshot())
    case "interfaceCounters":
      result(InterfaceCounters.read())
    case "appGroupId":
      result(Bundle.main.object(forInfoDictionaryKey: "WBAppGroup") as? String)
    case "deviceInfo":
      result(DeviceInfo.read())
    case "drainSamples":
      result([])
    case "openUsageAccessSettings", "ensureChargingWorker", "cancelChargingWorker", "setChargingNotification":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Public, non-identifying facts the automatic setup needs: the model code (to
/// look the battery up in the device catalog) and the Region setting (for the
/// default currency). No serial number, no advertising id, no location.
enum DeviceInfo {
  static func read() -> [String: Any?] {
    let env = ProcessInfo.processInfo.environment
    // On the simulator utsname reports the Mac; CoreSimulator exposes the simulated model instead.
    let identifier = env["SIMULATOR_MODEL_IDENTIFIER"] ?? machineIdentifier()
    let region: String?
    if #available(iOS 16, *) {
      region = Locale.current.region?.identifier
    } else {
      region = Locale.current.regionCode
    }
    return [
      "manufacturer": "Apple",
      "model": UIDevice.current.model, // "iPhone" / "iPad"; the identifier carries the generation
      "modelIdentifier": identifier,
      "regionCode": region,
      "localeTag": Locale.preferredLanguages.first,
      "isSimulator": env["SIMULATOR_MODEL_IDENTIFIER"] != nil,
    ]
  }

  /// `utsname.machine`, e.g. "iPhone16,1". Documented and stable per model.
  static func machineIdentifier() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
    }
  }
}

enum BatteryReader {
  static func snapshot() -> [String: Any?] {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let level = device.batteryLevel // -1 when unknown
    let plugged = device.batteryState == .charging || device.batteryState == .full
    return [
      "timeMs": Int64(Date().timeIntervalSince1970 * 1000),
      "level": level < 0 ? -1 : Int((level * 100).rounded()),
      "plugged": plugged,
      "chargeUah": nil,
      "energyNwh": nil,
      "voltageMv": nil,
      "source": "app",
    ]
  }
}

enum InterfaceCounters {
  /// Sums `ifi_ibytes` / `ifi_obytes` of en0 (Wi-Fi) and pdp_ip* (cellular).
  /// Counters are 32-bit and since boot; Dart handles wrap and reboot.
  static func read() -> [String: Any] {
    var wifiRx: UInt64 = 0, wifiTx: UInt64 = 0, cellRx: UInt64 = 0, cellTx: UInt64 = 0
    var first: UnsafeMutablePointer<ifaddrs>? = nil
    if getifaddrs(&first) == 0, let head = first {
      defer { freeifaddrs(head) }
      var ptr: UnsafeMutablePointer<ifaddrs>? = head
      while let p = ptr {
        defer { ptr = p.pointee.ifa_next }
        guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
              let raw = p.pointee.ifa_data else { continue }
        let data = raw.assumingMemoryBound(to: if_data.self).pointee
        let name = String(cString: p.pointee.ifa_name)
        let rx = UInt64(data.ifi_ibytes), tx = UInt64(data.ifi_obytes)
        if name == "en0" {
          wifiRx += rx; wifiTx += tx
        } else if name.hasPrefix("pdp_ip") {
          cellRx += rx; cellTx += tx
        }
      }
    }
    return [
      "wifiRx": Int64(wifiRx),
      "wifiTx": Int64(wifiTx),
      "cellRx": Int64(cellRx),
      "cellTx": Int64(cellTx),
      "bootTimeMs": bootTimeMs(),
      "timeMs": Int64(Date().timeIntervalSince1970 * 1000),
    ]
  }

  static func bootTimeMs() -> Int64 {
    var tv = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
    return Int64(tv.tv_sec) * 1000 + Int64(tv.tv_usec) / 1000
  }
}
