/**
 * Public API contracts for /api/v1. The TypeScript API validates with these
 * schemas and publishes an OpenAPI document generated from them; the Flutter
 * client is generated from that document (see openapi/README.md).
 */
import { AI_LOCALES, AI_MODES, AIInputSchema, AIOutputSchema } from '@wattbyte/ai';
import { z } from 'zod';

export { AIInputSchema, AIOutputSchema };
export * from './cloud-data.js';

// ------------------------------------------------------------------ common

export const ErrorResponse = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
  }),
});

/** True for a real calendar date written as YYYY-MM-DD (rejects 2026-13-45, 2026-02-30). */
export function isRealCalendarDate(value: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d;
}

/** Earliest date the API accepts; anything older is a client bug. */
export const MIN_USAGE_DATE = '2015-01-01';

export const IsoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD')
  .refine(isRealCalendarDate, 'must be a real calendar date')
  .refine((v) => v >= MIN_USAGE_DATE, `must not be before ${MIN_USAGE_DATE}`);

/** Physical upper bounds for one day; far above any real phone, below the column precision. */
export const LIMITS = {
  bytesPerDay: 10 ** 13, // 10 TB
  whPerDay: 100_000, // 100 kWh of battery energy
  costPerDay: 100_000,
  sessionsPerDay: 1_000,
  maxDaysPerSync: 92,
  /** Battery capacity sanity bounds (a laptop battery is ~100 Wh). */
  capacityMah: 30_000,
  capacityWh: 200,
  /** Electricity price per kWh in any currency. */
  pricePerKwh: 1_000,
} as const;

const finiteNonNegative = (max: number) => z.number().finite().nonnegative().max(max);

/**
 * Optional flag with a default. Generated clients may send an absent optional field as `null`;
 * `null` then means "not given" and the default applies (the published schema stays `boolean`, default included).
 */
const booleanOrDefault = (value: boolean) => z.preprocess((v) => (v === null ? undefined : v), z.boolean().default(value));

/** ISO 3166-1 alpha-2, upper case. Validated strictly: it selects an external data query. */
export const CountryCode = z.string().regex(/^[A-Z]{2}$/, 'ISO 3166-1 alpha-2, upper case');
/** ISO 4217, upper case. */
export const CurrencyCode = z.string().regex(/^[A-Z]{3}$/, 'ISO 4217 code, upper case');
export const Platform = z.enum(['android', 'ios']);
export const Plan = z.enum(['free', 'premium']);

// ------------------------------------------------------------------ health

export const HealthResponse = z.object({
  status: z.literal('ok'),
  version: z.string(),
  uptimeSec: z.number().int().nonnegative(),
});

export const ReadyResponse = z.object({
  status: z.enum(['ok', 'degraded']),
  database: z.enum(['ok', 'unavailable']),
  aiProviders: z.array(z.string()),
});

// -------------------------------------------------------------------- auth

export const Email = z.string().trim().toLowerCase().email().max(254);
export const Password = z.string().min(8).max(200);

export const RegisterRequest = z.object({ email: Email, password: Password, displayName: z.string().trim().min(1).max(60).nullish() });
export const LoginRequest = z.object({ email: Email, password: Password });
export const RefreshRequest = z.object({ refreshToken: z.string().min(20) });
export const LogoutRequest = RefreshRequest;

export const UserDto = z.object({
  id: z.string().uuid(),
  email: z.string(),
  displayName: z.string().nullable(),
  plan: Plan,
  createdAt: z.string().datetime(),
});

export const TokenPair = z.object({
  accessToken: z.string(),
  /** Rotated on every refresh; the previous value stops working. */
  refreshToken: z.string(),
  /** Access token lifetime in seconds. */
  expiresIn: z.number().int().positive(),
  tokenType: z.literal('Bearer'),
});

export const AuthResponse = z.object({ user: UserDto, tokens: TokenPair });

