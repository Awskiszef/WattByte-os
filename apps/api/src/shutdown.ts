import type { Server } from 'node:http';

export interface ShutdownApp {
  server: Pick<Server, 'closeIdleConnections' | 'closeAllConnections'>;
  lifecycle: { draining: boolean };
  log: { info(o: object, m?: string): void; warn(o: object, m?: string): void; error(o: object, m?: string): void };
  close(): Promise<void>;
}

export interface ShutdownOptions {
  app: ShutdownApp;
  closeRepos: () => Promise<void>;
  /** After the readiness flip, wait this long so the balancer notices before the listener closes. */
  drainMs: number;
  /** Hard deadline of the whole sequence. */
  timeoutMs: number;
  /** How often idle keep-alive connections are swept while the server closes. */
  sweepMs?: number;
  exit: (code: number) => void;
}

/**
 * Graceful shutdown as one state machine (B-05):
 *  1. the first signal flips /ready to 503 and responses to `Connection: close`;
 *  2. after the drain delay the listener closes (`app.close()`), while idle keep-alive connections are swept
 *     every `sweepMs` so a connection that finishes its request late is not left waiting for its keep-alive timeout;
 *  3. then the database pool is closed (`app.close()` first, so in-flight requests can still use it);
 *  4. a hard deadline cuts every remaining connection and exits 1 before the orchestrator's SIGKILL;
 *  5. any failure is logged and exits 1; a repeated signal only logs and returns the same promise.
 * `reason` is a signal name or the fatal error that started it; `code` is the exit code on success.
 */
export function createShutdown(options: ShutdownOptions): (reason: string, code?: number) => Promise<void> {
  const { app, closeRepos, drainMs, timeoutMs, sweepMs = 250, exit } = options;
  let running: Promise<void> | undefined;

  const run = async (reason: string, code: number): Promise<void> => {
    app.log.info({ reason, drainMs, timeoutMs }, 'shutting down');
    app.lifecycle.draining = true;
    const deadline = setTimeout(() => {
      app.log.error({ reason, timeoutMs }, 'shutdown deadline reached; closing remaining connections');
      app.server.closeAllConnections();
      exit(1);
    }, timeoutMs);
    let sweep: NodeJS.Timeout | undefined;
    try {
      if (drainMs > 0) await new Promise<void>((resolve) => setTimeout(resolve, drainMs));
      const closing = app.close();
      sweep = setInterval(() => app.server.closeIdleConnections(), sweepMs);
      await closing;
      clearInterval(sweep);
      await closeRepos();
      clearTimeout(deadline);
      app.log.info({ reason }, 'shutdown complete');
      exit(code);
    } catch (e) {
      clearTimeout(deadline);
      if (sweep) clearInterval(sweep);
      app.log.error({ reason, err: e }, 'shutdown failed');
      exit(1);
    }
  };

  return (reason, code = 0) => {
    if (running) {
      app.log.warn({ reason }, 'shutdown already in progress');
      return running;
    }
    running = run(reason, code);
    return running;
  };
}
