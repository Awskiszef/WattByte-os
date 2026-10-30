// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { describe, expect, it } from 'vitest';
import { faq } from '@/config/faq';
import { footerColumns, mainNav, navActions, routes } from '@/config/navigation';
import { plans, pricingAnnouncement } from '@/config/pricing';
import { consumptionBlocks, reportsSection } from '@/config/features';

const required = [
  'What is WattByte?',
  'How does WattByte calculate energy usage?',
  'Is WattByte measuring electricity directly?',
  'Does WattByte drain my battery?',
  'Does WattByte track my location?',
  'Does WattByte sell my data?',
  'Can I delete my account?',
  'Does WattByte work on iOS?',
  'Does WattByte work on Android?',
  'Is the electricity cost exact?',
  'How does WattByte AI work?',
  'Can I export my data?',
];

describe('faq', () => {
  it('contains every required question, each with a unique id and a non-empty answer', () => {
    const questions = faq.map((f) => f.question);
    for (const q of required) expect(questions).toContain(q);
    expect(new Set(faq.map((f) => f.id)).size).toBe(faq.length);
    for (const f of faq) expect(f.answer.length).toBeGreaterThan(40);
  });
});

describe('navigation', () => {
  const routeSet = new Set<string>(routes);
  const pathOf = (href: string) => href.split('#')[0] || '/';

  it('main navigation and actions point at existing routes', () => {
    for (const item of mainNav) expect(routeSet.has(pathOf(item.href))).toBe(true);
    expect(routeSet.has(navActions.signIn.href)).toBe(true);
    expect(routeSet.has(navActions.download.href)).toBe(true);
  });

  it('footer links point at existing routes or are marked coming soon', () => {
    for (const column of footerColumns) {
      for (const link of column.links) {
        if ('comingSoon' in link && link.comingSoon) continue;
        expect(routeSet.has(pathOf(link.href)), `${column.title}: ${link.label}`).toBe(true);
      }
    }
  });
});

describe('pricing', () => {
  it('never invents an amount: a plan without a price uses the announcement text', () => {
    expect(pricingAnnouncement).toBe('Pricing announced at launch');
    for (const plan of plans) {
      if (plan.price) {
        expect(Number(plan.price.amount)).not.toBeNaN();
        expect(plan.price.currency).toMatch(/^[A-Z]{3}$/);
      }
    }
    expect(plans.find((p) => p.id === 'pro')?.status).toBe('planned');
  });
});

describe('features', () => {
  it('marks custom range as coming soon everywhere it appears', () => {
    const history = consumptionBlocks.find((b) => b.id === 'history')!;
    expect(history.capabilities.find((c) => c.label === 'Custom range')?.comingSoon).toBe(true);
    expect(reportsSection.periods.find((p) => p.label === 'Custom range')?.comingSoon).toBe(true);
  });
});
