import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { afterEach, describe, expect, it } from 'vitest';

import { containsNul } from '../src/middleware/input-guards.js';
import { isMainModule } from '../src/util/is-main.js';
import { type BuiltApp, buildTestApp } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});
async function make(opts: Parameters<typeof buildTestApp>[0] = {}): Promise<BuiltApp> {
  const built = await buildTestApp(opts);
  apps.push(built);
  return built;
}

describe('liveness and readiness probes are exempt from the rate limiter (B-09)', () => {
  it('/health and /ready answer 200 far beyond the per-IP limit, while an ordinary route is limited', async () => {
    const { app } = await make({ rateLimitMax: 2 });
    for (const url of ['/health', '/ready']) {
      for (let i = 0; i < 25; i += 1) expect((await app.inject({ method: 'GET', url })).statusCode, `${url} #${i}`).toBe(200);
    }
    // The same client is still limited on everything else (the probes did not even consume the budget).
    const statuses: number[] = [];
    for (let i = 0; i < 4; i += 1) statuses.push((await app.inject({ method: 'GET', url: '/no-such-route' })).statusCode);
    expect(statuses).toEqual([404, 404, 429, 429]);
  });
});

describe('a huge JSON array cannot crash body handling (B-10)', () => {
  it('containsNul scans an array of two million elements without a RangeError', () => {
    const big = new Array<number>(2_000_000).fill(1);
    expect(containsNul(big)).toBe(false);
    big[1_999_999] = 0;
    expect(containsNul({ rows: big })).toBe(false);
    expect(containsNul([...big.slice(0, 10), 'a\u0000b'])).toBe(true);
  });

  it('a ~600 KB array body on a public route is a 400, not a 500', async () => {
    const { app } = await make();
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      headers: { 'content-type': 'application/json' },
      payload: `[${'0,'.repeat(299_999)}0]`,
    });
    expect(res.statusCode).toBe(400);
  });
});

describe('client address trust (B-13): what the rate limiter keys on', () => {
  const via = (xff: string) => ({ method: 'GET' as const, url: '/no-such-route', remoteAddress: '10.0.0.1', headers: { 'x-forwarded-for': xff } });

  it('TRUST_PROXY_HOPS=0: X-Forwarded-For is ignored, every caller is the socket address', async () => {
    const { app } = await make({ rateLimitMax: 1, env: { TRUST_PROXY_HOPS: '0' } });
    expect((await app.inject(via('1.1.1.1'))).statusCode).toBe(404);
    // A different claimed address does not buy a fresh bucket.
    expect((await app.inject(via('2.2.2.2'))).statusCode).toBe(429);
    expect((await app.inject(via('3.3.3.3'))).statusCode).toBe(429);
  });

  it('TRUST_PROXY_HOPS=1: the address the one trusted proxy appended counts, earlier (client-chosen) entries do not', async () => {
    const { app } = await make({ rateLimitMax: 1, env: { TRUST_PROXY_HOPS: '1' } });
    expect((await app.inject(via('spoof-a, 2.2.2.2'))).statusCode).toBe(404);
    // Same real client (2.2.2.2), a different forged leading entry: still the same bucket.
    expect((await app.inject(via('spoof-b, 2.2.2.2'))).statusCode).toBe(429);
    // A different client behind the proxy has its own bucket.
    expect((await app.inject(via('spoof-a, 3.3.3.3'))).statusCode).toBe(404);
  });

  it('TRUST_PROXY_HOPS=2: two trusted proxies, the client is the entry before them', async () => {
    const { app } = await make({ rateLimitMax: 1, env: { TRUST_PROXY_HOPS: '2' } });
    expect((await app.inject(via('forged, 4.4.4.4, 10.0.0.9'))).statusCode).toBe(404);
    expect((await app.inject(via('other-forged, 4.4.4.4, 10.0.0.9'))).statusCode).toBe(429);
    expect((await app.inject(via('forged, 5.5.5.5, 10.0.0.9'))).statusCode).toBe(404);
  });
});

describe('isMainModule resolves symlinks (C-10)', () => {
  it('is true for the real path, a symlink to it and a relative path, false otherwise', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'wb-ismain-'));
    try {
      const real = path.join(dir, 'real.mjs');
      writeFileSync(real, 'export {};\n');
      const link = path.join(dir, 'link.mjs');
      symlinkSync(real, link);
      const url = pathToFileURL(real).href;
      expect(isMainModule(url, real)).toBe(true);
      expect(isMainModule(url, link)).toBe(true);
      expect(isMainModule(url, path.relative(process.cwd(), link))).toBe(true);
      expect(isMainModule(url, path.join(dir, 'other.mjs'))).toBe(false);
      expect(isMainModule(url, undefined)).toBe(false);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
