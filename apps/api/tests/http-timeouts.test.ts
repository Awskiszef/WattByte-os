import net from 'node:net';
import type { AddressInfo } from 'node:net';

import { afterEach, describe, expect, it, vi } from 'vitest';

import { createShutdown } from '../src/shutdown.js';
import { type BuiltApp, buildTestApp } from './support.js';

/**
 * B-06 / B-05 on a real listening socket (the in-process `inject` never exercises Node's HTTP server timeouts).
 * Needs permission to listen on 127.0.0.1.
 */
const apps: BuiltApp[] = [];
const sockets: net.Socket[] = [];
afterEach(async () => {
  for (const s of sockets.splice(0)) s.destroy();
  while (apps.length) await apps.pop()!.app.close();
});

async function listen(env: Record<string, string>): Promise<{ built: BuiltApp; port: number }> {
  const built = await buildTestApp({ env });
  apps.push(built);
  await built.app.listen({ port: 0, host: '127.0.0.1' });
  return { built, port: (built.app.server.address() as AddressInfo).port };
}

function connect(port: number): Promise<{ socket: net.Socket; received: () => string; closed: Promise<number> }> {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, '127.0.0.1');
    sockets.push(socket);
    let data = '';
    const t0 = Date.now();
    const closed = new Promise<number>((done) => socket.on('close', () => done(Date.now() - t0)));
    socket.on('data', (d) => (data += d.toString('utf8')));
    socket.on('error', () => undefined);
    socket.once('connect', () => resolve({ socket, received: () => data, closed }));
    socket.once('error', reject);
  });
}

const within = async <T>(p: Promise<T>, ms: number, what: string): Promise<T> => {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => (timer = setTimeout(() => reject(new Error(`${what}: still open after ${ms} ms`)), ms)));
  try {
    return await Promise.race([p, timeout]);
  } finally {
    clearTimeout(timer);
  }
};

describe('HTTP server timeouts (B-06)', () => {
  it('a client that announces a body and stalls is cut off within REQUEST_TIMEOUT_MS', async () => {
    const { port } = await listen({ REQUEST_TIMEOUT_MS: '300' });
    const c = await connect(port);
    c.socket.write('POST /api/v1/auth/login HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{"email"');
    const elapsed = await within(c.closed, 3_000, 'stalled body');
    expect(elapsed).toBeLessThan(3_000);
  });

  it('a client that trickles its body slowly is cut off at the deadline, not after the body ends', async () => {
    const { port } = await listen({ REQUEST_TIMEOUT_MS: '400' });
    const c = await connect(port);
    c.socket.write('POST /api/v1/auth/login HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n');
    const trickle = setInterval(() => c.socket.write('x'), 100);
    try {
      const elapsed = await within(c.closed, 3_000, 'trickled body');
      expect(elapsed).toBeLessThan(2_000);
    } finally {
      clearInterval(trickle);
    }
  });

  it('the deadline ends once the body has arrived (a response after REQUEST_TIMEOUT_MS is fine)', async () => {
    const { port } = await listen({ REQUEST_TIMEOUT_MS: '300' });
    const body = JSON.stringify({ email: 'nobody@test.wattbyte', password: 'password123' });
    const c = await connect(port);
    c.socket.write(`POST /api/v1/auth/login HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n${body}`);
    await new Promise((r) => setTimeout(r, 900)); // well past REQUEST_TIMEOUT_MS
    expect(c.received()).toMatch(/^HTTP\/1\.1 401 /);
  });

  it('a client that stays silent after the headers started is cut off too (slowloris)', async () => {
    const { port } = await listen({ REQUEST_TIMEOUT_MS: '300' });
    const c = await connect(port);
    c.socket.write('GET /health HTTP/1.1\r\nHost: x\r\nX-Slow: 1');
    await within(c.closed, 3_000, 'unfinished headers');
  });

  it('an idle keep-alive connection closes after KEEP_ALIVE_TIMEOUT_MS, a normal request is served first', async () => {
    const { port } = await listen({ KEEP_ALIVE_TIMEOUT_MS: '300' });
    const c = await connect(port);
    c.socket.write('GET /health HTTP/1.1\r\nHost: x\r\n\r\n');
    await within(c.closed, 5_000, 'idle keep-alive');
    expect(c.received()).toMatch(/^HTTP\/1\.1 200 /);
  });

  it('a normal small POST on a real socket still works with the defaults', async () => {
    const { port } = await listen({});
    const res = await fetch(`http://127.0.0.1:${port}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'nobody@test.wattbyte', password: 'password123' }),
    });
    expect(res.status).toBe(401);
  });
});

describe('graceful shutdown on a real server (B-05)', () => {
  it('/ready turns 503 with Connection: close while draining, and a request in flight still completes', async () => {
    const { built, port } = await listen({ KEEP_ALIVE_TIMEOUT_MS: '60000' });
    const exit = vi.fn();
    const shutdown = createShutdown({ app: built.app, closeRepos: async () => undefined, drainMs: 600, timeoutMs: 10_000, sweepMs: 50, exit });

    const body = JSON.stringify({ email: 'nobody@test.wattbyte', password: 'password123' });
    const inFlight = await connect(port);
    inFlight.socket.write(`POST /api/v1/auth/login HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\n\r\n${body.slice(0, 5)}`);
    await new Promise((r) => setTimeout(r, 100));

    const started = Date.now();
    const done = shutdown('SIGTERM');
    const ready = await fetch(`http://127.0.0.1:${port}/ready`);
    expect(ready.status).toBe(503);
    expect(ready.headers.get('connection')).toBe('close');
    expect(await ready.json()).toMatchObject({ status: 'degraded' });

    // The in-flight request finishes during the drain, and the connection it used does not outlive the shutdown.
    inFlight.socket.write(body.slice(5));
    await within(done, 5_000, 'shutdown');
    expect(Date.now() - started).toBeLessThan(2_500);
    expect(inFlight.received()).toMatch(/^HTTP\/1\.1 401 /);
    expect(exit).toHaveBeenCalledWith(0);
    await within(inFlight.closed, 2_000, 'in-flight connection after shutdown');
  });

  it('a keep-alive connection that is idle when the server closes is swept, not waited for', async () => {
    const { built, port } = await listen({ KEEP_ALIVE_TIMEOUT_MS: '60000' });
    const exit = vi.fn();
    const shutdown = createShutdown({ app: built.app, closeRepos: async () => undefined, drainMs: 0, timeoutMs: 10_000, sweepMs: 50, exit });
    const idle = await connect(port);
    idle.socket.write('GET /health HTTP/1.1\r\nHost: x\r\n\r\n');
    await new Promise((r) => setTimeout(r, 150));
    expect(idle.received()).toMatch(/^HTTP\/1\.1 200 /);

    const started = Date.now();
    await within(shutdown('SIGTERM'), 5_000, 'shutdown with an idle keep-alive client');
    expect(Date.now() - started).toBeLessThan(2_000);
    expect(exit).toHaveBeenCalledWith(0);
  });
});