/** Changing the password signs every device out and returns a fresh session for the one that asked. */
export const ChangePasswordRequest = z.object({ currentPassword: z.string().min(1).max(200), newPassword: Password });

/** One signed-in device (a refresh-token family). The id is only meaningful to `DELETE /me/sessions/{id}`. */
export const SessionDto = z.object({
  id: z.string().uuid(),
  createdAt: z.string().datetime(),
  /** The newest token rotation: the last time the device refreshed its session. */
  lastUsedAt: z.string().datetime(),
  expiresAt: z.string().datetime(),
  /** True for the session the request was made with. */
  current: z.boolean(),
});
export const SessionListResponse = z.object({ sessions: z.array(SessionDto) });

export const UpdateMeRequest = z.object({ displayName: z.string().trim().min(1).max(60).nullable() });

// --------------------------------------------------------- account settings

export const ElectricityPriceMode = z.enum(['automatic', 'manual']);

/**
 * Where an account-level value came from ON THE DEVICE THAT SAVED IT: detected by the app, chosen by the user, or an
 * answer the user gave in an older version of the app that the migration keeps as a conscious choice. It is the
 * receiving device's `originalSource`: a device that pulls the value records it as "synced from the account" and keeps
 * this one as the reason the account holds it. `accountSynced` is deliberately not a member: it describes how a value
 * reached a device, never how the account got it (see docs/SETTING_SOURCES.md).
 */
export const SettingOrigin = z.enum(['detected', 'manual', 'migratedManual']);

/**
 * Account-level preferences that follow the user across devices. Device-bound
 * facts (battery capacity, model) live on the device registration instead.
 *
 * Each `*Source` is the origin of the value next to it; `null` = unknown (a value saved by a client that did not say, or
 * saved before sources existed) and is never guessed.
 */
export const UserSettingsDto = z.object({
  countryCode: CountryCode.nullable(),
  countryCodeSource: SettingOrigin.nullable(),
  currencyCode: CurrencyCode.nullable(),
  currencyCodeSource: SettingOrigin.nullable(),
  electricityPriceMode: ElectricityPriceMode,
  manualElectricityPrice: z.number().nullable(),
  /** Origin of the price decision as a whole: the mode and the manual tariff. */
  electricityPriceSource: SettingOrigin.nullable(),
  updatedAt: z.string().datetime(),
});

export const UpdateUserSettingsRequest = z.object({
  countryCode: CountryCode.nullish(),
  countryCodeSource: SettingOrigin.nullish(),
  currencyCode: CurrencyCode.nullish(),
  currencyCodeSource: SettingOrigin.nullish(),
  /** Not nullable in the database: `null` is read as "not given", like an absent field. */
  electricityPriceMode: ElectricityPriceMode.nullish(),
  manualElectricityPrice: finiteNonNegative(LIMITS.pricePerKwh).nullish(),
  /**
   * `null` / absent = "not given": the stored origin is kept while the value it describes is unchanged, and becomes unknown
   * when the value changes (an origin is never carried over to a different value).
   */
  electricityPriceSource: SettingOrigin.nullish(),
});

// ----------------------------------------------------------------- devices

/**
 * Where a device's DESIGN capacity (the nominal figure of the phone model) came from
 * (mirrors `DesignCapacitySource` in the app). The enum has no measurement member on
 * purpose: a reading such as Android's `BATTERY_PROPERTY_CHARGE_COUNTER` can not be
 * expressed as a design capacity. See docs/BATTERY_CAPACITY.md.
 */
export const DesignCapacitySource = z.enum(['manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual', 'unknown']);

/** Where an ESTIMATED FULL-CHARGE capacity (what this battery holds today) came from. */
export const FullChargeCapacitySource = z.enum(['androidChargeCounter', 'unknown']);

/** How far the estimate can be trusted: it follows the battery level of the reading. */
export const FullChargeCapacityConfidence = z.enum(['low', 'medium', 'high']);

