import { STATUS_CODES } from 'node:http';

import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';

import { ForeignKeyViolation, UniqueViolation } from '../database/memory.js';

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    /** Seconds until a 429/503 caller may retry; sent as the `retry-after` header. */
    readonly retryAfterSec?: number,
  ) {
    super(message);
    this.name = 'HttpError';
  }

  static badRequest(code: string, message: string): HttpError {
    return new HttpError(400, code, message);
  }
  static unauthorized(code = 'unauthorized', message = 'Authentication required'): HttpError {
    return new HttpError(401, code, message);
  }
  static forbidden(code = 'forbidden', message = 'Not allowed'): HttpError {
    return new HttpError(403, code, message);
  }
  static notFound(code: string, message: string): HttpError {
    return new HttpError(404, code, message);
  }
  static conflict(code: string, message: string): HttpError {
    return new HttpError(409, code, message);
  }
  static tooMany(code: string, message: string, retryAfterSec?: number): HttpError {
    return new HttpError(429, code, message, retryAfterSec);
  }
  static notImplemented(code: string, message: string): HttpError {
    return new HttpError(501, code, message);
  }
  static unavailable(code: string, message: string): HttpError {
    return new HttpError(503, code, message);
  }
}

/**
 * The error contract: every failure, from a handler, a hook, the router or the parser, leaves as
 * `{ "error": { "code", "message" } }` with a status and a machine `code` that stay stable. Clients
 * branch on `code`; `message` is for people and may be reworded. Neither ever carries a stack trace,
 * SQL, a constraint name or a provider's response, whatever went wrong inside.
 *
 * | status | code                                           |
 * |--------|------------------------------------------------|
 * | 400    | `validation`, `invalid_json`, `bad_request`, ...  (route-specific codes) |
 * | 401    | `unauthorized`, `invalid_token`, `invalid_credentials`, ...                |
 * | 403    | `forbidden`                                     |
 * | 404    | `not_found` (unknown route), route-specific codes |
 * | 405    | `method_not_allowed` (+ `allow` header)         |
 * | 409    | `conflict`, `email_taken`                       |
 * | 413    | `payload_too_large`                             |
 * | 415    | `unsupported_media_type`                        |
 * | 429    | `rate_limited`, `ai_quota_exceeded` (+ `retry-after`) |
 * | 500    | `internal`                                      |
 * | 503    | `ai_unavailable`, `feature_disabled`, `service_unavailable`, `electricity_price_unavailable` (+ `retry-after`) |
 */
export interface ErrorBody {
  error: { code: string; message: string };
}

const body = (code: string, message: string): ErrorBody => ({ error: { code, message } });

/** Parser / router failures raised by Fastify itself, mapped to stable codes and fixed texts. */
const FRAMEWORK_ERRORS = new Map<string, { status: number; code: string; message: string }>([
  ['FST_ERR_CTP_INVALID_JSON_BODY', { status: 400, code: 'invalid_json', message: 'The request body is not valid JSON' }],
  ['FST_ERR_CTP_EMPTY_JSON_BODY', { status: 400, code: 'invalid_json', message: 'The request body is empty but a JSON body is required' }],
  ['FST_ERR_CTP_INVALID_CONTENT_LENGTH', { status: 400, code: 'bad_request', message: 'The content-length header does not match the body' }],
  ['FST_ERR_CTP_BODY_TOO_LARGE', { status: 413, code: 'payload_too_large', message: 'The request body is too large' }],
  ['FST_ERR_CTP_INVALID_MEDIA_TYPE', { status: 415, code: 'unsupported_media_type', message: 'Send the body as application/json' }],
  ['FST_ERR_BAD_URL', { status: 400, code: 'bad_request', message: 'The URL is not valid' }],
]);

/** Stable machine code for a bare status the router or a plugin produced. */
const GENERIC_CODES: Readonly<Record<number, string>> = {
  400: 'bad_request',
  401: 'unauthorized',
  403: 'forbidden',
  404: 'not_found',
  405: 'method_not_allowed',
  408: 'request_timeout',
  409: 'conflict',
  413: 'payload_too_large',
  415: 'unsupported_media_type',
  429: 'rate_limited',
};

const MAX_VALIDATION_MESSAGE = 300;
/** Only the first issues are rendered: ZodError.message stringifies all of them, whose count the client chooses. */
const MAX_VALIDATION_ISSUES = 5;

function validationMessage(error: FastifyError): string {
  const issues = (error as { issues?: unknown }).issues;
  if (Array.isArray(issues)) return JSON.stringify(issues.slice(0, MAX_VALIDATION_ISSUES), null, 2).slice(0, MAX_VALIDATION_MESSAGE);
  return error.message.slice(0, MAX_VALIDATION_MESSAGE);
}

/** SQLSTATE classes / codes that mean the database could not serve the request right now (not that the request was wrong). */
const OUTAGE_SQLSTATES = new Set(['53300', '57P01', '57P02', '57P03', '57014', '40001', '40P01', '55P03', '25P03']);
const OUTAGE_NODE_CODES = new Set(['ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT', 'EPIPE', 'EHOSTUNREACH', 'ENOTFOUND', 'EAI_AGAIN']);
const OUTAGE_MESSAGES = /timeout exceeded when trying to connect|Connection terminated|Client has encountered a connection error|Query read timeout|Connection (?:ended|refused)/i;

