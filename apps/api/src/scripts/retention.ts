
import pg from 'pg';
import { z } from 'zod';

import { RetentionEnvShape } from '../config/env.js';
import { isMainModule } from '../util/is-main.js';

/**
 * Data retention. Run on a schedule (daily is plenty):
 *
 *   pnpm --filter @wattbyte/api retention              # purge
 *   pnpm --filter @wattbyte/api retention -- --dry-run # count only
 *   node dist/scripts/retention.js                     # from a production build
 *
 * What is purged, and after how long (docs/security.md has the full retention table):
 *
 *   ai_generations   older than AI_HISTORY_RETENTION_DAYS (default 90): the usage/cost log of AI calls
 *   sessions         expired or revoked more than 30 days ago: dead refresh tokens (live sessions are never touched)
 *   ai_quota_usage   days older than 7: the per-day counters only matter for "today"
 *
 * Everything else (accounts, devices, daily aggregates, settings) is kept until the account is deleted
 * (`DELETE /api/v1/me` cascades), which is the user's decision, not a timer's.
 */

export const SESSION_RETENTION_DAYS = 30;
export const AI_QUOTA_RETENTION_DAYS = 7;
export const DEFAULT_BATCH_SIZE = 5_000;

const DAY_MS = 86_400_000;

export interface RetentionOptions {
  /** The reference time ("now"); tests pin it. */
  now?: Date;
  aiHistoryDays?: number;
  sessionDays?: number;
  quotaDays?: number;
  /** Rows per DELETE statement, so a large backlog never holds a long lock. */
  batchSize?: number;
  /** Count what would be purged, delete nothing. */
  dryRun?: boolean;
}

export interface RetentionResult {
  dryRun: boolean;
  ranAt: string;
  /** Rows older than these instants / days are purged. */
  cutoffs: { aiGenerations: string; sessions: string; aiQuotaDay: string };
  /** Rows purged (or, with `dryRun`, rows that would be). */
  rows: { aiGenerations: number; sessions: number; aiQuotaUsage: number };
}

/** A pool or a single client: all the script needs. */
export type Queryable = Pick<pg.ClientBase, 'query'>;

const utcDay = (d: Date): string => d.toISOString().slice(0, 10);

async function purge(db: Queryable, select: string, params: unknown[], del: string, batchSize: number, dryRun: boolean): Promise<number> {
  if (dryRun) {
    const res = await db.query(`SELECT count(*)::int AS n FROM (${select}) AS doomed`, params);
    return (res.rows[0] as { n: number }).n;
  }
  let total = 0;
  for (;;) {
    const res = await db.query(del, [...params, batchSize]);
    const n = res.rowCount ?? 0;
    total += n;
    if (n < batchSize) return total;
  }
}

/** Purges what is past retention. Idempotent and safe to run while the API serves traffic. */
export async function runRetention(db: Queryable, options: RetentionOptions = {}): Promise<RetentionResult> {
  const now = options.now ?? new Date();
  const aiDays = options.aiHistoryDays ?? 90;
  const sessionDays = options.sessionDays ?? SESSION_RETENTION_DAYS;
  const quotaDays = options.quotaDays ?? AI_QUOTA_RETENTION_DAYS;
  const batchSize = options.batchSize ?? DEFAULT_BATCH_SIZE;
  const dryRun = options.dryRun ?? false;
  if (!Number.isInteger(aiDays) || aiDays < 1) throw new Error('aiHistoryDays must be an integer >= 1');
  if (!Number.isInteger(batchSize) || batchSize < 1) throw new Error('batchSize must be an integer >= 1');

  const aiCutoff = new Date(now.getTime() - aiDays * DAY_MS);
  const sessionCutoff = new Date(now.getTime() - sessionDays * DAY_MS);
  const quotaCutoffDay = utcDay(new Date(now.getTime() - quotaDays * DAY_MS));

  const aiGenerations = await purge(
    db,
    'SELECT id FROM ai_generations WHERE created_at < $1',
    [aiCutoff],
    'DELETE FROM ai_generations WHERE id IN (SELECT id FROM ai_generations WHERE created_at < $1 ORDER BY created_at LIMIT $2)',
    batchSize,
    dryRun,
  );
  // A session is dead once it expired or was revoked; only the ones dead for longer than the window go.
  // A live session (not revoked, not expired) matches neither condition.
  const sessions = await purge(
    db,
    'SELECT id FROM sessions WHERE expires_at < $1 OR revoked_at < $1',
    [sessionCutoff],
    'DELETE FROM sessions WHERE id IN (SELECT id FROM sessions WHERE expires_at < $1 OR revoked_at < $1 LIMIT $2)',
    batchSize,
    dryRun,
  );
  const aiQuotaUsage = await purge(
    db,
    'SELECT user_id, day FROM ai_quota_usage WHERE day < $1::date',
    [quotaCutoffDay],
    'DELETE FROM ai_quota_usage WHERE (user_id, day) IN (SELECT user_id, day FROM ai_quota_usage WHERE day < $1::date LIMIT $2)',
    batchSize,
    dryRun,
  );

  return {
    dryRun,
    ranAt: now.toISOString(),
    cutoffs: { aiGenerations: aiCutoff.toISOString(), sessions: sessionCutoff.toISOString(), aiQuotaDay: quotaCutoffDay },
    rows: { aiGenerations, sessions, aiQuotaUsage },
  };
}

const RetentionConfigSchema = z.object({
  DATABASE_URL: z.string().url({ message: 'DATABASE_URL is required' }),
  DATABASE_SSL: z.enum(['0', '1']).default('0'),
  ...RetentionEnvShape,
});

/** Reads the three variables the script needs; it does not require the API's JWT secret or provider keys. */
export function loadRetentionConfig(source: NodeJS.ProcessEnv = process.env) {
  const cleaned = Object.fromEntries(Object.entries(source).filter(([, v]) => v !== ''));
  const parsed = RetentionConfigSchema.safeParse(cleaned);
  if (!parsed.success) {
    throw new Error(`Invalid environment:\n${parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`).join('\n')}`);
  }
  return {
    databaseUrl: parsed.data.DATABASE_URL,
    ssl: parsed.data.DATABASE_SSL === '1' ? { rejectUnauthorized: true } : undefined,
    aiHistoryDays: parsed.data.AI_HISTORY_RETENTION_DAYS,
  };
}

/** Serialises concurrent runs (two schedulers, a manual run during the cron job). */
const ADVISORY_LOCK_KEY = 727_275;

async function main(): Promise<void> {
  const dryRun = process.argv.includes('--dry-run');
  const config = loadRetentionConfig();
  const pool = new pg.Pool({ connectionString: config.databaseUrl, ssl: config.ssl, max: 1, statement_timeout: 120_000 });
  const client = await pool.connect();
  try {
    const lock = await client.query('SELECT pg_try_advisory_lock($1) AS locked', [ADVISORY_LOCK_KEY]);
    if (!(lock.rows[0] as { locked: boolean }).locked) {
      process.stdout.write(`${JSON.stringify({ skipped: 'another retention run holds the lock' })}\n`);
      return;
    }
    const result = await runRetention(client, { aiHistoryDays: config.aiHistoryDays, dryRun });
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [ADVISORY_LOCK_KEY]).catch(() => undefined);
    client.release();
    await pool.end();
  }
}

if (isMainModule(import.meta.url)) {
  main().catch((e: unknown) => {
    // Print the class and message of a failure of this script only; it handles no user input.
    console.error(e instanceof Error ? `${e.name}: ${e.message}` : e);
    process.exit(1);
  });
}
