// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';

import { DEVICE_CATALOG, lookupDeviceSpecification } from '../src/index.js';

describe('device specification catalog', () => {
  it('resolves a known iPhone identifier to its published capacity', () => {
    const spec = lookupDeviceSpecification('iPhone16,1');
    expect(spec).toMatchObject({ manufacturer: 'Apple', model: 'iPhone 15 Pro', designCapacityMah: 3274, designCapacityWh: 12.7 });
    expect(spec?.nominalVoltage).toBeCloseTo(3.88, 2);
  });

  it('resolves a Google model name and a Samsung model code by prefix', () => {
    expect(lookupDeviceSpecification('Pixel 8')?.designCapacityMah).toBe(4575);
    expect(lookupDeviceSpecification('pixel 8 pro')?.model).toBe('Pixel 8 Pro');
    expect(lookupDeviceSpecification('SM-S921B')?.model).toBe('Galaxy S24');
    expect(lookupDeviceSpecification('SM-S928U1')?.model).toBe('Galaxy S24 Ultra');
  });

  it('answers null for unknown, empty and absurd identifiers instead of a typical value', () => {
    expect(lookupDeviceSpecification('iPhone19,2')).toBeNull();
    expect(lookupDeviceSpecification('')).toBeNull();
    expect(lookupDeviceSpecification('x'.repeat(65))).toBeNull();
    expect(lookupDeviceSpecification('Nokia 3310')).toBeNull();
  });

  it('every catalog entry has a plausible design capacity and at least one matcher', () => {
    for (const d of DEVICE_CATALOG.devices) {
      expect(typeof d.designCapacityMah, d.model).toBe('number');
      expect(Number.isFinite(d.designCapacityMah), d.model).toBe(true);
      expect(d.designCapacityMah, d.model).toBeGreaterThan(1000);
      expect(d.designCapacityMah, d.model).toBeLessThan(10000);
      expect((d.identifiers?.length ?? 0) + (d.identifierPrefixes?.length ?? 0), d.model).toBeGreaterThan(0);
      if (d.designCapacityWh != null) expect(d.designCapacityWh / (d.designCapacityMah / 1000), d.model).toBeGreaterThan(3.5);
    }
    const ids = DEVICE_CATALOG.devices.flatMap((d) => d.identifiers ?? []);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('the catalog is design capacity only: no entry carries a measurement or the pre-split key names', () => {
    for (const d of DEVICE_CATALOG.devices) {
      const keys = Object.keys(d);
      expect(keys, d.model).toContain('designCapacityMah');
      expect(keys.filter((k) => /^battery|charge|estimated|measured/i.test(k)), d.model).toEqual([]);
    }
  });

  it('a lookup answers design* names only, with the voltage derived from published figures', () => {
    const spec = lookupDeviceSpecification('iPhone16,1');
    expect(spec).not.toBeNull();
    expect(Object.keys(spec ?? {}).sort()).toEqual(
      ['catalogVersion', 'designCapacityMah', 'designCapacityWh', 'manufacturer', 'model', 'modelIdentifier', 'nominalVoltage'],
    );
    // An entry without a published Wh figure has no voltage either (it is never assumed).
    const noWh = DEVICE_CATALOG.devices.find((d) => d.designCapacityWh == null && d.identifiers?.length);
    expect(noWh).toBeDefined();
    const id = noWh?.identifiers?.[0] ?? '';
    expect(lookupDeviceSpecification(id)).toMatchObject({ designCapacityWh: null, nominalVoltage: null });
  });
});
