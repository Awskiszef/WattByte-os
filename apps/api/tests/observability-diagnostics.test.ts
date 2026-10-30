// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Audit B-12: a failure can be told apart without putting its data in the log, and the service can be measured.
import { afterEach, describe, expect, it } from 'vitest';

import { loadEnv } from '../src/config/env.js';
import { logSerializers, makeErrSerializer, safeErrorFields } from '../src/observability/logging.js';
import { bearerMatches, Metrics } from '../src/observability/metrics.js';
import { type BuiltApp, buildTestApp, pgStyleError } from './support.js';

const serialize = (err: Error, verbose = false) => makeErrSerializer(verbose)(err as never) as Record<string, unknown>;

describe('error log fields', () => {
  it('keeps the SQLSTATE and severity, never the offending value or the schema object names', () => {
    const out = serialize(pgStyleError('victim@example.test'));
    expect(out).toMatchObject({ type: 'error', code: '23505', severity: 'ERROR', message: 'omitted' });
    expect(JSON.stringify(out)).not.toContain('victim@example.test');
    for (const field of ['detail', 'table', 'column', 'constraint', 'schema']) expect(out).not.toHaveProperty(field);
    expect(JSON.stringify(out)).not.toContain('users_email_key');
  });

  it('adds the schema object names, and the message, only in the development switch', () => {
    const out = serialize(pgStyleError('victim@example.test'), true);
    expect(out).toMatchObject({ schema: 'public', table: 'users', constraint: 'users_email_key' });
    expect(out.message).toContain('users_email_key');
    expect(out).not.toHaveProperty('detail');
  });

  it('keeps the failing syscall of a system error but not the address it was talking to', () => {
    const e = Object.assign(new Error('connect ECONNREFUSED 10.1.2.3:5432'), { code: 'ECONNREFUSED', syscall: 'connect', address: '10.1.2.3', port: 5432 });
    const out = serialize(e);
    expect(out).toMatchObject({ code: 'ECONNREFUSED', syscall: 'connect', message: 'omitted' });
    expect(JSON.stringify(out)).not.toContain('10.1.2.3');
  });

  it('drops a field that does not look like an identifier', () => {
    const e = Object.assign(new Error('x'), { table: 'users; mallory@example.test', column: 'a b', constraint: 'x'.repeat(64), code: 'bad code!', syscall: 'connect to mallory@example.test' });
    expect(safeErrorFields(e, true)).toMatchObject({ table: undefined, column: undefined, constraint: undefined, code: undefined, syscall: undefined });
  });

  it('shows the message only when asked, and the default serializer never does', () => {
    const e = pgStyleError('victim@example.test');
    expect(serialize(e, true).message).toContain('users_email_key');
    expect(serialize(e).message).toBe('omitted');
    expect((logSerializers.err!(e as never) as Record<string, unknown>).message).toBe('omitted');
  });
});

describe('LOG_ERROR_MESSAGES and METRICS_TOKEN', () => {
  const production = { JWT_SECRET: 'k3J9xQ2vLm8Zp4Rt7Yw1Nb6Hc5Df0Gs2AaBbCcDd', NODE_ENV: 'production', DATABASE_URL: 'postgres://app:s3cr3t-db-pass@db.internal:5432/wattbyte', DATABASE_SSL: '1', TRUST_PROXY_HOPS: '1' };

  it('error messages in the log are a development-only switch', () => {
    expect(loadEnv({ NODE_ENV: 'development', JWT_SECRET: production.JWT_SECRET, LOG_ERROR_MESSAGES: '1' }).LOG_ERROR_MESSAGES).toBe('1');
    expect(() => loadEnv({ ...production, LOG_ERROR_MESSAGES: '1' })).toThrow(/LOG_ERROR_MESSAGES=1 is not allowed/);
    expect(() => loadEnv({ ...production, APP_ENV: 'staging', LOG_ERROR_MESSAGES: '1' })).toThrow(/LOG_ERROR_MESSAGES=1 is not allowed/);
    expect(loadEnv(production).LOG_ERROR_MESSAGES).toBe('0');
  });

  it('the metrics token must be long and not a placeholder in staging and production', () => {
    expect(() => loadEnv({ ...production, METRICS_TOKEN: 'short' })).toThrow(/METRICS_TOKEN/);
    expect(() => loadEnv({ ...production, METRICS_TOKEN: 'change-me-change-me-change-me-123' })).toThrow(/placeholder/);
    expect(() => loadEnv({ ...production, METRICS_TOKEN: 'abababababababababababababababab' })).toThrow(/repeated pattern/);
    expect(loadEnv({ ...production, METRICS_TOKEN: 'f3a91c07d2b84e5a96c0d1e7b3a8f4c2' }).METRICS_TOKEN).toBeDefined();
    expect(loadEnv(production).METRICS_TOKEN).toBeUndefined();
  });
});

