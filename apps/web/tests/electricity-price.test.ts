import { describe, expect, it } from 'vitest';
import { eurostatUrl, formatPeriod, latestValue } from '@/lib/electricity-price';

describe('eurostat query', () => {
  it('asks for band DC, taxes included, national currency', () => {
    const url = new URL(eurostatUrl('PL'));
    expect(url.pathname.endsWith('/nrg_pc_204')).toBe(true);
    expect(url.searchParams.get('geo')).toBe('PL');
    expect(url.searchParams.get('nrg_cons')).toBe('KWH2500-4999');
    expect(url.searchParams.get('tax')).toBe('I_TAX');
    expect(url.searchParams.get('currency')).toBe('NAC');
  });
});

describe('latestValue', () => {
  const stat = {
    id: ['freq', 'geo', 'time'],
    size: [1, 1, 3],
    value: { '0': 0.91, '1': 0.95, '2': null },
    dimension: { time: { category: { index: { '2024-S1': 0, '2024-S2': 1, '2025-S1': 2 } } } },
  };

  it('skips an empty newest period and returns the newest one with a value', () => {
    expect(latestValue(stat)).toEqual({ period: '2024-S2', value: 0.95 });
  });

  it('refuses a response whose other dimensions are not single categories', () => {
    expect(latestValue({ ...stat, size: [1, 2, 3] })).toBeNull();
  });

  it('formats a half-year period in words', () => {
    expect(formatPeriod('2025-S1')).toBe('first half of 2025');
    expect(formatPeriod('2024')).toBe('2024');
  });
});
