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

  it('states unknown energy and cost as unknown, never as 0 (G-02)', () => {
    for (const unknown of [{}, { batteryEnergyKwh: null, wallEnergyKwh: null, electricityCost: null }]) {
      const { batteryEnergyKwh: _b, wallEnergyKwh: _w, electricityCost: _c, ...rest } = input;
      const parsed = AIInputSchema.parse({ ...rest, ...unknown });
      const p = buildPrompt('weekly_summary', 'normal', 'en', parsed);
      expect(p.user).not.toMatch(/kWh/);
      expect(p.user).not.toContain('electricity cost');
      expect(p.user).toContain('energy and cost: unknown');
      expect(p.user).toContain('12.5 GB');
    }
  });

  it('a known figure next to an unknown one keeps only the known one', () => {
    const { wallEnergyKwh: _w, electricityCost: _c, ...rest } = input;
    const p = buildPrompt('weekly_summary', 'normal', 'en', AIInputSchema.parse(rest));
    expect(p.user).toContain('0.11 kWh');
    expect(p.user).not.toContain('energy drawn from the wall');
    expect(p.user).not.toContain('energy and cost: unknown');
  });
});