describe('Metrics', () => {
  it('renders counters and a cumulative histogram per route template', () => {
    const m = new Metrics({ version: '9.9.9' });
    m.record('GET', '/health', 200, 0.004);
    m.record('GET', '/health', 200, 0.2);
    m.record('POST', '/api/v1/auth/login', 401, 12);
    const text = m.render();
    expect(text).toContain('wattbyte_build_info{version="9.9.9"} 1');
    expect(text).toContain('wattbyte_http_requests_total{method="GET",route="/health",status="200"} 2');
    expect(text).toContain('wattbyte_http_requests_total{method="POST",route="/api/v1/auth/login",status="401"} 1');
    expect(text).toContain('wattbyte_http_request_duration_seconds_bucket{method="GET",route="/health",le="0.005"} 1');
    expect(text).toContain('wattbyte_http_request_duration_seconds_bucket{method="GET",route="/health",le="0.25"} 2');
    expect(text).toContain('wattbyte_http_request_duration_seconds_bucket{method="POST",route="/api/v1/auth/login",le="10"} 0');
    expect(text).toContain('wattbyte_http_request_duration_seconds_bucket{method="POST",route="/api/v1/auth/login",le="+Inf"} 1');
    expect(text).toContain('wattbyte_http_request_duration_seconds_count{method="GET",route="/health"} 2');
  });

  it('escapes label values and renders caller-supplied gauges', () => {
    const m = new Metrics({ version: '1', gauges: () => [{ name: 'wattbyte_db_pool_connections', help: 'h', value: 3, labels: { state: 'idle' } }] });
    m.record('GET', 'a"b\\c\nd', 200, 0.001);
    const text = m.render();
    expect(text).toContain('route="a\\"b\\\\c\\nd"');
    expect(text).toContain('wattbyte_db_pool_connections{state="idle"} 3');
  });

  it('compares the bearer token in constant time and rejects an empty one', () => {
    expect(bearerMatches('Bearer abc', 'abc')).toBe(true);
    expect(bearerMatches('Bearer abd', 'abc')).toBe(false);
    expect(bearerMatches('abc', 'abc')).toBe(false);
    expect(bearerMatches(undefined, 'abc')).toBe(false);
    expect(bearerMatches('Bearer ', '')).toBe(false);
  });
});

describe('GET /metrics', () => {
  const apps: BuiltApp[] = [];
  afterEach(async () => {
    await Promise.all(apps.splice(0).map((c) => c.app.close()));
  });
  const TOKEN = 'f3a91c07d2b84e5a96c0d1e7b3a8f4c2';

  it('does not exist unless METRICS_TOKEN is set', async () => {
    const ctx = await buildTestApp();
    apps.push(ctx);
    expect((await ctx.app.inject({ method: 'GET', url: '/metrics' })).statusCode).toBe(404);
  });

  it('answers only the right bearer token, and counts route templates, not URLs', async () => {
    const ctx = await buildTestApp({ env: { METRICS_TOKEN: TOKEN } });
    apps.push(ctx);
    const { app } = ctx;
    expect((await app.inject({ method: 'GET', url: '/metrics' })).statusCode).toBe(401);
    const wrong = await app.inject({ method: 'GET', url: '/metrics', headers: { authorization: 'Bearer nope' } });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.headers['www-authenticate']).toBe('Bearer');

    await app.inject({ method: 'GET', url: '/health' });
    await app.inject({ method: 'DELETE', url: '/api/v1/devices/6f1c2b1e-3c2d-4a55-9d3a-0b8f2f6f1a11?token=secret-in-query' });
    await app.inject({ method: 'GET', url: '/no/such/page/victim@example.test' });

    const res = await app.inject({ method: 'GET', url: '/metrics', headers: { authorization: `Bearer ${TOKEN}` } });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/plain');
    const text = res.body;
    expect(text).toContain('wattbyte_http_requests_total{method="GET",route="/health",status="200"} 1');
    expect(text).toMatch(/method="DELETE",route="\/api\/v1\/devices\/:[A-Za-z]+",status="401"/);
    expect(text).toContain('route="[unmatched]",status="404"');
    for (const leak of ['6f1c2b1e', 'secret-in-query', 'victim@example.test', TOKEN]) expect(text).not.toContain(leak);
  });

  it('is not part of the published OpenAPI document', async () => {
    const ctx = await buildTestApp({ env: { METRICS_TOKEN: TOKEN } });
    apps.push(ctx);
    expect((await ctx.app.inject({ method: 'GET', url: '/openapi.json' })).body).not.toContain('/metrics');
  });
});
