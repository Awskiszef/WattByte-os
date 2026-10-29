import { afterEach, describe, expect, it } from 'vitest';

import { hasOversizedArray, MAX_BODY_ARRAY_LENGTH } from '../src/middleware/input-guards.js';
import { type BuiltApp, buildTestApp, register, sampleDay } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  while (apps.length) await apps.pop()!.app.close();
});
async function make(): Promise<BuiltApp> {
  const built = await buildTestApp();
  apps.push(built);
  return built;
}
const json = { 'content-type': 'application/json' };

/** B-04: work and memory of a request must not grow with an attacker-chosen element count. */
describe('POST /usage/sync with a hostile `days` array', () => {
  async function post(app: BuiltApp['app'], token: string, days: unknown[], extra: Record<string, unknown> = {}) {
    return app.inject({
      method: 'POST',
      url: '/api/v1/usage/sync',
      headers: { ...json, authorization: `Bearer ${token}` },
      payload: JSON.stringify({ installationId: 'install-00000001', days, ...extra }),
    });
  }

  it.each([93, 1_001, 5_000])('%i empty days: 400, answered fast, no per-element error text', async (count) => {
    const { app } = await make();
    const user = await register(app, `sync-${count}@test.wattbyte`);
    const started = performance.now();
    const res = await post(app, user.accessToken, Array.from({ length: count }, () => ({})));
    const elapsed = performance.now() - started;
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('validation');
    expect(res.body.length).toBeLessThan(600);
    expect(elapsed).toBeLessThan(500);
  });

  it('a body above 64 KiB is 413 before any parsing work', async () => {
    const { app } = await make();
    const user = await register(app, 'sync-big@test.wattbyte');
    const res = await post(app, user.accessToken, Array.from({ length: 30_000 }, () => ({})));
    expect(res.statusCode).toBe(413);
  });

  it('a valid 92-day body (the largest legitimate one) is still accepted and fits the limit', async () => {
    const { app } = await make();
    const user = await register(app, 'sync-92@test.wattbyte');
    await app.inject({ method: 'POST', url: '/api/v1/devices', headers: { ...json, authorization: `Bearer ${user.accessToken}` }, payload: JSON.stringify({ installationId: 'install-00000001', platform: 'android' }) });
    const start = Date.UTC(2026, 0, 1);
    const days = Array.from({ length: 92 }, (_, i) => ({ ...sampleDay(new Date(start + i * 86_400_000).toISOString().slice(0, 10)) }));
    const body = JSON.stringify({ installationId: 'install-00000001', days });
    expect(body.length).toBeLessThan(65_536);
    const res = await post(app, user.accessToken, days);
    expect(res.statusCode, res.body).toBe(200);
  });
});

describe('array length guard', () => {
  it('flags an array above the limit at any depth, and nothing else', () => {
    expect(hasOversizedArray({ a: new Array(MAX_BODY_ARRAY_LENGTH).fill(0) })).toBe(false);
    expect(hasOversizedArray({ a: new Array(MAX_BODY_ARRAY_LENGTH + 1).fill(0) })).toBe(true);
    expect(hasOversizedArray({ a: { b: [[new Array(MAX_BODY_ARRAY_LENGTH + 1).fill(0)]] } })).toBe(true);
    expect(hasOversizedArray('text')).toBe(false);
    expect(hasOversizedArray(null)).toBe(false);
  });

  it('a small public body with 1001 entries is refused as validation (not by size)', async () => {
    const { app } = await make();
    const res = await app.inject({ method: 'POST', url: '/api/v1/auth/login', headers: json, payload: `[${'0,'.repeat(1_000)}0]` });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('validation');
  });
});

describe('the validation message is built from the first issues only', () => {
  it('an object with many bad fields does not echo more than a few issues', async () => {
    const { app } = await make();
    const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', headers: json, payload: '{}' });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.message.length).toBeLessThanOrEqual(300);
  });
});
