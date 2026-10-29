import Darwin
import Foundation

struct InterfaceBytes: Equatable {
  var rx: UInt64
  var tx: UInt64
}

/// Reads the 64-bit per-interface byte counters of the kernel (`sysctl NET_RT_IFLIST2`, `if_data64`).
///
/// `getifaddrs()` only exposes `struct if_data`, whose byte counters are 32-bit and wrap every 4 GiB; the Dart side
/// could neither tell a wrap from a counter restart nor count more than one wrap (audit G-09, H-03). The parser is
/// free of UIKit and of the live system so `Tests/check_interface_counters.swift` can run it on a Mac.
enum InterfaceCounterParser {
  /// `RTM_IFINFO2`: message type that carries `if_msghdr2` (the constant is not exported by the iOS SDK).
  static let ifInfo2: UInt8 = 0x12

  /// Walks a NET_RT_IFLIST2 buffer. A truncated or zero-length message ends the walk instead of reading past the buffer.
  static func parse(_ buffer: UnsafeRawBufferPointer, nameOf: (UInt16) -> String?) -> [String: InterfaceBytes] {
    var result: [String: InterfaceBytes] = [:]
    let headerSize = MemoryLayout<if_msghdr>.size
    var offset = 0
    while offset + headerSize <= buffer.count {
      let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
      let length = Int(header.ifm_msglen)
      if length < headerSize || offset + length > buffer.count { break }
      if header.ifm_type == ifInfo2 && length >= MemoryLayout<if_msghdr2>.size {
        let message = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
        if let name = nameOf(message.ifm_index) {
          result[name] = InterfaceBytes(rx: message.ifm_data.ifi_ibytes, tx: message.ifm_data.ifi_obytes)
        }
      }
      offset += length
    }
    return result
  }

  /// All interfaces by name, or nil when the kernel refuses (the caller falls back to the 32-bit counters).
  static func readAll() -> [String: InterfaceBytes]? {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
    // The table can grow between the two calls: ask for some headroom and retry once if it still does not fit.
    for _ in 0..<2 {
      var capacity = length + length / 8 + 4096
      var buffer = [UInt8](repeating: 0, count: capacity)
      if sysctl(&mib, UInt32(mib.count), &buffer, &capacity, nil, 0) == 0 {
        return buffer.withUnsafeBytes { raw in
          parse(UnsafeRawBufferPointer(rebasing: raw[0..<capacity])) { index in
            var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
            return if_indextoname(UInt32(index), &name) == nil ? nil : String(cString: name)
          }
        }
      }
      guard errno == ENOMEM, sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else { return nil }
    }
    return nil
  }
}
