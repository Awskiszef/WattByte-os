import { DeviceDto, DeviceListResponse, DeviceRegisterRequest, DeviceSpecificationDto, DeviceSpecificationParams, ErrorResponse } from '@wattbyte/contracts';
import { lookupDeviceSpecification } from '@wattbyte/device-specs';
import type { FastifyRequest } from 'fastify';
import type { FastifyPluginAsyncZod } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { DeviceLimitReached } from '../../database/memory.js';
import type { DeviceRow, Repositories } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';
import { currentUser, requireAuth } from '../../middleware/auth.js';
import type { TokenService } from '../auth/tokens.js';
import { validateBatteryCapacityGroups } from './battery-capacity.js';

export interface DevicesRoutesOptions {
  repos: Repositories;
  tokens: TokenService;
  /** Installations one account may hold (see MAX_DEVICES_PER_ACCOUNT). */
  maxDevices?: number;
  /** POST /devices per signed-in account per minute. */
  writeRateLimitMax?: number;
}

/**
 * Resolution of the capacity columns: mAh is numeric(8,1), Wh numeric(8,3), for the design and the
 * estimated full-charge capacity alike. A smaller value is rounded to 0 by the column and trips its
 * `> 0` check, which would surface as a 500 for plainly invalid input. (The request schema bounds the
 * values too; this guards the route if the schema is ever loosened.)
 */
const MIN_CAPACITY_MAH = 0.1;
const MIN_CAPACITY_WH = 0.001;

export function toDeviceDto(d: DeviceRow) {
  return {
    id: d.id,
    installationId: d.installationId,
    platform: d.platform,
    model: d.model,
    modelIdentifier: d.modelIdentifier,
    designCapacityMah: d.designCapacityMah,
    designCapacityWh: d.designCapacityWh,
    designCapacitySource: d.designCapacitySource,
    estimatedFullChargeCapacityMah: d.estimatedFullChargeCapacityMah,
    estimatedFullChargeCapacityWh: d.estimatedFullChargeCapacityWh,
    fullChargeCapacitySource: d.fullChargeCapacitySource,
    fullChargeCapacityConfidence: d.fullChargeCapacityConfidence,
    createdAt: d.createdAt.toISOString(),
    lastSeenAt: d.lastSeenAt.toISOString(),
  };
}

export const devicesRoutes: FastifyPluginAsyncZod<DevicesRoutesOptions> = async (app, { repos, tokens, maxDevices, writeRateLimitMax }) => {
  const auth = requireAuth(tokens);
  const security = [{ bearerAuth: [] }];

  app.get(
    '/devices',
    { preHandler: auth, schema: { tags: ['devices'], security, response: { 200: DeviceListResponse, 401: ErrorResponse } } },
    async (request) => ({ devices: (await repos.devices.listForUser(currentUser(request).userId)).map(toDeviceDto) }),
  );

  app.post(
    '/devices',
    {
      preHandler: auth,
      // Per signed-in ACCOUNT (the global limit is per address): rotating addresses does not multiply it.
      config: { rateLimit: { max: writeRateLimitMax ?? 30, timeWindow: '1 minute', groupId: 'cloud-write', hook: 'preHandler', keyGenerator: (request: FastifyRequest) => `user:${request.user?.userId ?? request.ip}` } },
      schema: {
        tags: ['devices'],
        summary: 'Register (or refresh) this installation; idempotent per installationId',
        description:
          'An account holds at most MAX_DEVICES_PER_ACCOUNT installations: registering one more answers 409 device_limit_reached (delete an old device with DELETE /devices/{id}); refreshing an installation the account already has always works. Battery capacity travels in two groups that are stored atomically: the design capacity of the model (designCapacityMah / designCapacityWh / designCapacitySource) and the estimated full-charge capacity of this battery (estimatedFullChargeCapacityMah / estimatedFullChargeCapacityWh / fullChargeCapacitySource / fullChargeCapacityConfidence). A group whose source is given replaces the stored group as a whole (nulls included); a group with a null source leaves the stored one untouched. A design capacity needs a source other than unknown; an estimate needs source androidChargeCounter and a confidence; Wh needs mAh. Violations are 400 validation.',
        security,
        body: DeviceRegisterRequest,
        response: { 201: DeviceDto, 400: ErrorResponse, 401: ErrorResponse, 409: ErrorResponse, 429: ErrorResponse },
      },
    },
    async (request, reply) => {
      const body = request.body;
      for (const field of ['designCapacityMah', 'estimatedFullChargeCapacityMah'] as const) {
        const value = body[field];
        if (value != null && value < MIN_CAPACITY_MAH) throw HttpError.badRequest('validation', `${field} must be at least ${MIN_CAPACITY_MAH}`);
      }
      for (const field of ['designCapacityWh', 'estimatedFullChargeCapacityWh'] as const) {
        const value = body[field];
        if (value != null && value < MIN_CAPACITY_WH) throw HttpError.badRequest('validation', `${field} must be at least ${MIN_CAPACITY_WH}`);
      }
      validateBatteryCapacityGroups(body);
      // The owner comes last on purpose: nothing in the body may ever choose whose device this is.
      const device = await repos.devices
        .upsert({ ...request.body, userId: currentUser(request).userId }, { maxDevices })
        .catch((e: unknown) => {
          if (e instanceof DeviceLimitReached) throw HttpError.conflict('device_limit_reached', `This account already has ${e.max} devices; remove one you no longer use to add another`);
          throw e;
        });
      return reply.status(201).send(toDeviceDto(device));
    },
  );

  // Public: a model code is not personal data, and the app needs it before it has an account in some flows.
  app.get(
    '/devices/specifications/:identifier',
    {
      config: { public: true },
      schema: {
        tags: ['devices'],
        summary: 'Design (nominal) battery capacity for a model identifier (iOS utsname.machine or Android Build.MODEL)',
        description: 'Served from the shared device catalog (packages/device-specs); every figure is a design capacity of the model, never a measurement. 404 when the model is not listed; the app then reports the capacity as unknown rather than guessing.',
        params: DeviceSpecificationParams,
        response: { 200: DeviceSpecificationDto, 400: ErrorResponse, 404: ErrorResponse },
      },
    },
    async (request) => {
      const spec = lookupDeviceSpecification(request.params.identifier);
      if (!spec) throw HttpError.notFound('device_specification_unknown', 'No specification for this model identifier');
      return spec;
    },
  );

  app.delete(
    '/devices/:id',
    {
      preHandler: auth,
      schema: {
        tags: ['devices'],
        security,
        params: z.object({ id: z.string().uuid() }),
        response: { 204: z.null(), 401: ErrorResponse, 404: ErrorResponse },
      },
    },
    async (request, reply) => {
      const ok = await repos.devices.delete(currentUser(request).userId, request.params.id);
      if (!ok) throw HttpError.notFound('device_not_found', 'Device not found');
      return reply.status(204).send(null);
    },
  );
};
