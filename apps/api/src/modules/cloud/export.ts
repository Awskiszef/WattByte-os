import { CLOUD_EXPORT_MAX_ROWS, CLOUD_EXPORT_SCHEMA_VERSION, type CloudExportDocument } from '@wattbyte/contracts';

import type { CloudExportData, DailyUsageRow } from '../../database/repositories.js';

const iso = (d: Date): string => d.toISOString();

/** `Content-Disposition` of an export: `attachment; filename="wattbyte-export-YYYY-MM-DD.<ext>"` (UTC date of the export). */
export function exportDisposition(exportedAt: Date, extension: 'json' | 'csv'): string {
  return `attachment; filename="wattbyte-export-${iso(exportedAt).slice(0, 10)}.${extension}"`;
}

/** One stored row per device and day, field by field (also the rows of the CSV). */
export function toDailyUsageRows(rows: readonly DailyUsageRow[]): CloudExportDocument['dailyUsage'] {
  return rows.map((r) => ({
    deviceId: r.deviceId,
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
  }));
}

/**
 * Maps repository rows to the export document. Every field is listed here on purpose: a column
 * added to a table later reaches an export only when someone adds it, never by accident
 * (the password hash, session hashes and other users' rows are structurally absent from `CloudExportData`).
 */
export function toExportDocument(data: CloudExportData, exportedAt: Date): CloudExportDocument {
  const s = data.settings;
  return {
    schemaVersion: CLOUD_EXPORT_SCHEMA_VERSION,
    exportedAt: iso(exportedAt),
    account: {
      id: data.account.id,
      email: data.account.email,
      displayName: data.account.displayName,
      plan: data.account.plan,
      createdAt: iso(data.account.createdAt),
    },
    settings: {
      countryCode: s?.countryCode ?? null,
      countryCodeSource: s?.countryCodeSource ?? null,
      currencyCode: s?.currencyCode ?? null,
      currencyCodeSource: s?.currencyCodeSource ?? null,
      electricityPriceMode: s?.electricityPriceMode ?? 'automatic',
      manualElectricityPrice: s?.manualPricePerKwh ?? null,
      electricityPriceSource: s?.electricityPriceSource ?? null,
      updatedAt: s ? iso(s.updatedAt) : null,
    },
    devices: data.devices.map((d) => ({
      id: d.id,
      installationId: d.installationId,
      platform: d.platform,
      model: d.model,
      modelIdentifier: d.modelIdentifier,
      designCapacityMah: d.designCapacityMah,
      designCapacityWh: d.designCapacityWh,
      designCapacitySource: d.designCapacitySource,
      estimatedFullChargeCapacityMah: d.estimatedFullChargeCapacityMah,
      estimatedFullChargeCapacityWh: d.estimatedFullChargeCapacityWh,
      fullChargeCapacitySource: d.fullChargeCapacitySource,
      fullChargeCapacityConfidence: d.fullChargeCapacityConfidence,
      createdAt: iso(d.createdAt),
      lastSeenAt: iso(d.lastSeenAt),
    })),
    dailyUsage: toDailyUsageRows(data.dailyUsage),
    chargingSummaries: data.chargingSummaries.map((c) => ({
      deviceId: c.deviceId,
      startedAt: iso(c.startedAt),
      endedAt: iso(c.endedAt),
      startPercent: c.startPercent,
      endPercent: c.endPercent,
      mah: c.mah,
      mahEstimated: c.mahEstimated,
      batteryWh: c.batteryWh,
      wallWh: c.wallWh,
      estimatedCost: c.estimatedCost,
      createdAt: iso(c.createdAt),
    })),
    monthlySummaries: data.monthlySummaries.map((m) => ({
      month: m.month,
      mobileBytes: m.mobileBytes,
      wifiBytes: m.wifiBytes,
      wallWh: m.wallWh,
      chargingSessions: m.chargingSessions,
      estimatedCost: m.estimatedCost,
      currency: m.currency,
      computedAt: iso(m.computedAt),
    })),
    aiGenerations: data.aiGenerations.map((g) => ({
      task: g.task,
      mode: g.mode,
      provider: g.provider,
      model: g.model,
      inputTokens: g.inputTokens,
      outputTokens: g.outputTokens,
      estimatedCostUsd: g.estimatedCostUsd,
      latencyMs: g.latencyMs,
      createdAt: iso(g.createdAt),
    })),
    subscriptions: data.subscriptions.map((x) => ({
      store: x.store,
      productId: x.productId,
      originalTransactionId: x.originalTransactionId,
      status: x.status,
      expiresAt: x.expiresAt ? iso(x.expiresAt) : null,
      createdAt: iso(x.createdAt),
      updatedAt: iso(x.updatedAt),
    })),
    limits: { maxRowsPerCollection: CLOUD_EXPORT_MAX_ROWS, truncated: { ...data.truncated } },
  };
}
