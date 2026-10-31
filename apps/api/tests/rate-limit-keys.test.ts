// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from 'vitest';

import { clientKey } from '../src/middleware/client-key.js';
import { GroupedLocalStore } from '../src/middleware/rate-limit-store.js';
import { type BuiltApp, buildTestApp } from './support.js';

describe('clientKey (A-02, B-01)', () => {
  it.each([
    ['203.0.113.9', '203.0.113.9'],
    ['::ffff:203.0.113.9', '203.0.113.9'],
    ['::ffff:cb00:7109', '203.0.113.9'],
    ['2001:db8:1:2::1', '2001:db8:1:2::/64'],
    ['2001:DB8:1:2:ffff:ffff:ffff:ffff', '2001:db8:1:2::/64'],
    ['2001:0db8:0001:0002:0000:0000:0000:0007', '2001:db8:1:2::/64'],
    ['fe80::1%eth0', 'fe80:0:0:0::/64'],
    ['::1', '0:0:0:0::/64'],
    ['not an ip', 'not an ip'],
  ])('%s -> %s', (ip, key) => {
    expect(clientKey(ip)).toBe(key);
  });

  it('every address of one /64 is one client, a neighbouring /64 is another', () => {
    expect(clientKey('2001:db8:1:2::1')).toBe(clientKey('2001:db8:1:2:dead:beef:0:1'));
    expect(clientKey('2001:db8:1:2::1')).not.toBe(clientKey('2001:db8:1:3::1'));
  });
});

describe('GroupedLocalStore', () => {
  const hit = (s: GroupedLocalStore, key: string): number => {
    let current = 0;
    s.incr(key, (_e, r) => (current = r.current), 60_000);
    return current;
  };

  it('routes with the same groupId share counters, others keep their own', () => {
    const root = new GroupedLocalStore();
    const a = root.child({ groupId: 'credentials' });
    const b = root.child({ groupId: 'credentials' });
    const c = root.child({ groupId: 'refresh' });
    const d = root.child({});
    expect(hit(a, 'k')).toBe(1);
    expect(hit(b, 'k')).toBe(2);
    expect(hit(c, 'k')).toBe(1);
    expect(hit(d, 'k')).toBe(1);
    expect(hit(root.child({}), 'k')).toBe(1); // a route without a group is private
  });

  it('memory stays bounded: beyond the cap the oldest counters go', () => {
    const s = new GroupedLocalStore(100);
    for (let i = 0; i < 1_000; i++) hit(s, `client-${i}`);
    expect(s.size).toBeLessThanOrEqual(100);
    expect(hit(s, 'client-999')).toBe(2); // a recent one survived
    expect(hit(s, 'client-0')).toBe(1); // an old one was evicted
  });
});

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});
async function make(opts: Parameters<typeof buildTestApp>[0]): Promise<BuiltApp> {
  const built = await buildTestApp(opts);
  apps.push(built);
  return built;
}
const from = (remoteAddress: string, headers: Record<string, string> = {}) => ({ method: 'GET' as const, url: '/no-such-route', remoteAddress, headers });

describe('the rate limiter keys IPv6 clients by /64', () => {
  it('rotating the host part inside one /64 does not buy a fresh budget; another /64 has its own', async () => {
    const { app } = await make({ rateLimitMax: 2 });
    const statuses: number[] = [];
    for (const host of ['1', '2', '3', 'dead:beef']) statuses.push((await app.inject(from(`2001:db8:1:2::${host}`))).statusCode);
    expect(statuses).toEqual([404, 404, 429, 429]);
    expect((await app.inject(from('2001:db8:1:3::1'))).statusCode).toBe(404);
  });

  it('an IPv4-mapped address and the plain IPv4 address are one client', async () => {
    const { app } = await make({ rateLimitMax: 1 });
    expect((await app.inject(from('203.0.113.9'))).statusCode).toBe(404);
    expect((await app.inject(from('::ffff:203.0.113.9'))).statusCode).toBe(429);
  });
});
