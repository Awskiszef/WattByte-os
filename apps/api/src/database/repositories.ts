/**
 * Persistence contracts. `postgres.ts` implements them for production,
 * `memory.ts` for tests and the OpenAPI export; services only see these.
 */

export type Plan = 'free' | 'premium';
export type Platform = 'android' | 'ios';

export interface UserRow {
  id: string;
  email: string;
  passwordHash: string | null;
  displayName: string | null;
  plan: Plan;
  createdAt: Date;
}

export interface SessionRow {
  id: string;
  userId: string;
  /** sha256 of the refresh token; the token itself is never stored. */
  refreshHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
  replacedBy: string | null;
  createdAt: Date;
}

/** Where the DESIGN capacity (nominal figure of the model) came from. No measurement member, on purpose. */
export type DesignCapacitySource = 'manufacturerSpecification' | 'localDeviceDatabase' | 'backendDeviceDatabase' | 'manual' | 'unknown';
/** Where an ESTIMATED FULL-CHARGE capacity came from. */
export type FullChargeCapacitySource = 'androidChargeCounter' | 'unknown';
export type FullChargeCapacityConfidence = 'low' | 'medium' | 'high';

export interface DeviceRow {
  id: string;
  userId: string;
  installationId: string;
  platform: Platform;
  model: string | null;
  modelIdentifier: string | null;
  designCapacityMah: number | null;
  designCapacityWh: number | null;
  designCapacitySource: DesignCapacitySource | null;
  estimatedFullChargeCapacityMah: number | null;
  estimatedFullChargeCapacityWh: number | null;
  fullChargeCapacitySource: FullChargeCapacitySource | null;
  fullChargeCapacityConfidence: FullChargeCapacityConfidence | null;
  createdAt: Date;
  lastSeenAt: Date;
}

/**
 * Battery capacity is stored in two groups, each atomically: design (`designCapacity*`) and
 * estimate (`estimatedFullChargeCapacity*`, `fullChargeCapacity*`). A group is replaced as a whole
 * (its values AND its nulls) when its source is given (not null / undefined); otherwise the stored
 * group is kept untouched and any values passed for it are ignored. The route has validated the
 * group beforehand (`validateBatteryCapacityGroups`).
 */
export interface DeviceUpsert {
  userId: string;
  installationId: string;
  platform: Platform;
  model?: string | null;
  modelIdentifier?: string | null;
  designCapacityMah?: number | null;
  designCapacityWh?: number | null;
  designCapacitySource?: DesignCapacitySource | null;
  estimatedFullChargeCapacityMah?: number | null;
  estimatedFullChargeCapacityWh?: number | null;
  fullChargeCapacitySource?: FullChargeCapacitySource | null;
  fullChargeCapacityConfidence?: FullChargeCapacityConfidence | null;
}

export type ElectricityPriceMode = 'automatic' | 'manual';

/**
 * Where an account-level value came from on the device that saved it. `accountSynced` is not a member: it is how a value reaches
 * a device, never how the account got it (docs/SETTING_SOURCES.md).
 */
export type SettingOrigin = 'detected' | 'manual' | 'migratedManual';

/** Account-level preferences; `null` = never set. A `*Source` of `null` = origin unknown (never guessed). */
export interface UserSettingsRow {
  userId: string;
  countryCode: string | null;
  countryCodeSource: SettingOrigin | null;
  currencyCode: string | null;
  currencyCodeSource: SettingOrigin | null;
  electricityPriceMode: ElectricityPriceMode;
  manualPricePerKwh: number | null;
  /** Origin of the price decision as a whole (the mode and the manual tariff). */
  electricityPriceSource: SettingOrigin | null;
  updatedAt: Date;
}

/**
 * `undefined` = leave as is for every field. The `*Source` fields describe the value next to them: the service layer decides what
 * a source becomes when the value changes without one (see `modules/users/routes.ts`); the repository stores what it is given.
 */
export interface UserSettingsPatch {
  countryCode?: string | null;
  countryCodeSource?: SettingOrigin | null;
  currencyCode?: string | null;
  currencyCodeSource?: SettingOrigin | null;
  /** The column is NOT NULL: `null` and `undefined` both mean "leave as is" (clients send an absent field as `null`). */
  electricityPriceMode?: ElectricityPriceMode | null;
  manualPricePerKwh?: number | null;
  electricityPriceSource?: SettingOrigin | null;
}

export type ElectricityPriceSource = 'eurostat' | 'government' | 'manual' | 'fallback';

/** Last known household price for a country (see modules/electricity). */
export interface ElectricityPriceRow {
  countryCode: string;
  currency: string;
  pricePerKwh: number;
  period: string;
  source: ElectricityPriceSource;
  includesTaxes: boolean | null;
  includesNetworkCosts: boolean | null;
  fetchedAt: Date;
}

