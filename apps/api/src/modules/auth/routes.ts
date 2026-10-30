// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { AuthResponse, ErrorResponse, LoginRequest, LogoutRequest, RefreshRequest, RegisterRequest } from '@wattbyte/contracts';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import type { TokenService } from './tokens.js';
import type { AuthService } from './service.js';

export interface AuthRoutesOptions {
  service: AuthService;
  tokens: TokenService;
  /** Per-IP requests per minute on credential endpoints (default 10); one bucket shared by register, login and the OAuth routes. */
  rateLimitMax?: number;
  /** Per-IP requests per minute on /auth/refresh (default 60); its own bucket. */
  refreshRateLimitMax?: number;
}

export const authRoutes: FastifyPluginAsyncZod<AuthRoutesOptions> = async (app, { service, tokens, rateLimitMax, refreshRateLimitMax }) => {
  /** Stricter per-route limit: credential endpoints are the brute-force surface. Public: they are how a caller gets a token. */
  // One `groupId` for all of them: a caller does not get a separate budget per credential route (A-02).
  const strict = { config: { public: true, rateLimit: { max: rateLimitMax ?? 10, timeWindow: '1 minute', groupId: 'credentials' } } };
  app.post(
    '/auth/register',
    {
      ...strict,
      schema: {
        tags: ['auth'],
        summary: 'Create an email + password account',
        body: RegisterRequest,
        response: { 201: AuthResponse, 400: ErrorResponse, 409: ErrorResponse },
      },
    },
    async (request, reply) => reply.status(201).send(await service.register(request.body)),
  );

  app.post(
    '/auth/login',
    {
      ...strict,
      schema: { tags: ['auth'], body: LoginRequest, response: { 200: AuthResponse, 400: ErrorResponse, 401: ErrorResponse } },
    },
    async (request) => service.login(request.body),
  );

  app.post(
    '/auth/refresh',
    {
      config: { public: true, rateLimit: { max: refreshRateLimitMax ?? 60, timeWindow: '1 minute', groupId: 'refresh' } },
      schema: {
        tags: ['auth'],
        summary: 'Exchange a refresh token for a new pair (rotation)',
        body: RefreshRequest,
        response: { 200: AuthResponse, 400: ErrorResponse, 401: ErrorResponse },
      },
    },
    async (request) => service.refresh(request.body.refreshToken),
  );

  app.post(
    '/auth/logout',
    { config: { public: true }, schema: { tags: ['auth'], body: LogoutRequest, response: { 204: z.null(), 400: ErrorResponse } } },
    async (request, reply) => {
      await service.logout(request.body.refreshToken);
      return reply.status(204).send(null);
    },
  );

  app.post(
    '/auth/logout-all',
    {
      preHandler: requireAuth(tokens),
      schema: {
        tags: ['auth'],
        summary: 'Sign out every device: all refresh tokens are revoked and every access token issued so far stops working',
        security: [{ bearerAuth: [] }],
        response: { 204: z.null(), 401: ErrorResponse },
      },
    },
    async (request, reply) => {
      await service.logoutAll(currentUser(request).userId);
      return reply.status(204).send(null);
    },
  );

  for (const provider of ['apple', 'google'] as const) {
    app.post(
      `/auth/${provider}`,
      {
        ...strict,
        schema: {
          tags: ['auth'],
          summary: `Sign in with ${provider === 'apple' ? 'Apple' : 'Google'} (not configured yet)`,
          body: z.object({ idToken: z.string().min(10) }),
          response: { 200: AuthResponse, 501: ErrorResponse },
        },
      },
      async () => {
        throw HttpError.notImplemented('not_configured', `Sign in with ${provider} requires provider credentials`);
      },
    );
  }
};
