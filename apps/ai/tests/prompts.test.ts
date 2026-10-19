import { describe, expect, it } from 'vitest';

import { buildPrompt } from '../src/prompts/index.js';
import { AIInputSchema } from '../src/schemas.js';

const input = AIInputSchema.parse({
  period: '2026-W41',
  periodType: 'week',
  mobileDataGb: 12.5,
  wifiDataGb: 80.25,
  totalDataGb: 92.75,
  chargingSessions: 9,
  batteryEnergyKwh: 0.11,
  wallEnergyKwh: 0.13,
  electricityCost: 0.15,
  currency: 'PLN',
  wifiSharePercent: 86.5,
  averageSessionMah: 2840,
});

describe('buildPrompt', () => {
  it('quotes every figure verbatim and forbids arithmetic', () => {
    const p = buildPrompt('weekly_summary', 'funny', 'pl', input);
    for (const needle of ['12.5 GB', '80.25 GB', '92.75 GB', '9', '0.13 kWh', '0.15 PLN', '86.5%', '2840 mAh']) {
      expect(p.user).toContain(needle);
    }
    expect(p.system).toMatch(/Do not calculate/);
    expect(p.system).toContain('po polsku');
    expect(p.system).toContain('"tone": "funny"');
  });

  it('keeps roast mode kind and never leaks identifiers', () => {
    const p = buildPrompt('roast', 'roast', 'en', input);
    expect(p.system).toMatch(/Never insult the person/);
    for (const forbidden of ['email', 'userId', 'token', 'ip', 'deviceId']) {
      expect(p.user.toLowerCase()).not.toContain(forbidden.toLowerCase());
    }
  });
});
