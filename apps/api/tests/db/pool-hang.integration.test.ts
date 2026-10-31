// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import net from 'node:net';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { PostgresRepositories } from '../../src/database/postgres.js';
import { DATABASE_URL, uniqueEmail } from './helpers.js';

/**
 * C-08 against a real server: the path to PostgreSQL goes silent after the connection is up (a dropped NAT entry, a
 * frozen proxy): no reset, no data. Before, a query waited for the OS TCP timeout (minutes) with its pool slot; now
 * the client gives up after statement_timeout + 5 s, discards the connection and the next call gets a fresh one.
 */
describe.skipIf(!DATABASE_URL)('hung database path (PostgreSQL)', () => {
  const sockets = new Set<net.Socket>();
  let muted = false;
  let proxy: net.Server;
  let repos: PostgresRepositories;
  const errors: Error[] = [];

  beforeAll(async () => {
    // The queries below read `users`. Prepare the shared database here instead of relying on another test file having done it first:
    // on a fresh database (every CI run) this file fails with `relation "users" does not exist` when it gets there before them.
    await migrate(DATABASE_URL!);
    const target = new URL(DATABASE_URL!);
    proxy = net.createServer((client) => {
      const upstream = net.connect(Number(target.port || 5432), target.hostname);
      sockets.add(client).add(upstream);
      for (const s of [client, upstream]) s.on('error', () => undefined);
      client.on('data', (d) => { if (!muted) upstream.write(d); });
      upstream.on('data', (d) => { if (!muted) client.write(d); });
      client.on('close', () => upstream.destroy());
      upstream.on('close', () => client.destroy());
    });
    await new Promise<void>((resolve) => proxy.listen(0, '127.0.0.1', resolve));
    const { port } = proxy.address() as net.AddressInfo;
    const url = new URL(DATABASE_URL!);
    url.hostname = '127.0.0.1';
    url.port = String(port);
    repos = new PostgresRepositories(url.toString(), { max: 2, statementTimeoutMs: 1_000, onError: (e) => errors.push(e) });
  });
  afterAll(async () => {
    muted = false;
    for (const s of sockets) s.destroy();
    await repos.close().catch(() => undefined);
    await new Promise<void>((resolve) => proxy.close(() => resolve()));
  });

  it('a silent path fails the call within statement_timeout + 5 s and the pool recovers afterwards', async () => {
    expect(await repos.users.findByEmail(uniqueEmail('hang'))).toBeNull();

    muted = true;
    const started = Date.now();
    await expect(repos.users.findByEmail(uniqueEmail('hang'))).rejects.toThrow();
    const took = Date.now() - started;
    expect(took).toBeGreaterThanOrEqual(5_000);
    expect(took).toBeLessThan(9_000);

    muted = false;
    for (const s of sockets) s.destroy();
    sockets.clear();
    expect(await repos.users.findByEmail(uniqueEmail('hang'))).toBeNull();
  }, 30_000);
});