/**
 * Battery capacity is a property of the device, not of the account: it travels with the registration.
 * Two groups that are stored atomically (see the route): design capacity, and the estimate of the
 * full-charge capacity. Cross-field rules are enforced by the route (`apps/api/src/modules/devices/battery-capacity.ts`).
 */
const batteryFields = {
  /** iOS `utsname.machine` (iPhone16,1) or Android `Build.MODEL`; a model code, never a serial number. */
  modelIdentifier: z.string().trim().max(64).nullish(),
  /** Column resolution is 0.1 mAh / 0.001 Wh: anything smaller is not a battery and would violate the CHECK constraint. */
  designCapacityMah: z.number().finite().min(0.1).max(LIMITS.capacityMah).nullish(),
  designCapacityWh: z.number().finite().min(0.001).max(LIMITS.capacityWh).nullish(),
  designCapacitySource: DesignCapacitySource.nullish(),
  estimatedFullChargeCapacityMah: z.number().finite().min(0.1).max(LIMITS.capacityMah).nullish(),
  estimatedFullChargeCapacityWh: z.number().finite().min(0.001).max(LIMITS.capacityWh).nullish(),
  fullChargeCapacitySource: FullChargeCapacitySource.nullish(),
  fullChargeCapacityConfidence: FullChargeCapacityConfidence.nullish(),
};

export const DeviceRegisterRequest = z.object({
  /** Random id generated once per installation; never a hardware identifier. */
  installationId: z.string().min(8).max(64),
  platform: Platform,
  /** Generated clients send an absent optional field as `null`, so null means "not given". */
  model: z.string().trim().max(80).nullish(),
  ...batteryFields,
});

export const DeviceDto = z.object({
  id: z.string().uuid(),
  installationId: z.string(),
  platform: Platform,
  model: z.string().nullable(),
  modelIdentifier: z.string().nullable(),
  designCapacityMah: z.number().nullable(),
  designCapacityWh: z.number().nullable(),
  designCapacitySource: DesignCapacitySource.nullable(),
  estimatedFullChargeCapacityMah: z.number().nullable(),
  estimatedFullChargeCapacityWh: z.number().nullable(),
  fullChargeCapacitySource: FullChargeCapacitySource.nullable(),
  fullChargeCapacityConfidence: FullChargeCapacityConfidence.nullable(),
  createdAt: z.string().datetime(),
  lastSeenAt: z.string().datetime(),
});

export const DeviceSpecificationParams = z.object({
  identifier: z.string().trim().min(1).max(64),
});

/** One row of the device catalog (`packages/device-specs`), as served to the app: design capacity by definition. */
export const DeviceSpecificationDto = z.object({
  manufacturer: z.string(),
  model: z.string(),
  modelIdentifier: z.string(),
  designCapacityMah: z.number(),
  designCapacityWh: z.number().nullable(),
  nominalVoltage: z.number().nullable(),
  catalogVersion: z.string(),
});

export const DeviceListResponse = z.object({ devices: z.array(DeviceDto) });

// ------------------------------------------------------------ electricity

export const ElectricityPriceSource = z.enum(['eurostat', 'government', 'manual', 'fallback']);

/**
 * Average household electricity price for a country, per kWh, in the national
 * currency. Always a statistical average (never the user's tariff), so the app
 * labels every cost derived from it as an estimate.
 */
export const ElectricityPriceDto = z.object({
  countryCode: CountryCode,
  currency: CurrencyCode,
  pricePerKwh: z.number(),
  /** Reporting period of the source, e.g. `2026-S1` (Eurostat half-year). */
  period: z.string(),
  source: ElectricityPriceSource,
  includesTaxes: z.boolean().nullable(),
  includesNetworkCosts: z.boolean().nullable(),
  /** When the value was last fetched from the source (not the period it describes). */
  updatedAt: z.string().datetime(),
  /** True when the source could not be reached and this is the last known value. */
  stale: z.boolean(),
});

