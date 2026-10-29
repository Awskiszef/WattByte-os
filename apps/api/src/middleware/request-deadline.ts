import type { FastifyReply, FastifyRequest } from 'fastify';

/**
 * Cuts the connection of a client that does not deliver its whole request body within `timeoutMs` (B-06).
 *
 * Node's `requestTimeout` only covers the time until the headers are complete; a client that announces a body
 * (`Content-Length`) and then stalls, or trickles one byte at a time, would otherwise hold its socket and its
 * file descriptor for ever, on public routes included. The deadline runs from the start of the request until
 * the body has arrived: once the request is complete the timer is gone, so a slow handler (an AI call)
 * is never affected.
 */
export function requestBodyDeadline(timeoutMs: number) {
  return (request: FastifyRequest, _reply: FastifyReply, done: () => void): void => {
    const raw = request.raw;
    if (raw.complete) {
      done();
      return;
    }
    const timer = setTimeout(() => {
      if (!raw.complete) {
        request.log.warn({ timeoutMs }, 'request body not received in time; closing the connection');
        raw.socket.destroy();
      }
    }, timeoutMs);
    timer.unref();
    const clear = (): void => clearTimeout(timer);
    raw.once('end', clear);
    raw.once('close', clear);
    raw.once('error', clear);
    done();
  };
}
