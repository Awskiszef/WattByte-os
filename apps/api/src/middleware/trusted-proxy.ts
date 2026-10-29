import { BlockList, isIPv4, isIPv6 } from 'node:net';

import type { FastifyRequest } from 'fastify';

import { type Env, trustedProxyList } from '../config/env.js';

/**
 * Did this request reach us through a reverse proxy we trust? Used before honouring a header only a proxy may set
 * (COUNTRY_HEADER, B-11).
 *  - TRUST_PROXY_CIDRS: the connection's own address must be one of the listed proxies, so a client that reaches the
 *    origin directly cannot forge the header;
 *  - TRUST_PROXY_HOPS > 0: the operator says a proxy is in front; there is no way to verify it (an origin reachable
 *    without the proxy stays spoofable: prefer CIDRS);
 *  - otherwise no proxy is declared and nothing is trusted.
 */
export function makeViaTrustedProxy(env: Pick<Env, 'TRUST_PROXY_CIDRS' | 'TRUST_PROXY_HOPS'>): (request: FastifyRequest) => boolean {
  const entries = trustedProxyList(env);
  if (entries.length === 0) {
    const declared = env.TRUST_PROXY_HOPS > 0;
    return () => declared;
  }
  const list = new BlockList();
  for (const entry of entries) {
    const [addr = '', prefix] = entry.split('/');
    const family = isIPv6(addr) ? 'ipv6' : 'ipv4';
    if (prefix === undefined) list.addAddress(addr, family);
    else list.addSubnet(addr, Number(prefix), family);
  }
  return (request) => {
    const remote = request.raw.socket.remoteAddress;
    if (!remote) return false;
    // A dual-stack listener reports IPv4 peers as ::ffff:a.b.c.d.
    const plain = remote.startsWith('::ffff:') && isIPv4(remote.slice(7)) ? remote.slice(7) : remote;
    return list.check(plain, isIPv6(plain) ? 'ipv6' : 'ipv4');
  };
}
