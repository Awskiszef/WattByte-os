// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { CloudExportDailyUsage } from '@wattbyte/contracts';

export type CsvValue = string | number | boolean;

/** RFC 4180 field: quoted when it holds a comma, a double quote, CR or LF; embedded quotes are doubled. */
export function csvField(value: CsvValue): string {
  if (typeof value === 'number' && !Number.isFinite(value)) throw new RangeError(`CSV cannot carry ${value}`);
  const text = String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/** Header and rows as RFC 4180 records: CRLF line ends, one trailing CRLF. The result is a JS string, sent as UTF-8. */
export function toCsv(header: readonly string[], rows: readonly (readonly CsvValue[])[]): string {
  return [header, ...rows].map((record) => record.map(csvField).join(',') + '\r\n').join('');
}

export const DAILY_USAGE_CSV_HEADER = [
  'date',
  'deviceId',
  'mobileBytes',
  'wifiBytes',
  'chargedWh',
  'wallWh',
  'chargingSessions',
  'estimatedCost',
  'currency',
  'dataEstimated',
  'energyEstimated',
] as const;

/**
 * The tabular part of the export. Every column is a number, a flag, an ISO date, a UUID or a
 * currency code, so no cell holds user-typed text (and none can start a spreadsheet formula).
 */
export function dailyUsageCsv(rows: readonly CloudExportDailyUsage[]): string {
  return toCsv(
    DAILY_USAGE_CSV_HEADER,
    rows.map((r) => [
      r.date,
      r.deviceId,
      r.mobileBytes,
      r.wifiBytes,
      r.chargedWh,
      r.wallWh,
      r.chargingSessions,
      r.estimatedCost,
      r.currency,
      r.dataEstimated,
      r.energyEstimated,
    ]),
  );
}
