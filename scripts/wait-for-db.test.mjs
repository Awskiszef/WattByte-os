// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/wait-for-db.test.mjs
// Pure-logic tests: no database is contacted (the fake driver below stands in for `pg`).
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { backoffMs, maskUrl, parseArgs, resolveConnection, waitForDb } from './wait-for-db.mjs';

describe('maskUrl', () => {
  it('hides the password and keeps the rest', () => {
    const pw = ['hunter', '2'].join('');
    const masked = maskUrl(`postgres://app:${pw}@db.internal:5432/main?sslmode=disable`);
    assert.equal(masked, 'postgres://app:***@db.internal:5432/main?sslmode=disable');
    assert.ok(!masked.includes(pw));
  });

  it('never echoes an unparseable URL', () => {
    assert.equal(maskUrl('not a url with a:secret'), '<unparseable database URL>');
  });
});

describe('backoffMs', () => {
  it('doubles from 250 ms and stops at 2 s', () => {
    assert.deepEqual([1, 2, 3, 4, 5, 9].map((n) => backoffMs(n)), [250, 500, 1000, 2000, 2000, 2000]);
  });
});

describe('resolveConnection (mirrors apps/api/src/database/connection.ts)', () => {
  it('DATABASE_SSL=1 means verified TLS and strips the URL TLS parameters', () => {
    const r = resolveConnection('postgres://u:p@h:5432/d?sslmode=require&application_name=x', { DATABASE_SSL: '1' });
    assert.deepEqual(r.ssl, { rejectUnauthorized: true });
    assert.ok(!r.connectionString.includes('sslmode'));
    assert.ok(r.connectionString.includes('application_name=x'));
  });
  it('refuses a URL that weakens an explicit DATABASE_SSL=1', () => {
    for (const q of ['sslmode=disable', 'sslmode=no-verify', 'sslmode=prefer', 'ssl=0']) {
      assert.throws(() => resolveConnection(`postgres://h/d?${q}`, { DATABASE_SSL: '1' }), /weaker TLS/);
    }
  });
  it('refuses DATABASE_SSL=0 together with a URL that asks for TLS', () => {
    assert.throws(() => resolveConnection('postgres://h/d?sslmode=verify-full', { DATABASE_SSL: '0' }), /decide one/);
  });
  it('leaves the URL in charge when DATABASE_SSL is not set', () => {
    const r = resolveConnection('postgres://h/d?sslmode=require', {});
    assert.equal(r.connectionString, 'postgres://h/d?sslmode=require');
    assert.equal(r.ssl, undefined);
  });
  it('rejects a CA file without DATABASE_SSL=1 and an unreadable one', () => {
    assert.throws(() => resolveConnection('postgres://h/d', { DATABASE_SSL_CA_FILE: '/x.pem' }), /needs DATABASE_SSL=1/);
    assert.throws(() => resolveConnection('postgres://h/d', { DATABASE_SSL: '1', DATABASE_SSL_CA_FILE: '/nonexistent.pem' }), /cannot be read/);
  });
});

describe('parseArgs', () => {
  it('takes the URL from the argument, then DATABASE_URL, then TEST_DATABASE_URL', () => {
    assert.equal(parseArgs(['postgres://a/b'], {}).url, 'postgres://a/b');
    assert.equal(parseArgs([], { DATABASE_URL: 'postgres://d/x', TEST_DATABASE_URL: 'postgres://t/x' }).url, 'postgres://d/x');
    assert.equal(parseArgs([], { TEST_DATABASE_URL: 'postgres://t/x' }).url, 'postgres://t/x');
  });

  it('reads --timeout and --quiet', () => {
    const o = parseArgs(['postgres://a/b', '--timeout', '15', '--quiet'], {});
    assert.equal(o.timeoutSec, 15);
    assert.equal(o.quiet, true);
  });

  it('rejects a missing URL, a bad timeout and unknown options', () => {
    assert.throws(() => parseArgs([], {}), /no database URL/);
    assert.throws(() => parseArgs(['postgres://a/b', '--timeout', 'soon'], {}), /positive number/);
    assert.throws(() => parseArgs(['postgres://a/b', '--timeout', '0'], {}), /positive number/);
    assert.throws(() => parseArgs(['postgres://a/b', '--nope'], {}), /unknown option/);
    assert.throws(() => parseArgs(['postgres://a/b', 'extra'], {}), /unexpected argument/);
  });
});

/** A `pg` stand-in whose connections fail `failures` times and then answer SELECT 1. */
function fakePg(failures) {
  const calls = { connect: 0, end: 0, queries: [] };
  class Client {
    on() {}
    async connect() {
      calls.connect += 1;
      if (calls.connect <= failures) throw new Error('connect ECONNREFUSED');
    }
    async query(sql) {
      calls.queries.push(sql);
      return { rows: [{ ok: 1 }] };
    }
    async end() {
      calls.end += 1;
    }
  }
  return { pg: { Client }, calls };
}

describe('waitForDb', () => {
  it('returns after the first successful SELECT 1 and closes every client', async () => {
    const { pg, calls } = fakePg(0);
    const res = await waitForDb('postgres://x/y', { pg, timeoutMs: 5000 });
    assert.equal(res.attempts, 1);
    assert.deepEqual(calls.queries, ['SELECT 1 AS ok']);
    assert.equal(calls.end, 1);
  });

  it('retries with backoff until the database answers', async () => {
    const { pg, calls } = fakePg(2);
    const logs = [];
    const res = await waitForDb('postgres://x/y', { pg, timeoutMs: 10_000, log: (m) => logs.push(m) });
    assert.equal(res.attempts, 3);
    assert.equal(calls.end, 3, 'a failed attempt still releases its client');
    assert.equal(logs.length, 2);
    assert.match(logs[0], /retrying in 250 ms/);
    assert.match(logs[1], /retrying in 500 ms/);
  });

  it('gives up with the last error once the timeout is spent', async () => {
    const { pg } = fakePg(Infinity);
    await assert.rejects(waitForDb('postgres://x/y', { pg, timeoutMs: 600 }), /database not ready after \d+ attempts.*ECONNREFUSED/);
  });
});
