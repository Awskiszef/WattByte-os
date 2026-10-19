import { ErrorResponse, UpdateMeRequest, UpdateUserSettingsRequest, UserDto, UserSettingsDto } from '@wattbyte/contracts';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import type { Repositories, SettingOrigin, UserSettingsRow } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import { toUserDto } from '../auth/service.js';
import type { TokenService } from '../auth/tokens.js';

export interface UsersRoutesOptions {
  repos: Repositories;
  tokens: TokenService;
}

export function toSettingsDto(s: UserSettingsRow | null, userId: string) {
  const row: UserSettingsRow = s ?? {
    userId,
    countryCode: null,
    countryCodeSource: null,
    currencyCode: null,
    currencyCodeSource: null,
    electricityPriceMode: 'automatic',
    manualPricePerKwh: null,
    electricityPriceSource: null,
    updatedAt: new Date(0),
  };
  return {
    countryCode: row.countryCode,
    countryCodeSource: row.countryCodeSource,
    currencyCode: row.currencyCode,
    currencyCodeSource: row.currencyCodeSource,
    electricityPriceMode: row.electricityPriceMode,
    manualElectricityPrice: row.manualPricePerKwh,
    electricityPriceSource: row.electricityPriceSource,
    updatedAt: row.updatedAt.toISOString(),
  };
}

/**
 * What a value's stored origin becomes after a write (`undefined` = keep what is stored).
 *
 * * An origin the client sent is stored (generated clients send an unset field as `null`, which means "not given").
 * * Without one, the stored origin survives only while the value it describes is unchanged: an origin is never carried over
 *   to a different value, and the server does not guess a new one (an older client that does not know the field leaves it
 *   unknown).
 * * A value that ends up cleared has no origin.
 */
function nextSource(given: SettingOrigin | null | undefined, changed: boolean, cleared = false): SettingOrigin | null | undefined {
  if (cleared) return null;
  if (given != null) return given;
  return changed ? null : undefined;
}

export const usersRoutes: FastifyPluginAsyncZod<UsersRoutesOptions> = async (app, { repos, tokens }) => {
  const auth = requireAuth(tokens);
  const security = [{ bearerAuth: [] }];

  app.get(
    '/me/settings',
    {
      preHandler: auth,
      schema: {
        tags: ['account'],
        summary: 'Account-level preferences (region, currency, electricity price mode) with the origin of each value; defaults before the first save',
        security,
        response: { 200: UserSettingsDto, 401: ErrorResponse },
      },
    },
    async (request) => {
      const { userId } = currentUser(request);
      return toSettingsDto(await repos.settings.get(userId), userId);
    },
  );

  app.put(
    '/me/settings',
    {
      preHandler: auth,
      schema: {
        tags: ['account'],
        summary: 'Update account-level preferences and the origin of each value; omitted fields keep their value',
        security,
        body: UpdateUserSettingsRequest,
        response: { 200: UserSettingsDto, 400: ErrorResponse, 401: ErrorResponse },
      },
    },
    async (request) => {
      const { userId } = currentUser(request);
      const b = request.body;
      // The state after the update must hold together: manual mode needs a price. For the mode `null` means "not given"
      // (generated clients send every unset field as null), for the price it means "no price"; `undefined` keeps what is stored.
      const stored = await repos.settings.get(userId);
      const mode = b.electricityPriceMode ?? stored?.electricityPriceMode ?? 'automatic';
      const price = b.manualElectricityPrice === undefined ? (stored?.manualPricePerKwh ?? null) : b.manualElectricityPrice;
      if (mode === 'manual' && price == null) throw HttpError.badRequest('manual_price_required', 'manual mode needs manualElectricityPrice');
      const countryChanged = b.countryCode !== undefined && b.countryCode !== (stored?.countryCode ?? null);
      const currencyChanged = b.currencyCode !== undefined && b.currencyCode !== (stored?.currencyCode ?? null);
      const priceChanged = mode !== (stored?.electricityPriceMode ?? 'automatic') || price !== (stored?.manualPricePerKwh ?? null);
      const row = await repos.settings.update(userId, {
        countryCode: b.countryCode === undefined ? undefined : b.countryCode,
        countryCodeSource: nextSource(b.countryCodeSource, countryChanged, b.countryCode === null),
        currencyCode: b.currencyCode === undefined ? undefined : b.currencyCode,
        currencyCodeSource: nextSource(b.currencyCodeSource, currencyChanged, b.currencyCode === null),
        electricityPriceMode: b.electricityPriceMode,
        manualPricePerKwh: b.manualElectricityPrice === undefined ? undefined : b.manualElectricityPrice,
        electricityPriceSource: nextSource(b.electricityPriceSource, priceChanged),
      });
      return toSettingsDto(row, userId);
    },
  );

  app.get(
    '/me',
    { preHandler: auth, schema: { tags: ['account'], security, response: { 200: UserDto, 401: ErrorResponse } } },
    async (request) => {
      const user = await repos.users.findById(currentUser(request).userId);
      if (!user) throw HttpError.unauthorized();
      return toUserDto(user);
    },
  );

  app.patch(
    '/me',
    {
      preHandler: auth,
      schema: { tags: ['account'], security, body: UpdateMeRequest, response: { 200: UserDto, 401: ErrorResponse } },
    },
    async (request) => {
      const user = await repos.users.updateDisplayName(currentUser(request).userId, request.body.displayName);
      if (!user) throw HttpError.unauthorized();
      return toUserDto(user);
    },
  );

  app.delete(
    '/me',
    {
      preHandler: auth,
      schema: {
        tags: ['account'],
        summary: 'Delete the account and every cloud record (GDPR erasure)',
        security,
        response: { 204: z.null(), 401: ErrorResponse },
      },
    },
    async (request, reply) => {
      await repos.users.delete(currentUser(request).userId);
      return reply.status(204).send(null);
    },
  );
};
