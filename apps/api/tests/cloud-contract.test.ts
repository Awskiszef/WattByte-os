// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import {
  CLOUD_EXPORT_MAX_ROWS,
  CLOUD_EXPORT_SCHEMA_VERSION,
  CloudExportAccount,
  type CloudExportDailyUsage,
  CloudExportDevice,
  CloudExportSettings,
  type DailyUsageDto,
  type DeviceDto,
  DeviceDto as DeviceDtoSchema,
  DesignCapacitySource,
  FullChargeCapacityConfidence,
  FullChargeCapacitySource,
  type UserDto,
  UserDto as UserDtoSchema,
  UserSettingsDto,
} from '@wattbyte/contracts';
import { afterEach, beforeEach, describe, expect, expectTypeOf, it } from 'vitest';
import type { z } from 'zod';

import { makeApp, type TestContext } from './helpers.js';

// The cloud-data contracts live in a leaf module and restate the shape of some DTOs from index.ts
// (importing them would be a load-time cycle). These checks make the compiler and the tests fail when they drift.
describe('cloud-data contracts stay in step with the DTOs they mirror', () => {
  it('has the same types (checked by tsc via `pnpm typecheck`)', () => {
    expectTypeOf<z.infer<typeof CloudExportDevice>>().toEqualTypeOf<DeviceDto>();
    expectTypeOf<z.infer<typeof CloudExportAccount>>().toEqualTypeOf<UserDto>();
    // The export row is the DailyUsageDto of the sync plus the device it belongs to.
    expectTypeOf<Omit<z.infer<typeof CloudExportDailyUsage>, 'deviceId'>>().toEqualTypeOf<DailyUsageDto>();
    expectTypeOf<z.infer<typeof CloudExportDailyUsage>['deviceId']>().toEqualTypeOf<string>();
  });

  it('accepts what the originals produce, with the same keys', () => {
    const device = {
      id: '11111111-1111-4111-8111-111111111111',
      installationId: 'install-1234',
      platform: 'ios',
      model: null,
      modelIdentifier: 'iPhone16,1',
      designCapacityMah: 3274,
      designCapacityWh: 12.7,
      designCapacitySource: 'localDeviceDatabase',
      estimatedFullChargeCapacityMah: 3190.5,
      estimatedFullChargeCapacityWh: 12.2,
      fullChargeCapacitySource: 'androidChargeCounter',
      fullChargeCapacityConfidence: 'high',
      createdAt: '2026-10-13T10:00:00.000Z',
      lastSeenAt: '2026-10-13T10:00:00.000Z',
    };
    expect(DeviceDtoSchema.parse(device)).toEqual(CloudExportDevice.parse(device));
    expect(Object.keys(CloudExportDevice.shape)).toEqual(Object.keys(DeviceDtoSchema.shape));
    expect(Object.keys(CloudExportAccount.shape)).toEqual(Object.keys(UserDtoSchema.shape));
    // The export restates the three battery enums: members and order must match the contract's enums.
    expect(CloudExportDevice.shape.designCapacitySource.unwrap().options).toEqual(DesignCapacitySource.options);
    expect(CloudExportDevice.shape.designCapacitySource.unwrap().options).toEqual(DeviceDtoSchema.shape.designCapacitySource.unwrap().options);
    expect(CloudExportDevice.shape.fullChargeCapacitySource.unwrap().options).toEqual(FullChargeCapacitySource.options);
    expect(CloudExportDevice.shape.fullChargeCapacitySource.unwrap().options).toEqual(DeviceDtoSchema.shape.fullChargeCapacitySource.unwrap().options);
    expect(CloudExportDevice.shape.fullChargeCapacityConfidence.unwrap().options).toEqual(FullChargeCapacityConfidence.options);
    expect(CloudExportDevice.shape.fullChargeCapacityConfidence.unwrap().options).toEqual(DeviceDtoSchema.shape.fullChargeCapacityConfidence.unwrap().options);
    // Design capacity has no measurement member, and the estimate no design member: the semantics stay apart.
    expect(DesignCapacitySource.options).not.toContain('androidChargeCounter');
    expect(DesignCapacitySource.options).not.toContain('system');
    expect(DesignCapacitySource.options).not.toContain('estimated');
    expect(FullChargeCapacitySource.options).not.toContain('manual');
    expect(FullChargeCapacitySource.options).not.toContain('localDeviceDatabase');
    expect(CloudExportAccount.shape.plan.options).toEqual(UserDtoSchema.shape.plan.options);
    expect(CloudExportSettings.shape.electricityPriceMode.options).toEqual(UserSettingsDto.shape.electricityPriceMode.options);
    expect(Object.keys(CloudExportSettings.shape)).toEqual(Object.keys(UserSettingsDto.shape));
  });

  it('documents the version and the row cap', () => {
    expect(CLOUD_EXPORT_SCHEMA_VERSION).toBe(1);
    expect(CLOUD_EXPORT_MAX_ROWS).toBe(10_000);
  });
});

