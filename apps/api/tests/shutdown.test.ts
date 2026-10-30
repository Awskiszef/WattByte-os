// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { createShutdown, type ShutdownApp } from '../src/shutdown.js';

/** B-05, the state machine without a network: order of steps, single run, deadline, failure exit codes. */
function harness(overrides: { close?: () => Promise<void>; closeRepos?: () => Promise<void> } = {}) {
  const events: string[] = [];
  const logs: { level: string; msg?: string; o: object }[] = [];
  const log = (level: string) => (o: object, msg?: string) => void logs.push({ level, msg, o });
  const app: ShutdownApp = {
    server: { closeIdleConnections: () => void events.push('sweep'), closeAllConnections: () => void events.push('cutAll') },
    lifecycle: { draining: false },
    log: { info: log('info'), warn: log('warn'), error: log('error') },
    close: overrides.close ?? (async () => void events.push(`close(draining=${String(app.lifecycle.draining)})`)),
  };
  const exit = vi.fn((code: number) => void events.push(`exit(${code})`));
  const closeRepos = overrides.closeRepos ?? (async () => void events.push('repos'));
  const shutdown = createShutdown({ app, closeRepos, drainMs: 1_000, timeoutMs: 10_000, sweepMs: 100, exit });
  return { app, events, logs, exit, shutdown };
}

beforeEach(() => void vi.useFakeTimers());
afterEach(() => void vi.useRealTimers());

describe('graceful shutdown (B-05)', () => {
  it('flips readiness first, drains, closes the server, then the pool, then exits 0', async () => {
    const h = harness();
    const done = h.shutdown('SIGTERM');
    expect(h.app.lifecycle.draining).toBe(true);
    expect(h.events).toEqual([]); // still draining: nothing closed yet
    await vi.advanceTimersByTimeAsync(1_000);
    await done;
    expect(h.events).toEqual(['close(draining=true)', 'repos', 'exit(0)']);
  });

  it('a second signal does not start a second shutdown (no double pool.end(), no second exit)', async () => {
    const h = harness();
    const first = h.shutdown('SIGTERM');
    const second = h.shutdown('SIGINT');
    expect(second).toBe(first);
    await vi.advanceTimersByTimeAsync(1_000);
    await first;
    expect(h.events.filter((e) => e === 'repos')).toHaveLength(1);
    expect(h.exit).toHaveBeenCalledTimes(1);
    expect(h.logs.some((l) => l.level === 'warn' && l.msg === 'shutdown already in progress')).toBe(true);
  });

  it('sweeps idle keep-alive connections while the server is closing', async () => {
    let finish!: () => void;
    const h = harness({ close: () => new Promise<void>((resolve) => (finish = resolve)) });
    const done = h.shutdown('SIGTERM');
    await vi.advanceTimersByTimeAsync(1_000);
    await vi.advanceTimersByTimeAsync(350);
    expect(h.events.filter((e) => e === 'sweep').length).toBeGreaterThanOrEqual(3);
    finish();
    await vi.advanceTimersByTimeAsync(0);
    await done;
    const sweeps = h.events.filter((e) => e === 'sweep').length;
    await vi.advanceTimersByTimeAsync(1_000);
    expect(h.events.filter((e) => e === 'sweep')).toHaveLength(sweeps); // the sweep stops with the close
    expect(h.exit).toHaveBeenCalledWith(0);
  });

  it('a close that never finishes is cut at the deadline: connections are closed and the exit code is 1', async () => {
    const h = harness({ close: () => new Promise<void>(() => undefined) });
    void h.shutdown('SIGTERM');
    await vi.advanceTimersByTimeAsync(9_999);
    expect(h.exit).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(h.events).toContain('cutAll');
    expect(h.exit).toHaveBeenCalledWith(1);
    expect(h.logs.some((l) => l.level === 'error' && /deadline/.test(l.msg ?? ''))).toBe(true);
  });

  it.each([
    ['app.close() fails', { close: async () => Promise.reject(new Error('close failed')) }],
    ['the pool cannot be closed', { closeRepos: async () => Promise.reject(new Error('pool failed')) }],
  ])('%s: it is logged and the exit code is 1', async (_name, overrides) => {
    const h = harness(overrides);
    const done = h.shutdown('SIGTERM');
    await vi.advanceTimersByTimeAsync(1_000);
    await done;
    expect(h.exit).toHaveBeenCalledWith(1);
    expect(h.exit).not.toHaveBeenCalledWith(0);
    expect(h.logs.some((l) => l.level === 'error' && l.msg === 'shutdown failed')).toBe(true);
  });

  it('a fatal error exits with its own code after an orderly close', async () => {
    const h = harness();
    const done = h.shutdown('uncaughtException', 1);
    await vi.advanceTimersByTimeAsync(1_000);
    await done;
    expect(h.events).toEqual(['close(draining=true)', 'repos', 'exit(1)']);
  });
});