/**
 * A dependency (PostgreSQL) that cannot serve the request at the moment: connection refused or lost, pool exhausted, a
 * statement or connection timeout, a deadlock or serialization abort, a server shutting down. The caller is told to come
 * back (503 + Retry-After) instead of getting an opaque 500 that looks like a bug and is not retried (B-14).
 */
export function isDependencyOutage(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const e = error as { code?: unknown; message?: unknown };
  const code = typeof e.code === 'string' ? e.code : '';
  if (OUTAGE_SQLSTATES.has(code) || code.startsWith('08') || OUTAGE_NODE_CODES.has(code)) return true;
  return typeof e.message === 'string' && OUTAGE_MESSAGES.test(e.message);
}

/** Seconds a client is asked to wait after a dependency outage. */
const OUTAGE_RETRY_AFTER_SEC = 5;

/** Seconds a rate-limited caller is told to wait when the limiter did not say (its window is one minute). */
const DEFAULT_RETRY_AFTER_SEC = 60;

function send(reply: FastifyReply, status: number, code: string, message: string, retryAfterSec?: number): void {
  if (retryAfterSec !== undefined) void reply.header('retry-after', String(Math.max(1, Math.ceil(retryAfterSec))));
  void reply.status(status).send(body(code, message));
}

export function errorHandler(error: FastifyError, request: FastifyRequest, reply: FastifyReply): void {
  if (error instanceof HttpError) {
    send(reply, error.status, error.code, error.message, error.retryAfterSec);
    return;
  }
  // A valid token whose account was deleted meanwhile: its rows are gone, so writes hit a foreign key.
  if (error instanceof ForeignKeyViolation) {
    send(reply, 401, 'account_not_found', 'The account no longer exists');
    return;
  }
  // A race two requests lost; the constraint name stays on the server.
  if (error instanceof UniqueViolation) {
    send(reply, 409, 'conflict', 'The request conflicts with existing data');
    return;
  }
  if (error.validation) {
    send(reply, 400, 'validation', validationMessage(error));
    return;
  }
  const framework = error.code ? FRAMEWORK_ERRORS.get(error.code) : undefined;
  if (framework) {
    send(reply, framework.status, framework.code, framework.message);
    return;
  }
  if (error.statusCode === 429) {
    send(reply, 429, 'rate_limited', 'Too many requests', reply.getHeader('retry-after') === undefined ? DEFAULT_RETRY_AFTER_SEC : undefined);
    return;
  }
  if (error.statusCode && error.statusCode >= 400 && error.statusCode < 500) {
    // The router or a plugin rejected the request: its own wording is not part of the contract.
    send(reply, error.statusCode, GENERIC_CODES[error.statusCode] ?? 'bad_request', STATUS_CODES[error.statusCode] ?? 'Bad request');
    return;
  }
  if (isDependencyOutage(error)) {
    request.log.warn({ err: error }, 'dependency unavailable');
    send(reply, 503, 'service_unavailable', 'The service is temporarily unavailable, try again shortly', OUTAGE_RETRY_AFTER_SEC);
    return;
  }
  // Anything else is a bug. The error serializer keeps the message out of the log
  // (database errors echo the offending value) and the client only gets the generic text.
  request.log.error({ err: error }, 'unhandled error');
  send(reply, 500, 'internal', 'Internal error');
}

/** Routes registered on the app, collected by an `onRoute` hook: feeds 405 answers and the route audit tests. */
export class RouteTable {
  private readonly entries: { method: string; url: string; pattern: RegExp }[] = [];

  add(method: string | readonly string[], url: string): void {
    for (const m of Array.isArray(method) ? method : [method]) {
      this.entries.push({ method: String(m).toUpperCase(), url, pattern: toPattern(url) });
    }
  }

  all(): { method: string; url: string }[] {
    return this.entries.map(({ method, url }) => ({ method, url }));
  }

  /** Methods that have a route for this path (empty when the path is unknown). */
  allowedMethods(pathname: string): string[] {
    const methods = new Set<string>();
    for (const e of this.entries) if (e.pattern.test(pathname)) methods.add(e.method);
    return [...methods].sort();
  }
}

function toPattern(url: string): RegExp {
  const source = url
    .split('/')
    .map((segment) => (segment.startsWith(':') ? '[^/]+' : segment === '*' ? '.*' : segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
    .join('/');
  return new RegExp(`^${source}$`);
}

/** 404 for an unknown path, 405 (with `allow`) when the path exists for other methods. */
export function notFoundHandler(routes: RouteTable) {
  return (request: FastifyRequest, reply: FastifyReply): void => {
    const pathname = request.url.split(/[?#]/, 1)[0] ?? '';
    const allowed = routes.allowedMethods(pathname);
    if (allowed.length > 0) {
      void reply.header('allow', allowed.join(', '));
      send(reply, 405, 'method_not_allowed', 'This method is not supported on this path');
      return;
    }
    send(reply, 404, 'not_found', 'No such route');
  };
}
