import type { FastifyServerOptions } from 'fastify';

/**
 * Structured (JSON) logging that can be shipped to a log service without a privacy review of every line.
 *
 * What a log line may contain: request id, method, route path, status, timings, provider id / model /
 * latency / token counts, error type + code + stack frames.
 *
 * What it must never contain: Authorization / Cookie headers, passwords, access or refresh tokens,
 * request or response bodies, AI prompt or answer text, e-mail addresses, client IP addresses.
 * Three layers enforce that:
 *  1. serializers: `req` is reduced to method + route path (no headers, no query, no address) and `err`
 *     drops the message, because database and library errors echo the offending value
 *     (`Key (lower(email))=(a@b.co) already exists`);
 *  2. `redact`: censors the usual secret field names should a developer ever log an object that has them;
 *  3. call sites log named fields, never `request.body` / `request.headers`.
 */

export const LOG_CENSOR = '[Redacted]';

/** pino `redact` paths: defence in depth for objects logged by hand. */
export const REDACT_PATHS: string[] = [
  'req.headers.authorization',
  'req.headers.cookie',
  'req.headers["set-cookie"]',
  'res.headers["set-cookie"]',
  'headers.authorization',
  'headers.cookie',
  '*.authorization',
  '*.cookie',
  '*.password',
  '*.passwordHash',
  '*.refreshToken',
  '*.accessToken',
  '*.idToken',
  '*.token',
  '*.email',
  '*.body',
  '*.prompt',
  '*.input',
  '*.output',
  'authorization',
  'cookie',
  'password',
  'passwordHash',
  'refreshToken',
  'accessToken',
  'idToken',
  'token',
  'email',
  'body',
  'prompt',
];

/** Only the stack frames: the first lines of `stack` repeat the message. */
function stackFrames(stack: string | undefined): string {
  return (stack ?? '')
    .split('\n')
    .filter((line) => /^\s+at /.test(line))
    .slice(0, 12)
    .join('\n');
}

type LoggerOptions = Exclude<NonNullable<FastifyServerOptions['logger']>, boolean>;
type Serializers = NonNullable<LoggerOptions['serializers']>;

export const logSerializers: Serializers = {
  req: (request) => ({
    method: request.method,
    // The route pattern (`/api/v1/devices/:id`) is what identifies an endpoint; undefined for an unknown route.
    route: request.routeOptions?.url,
    // Never inspect the raw URL: it can contain private identifiers or adversarially long segments.
    // Keep the existing `url` field, but only with a server-defined route template or a constant.
    url: request.routeOptions?.url ?? '[unmatched]',
  }),
  res: (reply) => ({ statusCode: reply.statusCode }),
  err: (err) => {
    const code = (err as { code?: unknown }).code;
    return {
      type: err.name,
      // Library errors carry user data in their message and detail fields; the code is enough to find the cause.
      message: 'omitted',
      code: typeof code === 'string' && /^[A-Za-z0-9_]{1,40}$/.test(code) ? code : undefined,
      stack: stackFrames(err.stack),
    };
  },
};

export interface LoggerConfig {
  level: string;
  /** Tests capture the stream; production writes to stdout. */
  stream?: { write(msg: string): void };
}

export function buildLoggerOptions(config: LoggerConfig): LoggerOptions & { redact: { paths: string[]; censor: string } } {
  return {
    level: config.level,
    redact: { paths: REDACT_PATHS, censor: LOG_CENSOR },
    serializers: logSerializers,
    ...(config.stream ? { stream: config.stream } : {}),
  };
}
