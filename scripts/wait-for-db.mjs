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
import { createRequire } from 'node:module';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
export async function waitForDb(url, { timeoutMs = 60_000, log = () => {}, pg = loadPg() } = {}) {
  const { Client } = pg.default ?? pg;
  const started = Date.now();
  let attempt = 0;
  let lastError;
  for (;;) {
    attempt += 1;
    const client = new Client({ connectionString: url, connectionTimeoutMillis: 3000, query_timeout: 3000 });
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

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  await main();
}
