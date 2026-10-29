import type { DailyUsageDto } from '@wattbyte/contracts';

import type { DailyUsageRow } from '../../database/repositories.js';

const round = (v: number, d: number): number => Math.round(v * 10 ** d) / 10 ** d;

/**
 * Sums the rows of every device for a date. Flags stay true if any device estimated. The PostgreSQL repository does the
 * same in SQL (`listDailyTotals`) so a read never loads one row per device and day; this is the reference for it and
 * the implementation of the in-memory store.
 */
export function mergeByDate(rows: DailyUsageRow[]): DailyUsageDto[] {
  const byDate = new Map<string, DailyUsageDto>();
  for (const r of rows) {
    const acc = byDate.get(r.date);
    if (!acc) {
      byDate.set(r.date, {
        date: r.date,
        mobileBytes: r.mobileBytes,
        wifiBytes: r.wifiBytes,
        chargedWh: r.chargedWh,
        wallWh: r.wallWh,
        chargingSessions: r.chargingSessions,
        estimatedCost: r.estimatedCost,
        currency: r.currency,
        dataEstimated: r.dataEstimated,
        energyEstimated: r.energyEstimated,
      });
      continue;
    }
    acc.mobileBytes += r.mobileBytes;
    acc.wifiBytes += r.wifiBytes;
    acc.chargedWh = round(acc.chargedWh + r.chargedWh, 3);
    acc.wallWh = round(acc.wallWh + r.wallWh, 3);
    acc.chargingSessions += r.chargingSessions;
    acc.estimatedCost = round(acc.estimatedCost + r.estimatedCost, 4);
    acc.dataEstimated ||= r.dataEstimated;
    acc.energyEstimated ||= r.energyEstimated;
  }
  return [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date));
}
