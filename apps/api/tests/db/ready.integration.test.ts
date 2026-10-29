import net from 'node:net';

import { afterAll, describe, expect, it } from 'vitest';

import { PostgresRepositories } from '../../src/database/postgres.js';
import { buildTestApp } from '../support.js';
import { DATABASE_URL } from './helpers.js';

/** The URL of the real test database, pointed at a port where nothing listens. */
function deadUrl(): string {
  const url = new URL(DATABASE_URL ?? 'postgres://wattbyte:wattbyte@localhost:5432/wattbyte');
  url.hostname = '127.0.0.1';
  url.port = '1';
  return url.toString();
}

describe.skipIf(!DATABASE_URL)('GET /ready against PostgreSQL', () => {
  const cleanups: (() => Promise<void>)[] = [];
  afterAll(async () => {
    for (const cleanup of cleanups.reverse()) await cleanup();
  });

  async function appWith(repos: PostgresRepositories, env: Record<string, string> = {}) {
    cleanups.push(() => repos.close());
    const ctx = await buildTestApp({ repos, env });
    cleanups.push(() => ctx.app.close());
    return ctx.app;
  }

  it('200 against the real database: SELECT 1 ran', async () => {
    const app = await appWith(new PostgresRepositories(DATABASE_URL!));
    const res = await app.inject({ url: '/ready' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok', database: 'ok' });
  });

  it('the schema gate against the real migration table: current = ready, a migration this database lacks = 503', async () => {
    const { migrate, latestMigrationName } = await import('../../src/database/migrate.js');
    await migrate(DATABASE_URL!);
    const latest = (await latestMigrationName())!;
    const current = await buildTestApp({ repos: new PostgresRepositories(DATABASE_URL!), expectedSchemaVersion: latest });
    cleanups.push(() => current.app.close(), () => current.repos.close());
    expect((await current.app.inject({ url: '/ready' })).json()).toMatchObject({ status: 'ok', schema: 'ok' });

    const behind = await buildTestApp({ repos: new PostgresRepositories(DATABASE_URL!), expectedSchemaVersion: '9999_not_applied_yet.sql' });
    cleanups.push(() => behind.app.close(), () => behind.repos.close());
    const res = await behind.app.inject({ url: '/ready' });
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ status: 'degraded', database: 'ok', schema: 'behind' });
    expect((await behind.app.inject({ url: '/health' })).statusCode).toBe(200);
  });

  it('503 with a pool pointing at a dead port, while /health stays 200', async () => {
    const app = await appWith(new PostgresRepositories(deadUrl()));
    const ready = await app.inject({ url: '/ready' });
    expect(ready.statusCode).toBe(503);
    expect(ready.json()).toMatchObject({ status: 'degraded', database: 'unavailable' });
    expect(ready.body).not.toMatch(/ECONNREFUSED|127\.0\.0\.1|wattbyte:/);
    expect((await app.inject({ url: '/health' })).statusCode).toBe(200);
  });

  it('503 when the server accepts the connection but never answers (black hole), within the timeout', async () => {
    const sockets = new Set<net.Socket>();
    const server = net.createServer((socket) => {
      sockets.add(socket);
      socket.on('error', () => undefined);
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const { port } = server.address() as net.AddressInfo;
    const url = new URL(DATABASE_URL!);
    url.hostname = '127.0.0.1';
    url.port = String(port);
    const repos = new PostgresRepositories(url.toString());
    const app = await appWith(repos, { READY_DB_TIMEOUT_MS: '300' });
    // Registered last, so it runs first: the pool can only end once its half-open connections are gone.
    cleanups.push(async () => {
      for (const s of sockets) s.destroy();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    });
    const started = Date.now();
    const res = await app.inject({ url: '/ready' });
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ status: 'degraded', database: 'unavailable' });
    expect(Date.now() - started).toBeLessThan(3_000);
    // and the process is alive
    expect((await app.inject({ url: '/health' })).statusCode).toBe(200);
  }, 20_000);

  it('follows the database through an outage and back, on one app and one pool', async () => {
    // A TCP forwarder to the real database that can be switched off (connections reset, live ones cut) and on.
    const live = new Set<net.Socket>();
    let enabled = true;
    const target = new URL(DATABASE_URL!);
    const proxy = net.createServer((client) => {
      if (!enabled) {
        client.destroy();
        return;
      }
      const upstream = net.connect(Number(target.port || 5432), target.hostname);
      live.add(client).add(upstream);
      client.pipe(upstream).pipe(client);
      for (const s of [client, upstream]) {
        s.on('error', () => undefined);
        s.on('close', () => {
          live.delete(client);
          live.delete(upstream);
          client.destroy();
          upstream.destroy();
        });
      }
    });
    await new Promise<void>((resolve) => proxy.listen(0, '127.0.0.1', resolve));
    const url = new URL(DATABASE_URL!);
    url.hostname = '127.0.0.1';
    url.port = String((proxy.address() as net.AddressInfo).port);
    const app = await appWith(new PostgresRepositories(url.toString()), { READY_DB_TIMEOUT_MS: '1000' });
    cleanups.push(async () => {
      for (const s of live) s.destroy();
      await new Promise<void>((resolve) => proxy.close(() => resolve()));
    });
    const ready = async (): Promise<number> => (await app.inject({ url: '/ready' })).statusCode;

    expect(await ready()).toBe(200);
    enabled = false;
    for (const s of live) s.destroy(); // the server went away under a pooled, idle connection
    expect(await ready()).toBe(503);
    expect((await app.inject({ url: '/health' })).statusCode).toBe(200);
    enabled = true;
    expect(await ready()).toBe(200);
    enabled = false;
    for (const s of live) s.destroy();
    expect(await ready()).toBe(503);
    enabled = true;
    expect(await ready()).toBe(200);
  }, 30_000);
});
