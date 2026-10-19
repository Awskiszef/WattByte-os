import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import type { Socket } from 'node:net';
import type { AddressInfo } from 'node:net';

export interface LoopbackServer {
  /** `http://127.0.0.1:<port>`; no path. */
  readonly origin: string;
  readonly requests: { method: string; url: string; headers: IncomingMessage['headers']; body: string }[];
  /** Responses whose connection was closed by the client before the server answered. */
  readonly aborted: () => number;
  close(): Promise<void>;
}

/** A real HTTP server on the loopback interface: exercises the real fetch, sockets and abort path. */
export async function startServer(handler: (req: IncomingMessage, res: ServerResponse, body: string) => void): Promise<LoopbackServer> {
  const requests: LoopbackServer['requests'] = [];
  let aborted = 0;
  const sockets = new Set<Socket>();
  const server: Server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      requests.push({ method: req.method ?? '', url: req.url ?? '', headers: req.headers, body });
      res.on('close', () => {
        if (!res.writableEnded) aborted += 1;
      });
      handler(req, res, body);
    });
  });
  server.on('connection', (s) => {
    sockets.add(s);
    s.on('close', () => sockets.delete(s));
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    origin: `http://127.0.0.1:${port}`,
    requests,
    aborted: () => aborted,
    close: () =>
      new Promise<void>((resolve) => {
        for (const s of sockets) s.destroy();
        server.close(() => resolve());
      }),
  };
}

/** Polls until `predicate` holds or `timeoutMs` passes. */
export async function waitFor(predicate: () => boolean, timeoutMs = 5000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return true;
    await new Promise((r) => setTimeout(r, 10));
  }
  return predicate();
}
