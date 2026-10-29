import { AI_PROVIDER_IDS, MockProvider, providersFromEnv, type AIProvider } from '@wattbyte/ai';
import type { FastifyBaseLogger } from 'fastify';

import { buildApp } from './app.js';
import { envWarnings, loadEnv } from './config/env.js';
import { resolveDatabaseConnection } from './database/connection.js';
import { latestMigrationName } from './database/migrate.js';
import { PostgresRepositories } from './database/postgres.js';
import { buildGateway } from './modules/ai/gateway.js';
import { createShutdown } from './shutdown.js';

async function main(): Promise<void> {
  const env = loadEnv();
  if (!env.DATABASE_URL) {
    console.error('DATABASE_URL is required (see .env.example)');
    process.exit(1);
  }
  // The pool is created before the app (the app needs it), so its error handler reaches the logger through this holder.
  const logger: { current?: FastifyBaseLogger } = {};
  const db = resolveDatabaseConnection({ url: env.DATABASE_URL, databaseSsl: process.env.DATABASE_SSL || undefined, caFile: env.DATABASE_SSL_CA_FILE });
  const repos = new PostgresRepositories(db.connectionString, {
    ssl: db.ssl,
    max: env.DATABASE_POOL_MAX,
    statementTimeoutMs: env.DATABASE_STATEMENT_TIMEOUT_MS,
    // An idle client dropped by the server or a proxy. Only the error class and SQLSTATE: the message can carry connection details.
    onError: (e) => {
      if (logger.current) logger.current.error({ err: e }, 'postgres pool error');
      else console.error('postgres pool error');
    },
  });

  const providers: AIProvider[] = env.AI_MOCK === '1' ? AI_PROVIDER_IDS.map((id) => new MockProvider(id)) : providersFromEnv(env);
  if (providers.length === 0) console.warn('No AI provider configured: /api/v1/ai/* will answer 503');
  // Per-attempt telemetry (provider, model, latency, tokens, status - never prompt/answer text) goes to the app logger,
  // which exists only after the gateway (the app needs the gateway), hence the late binding.
  const gatewayLogger = {
    info: (entry: Record<string, unknown>, message?: string) => (logger.current ?? console).info(entry, message),
    warn: (entry: Record<string, unknown>, message?: string) => (logger.current ?? console).warn(entry, message),
  };
  const gateway = buildGateway(env, repos, providers, gatewayLogger);

  // Readiness requires the schema to have reached the newest migration this build ships (undefined = files not found: unchecked).
  const expectedSchemaVersion = await latestMigrationName().catch(() => undefined);
  if (expectedSchemaVersion === undefined) console.warn('migration files not found: /ready will not check the schema version');
  const app = await buildApp({ env, repos, gateway, providerIds: providers.map((p) => p.id), expectedSchemaVersion });
  logger.current = app.log;
  for (const warning of envWarnings(env)) app.log.warn({ appEnv: env.APP_ENV }, warning);
  // What the AI layer will do, in one line: providers, never keys or model names.
  const ai = gateway.status();
  app.log.info(
    {
      ai: {
        providers: ai.providers.filter((p) => p.configured).map((p) => p.id),
        defaultProvider: ai.defaultProvider,
        fallback: ai.fallbackEnabled,
        maxRetries: ai.maxRetries,
        attemptTimeoutMs: ai.attemptTimeoutMs,
        requestTimeoutMs: ai.requestTimeoutMs,
        budgetEnforced: ai.budgetEnforced,
      },
    },
    'ai configuration',
  );

  const shutdown = createShutdown({
    app,
    closeRepos: () => repos.close(),
    drainMs: env.SHUTDOWN_DRAIN_MS,
    timeoutMs: env.SHUTDOWN_TIMEOUT_MS,
    exit: (code) => process.exit(code),
  });
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
  // A bug that escapes every handler ends the process through the same orderly path, with a failing exit code.
  process.on('unhandledRejection', (e) => {
    app.log.fatal({ err: e }, 'unhandled rejection');
    void shutdown('unhandledRejection', 1);
  });
  process.on('uncaughtException', (e) => {
    app.log.fatal({ err: e }, 'uncaught exception');
    void shutdown('uncaughtException', 1);
  });

  // The server starts even when PostgreSQL is down: /health stays 200 (the process is alive), /ready answers
  // 503 until `SELECT 1` works, so a load balancer sends no traffic to an instance that cannot serve it, and
  // a database outage does not turn into a restart loop. Migrations are a separate step (`pnpm migrate`).
  await app.listen({ port: env.PORT, host: env.HOST });
  const databaseUp = await repos.ping();
  if (databaseUp) app.log.info({ appEnv: env.APP_ENV, features: featureSummary(env) }, 'database reachable at boot');
  else app.log.warn({ appEnv: env.APP_ENV }, 'database NOT reachable at boot; /ready answers 503 until it is');
}

function featureSummary(env: ReturnType<typeof loadEnv>): Record<string, boolean> {
  return { ai: env.FEATURE_AI === '1', subscriptions: env.FEATURE_SUBSCRIPTIONS === '1', cloudSync: env.FEATURE_CLOUD_SYNC === '1' };
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
