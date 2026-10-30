// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Production smoke test (audit E-08): the COMPILED API, started the way a deployment starts it.
//
//   pnpm build && node scripts/smoke-production.mjs [ADMIN_DATABASE_URL]
//
// ADMIN_DATABASE_URL (or $SMOKE_ADMIN_DATABASE_URL / $DATABASE_URL) is a PostgreSQL superuser or CREATEDB+CREATEROLE role. The
// script creates a throw-away role and database with random names (the production guards refuse the docker-compose
// credentials, so the smoke test cannot reuse them), and drops both at the end. Nothing else in that server is touched.
//
// What it proves, in order, each step failing the run:
//   1. the production guards bite: no JWT_SECRET, a placeholder secret, mock AI and the compose credentials are all refused
//   2. `node apps/api/dist/database/migrate.js` (no tsx, no devDependencies) applies every migration; --status then reports none pending
//   3. `node apps/api/dist/main.js` boots with NODE_ENV=production; /health 200; /ready 200 with schema "ok"
//   4. register -> login -> refresh (rotation) -> an authenticated call work against that PostgreSQL
//   5. `node apps/api/dist/scripts/retention.js --dry-run` and the real run print their JSON line
//   6. SIGTERM stops the server cleanly (exit code 0)
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.join(root, 'apps', 'api', 'dist');

/** Random lowercase identifier safe to use unquoted as a role/database name. */
export function randomIdent(prefix) {
  return `${prefix}_${randomBytes(6).toString('hex')}`;
}

/** The same server, another database and role. */
export function withCredentials(adminUrl, { user, password, database }) {
  const u = new URL(adminUrl);
  u.username = user;
  u.password = password;
  u.pathname = `/${database}`;
  return u.toString();
}

export function maskUrl(raw) {
  try {
    const u = new URL(raw);
    if (u.password) u.password = '***';
    return u.toString();
  } catch {
    return '<unparseable database URL>';
  }
}

/** Environment of a production-like process: nothing inherited except PATH, so a stray local .env value cannot help it pass. */
export function productionEnv(extra) {
  return {
    PATH: process.env.PATH ?? '',
    NODE_ENV: 'production',
    HOST: '127.0.0.1',
    DATABASE_SSL: '0', // production requires an explicit choice; the loopback connection is the "private link" case
    TRUST_PROXY_HOPS: '0',
    ...extra,
  };
}

function runNode(args, env, timeoutMs = 120_000) {
  return spawnSync(process.execPath, args, { cwd: root, env, encoding: 'utf8', timeout: timeoutMs });
}

class Step {
  constructor() {
    this.failures = [];
  }
  ok(name, detail = '') {
    console.log(`  ok    ${name}${detail ? ` (${detail})` : ''}`);
  }
  fail(name, detail) {
    this.failures.push(name);
    console.error(`  FAIL  ${name}: ${detail}`);
  }
  check(name, cond, detail) {
    if (cond) this.ok(name);
    else this.fail(name, detail);
    return cond;
  }
}

