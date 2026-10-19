/**
 * Contracts for an account's cloud data: erasing it without deleting the account
 * (`DELETE /api/v1/me/cloud-data`) and exporting it (`GET /api/v1/me/export`).
 * What each one covers is documented in docs/CLOUD_DATA.md.
 *
 * This is a leaf module on purpose: `index.ts` re-exports it, so importing
 * values from `index.ts` here would be a cycle that fails at load time. The
 * row shapes below therefore restate the matching DTOs from `index.ts`; the API
 * tests pin them together at the type level (`tests/cloud-contract.test.ts`).
 */
import { z } from 'zod';

/** Bumped when the export document changes incompatibly; consumers branch on it. */
export const CLOUD_EXPORT_SCHEMA_VERSION = 1;

/**
 * Hard cap on rows per collection in one export. 10 000 daily rows cover 27 years of
 * one device; real accounts hold a few thousand rows in total. A collection above the
 * cap is cut to its newest rows and flagged in `limits.truncated`, never cut silently.
 */
export const CLOUD_EXPORT_MAX_ROWS = 10_000;

const dateTime = z.string().datetime();
const count = z.number().int().nonnegative();

// ------------------------------------------------------------------ delete

/** `?devices=true` also removes the registered devices; the default keeps them so sync can resume. */
export const CloudDataDeleteQuery = z.object({ devices: z.enum(['true', 'false']).optional() });

export const CloudDataDeletedCounts = z.object({
  dailyUsage: count,
  chargingSummaries: count,
  monthlySummaries: count,
  aiGenerations: count,
  /** Always 0 unless `?devices=true` was passed. */
  devices: count,
});

export const CloudDataDeleteResponse = z.object({ deleted: CloudDataDeletedCounts });

// ------------------------------------------------------------------ export

export const CloudExportQuery = z.object({ format: z.enum(['json', 'csv']).optional() });

/** Mirrors `UserDto`; the password hash and every session are never part of an export. */
export const CloudExportAccount = z.object({
  id: z.string().uuid(),
  email: z.string(),
  displayName: z.string().nullable(),
  plan: z.enum(['free', 'premium']),
  createdAt: dateTime,
});

/** Account-level settings; `updatedAt` is null while the user never saved any. */
export const CloudExportSettings = z.object({
  countryCode: z.string().nullable(),
  countryCodeSource: z.enum(['detected', 'manual', 'migratedManual']).nullable(),
  currencyCode: z.string().nullable(),
  currencyCodeSource: z.enum(['detected', 'manual', 'migratedManual']).nullable(),
  electricityPriceMode: z.enum(['automatic', 'manual']),
  manualElectricityPrice: z.number().nullable(),
  electricityPriceSource: z.enum(['detected', 'manual', 'migratedManual']).nullable(),
  updatedAt: dateTime.nullable(),
});

/** Mirrors `DeviceDto`, including the device-bound design capacity and full-charge estimate. */
export const CloudExportDevice = z.object({
  id: z.string().uuid(),
  installationId: z.string(),
  platform: z.enum(['android', 'ios']),
  model: z.string().nullable(),
  modelIdentifier: z.string().nullable(),
  designCapacityMah: z.number().nullable(),
  designCapacityWh: z.number().nullable(),
  designCapacitySource: z.enum(['manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual', 'unknown']).nullable(),
  estimatedFullChargeCapacityMah: z.number().nullable(),
  estimatedFullChargeCapacityWh: z.number().nullable(),
  fullChargeCapacitySource: z.enum(['androidChargeCounter', 'unknown']).nullable(),
  fullChargeCapacityConfidence: z.enum(['low', 'medium', 'high']).nullable(),
  createdAt: dateTime,
  lastSeenAt: dateTime,
});

