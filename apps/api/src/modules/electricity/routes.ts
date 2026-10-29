import { ElectricityPriceDto, ElectricityPriceQuery, ErrorResponse } from '@wattbyte/contracts';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import type { TokenService } from '../auth/tokens.js';
import { PriceUnavailableError, type ElectricityPriceService } from './service.js';
import type { Repositories } from '../../database/repositories.js';

export interface ElectricityRoutesOptions {
  service: ElectricityPriceService;
  repos: Repositories;
  tokens: TokenService;
}

export const electricityRoutes: FastifyPluginAsyncZod<ElectricityRoutesOptions> = async (app, { service, repos, tokens }) => {
  app.get(
    '/electricity-price',
    {
      preHandler: requireAuth(tokens),
      schema: {
        tags: ['electricity'],
        summary: 'Average household electricity price per kWh for a country (defaults to the account country)',
        description:
          'A statistical average from a public source (Eurostat nrg_pc_204, band DC, taxes included), cached server-side. ' +
          'Never a wholesale or spot price and never the user\'s own tariff. 404 when no source covers the country.',
        security: [{ bearerAuth: [] }],
        querystring: ElectricityPriceQuery,
        response: { 200: ElectricityPriceDto, 400: ErrorResponse, 401: ErrorResponse, 404: ErrorResponse, 503: ErrorResponse },
      },
    },
    async (request) => {
      let country = request.query.country;
      if (!country) {
        country = (await repos.settings.get(currentUser(request).userId))?.countryCode ?? undefined;
        if (!country) throw HttpError.badRequest('country_required', 'Pass ?country=XX or save a country in the account settings');
      }
      try {
        return await service.get(country);
      } catch (e) {
        if (!(e instanceof PriceUnavailableError)) throw e;
        // "Not covered" is an answer (404); "the source failed and nothing is cached" is an outage (503, try again).
        if (e.reason === 'not_covered') throw HttpError.notFound('electricity_price_unavailable', `No household electricity price source covers ${country}`);
        throw new HttpError(503, 'electricity_price_unavailable', 'The price source is temporarily unavailable', e.retryAfterSec ?? 60);
      }
    },
  );
};