async function http(base, method, pathname, { body, token } = {}) {
  const res = await fetch(`${base}${pathname}`, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json;
  try {
    json = await res.json();
  } catch {
    json = undefined;
  }
  return { status: res.status, json };
}

export async function main(argv = process.argv.slice(2), env = process.env) {
  const adminUrl = argv[0] ?? env.SMOKE_ADMIN_DATABASE_URL ?? env.DATABASE_URL;
  if (!adminUrl) {
    console.error('usage: node scripts/smoke-production.mjs ADMIN_DATABASE_URL   (or set SMOKE_ADMIN_DATABASE_URL)');
    return 2;
  }
  for (const f of ['main.js', path.join('database', 'migrate.js'), path.join('scripts', 'retention.js')]) {
    if (!existsSync(path.join(dist, f))) {
      console.error(`missing apps/api/dist/${f}: run "pnpm build" first`);
      return 2;
    }
  }
  let Client;
  try {
    const pg = createRequire(path.join(root, 'apps', 'api', 'package.json'))('pg');
    Client = (pg.default ?? pg).Client;
  } catch (e) {
    console.error(`cannot load "pg" from apps/api (run "pnpm install"): ${e instanceof Error ? e.message : e}`);
    return 2;
  }

  const role = randomIdent('wb_smoke');
  const database = randomIdent('wb_smoke_db');
  const password = randomBytes(18).toString('base64url');
  const url = withCredentials(adminUrl, { user: role, password, database });
  const jwtSecret = randomBytes(32).toString('hex');
  const port = String(18100 + Math.floor(Math.random() * 800));
  const base = `http://127.0.0.1:${port}`;
  const steps = new Step();
  const admin = new Client({ connectionString: adminUrl });
  admin.on('error', () => {});
  let api;

  try {
    await admin.connect();
    await admin.query(`CREATE ROLE ${role} LOGIN PASSWORD '${password}'`);
    await admin.query(`CREATE DATABASE ${database} OWNER ${role}`);
    console.log(`smoke database ${database} on ${maskUrl(url)}`);

    // 1. guards
    console.log('production guards');
    const refuse = (name, extra, expect) => {
      const r = runNode([path.join(dist, 'main.js')], productionEnv({ PORT: port, ...extra }), 30_000);
      steps.check(name, r.status !== 0 && (r.stderr + r.stdout).includes(expect), `exit ${r.status}, output did not mention ${expect}: ${(r.stderr + r.stdout).slice(0, 300)}`);
    };
    refuse('no JWT_SECRET is refused', { DATABASE_URL: url }, 'JWT_SECRET');
    refuse('a placeholder JWT_SECRET is refused', { DATABASE_URL: url, JWT_SECRET: 'change-me-change-me-change-me-change-me' }, 'JWT_SECRET');
    refuse('mock AI is refused', { DATABASE_URL: url, JWT_SECRET: jwtSecret, AI_MOCK: '1' }, 'AI_MOCK');
    refuse('the docker-compose credentials are refused', { DATABASE_URL: 'postgres://wattbyte:wattbyte@localhost:5432/wattbyte', JWT_SECRET: jwtSecret }, 'DATABASE_URL');
    refuse('an unset DATABASE_SSL is refused', { DATABASE_URL: url, JWT_SECRET: jwtSecret, DATABASE_SSL: '' }, 'DATABASE_SSL');

    // 2. compiled migrate
    console.log('migrations (compiled)');
    const migrateEnv = productionEnv({ DATABASE_URL: url });
    const mig = runNode([path.join(dist, 'database', 'migrate.js')], migrateEnv);
    if (!steps.check('migrate.js applies the migrations', mig.status === 0, `exit ${mig.status}: ${(mig.stderr || mig.stdout).slice(0, 400)}`)) throw new Error('migrate failed');
    const status = runNode([path.join(dist, 'database', 'migrate.js'), '--status'], migrateEnv);
    let parsed;
    try {
      parsed = JSON.parse(status.stderr || status.stdout); // the CLI reports on stderr, like every message of the migrator
    } catch {
      parsed = undefined;
    }
    steps.check('--status reports nothing pending', status.status === 0 && parsed !== undefined && (parsed.pending?.length ?? 1) === 0, `exit ${status.status}: ${(status.stderr || status.stdout).slice(0, 300)}`);

    // 3. boot
    console.log('server (compiled)');
    const logs = [];
    api = spawn(process.execPath, [path.join(dist, 'main.js')], {
      cwd: root,
      env: productionEnv({ PORT: port, DATABASE_URL: url, JWT_SECRET: jwtSecret }),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const exited = new Promise((resolve) => api.on('exit', (code, signal) => resolve({ code, signal })));
    for (const stream of [api.stdout, api.stderr]) stream.on('data', (d) => logs.push(String(d)));
    let ready = false;
    for (let i = 0; i < 60 && !ready; i += 1) {
      try {
        ready = (await fetch(`${base}/ready`)).status === 200;
      } catch {
        /* not listening yet */
      }
      if (!ready) await sleep(500);
    }
    if (!steps.check('the server answers /ready', ready, `never ready; log:\n${logs.join('').slice(-1500)}`)) throw new Error('server did not start');
    const health = await http(base, 'GET', '/health');
    steps.check('/health is 200', health.status === 200, `status ${health.status}`);
    const rdy = await http(base, 'GET', '/ready');
    steps.check('/ready reports schema ok', rdy.status === 200 && rdy.json?.schema === 'ok', `${rdy.status} ${JSON.stringify(rdy.json)}`);

    // 4. account flow
    console.log('account flow');
    const email = `smoke-${randomBytes(4).toString('hex')}@example.test`;
    const accountPassword = randomBytes(12).toString('base64url');
    const reg = await http(base, 'POST', '/api/v1/auth/register', { body: { email, password: accountPassword } });
    steps.check('register', reg.status === 201 && !!reg.json?.tokens?.refreshToken, `${reg.status} ${JSON.stringify(reg.json)?.slice(0, 200)}`);
    const login = await http(base, 'POST', '/api/v1/auth/login', { body: { email, password: accountPassword } });
    steps.check('login', login.status === 200 && !!login.json?.tokens?.refreshToken, `${login.status}`);
    const refreshed = await http(base, 'POST', '/api/v1/auth/refresh', { body: { refreshToken: login.json?.tokens?.refreshToken } });
    steps.check('refresh rotates the token', refreshed.status === 200 && refreshed.json?.tokens?.refreshToken !== login.json?.tokens?.refreshToken, `${refreshed.status}`);
    // Inside REFRESH_REUSE_GRACE_SEC a repeat is a retry after a lost response: it gets the SAME successor, nothing else changes.
    const retry = await http(base, 'POST', '/api/v1/auth/refresh', { body: { refreshToken: login.json?.tokens?.refreshToken } });
    steps.check('a repeated refresh inside the grace window gets the same successor', retry.status === 200 && retry.json?.tokens?.refreshToken === refreshed.json?.tokens?.refreshToken, `${retry.status}`);
    const forged = await http(base, 'POST', '/api/v1/auth/refresh', { body: { refreshToken: `${randomBytes(32).toString('base64url')}` } });
    steps.check('an unknown refresh token is refused', forged.status === 401, `${forged.status}`);
    const me = await http(base, 'GET', '/api/v1/me', { token: refreshed.json?.tokens?.accessToken });
    steps.check('an authenticated call works', me.status === 200, `${me.status}`);

    // 5. retention
    console.log('retention (compiled)');
    for (const flag of [['--dry-run'], []]) {
      const r = runNode([path.join(dist, 'scripts', 'retention.js'), ...flag], productionEnv({ DATABASE_URL: url }));
      const line = r.stdout.trim().split('\n').at(-1) ?? '';
      let json;
      try {
        json = JSON.parse(line);
      } catch {
        json = undefined;
      }
      steps.check(`retention ${flag[0] ?? '(purge)'} prints its JSON line`, r.status === 0 && json?.rows !== undefined, `exit ${r.status}: ${(r.stderr || r.stdout).slice(0, 300)}`);
    }

    // 6. shutdown
    console.log('shutdown');
    api.kill('SIGTERM');
    const result = await Promise.race([exited, sleep(15_000).then(() => 'timeout')]);
    steps.check('SIGTERM stops the server with exit code 0', result !== 'timeout' && result.code === 0, `result ${JSON.stringify(result)}`);
    api = undefined;
  } catch (e) {
    steps.fail('smoke run', e instanceof Error ? e.message : String(e));
  } finally {
    if (api && api.exitCode === null) api.kill('SIGKILL');
    try {
      await admin.query(`DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
      await admin.query(`DROP ROLE IF EXISTS ${role}`);
    } catch (e) {
      console.error(`cleanup failed (drop ${database} and ${role} by hand): ${e instanceof Error ? e.message : e}`);
    }
    await admin.end().catch(() => {});
  }
  console.log(steps.failures.length ? `smoke-production: ${steps.failures.length} step(s) FAILED` : 'smoke-production: all steps passed');
  return steps.failures.length ? 1 : 0;
}

if (isMainModule(import.meta.url)) process.exit(await main());
