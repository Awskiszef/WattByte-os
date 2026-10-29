// Run on a Mac (no simulator needed):
//   swiftc Classes/InterfaceCounterParser.swift Tests/InterfaceCounters/main.swift -o /tmp/check_ifc && /tmp/check_ifc
// Exits non-zero on the first failed check. Covers the pure parser with synthetic NET_RT_IFLIST2 buffers and one live read.
import Darwin
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
  if ok { print("ok   \(what)") } else { print("FAIL \(what)"); failures += 1 }
}

/// One RTM_IFINFO2 message for interface `index` with the given 64-bit counters.
func message(index: UInt16, rx: UInt64, tx: UInt64, type: UInt8 = InterfaceCounterParser.ifInfo2) -> [UInt8] {
  var m = if_msghdr2()
  m.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
  m.ifm_version = UInt8(RTM_VERSION)
  m.ifm_type = type
  m.ifm_index = index
  m.ifm_data.ifi_ibytes = rx
  m.ifm_data.ifi_obytes = tx
  return withUnsafeBytes(of: &m) { Array($0) }
}
let names: [UInt16: String] = [1: "en0", 2: "pdp_ip0", 3: "lo0"]
let nameOf: (UInt16) -> String? = { names[$0] }

// 1. values above 2^32 survive (the whole point of if_data64)
let nine: UInt64 = 9 * 1024 * 1024 * 1024
var buffer = message(index: 1, rx: nine, tx: 5) + message(index: 2, rx: 7, tx: 8) + message(index: 3, rx: 1, tx: 1)
var parsed = buffer.withUnsafeBytes { InterfaceCounterParser.parse($0, nameOf: nameOf) }
check(parsed["en0"] == InterfaceBytes(rx: nine, tx: 5), "64-bit counters above 4 GiB are read intact")
check(parsed["pdp_ip0"] == InterfaceBytes(rx: 7, tx: 8), "second interface is read")
check(parsed.count == 3, "every named interface is returned (the caller filters)")

// 2. other message types are skipped, unknown interface indexes are skipped
buffer = message(index: 1, rx: 1, tx: 1, type: 0x0e) + message(index: 99, rx: 2, tx: 2) + message(index: 2, rx: 3, tx: 4)
parsed = buffer.withUnsafeBytes { InterfaceCounterParser.parse($0, nameOf: nameOf) }
check(parsed == ["pdp_ip0": InterfaceBytes(rx: 3, tx: 4)], "foreign message types and unknown indexes are ignored")

// 3. a truncated last message and a zero-length message end the walk without reading past the buffer
let full = message(index: 1, rx: 11, tx: 12)
buffer = full + Array(message(index: 2, rx: 1, tx: 1).prefix(20))
parsed = buffer.withUnsafeBytes { InterfaceCounterParser.parse($0, nameOf: nameOf) }
check(parsed == ["en0": InterfaceBytes(rx: 11, tx: 12)], "a truncated trailing message is dropped")
var zero = full
zero[0] = 0; zero[1] = 0
parsed = (zero + full).withUnsafeBytes { InterfaceCounterParser.parse($0, nameOf: nameOf) }
check(parsed.isEmpty, "a zero-length message stops the walk (no endless loop)")
parsed = [UInt8]().withUnsafeBytes { InterfaceCounterParser.parse($0, nameOf: nameOf) }
check(parsed.isEmpty, "an empty buffer yields nothing")

// 4. live read: the loopback interface exists everywhere and its counters are non-decreasing between two reads
if let a = InterfaceCounterParser.readAll() {
  check(!a.isEmpty, "live: the kernel returned interfaces")
  let b = InterfaceCounterParser.readAll() ?? [:]
  let lo = "lo0"
  check((b[lo]?.rx ?? 0) >= (a[lo]?.rx ?? 0), "live: counters never go backwards between two reads")
} else {
  check(false, "live: sysctl NET_RT_IFLIST2 failed")
}

exit(failures == 0 ? 0 : 1)