describe('OpenAPI document', () => {
  let ctx: TestContext;
  beforeEach(async () => {
    ctx = await makeApp();
  });
  afterEach(() => ctx.app.close());

  it('lists both routes with bearer auth, their query parameters and named components', () => {
    const spec = ctx.app.swagger() as unknown as {
      paths: Record<string, Record<string, { security?: unknown; parameters?: { name: string; in: string }[]; responses: Record<string, unknown> }>>;
      components: { schemas: Record<string, unknown> };
    };
    const del = spec.paths['/api/v1/me/cloud-data']?.delete;
    const exp = spec.paths['/api/v1/me/export']?.get;
    expect(del?.security).toEqual([{ bearerAuth: [] }]);
    expect(exp?.security).toEqual([{ bearerAuth: [] }]);
    expect(del?.parameters?.map((p) => [p.name, p.in])).toEqual([['devices', 'query']]);
    expect(exp?.parameters?.map((p) => [p.name, p.in])).toEqual([['format', 'query']]);
    expect(Object.keys(del?.responses ?? {})).toEqual(expect.arrayContaining(['200', '400', '401', '429']));
    expect(Object.keys(exp?.responses ?? {})).toEqual(expect.arrayContaining(['200', '400', '401', '429']));
    for (const name of [
      'CloudDataDeleteResponse', 'CloudDataDeletedCounts', 'CloudExportDocument', 'CloudExportSettings', 'CloudExportDailyUsage',
      'CloudExportChargingSummary', 'CloudExportMonthlySummary', 'CloudExportAiGeneration', 'CloudExportSubscription', 'CloudExportLimits', 'CloudExportTruncated',
    ]) {
      expect(spec.components.schemas[name], name).toBeDefined();
    }
  });

  // The component registry replaces JSON-identical schemas by a $ref to the registered one. The export's account and
  // device rows are identical to UserDto and DeviceDto, so they must resolve to those, and must not rename them.
  it('reuses UserDto and DeviceDto for the export, and leaves the existing models alone', () => {
    const spec = ctx.app.swagger() as unknown as {
      paths: Record<string, Record<string, { responses: Record<string, { content?: { 'application/json'?: { schema?: { $ref?: string } } } }> }>>;
      components: { schemas: Record<string, { properties?: Record<string, { $ref?: string; items?: { $ref?: string } }> }> };
    };
    const doc = spec.components.schemas.CloudExportDocument?.properties;
    expect(doc?.account?.$ref).toBe('#/components/schemas/UserDto');
    expect(doc?.devices?.items?.$ref).toBe('#/components/schemas/DeviceDto');
    expect(spec.components.schemas.CloudExportAccount).toBeUndefined();
    expect(spec.components.schemas.CloudExportDevice).toBeUndefined();
    const ref = (path: string, method: string, status: string) => spec.paths[path]?.[method]?.responses[status]?.content?.['application/json']?.schema?.$ref;
    expect(ref('/api/v1/me', 'get', '200')).toBe('#/components/schemas/UserDto');
    expect(ref('/api/v1/devices', 'post', '201')).toBe('#/components/schemas/DeviceDto');
    expect(ref('/api/v1/auth/register', 'post', '201')).toBe('#/components/schemas/AuthResponse');
    expect(spec.components.schemas.AuthResponse?.properties?.user?.$ref).toBe('#/components/schemas/UserDto');
    expect(spec.components.schemas.DeviceListResponse?.properties?.devices?.items?.$ref).toBe('#/components/schemas/DeviceDto');
  });
});
