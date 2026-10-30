// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/** Number formatting shared by counters and mockups (en-US, matches the demo copy). */
const formatter = new Intl.NumberFormat('en-US');

export function formatNumber(value: number, fractionDigits = 0): string {
  if (fractionDigits === 0) return formatter.format(Math.round(value));
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(value);
}