export const ElectricityPriceQuery = z.object({ country: CountryCode.optional() });

// ------------------------------------------------------------------ region

export const RegionDetectionSource = z.enum(['backendCountry', 'none']);

/** Country guessed from the request by an edge proxy header; `null` when the API has none. */
export const RegionResponse = z.object({
  countryCode: CountryCode.nullable(),
  source: RegionDetectionSource,
});

// ------------------------------------------------------------------- usage

/** One local day of aggregates; mirrors `DailyAggregate` in the Flutter app. */
export const DailyUsageDto = z.object({
  date: IsoDate,
  mobileBytes: z.number().int().nonnegative().max(LIMITS.bytesPerDay),
  wifiBytes: z.number().int().nonnegative().max(LIMITS.bytesPerDay),
  chargedWh: finiteNonNegative(LIMITS.whPerDay),
  wallWh: finiteNonNegative(LIMITS.whPerDay),
  chargingSessions: z.number().int().nonnegative().max(LIMITS.sessionsPerDay),
  estimatedCost: finiteNonNegative(LIMITS.costPerDay),
  currency: z.string().regex(/^[A-Z]{3}$/, 'ISO 4217 code, upper case'),
  dataEstimated: booleanOrDefault(false),
  energyEstimated: booleanOrDefault(true),
});

export const UsageSyncRequest = z.object({
  installationId: z.string().min(8).max(64),
  days: z.array(DailyUsageDto).min(1).max(LIMITS.maxDaysPerSync),
});

export const UsageSyncResponse = z.object({
  accepted: z.number().int().nonnegative(),
  dates: z.array(IsoDate),
});

export const UsageDailyQuery = z.object({ from: IsoDate, to: IsoDate });
export const UsageDailyResponse = z.object({ days: z.array(DailyUsageDto) });

// ---------------------------------------------------------------------- ai

export const AIMode = z.enum(AI_MODES);
export const AILocale = z.enum(AI_LOCALES);

/**
 * `mode` and `locale` are optional with no schema default on purpose: the server
 * applies `normal` / `en`. (openapi-generator emits uncompilable Dart for enum defaults.)
 * Generated clients send an absent optional field as `null`, so `null` means "not given".
 */
export const AIGenerateRequest = z.object({
  mode: AIMode.nullish(),
  locale: AILocale.nullish(),
  input: AIInputSchema,
});

export const AIGenerateResponse = z.object({
  output: AIOutputSchema,
  provider: z.string(),
  model: z.string(),
  remainingToday: z.number().int().nonnegative(),
});

export type RegisterRequest = z.infer<typeof RegisterRequest>;
export type LoginRequest = z.infer<typeof LoginRequest>;
export type UserDto = z.infer<typeof UserDto>;
export type TokenPair = z.infer<typeof TokenPair>;
export type AuthResponse = z.infer<typeof AuthResponse>;
export type DeviceDto = z.infer<typeof DeviceDto>;
export type DeviceSpecificationDto = z.infer<typeof DeviceSpecificationDto>;
export type UserSettingsDto = z.infer<typeof UserSettingsDto>;
export type UpdateUserSettingsRequest = z.infer<typeof UpdateUserSettingsRequest>;
export type ElectricityPriceDto = z.infer<typeof ElectricityPriceDto>;
export type ElectricityPriceSource = z.infer<typeof ElectricityPriceSource>;
export type RegionResponse = z.infer<typeof RegionResponse>;
export type DailyUsageDto = z.infer<typeof DailyUsageDto>;
export type UsageSyncRequest = z.infer<typeof UsageSyncRequest>;
export type AIGenerateRequest = z.infer<typeof AIGenerateRequest>;
export type AIGenerateResponse = z.infer<typeof AIGenerateResponse>;

export * from './app-config.js';
