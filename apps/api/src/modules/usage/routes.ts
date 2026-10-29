import { ErrorResponse, UsageDailyQuery, UsageDailyResponse, UsageSyncRequest, UsageSyncResponse } from '@wattbyte/contracts';
import type { FastifyRequest } from 'fastify';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

import type { DailyUsageRow, Repositories } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import { type FeatureFlags, requireFeature } from '../../features/flags.js';
import type { TokenService } from '../auth/tokens.js';

export interface UsageRoutesOptions {
  repos: Repositories;
  tokens: TokenService;
  features: FeatureFlags;
  /** POST /usage/sync per signed-in account per minute. */
  writeRateLimitMax?: number;
}

const MAX_RANGE_DAYS = 366;

export { mergeByDate } from './merge.js';

export const usageRoutes: FastifyPluginAsyncZod<UsageRoutesOptions> = async (app, { repos, tokens, features, writeRateLimitMax }) => {
  const auth = requireAuth(tokens);
  const security = [{ bearerAuth: [] }];
  /** `FEATURE_CLOUD_SYNC=0` switches the cloud copy off: 503 `feature_disabled`. */
  const cloudSync = requireFeature(features, 'cloudSync');

  app.post(
    '/usage/sync',
    {
      preHandler: auth,
      preParsing: cloudSync,
      // One budget per signed-in account for registrations and syncs together (C-04); the global limit stays per address.
      config: { rateLimit: { max: writeRateLimitMax ?? 30, timeWindow: '1 minute', groupId: 'cloud-write', hook: 'preHandler', keyGenerator: (request: FastifyRequest) => `user:${request.user?.userId ?? request.ip}` } },
      // 92 days are about 25 KB; the global default (16 KiB) is for every other route.
      bodyLimit: 65_536,
      schema: {
        tags: ['usage'],
        summary: 'Upload per-day aggregates for one installation; safe to repeat',
        security,
        body: UsageSyncRequest,
        response: { 200: UsageSyncResponse, 400: ErrorResponse, 401: ErrorResponse, 404: ErrorResponse, 429: ErrorResponse, 503: ErrorResponse },
      },
    },
    async (request) => {
      const { userId } = currentUser(request);
      const device = await repos.devices.findForUser(userId, request.body.installationId);
      if (!device) throw HttpError.notFound('device_not_registered', 'Register the device first (POST /devices)');
      const dates = request.body.days.map((d) => d.date);
      if (new Set(dates).size !== dates.length) throw HttpError.badRequest('duplicate_date', 'Each date may appear once per request');
      // One day of slack covers every time zone ahead of UTC.
      const latest = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
      if (dates.some((d) => d > latest)) throw HttpError.badRequest('date_in_future', 'Dates in the future are not accepted');
      // Owner and device come last on purpose: nothing in the body may choose whose row this is.
      const rows: DailyUsageRow[] = request.body.days.map((d) => ({ ...d, userId, deviceId: device.id }));
      const accepted = await repos.usage.upsertDaily(rows);
      return { accepted, dates: [...new Set(rows.map((r) => r.date))].sort() };
    },
  );

  app.get(
    '/usage/daily',
    {
      preHandler: auth,
      preParsing: cloudSync,
      schema: {
        tags: ['usage'],
        summary: 'Daily totals across all devices in [from, to]',
        security,
        querystring: UsageDailyQuery,
        response: { 200: UsageDailyResponse, 400: ErrorResponse, 401: ErrorResponse, 503: ErrorResponse },
      },
    },
    async (request) => {
      const { from, to } = request.query;
      if (from > to) throw HttpError.badRequest('invalid_range', '`from` must not be after `to`');
      const days = (Date.parse(to) - Date.parse(from)) / 86_400_000;
      if (days > MAX_RANGE_DAYS) throw HttpError.badRequest('range_too_large', `At most ${MAX_RANGE_DAYS} days`);
      // Summed over the devices in SQL: at most one row per day (<= 367) however many devices and rows the account has.
      return { days: await repos.usage.listDailyTotals(currentUser(request).userId, from, to) };
    },
  );
};