/** One stored row per device and day (unlike `/usage/daily`, devices are not merged). */
export const CloudExportDailyUsage = z.object({
  deviceId: z.string().uuid(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  mobileBytes: z.number().int().nonnegative(),
  wifiBytes: z.number().int().nonnegative(),
  chargedWh: z.number().nonnegative(),
  wallWh: z.number().nonnegative(),
  chargingSessions: z.number().int().nonnegative(),
  estimatedCost: z.number().nonnegative(),
  currency: z.string(),
  dataEstimated: z.boolean(),
  energyEstimated: z.boolean(),
});

export const CloudExportChargingSummary = z.object({
  deviceId: z.string().uuid(),
  startedAt: dateTime,
  endedAt: dateTime,
  startPercent: z.number().int(),
  endPercent: z.number().int(),
  mah: z.number(),
  mahEstimated: z.boolean(),
  batteryWh: z.number(),
  wallWh: z.number(),
  estimatedCost: z.number(),
  createdAt: dateTime,
});

export const CloudExportMonthlySummary = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/),
  mobileBytes: z.number().int().nonnegative(),
  wifiBytes: z.number().int().nonnegative(),
  wallWh: z.number(),
  chargingSessions: z.number().int().nonnegative(),
  estimatedCost: z.number(),
  currency: z.string(),
  computedAt: dateTime,
});

/** Metadata of an AI request: never the prompt, the aggregates sent or the generated text. */
export const CloudExportAiGeneration = z.object({
  /** `insight`, `weekly_summary`, `monthly_summary`, `roast`; a plain string so a new AI task can never make an export fail. */
  task: z.string(),
  mode: z.string(),
  provider: z.string(),
  model: z.string(),
  inputTokens: z.number().int().nonnegative(),
  outputTokens: z.number().int().nonnegative(),
  estimatedCostUsd: z.number().nonnegative(),
  latencyMs: z.number().int().nonnegative(),
  createdAt: dateTime,
});

/** Store-verified purchase records; deleting the account does not cancel them with the store. */
export const CloudExportSubscription = z.object({
  store: z.enum(['app_store', 'play']),
  productId: z.string(),
  originalTransactionId: z.string(),
  status: z.enum(['active', 'grace', 'expired', 'revoked']),
  expiresAt: dateTime.nullable(),
  createdAt: dateTime,
  updatedAt: dateTime,
});

export const CloudExportTruncated = z.object({
  devices: z.boolean(),
  dailyUsage: z.boolean(),
  chargingSummaries: z.boolean(),
  monthlySummaries: z.boolean(),
  aiGenerations: z.boolean(),
  subscriptions: z.boolean(),
});

export const CloudExportLimits = z.object({
  /** Rows per collection; a truncated collection holds its newest rows. */
  maxRowsPerCollection: z.number().int().positive(),
  truncated: CloudExportTruncated,
});

export const CloudExportDocument = z.object({
  schemaVersion: z.number().int().positive(),
  exportedAt: dateTime,
  account: CloudExportAccount,
  settings: CloudExportSettings,
  devices: z.array(CloudExportDevice),
  dailyUsage: z.array(CloudExportDailyUsage),
  chargingSummaries: z.array(CloudExportChargingSummary),
  monthlySummaries: z.array(CloudExportMonthlySummary),
  aiGenerations: z.array(CloudExportAiGeneration),
  subscriptions: z.array(CloudExportSubscription),
  limits: CloudExportLimits,
});

/**
 * Named OpenAPI components for the schemas above (spread into the swagger `transformObject` registry).
 *
 * `CloudExportAccount` and `CloudExportDevice` are deliberately NOT registered. The registry replaces every schema whose
 * JSON equals a registered one by a `$ref` to it, and these two are JSON-identical to `UserDto` and `DeviceDto`:
 * registering them would silently rename those models in the spec (and in the generated Dart client). Unregistered, the
 * export document refers to `UserDto` and `DeviceDto` themselves, which is the intent; `tests/cloud-contract.test.ts` pins it.
 */
export const cloudDataOpenApiSchemas = {
  CloudDataDeletedCounts,
  CloudDataDeleteResponse,
  CloudExportSettings,
  CloudExportDailyUsage,
  CloudExportChargingSummary,
  CloudExportMonthlySummary,
  CloudExportAiGeneration,
  CloudExportSubscription,
  CloudExportTruncated,
  CloudExportLimits,
  CloudExportDocument,
};

export type CloudDataDeleteResponse = z.infer<typeof CloudDataDeleteResponse>;
export type CloudExportDocument = z.infer<typeof CloudExportDocument>;
export type CloudExportDailyUsage = z.infer<typeof CloudExportDailyUsage>;
