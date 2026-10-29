import { DailyUsageDto, LIMITS } from '@wattbyte/contracts';
import { describe, expect, it } from 'vitest';

import type { DailyUsageRow } from '../src/database/repositories.js';
import { mergeByDate } from '../src/modules/usage/merge.js';

const row = (over: Partial<DailyUsageRow>): DailyUsageRow => ({
  userId: 'u', deviceId: 'd1', date: '2026-10-01', mobileBytes: 1, wifiBytes: 1, chargedWh: 1, wallWh: 1, chargingSessions: 1,
  estimatedCost: 1, currency: 'PLN', dataEstimated: false, energyEstimated: false, ...over,
});

describe('mergeByDate (C-13)', () => {
  it('one currency per day: the larger cost wins, the other currency is not added under its label', () => {
    const [d] = mergeByDate([row({ estimatedCost: 3, currency: 'PLN' }), row({ deviceId: 'd2', estimatedCost: 5, currency: 'EUR' }), row({ deviceId: 'd3', estimatedCost: 1, currency: 'EUR' })]);
    expect(d).toMatchObject({ currency: 'EUR', estimatedCost: 6 });
    expect(d!.mobileBytes).toBe(3);
  });

  it('a tie in cost goes to the smaller currency code, whatever the order of the rows', () => {
    const a = mergeByDate([row({ estimatedCost: 2, currency: 'PLN' }), row({ deviceId: 'd2', estimatedCost: 2, currency: 'EUR' })]);
    const b = mergeByDate([row({ deviceId: 'd2', estimatedCost: 2, currency: 'EUR' }), row({ estimatedCost: 2, currency: 'PLN' })]);
    expect(a[0]!.currency).toBe('EUR');
    expect(b).toEqual(a);
  });

  it('flags are true if any device estimated; days are sorted', () => {
    const out = mergeByDate([row({ date: '2026-10-03' }), row({ date: '2026-10-01', dataEstimated: true }), row({ date: '2026-10-01', deviceId: 'd2' })]);
    expect(out.map((d) => d.date)).toEqual(['2026-10-01', '2026-10-03']);
    expect(out[0]).toMatchObject({ dataEstimated: true, energyEstimated: false });
  });

  it('sums are capped so the day still satisfies the response contract', () => {
    const big = { mobileBytes: 9_000_000_000_000, chargedWh: 90_000, chargingSessions: 900, estimatedCost: 90_000 };
    const [d] = mergeByDate([row(big), row({ ...big, deviceId: 'd2' })]);
    expect(d).toMatchObject({ mobileBytes: LIMITS.bytesPerDay, chargedWh: LIMITS.whPerDay, chargingSessions: LIMITS.sessionsPerDay, estimatedCost: LIMITS.costPerDay });
    expect(() => DailyUsageDto.parse(d)).not.toThrow();
  });
});
