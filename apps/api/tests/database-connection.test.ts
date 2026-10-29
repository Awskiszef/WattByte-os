import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { describe, expect, it } from 'vitest';

import { loadEnv } from '../src/config/env.js';
import { poolSettings, resolveDatabaseConnection } from '../src/database/connection.js';
import { loadRetentionConfig } from '../src/scripts/retention.js';

const BASE = 'postgres://app:secret@db.internal:5432/wattbyte';

describe('resolveDatabaseConnection (C-06, C-11)', () => {
  it('DATABASE_SSL=1: verified TLS, and the URL TLS parameters cannot override it', () => {
    const r = resolveDatabaseConnection({ url: `${BASE}?sslmode=require&application_name=wb`, databaseSsl: '1' });
    expect(r.ssl).toEqual({ rejectUnauthorized: true });
    expect(r.connectionString).not.toMatch(/sslmode|ssl=/);
    expect(r.connectionString).toContain('application_name=wb');
  });

  it.each(['sslmode=disable', 'sslmode=allow', 'sslmode=prefer', 'sslmode=no-verify', 'ssl=0', 'ssl=false'])(
    'DATABASE_SSL=1 refuses a URL that asks for less (%s) instead of letting it win',
    (q) => {
      expect(() => resolveDatabaseConnection({ url: `${BASE}?${q}`, databaseSsl: '1' })).toThrow(/requires verified TLS/);
    },
  );

  it('DATABASE_SSL=0 refuses a URL that asks for TLS', () => {
    expect(() => resolveDatabaseConnection({ url: `${BASE}?sslmode=verify-full`, databaseSsl: '0' })).toThrow(/decide one/);
    expect(resolveDatabaseConnection({ url: `${BASE}?sslmode=disable`, databaseSsl: '0' }).ssl).toBeUndefined();
  });

  it('DATABASE_SSL unset: the URL decides, exactly as before', () => {
    expect(resolveDatabaseConnection({ url: `${BASE}?sslmode=require` })).toEqual({ connectionString: `${BASE}?sslmode=require` });
    expect(resolveDatabaseConnection({ url: BASE, databaseSsl: '' })).toEqual({ connectionString: BASE });
  });

  it('a CA file becomes the trust anchor; unreadable / non-PEM / without DATABASE_SSL=1 is refused', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'wb-ca-'));
    const good = path.join(dir, 'ca.pem');
    writeFileSync(good, '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n');
    const bad = path.join(dir, 'not-a-ca.txt');
    writeFileSync(bad, 'hello');
    expect(resolveDatabaseConnection({ url: BASE, databaseSsl: '1', caFile: good }).ssl).toMatchObject({ rejectUnauthorized: true, ca: expect.stringContaining('BEGIN CERTIFICATE') });
    expect(() => resolveDatabaseConnection({ url: BASE, databaseSsl: '1', caFile: bad })).toThrow(/PEM/);
    expect(() => resolveDatabaseConnection({ url: BASE, databaseSsl: '1', caFile: path.join(dir, 'missing.pem') })).toThrow(/cannot be read/);
    expect(() => resolveDatabaseConnection({ url: BASE, caFile: good })).toThrow(/needs DATABASE_SSL=1/);
  });

  it('error messages never carry the URL (it holds the password)', () => {
    for (const q of ['sslmode=disable', 'ssl=0']) {
      try {
        resolveDatabaseConnection({ url: `${BASE}?${q}`, databaseSsl: '1' });
      } catch (e) {
        expect(String(e)).not.toContain('secret');
      }
    }
  });

  it('rejects a DATABASE_SSL value other than 0/1', () => {
    expect(() => resolveDatabaseConnection({ url: BASE, databaseSsl: 'true' })).toThrow(/0 or 1/);
  });
});

describe('where the helper is enforced', () => {
  const base = { NODE_ENV: 'test', JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret' };

  it('loadEnv rejects a DATABASE_URL that contradicts DATABASE_SSL', () => {
    expect(() => loadEnv({ ...base, DATABASE_URL: `${BASE}?sslmode=disable`, DATABASE_SSL: '1' })).toThrow(/DATABASE_SSL=1/);
    expect(() => loadEnv({ ...base, DATABASE_URL: `${BASE}?sslmode=require` })).not.toThrow();
  });

  it('the retention job applies the same rules', () => {
    expect(() => loadRetentionConfig({ DATABASE_URL: `${BASE}?sslmode=disable`, DATABASE_SSL: '1' })).toThrow(/DATABASE_SSL=1/);
    const cfg = loadRetentionConfig({ DATABASE_URL: `${BASE}?sslmode=require`, DATABASE_SSL: '1' });
    expect(cfg.ssl).toEqual({ rejectUnauthorized: true });
    expect(cfg.databaseUrl).not.toContain('sslmode');
    expect(loadRetentionConfig({ DATABASE_URL: `${BASE}?sslmode=require` }).ssl).toBeUndefined();
  });

  it('pool settings bound every query and detect dead peers (C-08)', () => {
    const s = poolSettings({ max: 7, statementTimeoutMs: 20_000 });
    expect(s).toMatchObject({ max: 7, statement_timeout: 20_000, query_timeout: 25_000, keepAlive: true });
    expect(s.idle_in_transaction_session_timeout).toBeGreaterThan(0);
  });
});