export interface DailyUsageRow {
  userId: string;
  deviceId: string;
  date: string;
  mobileBytes: number;
  wifiBytes: number;
  chargedWh: number;
  wallWh: number;
  chargingSessions: number;
  estimatedCost: number;
  currency: string;
  dataEstimated: boolean;
  energyEstimated: boolean;
}

export interface AiGenerationRow {
  userId: string;
  task: string;
  mode: string;
  provider: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  /** 0 when `costBasis` is 'unknown'. */
  estimatedCostUsd: number;
  /** How the cost was derived; 'unknown' = the provider sent no usage, so 0 does not mean free. */
  costBasis: 'provider_reported' | 'model_price' | 'provider_estimate' | 'conservative_estimate' | 'unknown';
  /** False when the provider reported no token counts (they are stored as 0). */
  usageReported: boolean;
  latencyMs: number;
  createdAt: Date;
}

/** Optional per-session detail (`charging_summaries`); no API route writes it yet. */
export interface ChargingSummaryRow {
  userId: string;
  deviceId: string;
  startedAt: Date;
  endedAt: Date;
  startPercent: number;
  endPercent: number;
  mah: number;
  mahEstimated: boolean;
  batteryWh: number;
  wallWh: number;
  estimatedCost: number;
  createdAt: Date;
}

/** Per-month totals (`monthly_summaries`); no API route writes them yet. */
export interface MonthlySummaryRow {
  userId: string;
  /** `YYYY-MM`. */
  month: string;
  mobileBytes: number;
  wifiBytes: number;
  wallWh: number;
  chargingSessions: number;
  estimatedCost: number;
  currency: string;
  computedAt: Date;
}

export type SubscriptionStore = 'app_store' | 'play';
export type SubscriptionStatus = 'active' | 'grace' | 'expired' | 'revoked';

/** Store-verified purchase (`subscriptions`); written by the future receipt verification, read by the export. */
export interface SubscriptionRow {
  userId: string;
  store: SubscriptionStore;
  productId: string;
  originalTransactionId: string;
  status: SubscriptionStatus;
  expiresAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
}

export interface UserRepository {
  create(input: { email: string; passwordHash: string | null; displayName?: string | null }): Promise<UserRow>;
  findByEmail(email: string): Promise<UserRow | null>;
  findById(id: string): Promise<UserRow | null>;
  updateDisplayName(id: string, displayName: string | null): Promise<UserRow | null>;
  delete(id: string): Promise<void>;
}

export type RotateResult =
  | { status: 'ok'; userId: string }
  /** Unknown token. */
  | { status: 'invalid' }
  | { status: 'expired' }
  /** The token was already used or revoked; `family` tells whether every session of the user was revoked. */
  | { status: 'reused'; userId: string; familyRevoked: boolean };

export interface SessionRepository {
  create(input: { userId: string; refreshHash: string; expiresAt: Date }): Promise<SessionRow>;
  findByHash(refreshHash: string): Promise<SessionRow | null>;
  revoke(id: string, replacedBy?: string): Promise<void>;
  revokeAllForUser(userId: string): Promise<void>;
  /**
   * Atomically consumes `oldHash` and creates the next session. Exactly one of any
   * number of concurrent callers presenting the same token gets `ok`.
   * A token rotated less than `graceMs` ago (`now - revokedAt < graceMs`; exactly `graceMs` is theft) is rejected without revoking the user's
   * other sessions (a client retry after a lost response); an older one is theft:
   * every session of the user is revoked.
   */
  rotate(input: {
    oldHash: string;
    newHash: string;
    newExpiresAt: Date;
    now: Date;
    graceMs: number;
  }): Promise<RotateResult>;
}

export interface DeviceRepository {
  /** Fields left undefined/null keep their stored value, so a sync-time re-registration never erases the setup data. */
  upsert(input: DeviceUpsert): Promise<DeviceRow>;
  findForUser(userId: string, installationId: string): Promise<DeviceRow | null>;
  listForUser(userId: string): Promise<DeviceRow[]>;
  delete(userId: string, id: string): Promise<boolean>;
}

export interface UsageRepository {
  /** Insert-or-update keyed by (user, device, date); returns rows written. */
  upsertDaily(rows: DailyUsageRow[]): Promise<number>;
  listDaily(userId: string, from: string, to: string): Promise<DailyUsageRow[]>;
}

export interface SpendLimits {
  /** All providers together, per UTC day. */
  dailyUsd?: number;
  /** All providers together, per UTC month. */
  monthlyUsd?: number;
  /** This provider, per UTC day. */
  providerDailyUsd?: number;
}

export interface SpendReservationRequest {
  /** UTC day `YYYY-MM-DD`. */
  day: string;
  provider: string;
  usd: number;
  limits: SpendLimits;
}

