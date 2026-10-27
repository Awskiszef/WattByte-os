import { EventEmitter } from 'node:events';

import type pg from 'pg';
import { describe, expect, it } from 'vitest';

import { PostgresRepositories } from '../src/database/postgres.js';
import type { DailyUsageRow } from '../src/database/repositories.js';

/**
 * C-01: a transaction client from pool.connect() is a bare EventEmitter. pg-pool only listens to it while it sits idle,
 * so a connection lost during BEGIN/queries/COMMIT emitted an unhandled 'error' and killed the whole API process.
 *
 * These tests drive the four transactional repository methods through a scripted fake pool, so they need no database.
 * An unhandled 'error' event on an EventEmitter throws synchronously from emit(): if the fix regresses, the
 * `emit` inside the fake client throws out of the test instead of being absorbed by the repository.
 */

const LOST = Object.assign(new Error('Connection terminated unexpectedly'), { code: undefined });
const ROW: DailyUsageRow = {
  userId: 'u1', deviceId: 'd1', date: '2026-01-01', mobileBytes: 1, wifiBytes: 1, chargedWh: 1, wallWh: 1,
  chargingSessions: 0, estimatedCost: 0, currency: 'PLN', dataEstimated: false, energyEstimated: false,
};

type Step = (sql: string, client: FakeClient) => Promise<unknown> | undefined;

class FakeClient extends EventEmitter {
  readonly statements: string[] = [];
  released: { called: boolean; arg?: unknown } = { called: false };
  constructor(private readonly step: Step) {
    super();
  }
  query(sql: string): Promise<unknown> {
    this.statements.push(sql.split(/\s+/)[0] === 'BEGIN' ? 'BEGIN' : sql.trim().split(/\s+/)[0]!.toUpperCase());
    return this.step(sql, this) ?? Promise.resolve({ rows: [], rowCount: 0 });
  }
  release(arg?: unknown): void {
    this.released = { called: true, arg };
  }
}

function repositoriesWith(client: FakeClient): PostgresRepositories {
  const repos = new PostgresRepositories('postgres://u:p@127.0.0.1:1/db');
  const real = (repos as unknown as { pool: pg.Pool }).pool;
  void real.end();
  (repos as unknown as { pool: unknown }).pool = { connect: async () => client, on: () => undefined, end: async () => undefined };
  return repos;
}

/** The connection dies while `when` runs: the socket emits 'error' and the pending query rejects, as in pg. */
const dieOn = (when: (sql: string) => boolean): Step => (sql, client) => {
  if (!when(sql)) return undefined;
  client.emit('error', LOST);
  return Promise.reject(LOST);
};

const operations = {
  'sessions.rotate': (r: PostgresRepositories) =>
    r.sessions.rotate({ oldHash: 'a', newHash: 'b', newExpiresAt: new Date(Date.now() + 1e6), now: new Date(), graceMs: 10_000 }),
  'usage.upsertDaily': (r: PostgresRepositories) => r.usage.upsertDaily([ROW]),
  'cloud.deleteData': (r: PostgresRepositories) => r.cloud.deleteData('u1'),
  'cloud.exportData': (r: PostgresRepositories) => r.cloud.exportData('u1', 100),
} as const;

describe.each(Object.entries(operations))('%s keeps the process alive when the connection is lost (C-01)', (_name, operate) => {
  it('during BEGIN', async () => {
    const client = new FakeClient(dieOn((sql) => /^BEGIN/.test(sql)));
    await expect(operate(repositoriesWith(client))).rejects.toBe(LOST);
    // The transaction was never opened on a healthy connection, the broken client is discarded, not pooled.
    expect(client.released.called).toBe(true);
    expect(client.released.arg).toBeTruthy();
  });

  it('during the first statement of the transaction', async () => {
    const client = new FakeClient(dieOn((sql) => !/^(BEGIN|ROLLBACK|COMMIT)/.test(sql)));
    await expect(operate(repositoriesWith(client))).rejects.toBe(LOST);
    expect(client.released.called).toBe(true);
    expect(client.released.arg).toBe(LOST);
    // ROLLBACK is attempted (and may fail); the connection never goes back to the pool as healthy.
    expect(client.statements).toContain('ROLLBACK');
    // Our listener is gone and nothing else was left on the client except what release() restores.
    expect(client.listenerCount('error')).toBe(0);
  });

  it('while the failed ROLLBACK itself cannot reach the server: the cause is kept and the client is destroyed', async () => {
    const dying = dieOn((s) => !/^(BEGIN|ROLLBACK|COMMIT)/.test(s));
    const client = new FakeClient((sql, c) => {
      if (/^ROLLBACK/.test(sql)) return Promise.reject(new Error('rollback failed'));
      return dying(sql, c);
    });
    await expect(operate(repositoriesWith(client))).rejects.toBe(LOST);
    expect(client.released.arg).toBeTruthy();
  });

  it('does not crash when an error event arrives after the last statement (an event with no pending query)', async () => {
    const client = new FakeClient((sql, c) => {
      if (/^COMMIT/.test(sql)) {
        c.emit('error', LOST);
        return Promise.resolve({ rows: [], rowCount: 0 });
      }
      return undefined;
    });
    // The commit was acknowledged: the data is written, so the caller gets the result, not an error.
    await operate(repositoriesWith(client)).catch((e: unknown) => {
      throw e;
    });
    expect(client.released.arg).toBe(LOST);
    expect(client.listenerCount('error')).toBe(0);
  });

  it('returns a healthy client to the pool unmarked, with no listener of ours left on it', async () => {
    const client = new FakeClient(() => undefined);
    await operate(repositoriesWith(client));
    expect(client.released.called).toBe(true);
    expect(client.released.arg).toBeUndefined();
    expect(client.listenerCount('error')).toBe(0);
  });
});

describe('a throwing onError callback cannot turn a handled connection loss into a crash', () => {
  it('rotate rejects with the database error, not the logger error', async () => {
    const client = new FakeClient(dieOn((sql) => /^SELECT/.test(sql)));
    const repos = new PostgresRepositories('postgres://u:p@127.0.0.1:1/db', {
      onError: () => {
        throw new Error('logger exploded');
      },
    });
    void (repos as unknown as { pool: pg.Pool }).pool.end();
    (repos as unknown as { pool: unknown }).pool = { connect: async () => client, on: () => undefined, end: async () => undefined };
    await expect(operations['sessions.rotate'](repos)).rejects.toBe(LOST);
  });
});
