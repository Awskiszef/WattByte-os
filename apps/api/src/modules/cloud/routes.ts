import {
  CLOUD_EXPORT_MAX_ROWS,
  CloudDataDeleteQuery,
  CloudDataDeleteResponse,
  CloudExportDocument,
  CloudExportQuery,
  ErrorResponse,
} from '@wattbyte/contracts';
import type { FastifyReply } from 'fastify';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';

import type { Repositories } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import type { TokenService } from '../auth/tokens.js';
import { dailyUsageCsv } from './csv.js';
import { exportDisposition, toDailyUsageRows, toExportDocument } from './export.js';

export interface CloudRoutesOptions {
  repos: Repositories;
  tokens: TokenService;
}

/** Per-IP requests per minute, stricter than the global limit (120): an export reads up to 10 000 rows per collection. */
export const CLOUD_EXPORT_RATE_LIMIT_PER_MIN = 6;
export const CLOUD_DELETE_RATE_LIMIT_PER_MIN = 10;

const accountGone = () => HttpError.unauthorized('account_not_found', 'The account no longer exists');

/**
 * `DELETE /me/cloud-data` erases synced data but keeps the account; `GET /me/export` returns
 * everything stored about the account. Both answer 401 for a valid token of a deleted account.
 * What they cover, and what they cannot, is in docs/CLOUD_DATA.md.
 */
export const cloudRoutes: FastifyPluginAsyncZod<CloudRoutesOptions> = async (app, { repos, tokens }) => {
  const auth = requireAuth(tokens);
  const security = [{ bearerAuth: [] }];

  app.delete(
    '/me/cloud-data',
    {
      preHandler: auth,
      config: { rateLimit: { max: CLOUD_DELETE_RATE_LIMIT_PER_MIN, timeWindow: '1 minute' } },
      schema: {
        tags: ['account'],
        summary: 'Delete the synced cloud data but keep the account',
        description:
          'Removes, in one transaction, the daily usage, charging and monthly summaries, AI generation log and AI quota counters. ' +
          'Keeps the account, its sessions, subscriptions, settings and registered devices, so sync can resume. ' +
          '`?devices=true` also removes the devices. Idempotent: repeating it deletes nothing and answers zeros.',
        security,
        querystring: CloudDataDeleteQuery,
        response: { 200: CloudDataDeleteResponse, 400: ErrorResponse, 401: ErrorResponse, 429: ErrorResponse },
      },
    },
    async (request) => {
      const { userId } = currentUser(request);
      const deleted = await repos.cloud.deleteData(userId, { devices: request.query.devices === 'true' });
      if (!deleted) throw accountGone();
      // Counts only: log lines carry no user identifier (docs/security.md, Logging); the request id correlates the call.
      request.log.info({ deleted }, 'cloud data deleted');
      return { deleted };
    },
  );

  app.get(
    '/me/export',
    {
      preHandler: auth,
      config: { rateLimit: { max: CLOUD_EXPORT_RATE_LIMIT_PER_MIN, timeWindow: '1 minute' } },
      schema: {
        tags: ['account'],
        summary: 'Export everything stored about the account',
        description:
          'A JSON document (`schemaVersion`, account, settings, devices with design capacity and estimated full-charge capacity, daily usage, charging and monthly summaries, ' +
          'AI generation metadata, subscriptions), sent as an attachment `wattbyte-export-YYYY-MM-DD.json`. Never contains the password hash, ' +
          'sessions or refresh tokens, or another user\'s data. `?format=csv` returns only the daily usage as RFC 4180 `text/csv; charset=utf-8`. ' +
          `At most ${CLOUD_EXPORT_MAX_ROWS} rows per collection (the newest); a cut collection is flagged in \`limits.truncated\` ` +
          '(CSV: header `x-wattbyte-truncated`).',
        security,
        querystring: CloudExportQuery,
        response: { 200: CloudExportDocument, 400: ErrorResponse, 401: ErrorResponse, 429: ErrorResponse },
      },
    },
    async (request, reply) => {
      const { userId } = currentUser(request);
      const exportedAt = new Date();
      const data = await repos.cloud.exportData(userId, CLOUD_EXPORT_MAX_ROWS);
      if (!data) throw accountGone();
      if (request.query.format === 'csv') {
        // The route schema describes the JSON document; `?format=csv` answers with text, so it goes through the untyped reply.
        const text: FastifyReply = reply;
        text.type('text/csv; charset=utf-8').header('content-disposition', exportDisposition(exportedAt, 'csv'));
        if (data.truncated.dailyUsage) text.header('x-wattbyte-truncated', 'dailyUsage');
        return text.send(dailyUsageCsv(toDailyUsageRows(data.dailyUsage)));
      }
      reply.header('content-disposition', exportDisposition(exportedAt, 'json'));
      return toExportDocument(data, exportedAt);
    },
  );
};
