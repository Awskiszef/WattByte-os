// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

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

/** Identifier-shaped, short: a PostgreSQL schema/table/column/constraint name or a syscall, never a value. */
const SAFE_IDENTIFIER = /^[A-Za-z0-9_$.]{1,63}$/;
const safeIdentifier = (v: unknown): string | undefined => (typeof v === 'string' && SAFE_IDENTIFIER.test(v) ? v : undefined);

/**
 * What identifies a failure without echoing data (B-12). Always: the error type, its `code` (a PostgreSQL SQLSTATE such as
 * `23505` unique violation, `40P01` deadlock, `57014` statement timeout, or a system code such as `ECONNREFUSED`), PostgreSQL's
 * `severity` and the failing `syscall`: enough to tell a dead dependency from a constraint from a bug, together with the route
 * and request id of the same log line. The names of schema objects (`table`, `column`, `constraint`) are NOT logged by default
 * (the privacy test treats them as schema detail); `verbose` (LOG_ERROR_MESSAGES=1, development only) adds them.
 * `detail` and `message` hold the offending VALUES and are never logged outside that switch.
 */
export function safeErrorFields(err: Error, verbose = false): Record<string, string | undefined> {
  const e = err as unknown as Record<string, unknown>;
  const code = e.code;
  return {
    type: err.name,
    code: typeof code === 'string' && /^[A-Za-z0-9_]{1,40}$/.test(code) ? code : undefined,
    severity: safeIdentifier(e.severity),
    syscall: safeIdentifier(e.syscall),
    ...(verbose ? { schema: safeIdentifier(e.schema), table: safeIdentifier(e.table), column: safeIdentifier(e.column), constraint: safeIdentifier(e.constraint) } : {}),
  };
}

/**
 * `verbose` is for local debugging only (LOG_ERROR_MESSAGES=1, refused outside APP_ENV=development): the message of a
 * library error can contain a user's e-mail address or any other value.
 */
export function makeErrSerializer(verbose: boolean): NonNullable<Serializers['err']> {
  return (err) => ({
    ...safeErrorFields(err, verbose),
    type: err.name,
    // Library errors carry user data in their message and detail fields; the code is enough to find the cause.
    message: verbose ? err.message : 'omitted',
    stack: stackFrames(err.stack),
  });
}

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
  err: makeErrSerializer(false),
};

export interface LoggerConfig {
  level: string;
  /** Tests capture the stream; production writes to stdout. */
  stream?: { write(msg: string): void };
  /** Development only (LOG_ERROR_MESSAGES=1): put the error message in the log. */
  includeErrorMessages?: boolean;
}

export function buildLoggerOptions(config: LoggerConfig): LoggerOptions & { redact: { paths: string[]; censor: string } } {
  return {
    level: config.level,
    redact: { paths: REDACT_PATHS, censor: LOG_CENSOR },
    serializers: config.includeErrorMessages ? { ...logSerializers, err: makeErrSerializer(true) } : logSerializers,
    ...(config.stream ? { stream: config.stream } : {}),
  };
}
