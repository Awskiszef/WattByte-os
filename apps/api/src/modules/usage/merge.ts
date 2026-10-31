// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import { type DailyUsageDto, LIMITS } from '@wattbyte/contracts';

import type { DailyUsageRow } from '../../database/repositories.js';

const round = (v: number, d: number): number => Math.round(v * 10 ** d) / 10 ** d;
const clamp = (v: number, max: number): number => Math.min(v, max);

/**
 * Sums the rows of every device for a date. Flags stay true if any device estimated.
 *
 * One day has ONE currency in the response, so the cost is the cost of the currency that accounts for most of it (ties:
 * the smaller code): rows in another currency are not added to it under its label (audit C-13: a day with PLN from one
 * phone and EUR from another summed both as PLN). Every sum is capped at the contract maximum, so a day built from
 * implausible rows cannot make the response fail its own schema (a 500 for the user's own data).
 *
 * The PostgreSQL repository does the same in SQL (`listDailyTotals`) so a read never loads one row per device and day;
 * this is the reference for it and the implementation of the in-memory store.
 */
export function mergeByDate(rows: DailyUsageRow[]): DailyUsageDto[] {
  const byDate = new Map<string, DailyUsageRow[]>();
  for (const r of rows) {
    const list = byDate.get(r.date);
    if (list) list.push(r);
    else byDate.set(r.date, [r]);
  }
  const out: DailyUsageDto[] = [];
  for (const [date, list] of byDate) {
    const costByCurrency = new Map<string, number>();
    for (const r of list) costByCurrency.set(r.currency, (costByCurrency.get(r.currency) ?? 0) + r.estimatedCost);
    const [currency, cost] = [...costByCurrency.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0]!;
    const sum = (pick: (r: DailyUsageRow) => number): number => list.reduce((a, r) => a + pick(r), 0);
    out.push({
      date,
      mobileBytes: clamp(sum((r) => r.mobileBytes), LIMITS.bytesPerDay),
      wifiBytes: clamp(sum((r) => r.wifiBytes), LIMITS.bytesPerDay),
      chargedWh: clamp(round(sum((r) => r.chargedWh), 3), LIMITS.whPerDay),
      wallWh: clamp(round(sum((r) => r.wallWh), 3), LIMITS.whPerDay),
      chargingSessions: clamp(sum((r) => r.chargingSessions), LIMITS.sessionsPerDay),
      estimatedCost: clamp(round(cost, 4), LIMITS.costPerDay),
      currency,
      dataEstimated: list.some((r) => r.dataEstimated),
      energyEstimated: list.some((r) => r.energyEstimated),
    });
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}
