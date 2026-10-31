// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { RegionResponse } from '@wattbyte/contracts';
import type { FastifyRequest } from 'fastify';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

export interface RegionRoutesOptions {
  /** Request header carrying a country code, e.g. `cf-ipcountry` behind Cloudflare; empty = feature off. */
  countryHeader: string;
  /** True when the request came through a proxy we trust; only then is the header believed (a client can send it too). */
  viaTrustedProxy: (request: FastifyRequest) => boolean;
}

/**
 * Coarse region hint for the app's `RegionDetectionService` (source `backendCountry`),
 * used only when the device's own region/locale settings give nothing. Nothing is
 * stored: the API never logs or keeps the client address or the derived country.
 */
export const regionRoutes: FastifyPluginAsyncZod<RegionRoutesOptions> = async (app, { countryHeader, viaTrustedProxy }) => {
  app.get(
    '/region',
    {
      config: { public: true },
      schema: {
        tags: ['region'],
        summary: 'Country of the caller as seen by the edge proxy, if the deployment provides one',
        response: { 200: RegionResponse },
      },
    },
    async (request) => {
      if (!countryHeader || !viaTrustedProxy(request)) return { countryCode: null, source: 'none' as const };
      const raw = request.headers[countryHeader.toLowerCase()];
      const value = (Array.isArray(raw) ? raw[0] : raw)?.trim().toUpperCase();
      // Cloudflare sends "XX" for unknown and "T1" for Tor; only a real alpha-2 code is useful.
      if (!value || !/^[A-Z]{2}$/.test(value) || value === 'XX' || value === 'T1') return { countryCode: null, source: 'none' as const };
      return { countryCode: value, source: 'backendCountry' as const };
    },
  );
};
