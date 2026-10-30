// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * The numbers shown in every mockup. They are illustrative and every mockup
 * that shows them carries the demo label from `site.ts`.
 */
export const todayDemo = {
  batteryMah: 1274,
  energyWh: 6.3,
  costLabel: '€0.0021',
  mobileGb: 1.8,
  wifiGb: 12.4,
  currency: 'EUR',
} as const;

/** Energy drawn per hour, Wh, 00:00 to 24:00 (25 points so the curve closes the day). */
export const hourlyEnergyWh = [
  0.05, 0.04, 0.04, 0.04, 0.05, 0.08, 0.18, 0.32, 0.36, 0.3, 0.28, 0.34, 0.4, 0.38, 0.52, 0.58, 0.49,
  0.33, 0.3, 0.36, 0.42, 0.31, 0.18, 0.09, 0.06,
] as const;

export const hourTicks = ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'] as const;

export const weeklyReportDemo = {
  title: 'Weekly Energy Report',
  rows: [
    { label: 'Battery', value: '8,420 mAh' },
    { label: 'Energy', value: '41.2 Wh' },
    { label: 'Mobile data', value: '7.8 GB' },
    { label: 'Wi-Fi', value: '63.7 GB' },
    { label: 'Estimated energy cost', value: '€0.014' },
  ],
  trend: { label: 'Trend', value: '-8.2%', direction: 'down' as const },
  /** Seven days of energy, Wh, for the small bar chart. */
  dailyWh: [5.1, 6.3, 5.7, 7.2, 6.0, 5.4, 5.5],
} as const;

export const aiDemo = {
  questions: [
    'Why was my battery usage higher today?',
    'How much energy did my phone use this week?',
    'Is my mobile data usage unusual?',
    'What caused this spike?',
    'How can I reduce my battery usage?',
  ],
  answer:
    'Your energy use was approximately 18% higher than your recent average. Most of the increase occurred between 14:00 and 17:00.',
  attribution: 'Based on your WattByte usage data',
} as const;

export const regionDemo = {
  country: 'Poland',
  countryCode: 'PL',
  currency: 'PLN',
  placeholderPrice: '0.XX',
} as const;