export interface AiGenerationRepository {
  /**
   * Atomically takes one quota slot for `day` (UTC `YYYY-MM-DD`).
   * Returns the number of slots used afterwards, or null when `limit` is already reached.
   */
  reserve(userId: string, day: string, limit: number): Promise<number | null>;
  /** Gives a slot back (the provider call failed, the user got nothing). */
  release(userId: string, day: string): Promise<void>;
  /**
   * Stores the row and, unless `spend` is false, adds its cost to the day's spend (one operation: the log and the budget
   * never disagree). The API books spend through `reserveSpend`/`adjustSpend` before and after each provider call and
   * passes `spend: false`; the default is for callers that have no reservation.
   */
  insert(row: AiGenerationRow, options?: { spend?: boolean }): Promise<void>;
  /**
   * Holds `usd` on the day's spend for `provider`, atomically against the limits: it succeeds only when the day's total,
   * the month's total and the provider's day all stay within their limits afterwards. Concurrent callers are serialised,
   * so a burst cannot overshoot a limit together. Counts one request.
   */
  reserveSpend(request: SpendReservationRequest): Promise<{ ok: true } | { ok: false; exceeded: 'daily' | 'monthly' | 'provider' }>;
  /** Corrects a hold by `deltaUsd` (negative = give back) and the request count by `deltaRequests`; never below zero. */
  adjustSpend(adjustment: { day: string; provider: string; deltaUsd: number; deltaRequests: number }): Promise<void>;
  /**
   * USD spent from the start of UTC day `sinceDay` (`YYYY-MM-DD`) up to now, for one provider or all of them.
   * Read from the daily spend table, which survives data erasure and retention (it holds no user id).
   */
  spentUsd(sinceDay: string, provider?: string): Promise<number>;
}

export interface UserSettingsRepository {
  get(userId: string): Promise<UserSettingsRow | null>;
  /** Creates the row on first write; only the given fields change. */
  update(userId: string, patch: UserSettingsPatch): Promise<UserSettingsRow>;
}

export interface ElectricityPriceRepository {
  get(countryCode: string): Promise<ElectricityPriceRow | null>;
  set(row: ElectricityPriceRow): Promise<void>;
}

/** Rows removed by `CloudDataRepository.deleteData`. */
export interface CloudDeleteCounts {
  dailyUsage: number;
  chargingSummaries: number;
  monthlySummaries: number;
  aiGenerations: number;
  devices: number;
}

/** The account as exported: deliberately has no password hash. */
export interface CloudAccountRow {
  id: string;
  email: string;
  displayName: string | null;
  plan: Plan;
  createdAt: Date;
}

export type CloudExportCollection = 'devices' | 'dailyUsage' | 'chargingSummaries' | 'monthlySummaries' | 'aiGenerations' | 'subscriptions';

/** Everything the export document is made of, read from one consistent snapshot. */
export interface CloudExportData {
  account: CloudAccountRow;
  /** `null` until the user saved settings. */
  settings: UserSettingsRow | null;
  devices: DeviceRow[];
  dailyUsage: DailyUsageRow[];
  chargingSummaries: ChargingSummaryRow[];
  monthlySummaries: MonthlySummaryRow[];
  aiGenerations: AiGenerationRow[];
  subscriptions: SubscriptionRow[];
  /** True where the collection holds only its newest `maxRowsPerCollection` rows. */
  truncated: Record<CloudExportCollection, boolean>;
}

/**
 * Erasing and exporting an account's cloud data. Both return `null` for an account
 * that does not exist (e.g. a valid access token of a deleted account).
 */
export interface CloudDataRepository {
  /**
   * In ONE transaction removes the user's daily usage, charging and monthly summaries, AI
   * generation log and AI quota counters. Keeps the account, sessions, subscriptions, settings
   * and (unless `devices`) the registered devices, so sync can resume. Idempotent: a second
   * call finds nothing and returns zeros. Never touches another user's rows.
   */
  deleteData(userId: string, options?: { devices?: boolean }): Promise<CloudDeleteCounts | null>;
  /** Reads the account's data without password hash, sessions or any other user's rows; at most `maxRowsPerCollection` rows each (newest kept). */
  exportData(userId: string, maxRowsPerCollection: number): Promise<CloudExportData | null>;
}

export interface LoginThrottleRepository {
  /** `lockedUntil` is set while attempts for this key are refused. */
  status(key: string, now: Date): Promise<{ lockedUntil: Date | null }>;
  /** Counts one failed sign-in atomically (shared by all instances) and returns the resulting state. */
  recordFailure(key: string, now: Date): Promise<{ failures: number; lockedUntil: Date | null }>;
  /** A successful sign-in forgets the failures. */
  clear(key: string): Promise<void>;
  /** Removes rows untouched since `before`; returns how many. */
  purge(before: Date): Promise<number>;
}

export interface Repositories {
  readonly loginThrottle: LoginThrottleRepository;
  readonly users: UserRepository;
  readonly sessions: SessionRepository;
  readonly devices: DeviceRepository;
  readonly settings: UserSettingsRepository;
  readonly prices: ElectricityPriceRepository;
  readonly usage: UsageRepository;
  readonly ai: AiGenerationRepository;
  readonly cloud: CloudDataRepository;
  ping(): Promise<boolean>;
  close(): Promise<void>;
}
