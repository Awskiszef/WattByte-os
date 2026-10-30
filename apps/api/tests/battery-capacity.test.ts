// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { DEVICE_CATALOG, lookupDeviceSpecification } from '@wattbyte/device-specs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { HttpError } from '../src/errors/http-error.js';
import { type BatteryCapacityGroups, validateBatteryCapacityGroups } from '../src/modules/devices/battery-capacity.js';
import { describeBatteryCapacity } from './battery-capacity-suite.js';
import { memoryFixture } from './cloud-support.js';
import { makeApp, type TestContext } from './helpers.js';

// Every register runs a scrypt hash (N=2^16); on a loaded machine it takes seconds.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

// The same suite runs on PostgreSQL in db/battery-capacity.integration.test.ts.
describeBatteryCapacity('memory repositories', memoryFixture);

describe('validateBatteryCapacityGroups', () => {
  const design = { designCapacityMah: 4000, designCapacityWh: 15.4, designCapacitySource: 'localDeviceDatabase' } as const;
  const estimate = {
    estimatedFullChargeCapacityMah: 3600,
    estimatedFullChargeCapacityWh: 13.8,
    fullChargeCapacitySource: 'androidChargeCounter',
    fullChargeCapacityConfidence: 'high',
  } as const;

  const messageOf = (groups: BatteryCapacityGroups): string => {
    try {
      validateBatteryCapacityGroups(groups);
    } catch (e) {
      expect(e).toBeInstanceOf(HttpError);
      expect((e as HttpError).status).toBe(400);
      expect((e as HttpError).code).toBe('validation');
      return (e as HttpError).message;
    }
    return '';
  };

  it.each<[string, BatteryCapacityGroups]>([
    ['nothing given', {}],
    ['every field null', { designCapacityMah: null, designCapacityWh: null, designCapacitySource: null, estimatedFullChargeCapacityMah: null, estimatedFullChargeCapacityWh: null, fullChargeCapacitySource: null, fullChargeCapacityConfidence: null }],
    ['design only', design],
    ['design without Wh', { designCapacityMah: 4000, designCapacitySource: 'manual' }],
    ['estimate only', estimate],
    ['estimate without Wh', { estimatedFullChargeCapacityMah: 3600, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'low' }],
    ['design and estimate', { ...design, ...estimate }],
    ['design unknown', { designCapacitySource: 'unknown' }],
    ['estimate unknown', { fullChargeCapacitySource: 'unknown' }],
    ['both unknown', { designCapacitySource: 'unknown', fullChargeCapacitySource: 'unknown' }],
  ])('accepts %s', (_name, groups) => {
    expect(messageOf(groups)).toBe('');
  });

  it.each<[string, BatteryCapacityGroups, RegExp]>([
    ['design mAh without a source', { designCapacityMah: 4000 }, /need a designCapacitySource/],
    ['design Wh without a source', { designCapacityMah: 4000, designCapacityWh: 15, designCapacitySource: null }, /need a designCapacitySource/],
    ['design unknown with mAh', { designCapacitySource: 'unknown', designCapacityMah: 4000 }, /unknown carries no/],
    ['design unknown with Wh', { designCapacitySource: 'unknown', designCapacityWh: 15 }, /unknown carries no/],
    ['design Wh without mAh', { designCapacitySource: 'manual', designCapacityWh: 15 }, /designCapacityWh needs designCapacityMah/],
    ['design source without a number', { designCapacitySource: 'localDeviceDatabase' }, /needs designCapacityMah/],
    ['estimate mAh without a source', { estimatedFullChargeCapacityMah: 3600, fullChargeCapacityConfidence: 'high' }, /need a fullChargeCapacitySource/],
    ['estimate unknown with mAh', { estimatedFullChargeCapacityMah: 3600, fullChargeCapacitySource: 'unknown', fullChargeCapacityConfidence: 'high' }, /unknown carries no/],
    ['estimate unknown with a confidence', { fullChargeCapacitySource: 'unknown', fullChargeCapacityConfidence: 'low' }, /unknown carries no/],
    ['estimate Wh without mAh', { estimatedFullChargeCapacityWh: 13, fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }, /estimatedFullChargeCapacityWh needs estimatedFullChargeCapacityMah/],
    ['measured source without mAh', { fullChargeCapacitySource: 'androidChargeCounter', fullChargeCapacityConfidence: 'high' }, /androidChargeCounter needs estimatedFullChargeCapacityMah/],
    ['confidence without mAh', { fullChargeCapacityConfidence: 'high' }, /fullChargeCapacityConfidence needs estimatedFullChargeCapacityMah/],
    ['estimate mAh without a confidence', { estimatedFullChargeCapacityMah: 3600, fullChargeCapacitySource: 'androidChargeCounter' }, /needs a fullChargeCapacityConfidence/],
  ])('rejects %s with a message naming the rule', (_name, groups, message) => {
    expect(messageOf(groups)).toMatch(message);
  });

  it('judges the groups independently: a valid estimate does not excuse a broken design group', () => {
    expect(messageOf({ ...estimate, designCapacityMah: 4000 })).toMatch(/designCapacitySource/);
    expect(messageOf({ ...design, estimatedFullChargeCapacityMah: 3600 })).toMatch(/fullChargeCapacitySource/);
  });
});

