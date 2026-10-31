// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { FastifyReply, FastifyRequest } from 'fastify';

import type { Repositories } from '../database/repositories.js';
import { HttpError } from '../errors/http-error.js';
import type { AccessClaims, TokenService } from '../modules/auth/tokens.js';

declare module 'fastify' {
  interface FastifyRequest {
    user?: AccessClaims;
  }
  interface FastifyContextConfig {
    /**
     * Route is reachable without a bearer token. Everything else requires one: the app-level
     * `authenticateUnlessPublic` hook rejects anonymous callers before the body is even parsed.
     */
    public?: boolean;
  }
}

/** RFC 7235: the scheme is case-insensitive and separated from the token by one or more spaces. */
const BEARER = /^Bearer +(\S+)$/i;

async function authenticate(tokens: TokenService, request: FastifyRequest): Promise<AccessClaims> {
  const header = request.headers.authorization;
  const match = typeof header === 'string' ? BEARER.exec(header) : null;
  if (!match?.[1]) throw HttpError.unauthorized();
  const claims = await tokens.verifyAccess(match[1]);
  if (!claims) throw HttpError.unauthorized('invalid_token', 'Invalid or expired token');
  return claims;
}

/**
 * Route-level guard: verifies `Authorization: Bearer <jwt>` unless the app-level hook already authenticated the
 * request (which is always the case inside `buildApp`; this stays so a module is safe on its own).
 */
export function requireAuth(tokens: TokenService) {
  return async (request: FastifyRequest, _reply: FastifyReply): Promise<void> => {
    if (request.user) return;
    request.user = await authenticate(tokens, request);
  };
}

/**
 * App-level, deny by default: a route needs a bearer token unless it says `config: { public: true }`.
 * A new route that forgets its own auth hook is therefore protected, not exposed. Unknown paths
 * (404/405) are not authenticated: there is nothing behind them to protect.
 *
 * Besides the signature, the account must still exist: an access token outlives `DELETE /me` by up to
 * `ACCESS_TOKEN_TTL_SEC`, and an erased account's token must open nothing in that time. The plan used for
 * quotas is read from that same row, so a downgrade applies at once instead of when the token expires.
 * Cost: one primary-key lookup per authenticated request.
 */
export function authenticateUnlessPublic(tokens: TokenService, repos: Pick<Repositories, 'users' | 'sessions'>) {
  return async (request: FastifyRequest, _reply: FastifyReply): Promise<void> => {
    if (request.is404 || request.routeOptions.config?.public) return;
    const claims = await authenticate(tokens, request);
    const user = await repos.users.findById(claims.userId);
    if (!user) throw HttpError.unauthorized('account_not_found', 'The account no longer exists');
    // "Sign out everywhere" and a password change refuse the access tokens issued before them (second resolution: a
    // token issued in the same second as the cut-off is still accepted, which is what lets a fresh sign-in through).
    if (user.tokensValidAfter && claims.iat !== undefined && claims.iat < Math.floor(user.tokensValidAfter.getTime() / 1000)) {
      throw HttpError.unauthorized('session_revoked', 'This session was signed out');
    }
    // An access token belongs to a device (its session family): once that device is signed out the token stops working at
    // once instead of living on until it expires (A-08). Tokens from before families existed carry no `sid` and are
    // accepted until they expire (at most ACCESS_TOKEN_TTL_SEC).
    if (claims.sid && !(await repos.sessions.familyLive(claims.sid, new Date()))) {
      throw HttpError.unauthorized('session_revoked', 'This session was signed out');
    }
    request.user = { userId: user.id, plan: user.plan, ...(claims.sid ? { sid: claims.sid } : {}) };
  };
}

export function currentUser(request: FastifyRequest): AccessClaims {
  if (!request.user) throw HttpError.unauthorized();
  return request.user;
}
