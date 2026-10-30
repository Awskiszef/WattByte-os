// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from 'vitest';

import { loadEnv, proxyCidrProblems } from '../src/config/env.js';
import { type BuiltApp, buildTestApp } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});
async function make(env: Record<string, string>, rateLimitMax?: number): Promise<BuiltApp> {
  const built = await buildTestApp({ env, rateLimitMax });
  apps.push(built);
  return built;
}
const base = { NODE_ENV: 'development', JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd' };

describe('TRUST_PROXY_CIDRS validation (B-11)', () => {
  it.each([
    ['10.0.0.0/8', []],
    ['10.0.0.0/8, fd00::/8 , 192.0.2.7', []],
    ['', ['lists no address']],
    ['10.0.0.0/33', ['not an IPv4/IPv6 address or CIDR']],
    ['fd00::/129', ['not an IPv4/IPv6 address or CIDR']],
    ['proxy.example.com', ['not an IPv4/IPv6 address or CIDR']],
    ['10.0.0.1/8/8', ['not an IPv4/IPv6 address or CIDR']],
    ['0.0.0.0/0', ['would trust every address']],
    ['::/0', ['would trust every address']],
  ])('%j', (value, expected) => {
    const problems = proxyCidrProblems(value);
    expect(problems).toHaveLength(expected.length);
    for (const part of expected) expect(problems.join('\n')).toContain(part);
  });

  it('loadEnv refuses a bad list and the combination with a hop count', () => {
    expect(() => loadEnv({ ...base, TRUST_PROXY_CIDRS: 'nonsense' })).toThrow(/TRUST_PROXY_CIDRS entry "nonsense"/);
    expect(() => loadEnv({ ...base, TRUST_PROXY_CIDRS: '10.0.0.0/8', TRUST_PROXY_HOPS: '1' })).toThrow(/alternatives/);
    expect(loadEnv({ ...base, TRUST_PROXY_CIDRS: '10.0.0.0/8', TRUST_PROXY_HOPS: '0' }).TRUST_PROXY_CIDRS).toBe('10.0.0.0/8');
  });
});

describe('with a proxy allow-list the forwarded address is believed only from those proxies', () => {
  const via = (remoteAddress: string, xff: string) => ({ method: 'GET' as const, url: '/no-such-route', remoteAddress, headers: { 'x-forwarded-for': xff } });

  it('a connection from a listed proxy: the address it forwarded is the client', async () => {
    const { app } = await make({ TRUST_PROXY_CIDRS: '10.0.0.0/8' }, 1);
    expect((await app.inject(via('10.1.2.3', 'forged, 2.2.2.2'))).statusCode).toBe(404);
    expect((await app.inject(via('10.1.2.3', 'other-forgery, 2.2.2.2'))).statusCode).toBe(429); // same client
    expect((await app.inject(via('10.9.9.9', 'x, 2.2.2.2'))).statusCode).toBe(429); // the same client through another proxy of the range
    expect((await app.inject(via('10.1.2.3', 'x, 3.3.3.3'))).statusCode).toBe(404); // another client behind the same proxy
  });

  it('a connection from anywhere else (the origin reached directly): X-Forwarded-For is ignored', async () => {
    const { app } = await make({ TRUST_PROXY_CIDRS: '10.0.0.0/8' }, 1);
    expect((await app.inject(via('192.0.2.50', '1.1.1.1'))).statusCode).toBe(404);
    // A new forged address does not give a new bucket: the socket address is the client.
    expect((await app.inject(via('192.0.2.50', '2.2.2.2'))).statusCode).toBe(429);
  });
});

describe('COUNTRY_HEADER is believed only through a trusted proxy (B-11)', () => {
  const region = (remoteAddress: string) => ({ method: 'GET' as const, url: '/api/v1/region', remoteAddress, headers: { 'cf-ipcountry': 'PL' } });

  it('CIDR mode: from a listed proxy yes, from another address no', async () => {
    const { app } = await make({ COUNTRY_HEADER: 'cf-ipcountry', TRUST_PROXY_CIDRS: '10.0.0.0/8' });
    expect((await app.inject(region('10.1.2.3'))).json()).toEqual({ countryCode: 'PL', source: 'backendCountry' });
    expect((await app.inject(region('192.0.2.50'))).json()).toEqual({ countryCode: null, source: 'none' });
  });

  it('hop mode: believed once a proxy is declared (TRUST_PROXY_HOPS > 0), ignored when none is', async () => {
    const withProxy = await make({ COUNTRY_HEADER: 'cf-ipcountry', TRUST_PROXY_HOPS: '1' });
    expect((await withProxy.app.inject(region('192.0.2.50'))).json().countryCode).toBe('PL');
    const direct = await make({ COUNTRY_HEADER: 'cf-ipcountry', TRUST_PROXY_HOPS: '0' });
    expect((await direct.app.inject(region('192.0.2.50'))).json().countryCode).toBeNull();
  });
});
