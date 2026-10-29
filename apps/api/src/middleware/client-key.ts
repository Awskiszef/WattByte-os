import { isIPv4, isIPv6 } from 'node:net';

/**
 * Parses an IPv6 address (any textual form) into its eight 16-bit groups; null when it is not one.
 * Embedded IPv4 tails (`::ffff:1.2.3.4`) and zone ids (`fe80::1%eth0`) are understood.
 */
function ipv6Groups(address: string): number[] | null {
  const bare = address.split('%', 1)[0] ?? '';
  if (!isIPv6(bare)) return null;
  let text = bare;
  const tail = /(\d+\.\d+\.\d+\.\d+)$/.exec(text);
  if (tail) {
    const octets = tail[1]!.split('.').map(Number);
    const hi = ((octets[0]! << 8) | octets[1]!).toString(16);
    const lo = ((octets[2]! << 8) | octets[3]!).toString(16);
    text = `${text.slice(0, -tail[1]!.length)}${hi}:${lo}`;
  }
  const [head = '', rest] = text.split('::');
  const left = head === '' ? [] : head.split(':');
  const right = rest === undefined || rest === '' ? [] : rest.split(':');
  const missing = rest === undefined ? 0 : 8 - left.length - right.length;
  const groups = [...left, ...new Array<string>(Math.max(0, missing)).fill('0'), ...right].map((g) => parseInt(g, 16));
  return groups.length === 8 && groups.every((g) => Number.isInteger(g) && g >= 0 && g <= 0xffff) ? groups : null;
}

/**
 * The key one client is rate limited under. An IPv6 client controls a whole /64 (2^64 addresses), so it is keyed by
 * its /64 prefix; an IPv4-mapped address (`::ffff:1.2.3.4`) is the same client as `1.2.3.4`. Everything else is
 * returned unchanged (A-02, B-01).
 */
export function clientKey(ip: string): string {
  if (isIPv4(ip)) return ip;
  const groups = ipv6Groups(ip);
  if (!groups) return ip;
  const mapped = groups.slice(0, 5).every((g) => g === 0) && groups[5] === 0xffff;
  if (mapped) return `${groups[6]! >> 8}.${groups[6]! & 255}.${groups[7]! >> 8}.${groups[7]! & 255}`;
  return `${groups.slice(0, 4).map((g) => g.toString(16)).join(':')}::/64`;
}
