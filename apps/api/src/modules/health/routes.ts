import { HealthResponse, ReadyResponse } from '@wattbyte/contracts';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

import type { Repositories } from '../../database/repositories.js';

export interface HealthRoutesOptions {
  repos: Repositories;
  providerIds: string[];
  version: string;
  /** How long `/ready` waits for the database before it answers 503. */
  readyTimeoutMs?: number;
}

export const healthRoutes: FastifyPluginAsyncZod<HealthRoutesOptions> = async (
  app,
  { repos, providerIds, version, readyTimeoutMs = 2_000 },
) => {
  const started = Date.now();

  /**
   * Concurrent `/ready` calls share one probe, so a load balancer polling a hung database does not queue a
   * connection attempt per request. A probe that has been running for half the timeout or longer is not joined
   * any more: a new one starts, so recovery is noticed even if an earlier probe never settles (a black-holed
   * host). Half, not the whole timeout, so a caller that just gave up on the old probe never joins it again.
   */
  let inflight: { startedAt: number; result: Promise<boolean> } | null = null;
  const probe = (): Promise<boolean> => {
    const now = Date.now();
    if (inflight && now - inflight.startedAt < readyTimeoutMs / 2) return inflight.result;
    const entry = { startedAt: now, result: repos.ping().catch(() => false) };
    inflight = entry;
    void entry.result.finally(() => {
      if (inflight === entry) inflight = null;
    });
    return entry.result;
  };

  /** True only when `SELECT 1` really ran and came back within the timeout. */
  const databaseReady = async (): Promise<boolean> => {
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<boolean>((resolve) => {
      timer = setTimeout(() => resolve(false), readyTimeoutMs);
    });
    try {
      return await Promise.race([probe(), timeout]);
    } finally {
      clearTimeout(timer);
    }
  };

  // Both probes are exempt from the per-IP rate limiter (`rateLimit: false`): a balancer that shares an address with
  // traffic, or an unset TRUST_PROXY_HOPS, must never get 429 and drain a healthy instance (B-09). /ready is cheap:
  // concurrent calls share one database probe.
  // Liveness: the process answers. Never touches the database, so a database outage does not get the API restarted.
  app.get('/health', { config: { public: true, rateLimit: false }, schema: { tags: ['ops'], response: { 200: HealthResponse } } }, async () => ({
    status: 'ok' as const,
    version,
    uptimeSec: Math.floor((Date.now() - started) / 1000),
  }));

  // Readiness: the API can serve traffic, i.e. the database executes a query right now.
  app.get(
    '/ready',
    { config: { public: true, rateLimit: false }, schema: { tags: ['ops'], response: { 200: ReadyResponse, 503: ReadyResponse } } },
    async (request, reply) => {
      const db = await databaseReady();
      // Draining (SIGTERM received): tell the balancer to stop sending traffic before the listener closes.
      const draining = app.lifecycle.draining;
      if (!db) request.log.warn({ database: 'unavailable', timeoutMs: readyTimeoutMs }, 'readiness check failed');
      const ok = db && !draining;
      const body = { status: ok ? ('ok' as const) : ('degraded' as const), database: db ? ('ok' as const) : ('unavailable' as const), aiProviders: providerIds };
      return reply.status(ok ? 200 : 503).send(body);
    },
  );
};
