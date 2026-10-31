// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Container smoke test of the API image (audit E-08, CI job `api-production`): the IMAGE, started the way a deployment starts it.
//
//   docker build -f apps/api/Dockerfile -t wattbyte-api:ci .
//   node scripts/smoke-image.mjs <admin database url> [--image wattbyte-api:ci] [--db-host host.docker.internal]
//
// Like scripts/smoke-production.mjs it creates a throw-away role and database (the production guards refuse the docker-compose
// credentials), then proves: `node dist/database/migrate.js` runs inside the image, the container becomes healthy, GET /ready
// answers 200 with `schema: ok`, the process runs as a NON-ROOT user, and `docker stop` ends it with exit code 0.
// --db-host: how the container reaches the database host (Linux runner: the default `localhost` with --network host;
// Docker Desktop: host.docker.internal).
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createRequire } from 'node:module';
import path from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

import { isMainModule } from './is-main.mjs';
import { randomIdent, withCredentials } from './smoke-production.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** The connection URL as the CONTAINER must see it (another host name for the same server). */
export function urlForContainer(url, host) {
  const u = new URL(url);
  u.hostname = host;
  return u.toString();
}

const docker = (...args) => spawnSync('docker', args, { encoding: 'utf8' });

export async function main(argv = process.argv.slice(2)) {
  const opt = (name, fallback) => {
    const i = argv.indexOf(name);
    return i >= 0 ? argv[i + 1] : fallback;
  };
  const adminUrl = argv.find((a) => !a.startsWith('--') && argv[argv.indexOf(a) - 1]?.startsWith('--') !== true) ?? process.env.SMOKE_ADMIN_DATABASE_URL;
  const image = opt('--image', 'wattbyte-api:ci');
  const dbHost = opt('--db-host', 'localhost');
  if (!adminUrl) {
    console.error('usage: node scripts/smoke-image.mjs ADMIN_DATABASE_URL [--image NAME] [--db-host HOST]');
    return 2;
  }
  const { Client } = (() => {
    const pg = createRequire(path.join(root, 'apps', 'api', 'package.json'))('pg');
    return pg.default ?? pg;
  })();
  const role = randomIdent('wb_img');
  const database = randomIdent('wb_img_db');
  const password = randomBytes(18).toString('base64url');
  const hostUrl = withCredentials(adminUrl, { user: role, password, database });
  const containerUrl = urlForContainer(hostUrl, dbHost);
  const secret = randomBytes(32).toString('hex');
  const name = `wb-smoke-${randomBytes(3).toString('hex')}`;
  const port = String(18300 + Math.floor(Math.random() * 600));
  const network = dbHost === 'localhost' ? ['--network', 'host'] : [];
  const env = ['-e', 'NODE_ENV=production', '-e', 'DATABASE_SSL=0', '-e', 'TRUST_PROXY_HOPS=0', '-e', `DATABASE_URL=${containerUrl}`];
  const failures = [];
  const check = (what, ok, detail = '') => {
    console.log(`  ${ok ? 'ok  ' : 'FAIL'}  ${what}${ok || !detail ? '' : `: ${detail}`}`);
    if (!ok) failures.push(what);
    return ok;
  };

  const admin = new Client({ connectionString: adminUrl });
  admin.on('error', () => {});
  try {
    await admin.connect();
    await admin.query(`CREATE ROLE ${role} LOGIN PASSWORD '${password}'`);
    await admin.query(`CREATE DATABASE ${database} OWNER ${role}`);

    const mig = docker('run', '--rm', ...network, ...env, image, 'node', 'dist/database/migrate.js');
    if (!check('migrate.js runs inside the image', mig.status === 0, (mig.stderr || mig.stdout).slice(0, 300))) throw new Error('migrate failed');

    const run = docker('run', '-d', '--name', name, ...network, ...(network.length ? ['-e', `PORT=${port}`] : ['-p', `127.0.0.1:${port}:8080`]), ...env, '-e', `JWT_SECRET=${secret}`, image);
    if (!check('the container starts', run.status === 0, run.stderr.slice(0, 300))) throw new Error('start failed');

    let status = '';
    for (let i = 0; i < 40 && status !== 'healthy'; i += 1) {
      status = docker('inspect', '-f', '{{.State.Health.Status}}', name).stdout.trim();
      if (status !== 'healthy') await sleep(2000);
    }
    check('the HEALTHCHECK turns healthy', status === 'healthy', status);

    const ready = await fetch(`http://127.0.0.1:${port}/ready`).then((r) => r.json().then((j) => ({ status: r.status, j }))).catch((e) => ({ status: 0, j: String(e) }));
    check('/ready is 200 with schema ok', ready.status === 200 && ready.j?.schema === 'ok', JSON.stringify(ready));

    const uid = docker('exec', name, 'id', '-u').stdout.trim();
    const user = docker('exec', name, 'id', '-un').stdout.trim();
    check('the process runs as a non-root user', uid !== '' && uid !== '0', `uid ${uid}`);
    console.log(`        (user ${user}, uid ${uid})`);

    const stop = docker('stop', '-t', '40', name);
    const exit = docker('inspect', '-f', '{{.State.ExitCode}}', name).stdout.trim();
    check('docker stop ends it with exit code 0', stop.status === 0 && exit === '0', `exit ${exit}`);
  } catch (e) {
    check('smoke run', false, e instanceof Error ? e.message : String(e));
  } finally {
    docker('rm', '-f', name);
    try {
      await admin.query(`DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
      await admin.query(`DROP ROLE IF EXISTS ${role}`);
    } catch (e) {
      console.error(`cleanup failed (drop ${database} and ${role} by hand): ${e instanceof Error ? e.message : e}`);
    }
    await admin.end().catch(() => {});
  }
  console.log(failures.length ? `smoke-image: ${failures.length} step(s) FAILED` : 'smoke-image: all steps passed');
  return failures.length ? 1 : 0;
}

if (isMainModule(import.meta.url)) process.exit(await main());
