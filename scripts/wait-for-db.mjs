// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Waits until a PostgreSQL database answers a real query (`SELECT 1`), for CI and
// dev scripts that must not race a database that is still starting.
//
//   node scripts/wait-for-db.mjs [DATABASE_URL] [--timeout 60] [--quiet]
//
// The URL comes from the first argument, else $DATABASE_URL, else $TEST_DATABASE_URL.
// Exit code: 0 ready, 1 timed out, 2 usage error. The password never reaches the output.
//
// `pg` is resolved from apps/api (this script has no dependencies of its own), so
// run `pnpm install` first. Only a read-only `SELECT 1` is ever sent.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** `postgres://user:***@host:port/db`: safe to print. */
export function maskUrl(raw) {
  try {
    const u = new URL(raw);
    if (u.password) u.password = '***';
    return u.toString();
  } catch {
    return '<unparseable database URL>';
  }
}

/** Backoff schedule: 250 ms, 500 ms, 1 s, then 2 s (capped). */
export function backoffMs(attempt, { initialMs = 250, maxMs = 2000 } = {}) {
  return Math.min(maxMs, initialMs * 2 ** Math.max(0, attempt - 1));
}

export function parseArgs(argv, env = process.env) {
  const opts = { url: undefined, timeoutSec: 60, quiet: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--quiet') opts.quiet = true;
    else if (a === '--timeout') {
      const v = Number(argv[(i += 1)]);
      if (!Number.isFinite(v) || v <= 0) throw new Error('--timeout needs a positive number of seconds');
      opts.timeoutSec = v;
    } else if (a.startsWith('--')) throw new Error(`unknown option ${a}`);
    else if (opts.url === undefined) opts.url = a;
    else throw new Error(`unexpected argument ${a}`);
  }
  opts.url ??= env.DATABASE_URL || env.TEST_DATABASE_URL;
  if (!opts.url) throw new Error('no database URL: pass it as an argument or set DATABASE_URL / TEST_DATABASE_URL');
  return opts;
}

const SSL_URL_PARAMS = ['sslmode', 'ssl', 'sslcert', 'sslkey', 'sslrootcert', 'sslcrl', 'uselibpqcompat'];
const WEAK_SSLMODES = new Set(['disable', 'allow', 'prefer', 'no-verify']);
const STRONG_SSLMODES = new Set(['require', 'verify-ca', 'verify-full']);

/**
 * Mirror of apps/api/src/database/connection.ts (this script has no build step): DATABASE_SSL=1 means verified TLS and
 * the URL's own TLS parameters must not weaken it; DATABASE_SSL=0 must not meet a URL that asks for TLS; unset = the URL decides.
 * Returns `{ connectionString, ssl }`; throws on contradictions.
 */
export function resolveConnection(url, env = process.env) {
  const choice = env.DATABASE_SSL === undefined || env.DATABASE_SSL === '' ? undefined : env.DATABASE_SSL;
  if (choice !== undefined && choice !== '0' && choice !== '1') throw new Error('DATABASE_SSL must be 0 or 1');
  const caFile = env.DATABASE_SSL_CA_FILE;
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return { connectionString: url, ssl: choice === '1' ? tlsOptions(caFile) : undefined };
  }
  const sslmode = parsed.searchParams.get('sslmode')?.toLowerCase();
  const flag = parsed.searchParams.get('ssl')?.toLowerCase();
  const weakens = (sslmode !== undefined && WEAK_SSLMODES.has(sslmode)) || flag === '0' || flag === 'false';
  const wantsTls = (sslmode !== undefined && STRONG_SSLMODES.has(sslmode)) || flag === '1' || flag === 'true';
  if (choice === '1') {
    if (weakens) throw new Error('DATABASE_URL asks for weaker TLS than DATABASE_SSL=1: remove the parameter from the URL');
    for (const p of SSL_URL_PARAMS) parsed.searchParams.delete(p);
    return { connectionString: parsed.toString(), ssl: tlsOptions(caFile) };
  }
  if (choice === '0' && wantsTls) throw new Error('DATABASE_URL asks for TLS but DATABASE_SSL=0: decide one');
  if (caFile) throw new Error('DATABASE_SSL_CA_FILE needs DATABASE_SSL=1');
  return { connectionString: url, ssl: undefined };
}

function tlsOptions(caFile) {
  if (!caFile) return { rejectUnauthorized: true };
  let ca;
  try {
    ca = readFileSync(caFile, 'utf8');
  } catch {
    throw new Error('DATABASE_SSL_CA_FILE cannot be read');
  }
  if (!ca.includes('BEGIN CERTIFICATE')) throw new Error('DATABASE_SSL_CA_FILE does not contain a PEM certificate');
  return { rejectUnauthorized: true, ca };
}

function loadPg() {
  try {
    return createRequire(path.join(root, 'apps', 'api', 'package.json'))('pg');
  } catch (e) {
    throw new Error(`cannot load "pg" from apps/api (run "pnpm install"): ${e instanceof Error ? e.message : e}`);
  }
}

/**
 * Resolves with `{ attempts, elapsedMs }` once `SELECT 1` succeeds; rejects with the
 * last error when `timeoutMs` is exceeded.
 */
export async function waitForDb(url, { timeoutMs = 60_000, log = () => {}, pg = loadPg(), env = process.env } = {}) {
  const { Client } = pg.default ?? pg;
  const conn = resolveConnection(url, env);
  const started = Date.now();
  let attempt = 0;
  let lastError;
  for (;;) {
    attempt += 1;
    const client = new Client({ connectionString: conn.connectionString, ssl: conn.ssl, connectionTimeoutMillis: 3000, query_timeout: 3000 });
    // An idle-client error after a failed attempt must not crash the process.
    client.on('error', () => {});
    try {
      await client.connect();
      const res = await client.query('SELECT 1 AS ok');
      if (res.rows[0]?.ok === 1) return { attempts: attempt, elapsedMs: Date.now() - started };
      lastError = new Error('SELECT 1 returned an unexpected result');
    } catch (e) {
      lastError = e;
    } finally {
      await client.end().catch(() => {});
    }
    const wait = backoffMs(attempt);
    if (Date.now() - started + wait >= timeoutMs) {
      const reason = lastError instanceof Error ? lastError.message : String(lastError);
      throw new Error(`database not ready after ${attempt} attempts / ${Math.round((Date.now() - started) / 1000)} s: ${reason}`);
    }
    log(`attempt ${attempt} failed (${lastError instanceof Error ? lastError.message : lastError}); retrying in ${wait} ms`);
    await sleep(wait);
  }
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(`wait-for-db: ${e.message}`);
    console.error('usage: node scripts/wait-for-db.mjs [DATABASE_URL] [--timeout SECONDS] [--quiet]');
    process.exit(2);
  }
  const say = opts.quiet ? () => {} : (m) => console.warn(`wait-for-db: ${m}`);
  say(`waiting for ${maskUrl(opts.url)} (timeout ${opts.timeoutSec} s)`);
  try {
    const { attempts, elapsedMs } = await waitForDb(opts.url, {
      timeoutMs: opts.timeoutSec * 1000,
      log: say,
    });
    say(`ready after ${attempts} attempt(s), ${elapsedMs} ms`);
  } catch (e) {
    console.error(`wait-for-db: ${e.message}`);
    process.exit(1);
  }
}

if (isMainModule(import.meta.url)) {
  await main();
}
