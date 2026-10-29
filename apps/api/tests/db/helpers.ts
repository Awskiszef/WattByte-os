import { AI_PROVIDER_IDS, AIGateway, MockProvider, ProviderRouter } from '@wattbyte/ai';
import pg from 'pg';

import { type App, buildApp } from '../../src/app.js';
import { loadEnv } from '../../src/config/env.js';
import { migrate } from '../../src/database/migrate.js';
import { PostgresRepositories } from '../../src/database/postgres.js';
import { spendLedger } from '../../src/modules/ai/gateway.js';

/** Integration tests run against a real PostgreSQL when TEST_DATABASE_URL is set (CI provides one). */
export const DATABASE_URL = process.env.TEST_DATABASE_URL;

export interface PgContext {
  app: App;
  repos: PostgresRepositories;
  pool: pg.Pool;
  providers: MockProvider[];
}

export async function makePgApp(overrides: Record<string, string> = {}, deps: { aiRateLimitMax?: number } = {}): Promise<PgContext> {
  if (!DATABASE_URL) throw new Error('TEST_DATABASE_URL is not set');
  await migrate(DATABASE_URL);
  const env = loadEnv({
    NODE_ENV: 'test',
    JWT_SECRET: 'test-secret-test-secret-test-secret-test-secret',
    // The per-account write budget is under test in device-limits; everywhere else it must not get in the way.
    CLOUD_WRITE_RATE_LIMIT_PER_MIN: '10000',
    DATABASE_URL,
    AI_FREE_DAILY_LIMIT: '3',
    AI_PREMIUM_DAILY_LIMIT: '10',
    ...overrides,
  });
  const repos = new PostgresRepositories(DATABASE_URL);
  const providers = AI_PROVIDER_IDS.map((id) => new MockProvider(id));
  const gateway = new AIGateway({ router: new ProviderRouter(providers, { cooldownMs: 0 }), sleep: async () => undefined, ledger: spendLedger(env, repos) });
  const app = await buildApp({ env, repos, gateway, providerIds: [], logger: false, rateLimitMax: 100_000, aiRateLimitMax: 100_000, authRateLimitMax: 100_000, refreshRateLimitMax: 100_000, ...deps });
  await app.ready();
  return { app, repos, pool: new pg.Pool({ connectionString: DATABASE_URL, max: 2 }), providers };
}

export async function closePgApp(ctx: PgContext): Promise<void> {
  await ctx.app.close();
  await ctx.repos.close();
  await ctx.pool.end();
}

let counter = 0;
export const uniqueEmail = (prefix: string): string => `${prefix}-${process.pid}-${Date.now()}-${counter++}@test.wattbyte`;

export async function register(app: App, email: string, password = 'password123') {
  const res = await app.inject({ method: 'POST', url: '/api/v1/auth/register', payload: { email, password } });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  return res.json() as {
    user: { id: string };
    tokens: { accessToken: string; refreshToken: string };
  };
}
