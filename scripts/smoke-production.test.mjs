// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/smoke-production.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { maskUrl, productionEnv, randomIdent, withCredentials } from './smoke-production.mjs';

describe('smoke-production helpers', () => {
  it('makes unquoted-safe random identifiers', () => {
    const a = randomIdent('wb_smoke');
    assert.match(a, /^wb_smoke_[0-9a-f]{12}$/);
    assert.notEqual(a, randomIdent('wb_smoke'));
  });

  it('points the same server at another role and database, and masks the password', () => {
    const url = withCredentials(['postgres://admin', 'adminpw'].join(':') + '@db.internal:5433/postgres?sslmode=disable', { user: 'u1', password: 'p w/1', database: 'd1' });
    const u = new URL(url);
    assert.equal(u.host, 'db.internal:5433');
    assert.equal(u.username, 'u1');
    assert.equal(decodeURIComponent(u.password), 'p w/1');
    assert.equal(u.pathname, '/d1');
    assert.ok(!maskUrl(url).includes('p%20w'));
    assert.equal(maskUrl('not a url'), '<unparseable database URL>');
  });

  it('gives the server a production environment and inherits nothing but PATH', () => {
    process.env.JWT_SECRET = 'leak-me';
    try {
      const env = productionEnv({ PORT: '1' });
      assert.equal(env.NODE_ENV, 'production');
      assert.equal(env.DATABASE_SSL, '0');
      assert.equal(env.JWT_SECRET, undefined);
      assert.deepEqual(Object.keys(env).sort(), ['DATABASE_SSL', 'HOST', 'NODE_ENV', 'PATH', 'PORT', 'TRUST_PROXY_HOPS']);
    } finally {
      delete process.env.JWT_SECRET;
    }
  });

  it('exits 2 with a usage message when no database URL is given', () => {
    const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'smoke-production.mjs');
    const r = spawnSync(process.execPath, [script], { encoding: 'utf8', env: { PATH: process.env.PATH } });
    assert.equal(r.status, 2);
    assert.match(r.stderr, /usage:/);
  });
});