describe('GET /devices/specifications/:identifier serves design capacity', () => {
  let ctx: TestContext;
  beforeEach(async () => {
    ctx = await makeApp();
  });
  afterEach(() => ctx.app.close());

  it('returns designCapacityMah / designCapacityWh and no pre-split names', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/iPhone16,1' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      manufacturer: 'Apple',
      model: 'iPhone 15 Pro',
      modelIdentifier: 'iPhone16,1',
      designCapacityMah: 3274,
      designCapacityWh: 12.7,
      nominalVoltage: 3.88,
      catalogVersion: DEVICE_CATALOG.version,
    });
  });

  it('answers a model without a published Wh figure with null Wh and null voltage (nothing is derived or guessed)', async () => {
    const res = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/iPhone10,1' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ model: 'iPhone 8', designCapacityMah: 1821, designCapacityWh: null, nominalVoltage: null });
  });

  it('serves exactly what the catalog says for every entry, and 404 for unknown models', async () => {
    for (const entry of DEVICE_CATALOG.devices) {
      const id = entry.identifiers?.[0] ?? `${entry.identifierPrefixes?.[0] ?? ''}XX`;
      const res = await ctx.app.inject({ method: 'GET', url: `/api/v1/devices/specifications/${encodeURIComponent(id)}` });
      expect(res.statusCode, `${entry.model} (${id})`).toBe(200);
      expect(res.json().designCapacityMah, entry.model).toBe(lookupDeviceSpecification(id)?.designCapacityMah);
      expect(res.json().designCapacityMah, entry.model).toBeGreaterThan(0);
    }
    const unknown = await ctx.app.inject({ method: 'GET', url: '/api/v1/devices/specifications/iPhone19,2' });
    expect(unknown.statusCode).toBe(404);
  });
});

describe('OpenAPI document of the device battery fields', () => {
  let ctx: TestContext;
  beforeEach(async () => {
    ctx = await makeApp();
  });
  afterEach(() => ctx.app.close());

  it('names the design and estimate fields and their enums, and not the pre-split ones', async () => {
    const doc = ctx.app.swagger() as { components?: { schemas?: Record<string, { properties?: Record<string, { enum?: string[]; anyOf?: { enum?: string[] }[] }> }> } };
    const schemas = doc.components?.schemas ?? {};
    const text = JSON.stringify(doc);
    expect(text).not.toMatch(/batteryCapacity|batterySpecificationSource/);
    const enumOf = (schema: string, field: string): string[] | undefined => {
      const prop = schemas[schema]?.properties?.[field];
      return prop?.enum ?? prop?.anyOf?.find((a) => a.enum)?.enum;
    };
    for (const schema of ['DeviceRegisterRequest', 'DeviceDto']) {
      expect(enumOf(schema, 'designCapacitySource'), schema).toEqual(['manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual', 'unknown']);
      expect(enumOf(schema, 'fullChargeCapacitySource'), schema).toEqual(['androidChargeCounter', 'unknown']);
      expect(enumOf(schema, 'fullChargeCapacityConfidence'), schema).toEqual(['low', 'medium', 'high']);
    }
    expect(Object.keys(schemas.DeviceSpecificationDto?.properties ?? {}).sort()).toEqual(
      ['catalogVersion', 'designCapacityMah', 'designCapacityWh', 'manufacturer', 'model', 'modelIdentifier', 'nominalVoltage'],
    );
  });
});
