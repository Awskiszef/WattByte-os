// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, describe, expect, it } from 'vitest';

import { MemoryRepositories } from '../src/database/memory.js';
import { type BuiltApp, buildTestApp, LogCapture } from './support.js';

const apps: BuiltApp[] = [];
afterEach(async () => {
  await Promise.all(apps.splice(0).map((c) => c.app.close()));
});

/** A repository whose ping is whatever the test says. */
class PingRepos extends MemoryRepositories {
  calls = 0;
  constructor(private behaviour: () => Promise<boolean>) {
    super();
  }
  set(behaviour: () => Promise<boolean>): void {
    this.behaviour = behaviour;
  }
  override async ping(): Promise<boolean> {
    this.calls++;
    return this.behaviour();
  }
}

async function make(repos: PingRepos, env: Record<string, string> = {}, logStream?: LogCapture): Promise<BuiltApp> {
  const ctx = await buildTestApp({ repos, env: { READY_DB_TIMEOUT_MS: '200', ...env }, logStream });
  apps.push(ctx);
  return ctx;
}

describe('GET /ready', () => {
  it('200 {status: ok, database: ok} when the database answers', async () => {
    const { app } = await make(new PingRepos(async () => true));
    const res = await app.inject({ url: '/ready' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', database: 'ok', aiProviders: ['openai', 'anthropic', 'google', 'xai'] });
  });

  it('503 {status: degraded, database: unavailable} when the query fails or returns false', async () => {
    for (const behaviour of [async () => false, async (): Promise<boolean> => { throw new Error('connect ECONNREFUSED 127.0.0.1:5432'); }]) {
      const { app } = await make(new PingRepos(behaviour));
      const res = await app.inject({ url: '/ready' });
      expect(res.statusCode).toBe(503);
      expect(res.json()).toMatchObject({ status: 'degraded', database: 'unavailable' });
      expect(res.headers['x-request-id']).toBeTruthy();
    }
  });

  it('503 within the timeout when the database hangs, not after the client gives up', async () => {
    const { app } = await make(new PingRepos(() => new Promise<boolean>(() => undefined)));
    const started = Date.now();
    const res = await app.inject({ url: '/ready' });
    const took = Date.now() - started;
    expect(res.statusCode).toBe(503);
    expect(res.json()).toMatchObject({ status: 'degraded', database: 'unavailable' });
    expect(took).toBeGreaterThanOrEqual(150);
    expect(took).toBeLessThan(1_500);
  });

  it('/health is liveness only: it answers 200 while the database is down and never pings', async () => {
    const repos = new PingRepos(async () => false);
    const { app } = await make(repos);
    expect((await app.inject({ url: '/health' })).statusCode).toBe(200);
    expect((await app.inject({ method: 'HEAD', url: '/health' })).statusCode).toBe(200);
    expect(repos.calls).toBe(0);
  });

  it('concurrent probes share one ping while it is in flight; a recovered database is noticed at once', async () => {
    let release: (v: boolean) => void = () => undefined;
    const repos = new PingRepos(() => new Promise<boolean>((resolve) => (release = resolve)));
    const { app } = await make(repos, { READY_DB_TIMEOUT_MS: '2000' });
    const burst = Promise.all(Array.from({ length: 8 }, () => app.inject({ url: '/ready' })));
    await new Promise((r) => setTimeout(r, 50));
    release(true);
    const results = await burst;
    expect(results.every((r) => r.statusCode === 200)).toBe(true);
    expect(repos.calls).toBe(1);

    // After it settled the next call asks the database again: the answer is never cached.
    repos.set(async () => false);
    expect((await app.inject({ url: '/ready' })).statusCode).toBe(503);
    repos.set(async () => true);
    expect((await app.inject({ url: '/ready' })).statusCode).toBe(200);
    expect(repos.calls).toBe(3);
  });

  it('a probe that never settles does not block recovery: after the timeout window a new probe is made', async () => {
    const repos = new PingRepos(() => new Promise<boolean>(() => undefined));
    const { app } = await make(repos, { READY_DB_TIMEOUT_MS: '100' });
    expect((await app.inject({ url: '/ready' })).statusCode).toBe(503);
    repos.set(async () => true);
    const res = await app.inject({ url: '/ready' });
    expect(res.statusCode).toBe(200);
    expect(repos.calls).toBe(2);
  });

  it('logs the failed readiness check without the error text', async () => {
    const log = new LogCapture();
    const { app } = await make(new PingRepos(async () => false), {}, log);
    await app.inject({ url: '/ready' });
    const line = log.records().find((r) => r.msg === 'readiness check failed');
    expect(line).toMatchObject({ database: 'unavailable', timeoutMs: 200 });
  });
});
