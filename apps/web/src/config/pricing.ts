// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Pricing is edited here and nowhere else. A plan without a `price` renders
 * "Pricing announced at launch"; a plan with `status: 'planned'` is shown as
 * not yet available, because subscriptions are switched off in the backend
 * (`FEATURE_SUBSCRIPTIONS=0`) until store receipts are verified.
 */
export type PlanPrice = { amount: string; currency: string; period: 'month' | 'year' } | null;

export type Plan = {
  id: 'free' | 'pro';
  name: string;
  summary: string;
  price: PlanPrice;
  status: 'available' | 'planned';
  features: readonly string[];
  footnote?: string;
};

export const pricingAnnouncement = 'Pricing announced at launch';

export const plans: readonly Plan[] = [
  {
    id: 'free',
    name: 'Free',
    summary: 'Everything you need to see what your phone uses today.',
    price: null,
    status: 'available',
    features: [
      'Dashboard with today’s battery, energy and data',
      'Daily usage, this week and this month',
      'Battery and charging-session monitoring',
      'Mobile and Wi-Fi usage, separately',
      'History for the last 30 days',
      'CSV and JSON export',
      'On-device notifications',
      'AI insights, a few per day',
    ],
  },
  {
    id: 'pro',
    name: 'WattByte Pro',
    summary: 'More history, more reports and a larger AI allowance.',
    price: null,
    status: 'planned',
    features: [
      'Advanced history',
      'Detailed reports',
      'Exports of the cloud copy',
      'A larger daily AI allowance',
      'Advanced comparisons',
      'Extended analytics',
    ],
    footnote: 'The final contents of Pro are confirmed at launch.',
  },
];
