import { randomUUID } from 'node:crypto';

import pg from 'pg';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { migrate } from '../../src/database/migrate.js';
import { PostgresRepositories } from '../../src/database/postgres.js';
import { DATABASE_URL, uniqueEmail } from './helpers.js';

/**
 * C-01 against a real server: the backend serving a transaction is killed while the transaction waits on a row lock.
 * Before the fix the checked-out client had no 'error' listener and the process died with an unhandled 'error' event
 * (vitest reports that as an unhandled error and fails the run); now the call rejects and the pool keeps working.
 */
describe.skipIf(!DATABASE_URL)('lost connection during a transaction (PostgreSQL)', () => {
  const app = `wb-c01-${randomUUID().slice(0, 8)}`;
  let admin: pg.Pool;
  let repos: PostgresRepositories;
  const userIds: string[] = [];

  beforeAll(async () => {
    await migrate(DATABASE_URL!);
    admin = new pg.Pool({ connectionString: DATABASE_URL, max: 3 });
    const url = new URL(DATABASE_URL!);
    url.searchParams.set('application_name', app);
    repos = new PostgresRepositories(url.toString(), { max: 3, onError: () => undefined });
  });
  afterAll(async () => {
    if (userIds.length) await admin.query('DELETE FROM users WHERE id = ANY($1)', [userIds]);
    await repos.close();
    await admin.end();
  });

  async function waitingBackend(): Promise<number> {
    for (let i = 0; i < 100; i += 1) {
      const res = await admin.query(
        "SELECT pid FROM pg_stat_activity WHERE application_name = $1 AND wait_event_type = 'Lock' AND state = 'active'",
        [app],
      );
      if (res.rows[0]) return (res.rows[0] as { pid: number }).pid;
      await new Promise((r) => setTimeout(r, 25));
    }
    throw new Error('the transaction never started waiting on the row lock');
  }

  it('rotate(): the call rejects, the process survives and the pool still serves queries', async () => {
    const user = await admin.query('INSERT INTO users(email) VALUES ($1) RETURNING id', [uniqueEmail('c01')]);
    const userId = (user.rows[0] as { id: string }).id;
    userIds.push(userId);
    const hash = randomUUID();
    await admin.query('INSERT INTO sessions(user_id, refresh_hash, expires_at) VALUES ($1, $2, now() + interval \'1 day\')', [userId, hash]);

    // Hold the row lock so rotate()'s SELECT ... FOR UPDATE blocks inside its transaction.
    const blocker = await admin.connect();
    try {
      await blocker.query('BEGIN');
      await blocker.query('SELECT 1 FROM sessions WHERE refresh_hash = $1 FOR UPDATE', [hash]);

      const rotation = repos.sessions.rotate({ oldHash: hash, newHash: randomUUID(), newExpiresAt: new Date(Date.now() + 1e6), now: new Date(), graceMs: 10_000 });
      const settled = rotation.then(() => 'resolved' as const, (e: unknown) => e);
      const pid = await waitingBackend();
      await admin.query('SELECT pg_terminate_backend($1)', [pid]);

      const outcome = await settled;
      expect(outcome).not.toBe('resolved');
      expect(outcome).toBeInstanceOf(Error);
    } finally {
      await blocker.query('ROLLBACK').catch(() => undefined);
      blocker.release();
    }

    // The broken client was discarded, not returned: the next calls get a fresh connection.
    expect(await repos.sessions.findByHash(hash)).toMatchObject({ userId });
    expect(await repos.usage.upsertDaily([])).toBe(0);
  });
});
