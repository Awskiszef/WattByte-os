import { randomUUID } from 'node:crypto';

import { FAILURE_WINDOW_SEC, lockSeconds } from '../modules/auth/login-throttle.js';
import type {
  LoginThrottleRepository,
  AiGenerationRepository,
  AiGenerationRow,
  ChargingSummaryRow,
  CloudDataRepository,
  CloudDeleteCounts,
  CloudExportData,
  MonthlySummaryRow,
  RotateResult,
  SubscriptionRow,
  DailyUsageRow,
  DeviceRepository,
  DeviceRow,
  ElectricityPriceRepository,
  ElectricityPriceRow,
  Repositories,
  SessionRepository,
  SessionRow,
  UsageRepository,
  UserRepository,
  UserRow,
  UserSettingsRepository,
  UserSettingsRow,
} from './repositories.js';

/** In-memory repositories with the same semantics as Postgres (unique keys, upserts). */
export class MemoryRepositories implements Repositories {
  private readonly userRows = new Map<string, UserRow>();
  private readonly sessionRows = new Map<string, SessionRow>();
  private readonly deviceRows = new Map<string, DeviceRow>();
  private readonly usageRows = new Map<string, DailyUsageRow>();
  private readonly settingsRows = new Map<string, UserSettingsRow>();
  private readonly priceRows = new Map<string, ElectricityPriceRow>();
  private aiRows: AiGenerationRow[] = [];
  private readonly quota = new Map<string, number>();
  /** `day|provider` -> USD; the in-memory twin of ai_spend_daily (no user id, survives data erasure). */
  private readonly spend = new Map<string, number>();
  /** `day|plan` -> USD (the twin of ai_spend_plan_daily). */
  private readonly planSpend = new Map<string, number>();
  private readonly chargingRows = new Map<string, ChargingSummaryRow>();
  private readonly monthlyRows = new Map<string, MonthlySummaryRow>();
  private readonly subscriptionRows = new Map<string, SubscriptionRow>();
  private readonly throttle = new Map<string, { failures: number; lockedUntil: Date | null; updatedAt: Date }>();

  readonly users: UserRepository = {
    create: async ({ email, passwordHash, displayName }) => {
      if ([...this.userRows.values()].some((u) => u.email === email.toLowerCase())) {
        throw new UniqueViolation('users.email');
      }
      const row: UserRow = {
        id: randomUUID(),
        email: email.toLowerCase(),
        passwordHash,
        displayName: displayName ?? null,
        plan: 'free',
        createdAt: new Date(),
      };
      this.userRows.set(row.id, row);
      return row;
    },
    findByEmail: async (email) => [...this.userRows.values()].find((u) => u.email === email.toLowerCase()) ?? null,
    findById: async (id) => this.userRows.get(id) ?? null,
    updateDisplayName: async (id, displayName) => {
      const row = this.userRows.get(id);
      if (!row) return null;
      const next = { ...row, displayName };
      this.userRows.set(id, next);
      return next;
    },
    // Mirrors ON DELETE CASCADE: every table with a user_id loses the user's rows.
    delete: async (id) => {
      this.userRows.delete(id);
      removeWhere(this.sessionRows, (s) => s.userId === id);
      removeWhere(this.deviceRows, (d) => d.userId === id);
      this.eraseCloudRows(id);
      removeWhere(this.subscriptionRows, (s) => s.userId === id);
      this.settingsRows.delete(id);
    },
  };

  readonly sessions: SessionRepository = {
    create: async ({ userId, refreshHash, expiresAt }) => {
      const row: SessionRow = {
        id: randomUUID(),
        userId,
        refreshHash,
        expiresAt,
        revokedAt: null,
        replacedBy: null,
        createdAt: new Date(),
      };
      this.sessionRows.set(row.id, row);
      return row;
    },
    findByHash: async (hash) => [...this.sessionRows.values()].find((s) => s.refreshHash === hash) ?? null,
    revoke: async (id, replacedBy) => {
      const row = this.sessionRows.get(id);
      if (row) this.sessionRows.set(id, { ...row, revokedAt: new Date(), replacedBy: replacedBy ?? null });
    },
    revokeAllForUser: async (userId) => {
      for (const [id, s] of this.sessionRows) {
        if (s.userId === userId && !s.revokedAt) this.sessionRows.set(id, { ...s, revokedAt: new Date() });
      }
    },
    // No await between the check and the writes: atomic on the single JS thread.
    rotate: async ({ oldHash, newHash, newExpiresAt, now, graceMs }): Promise<RotateResult> => {
      const old = [...this.sessionRows.values()].find((s) => s.refreshHash === oldHash);
      if (!old) return { status: 'invalid' };
      if (old.revokedAt) {
        const rotatedRecently = old.replacedBy !== null && now.getTime() - old.revokedAt.getTime() < graceMs;
        if (!rotatedRecently) {
          for (const [id, s] of this.sessionRows) {
            if (s.userId === old.userId && !s.revokedAt) this.sessionRows.set(id, { ...s, revokedAt: now });
          }
        }
        return { status: 'reused', userId: old.userId, familyRevoked: !rotatedRecently };
      }
      if (old.expiresAt <= now) return { status: 'expired' };
      const next: SessionRow = {
        id: randomUUID(),
        userId: old.userId,
        refreshHash: newHash,
        expiresAt: newExpiresAt,
        revokedAt: null,
        replacedBy: null,
        createdAt: now,
      };
      this.sessionRows.set(next.id, next);
      this.sessionRows.set(old.id, { ...old, revokedAt: now, replacedBy: next.id });
      return { status: 'ok', userId: old.userId };
    },
  };

  readonly devices: DeviceRepository = {
    upsert: async (input) => {
      if (!this.userRows.has(input.userId)) throw new ForeignKeyViolation('devices.user_id');
      const existing = [...this.deviceRows.values()].find(
        (d) => d.userId === input.userId && d.installationId === input.installationId,
      );
      const base: DeviceRow = existing ?? {
        id: randomUUID(),
        userId: input.userId,
        installationId: input.installationId,
        platform: input.platform,
        model: null,
        modelIdentifier: null,
        designCapacityMah: null,
        designCapacityWh: null,
        designCapacitySource: null,
        estimatedFullChargeCapacityMah: null,
        estimatedFullChargeCapacityWh: null,
        fullChargeCapacitySource: null,
        fullChargeCapacityConfidence: null,
        createdAt: new Date(),
        lastSeenAt: new Date(),
      };
      // Same rule as the SQL upsert: a group is replaced as a whole (nulls included) when its source is
      // given, otherwise the stored group stays untouched.
      const design =
        input.designCapacitySource != null
          ? {
              designCapacityMah: input.designCapacityMah ?? null,
              designCapacityWh: input.designCapacityWh ?? null,
              designCapacitySource: input.designCapacitySource,
            }
          : {};
      const estimate =
        input.fullChargeCapacitySource != null
          ? {
              estimatedFullChargeCapacityMah: input.estimatedFullChargeCapacityMah ?? null,
              estimatedFullChargeCapacityWh: input.estimatedFullChargeCapacityWh ?? null,
              fullChargeCapacitySource: input.fullChargeCapacitySource,
              fullChargeCapacityConfidence: input.fullChargeCapacityConfidence ?? null,
            }
          : {};
      const row: DeviceRow = {
        ...base,
        platform: input.platform,
        model: input.model ?? base.model,
        modelIdentifier: input.modelIdentifier ?? base.modelIdentifier,
        ...design,
        ...estimate,
        lastSeenAt: new Date(),
      };
      this.deviceRows.set(row.id, row);
      return row;
    },
    findForUser: async (userId, installationId) =>
      [...this.deviceRows.values()].find((d) => d.userId === userId && d.installationId === installationId) ?? null,
    listForUser: async (userId) => [...this.deviceRows.values()].filter((d) => d.userId === userId),
    delete: async (userId, id) => {
      const row = this.deviceRows.get(id);
      if (!row || row.userId !== userId) return false;
      this.deviceRows.delete(id);
      removeWhere(this.usageRows, (u) => u.deviceId === id);
      removeWhere(this.chargingRows, (c) => c.deviceId === id);
      return true;
    },
  };

  readonly settings: UserSettingsRepository = {
    get: async (userId) => this.settingsRows.get(userId) ?? null,
    update: async (userId, patch) => {
      if (!this.userRows.has(userId)) throw new ForeignKeyViolation('user_settings.user_id');
      const base: UserSettingsRow = this.settingsRows.get(userId) ?? {
        userId,
        countryCode: null,
        countryCodeSource: null,
        currencyCode: null,
        currencyCodeSource: null,
        electricityPriceMode: 'automatic',
        manualPricePerKwh: null,
        electricityPriceSource: null,
        updatedAt: new Date(),
      };
      const row: UserSettingsRow = {
        ...base,
        countryCode: patch.countryCode === undefined ? base.countryCode : patch.countryCode,
        countryCodeSource: patch.countryCodeSource === undefined ? base.countryCodeSource : patch.countryCodeSource,
        currencyCode: patch.currencyCode === undefined ? base.currencyCode : patch.currencyCode,
        currencyCodeSource: patch.currencyCodeSource === undefined ? base.currencyCodeSource : patch.currencyCodeSource,
        electricityPriceMode: patch.electricityPriceMode ?? base.electricityPriceMode,
        manualPricePerKwh: patch.manualPricePerKwh === undefined ? base.manualPricePerKwh : patch.manualPricePerKwh,
        electricityPriceSource: patch.electricityPriceSource === undefined ? base.electricityPriceSource : patch.electricityPriceSource,
        updatedAt: new Date(),
      };
      this.settingsRows.set(userId, row);
      return row;
    },
  };

  readonly prices: ElectricityPriceRepository = {
    get: async (countryCode) => this.priceRows.get(countryCode) ?? null,
    set: async (row) => {
      this.priceRows.set(row.countryCode, row);
    },
  };

  readonly usage: UsageRepository = {
    upsertDaily: async (rows) => {
      for (const r of rows) this.usageRows.set(`${r.userId}|${r.deviceId}|${r.date}`, { ...r });
      return rows.length;
    },
    listDaily: async (userId, from, to) =>
      [...this.usageRows.values()]
        .filter((r) => r.userId === userId && r.date >= from && r.date <= to)
        .sort((a, b) => a.date.localeCompare(b.date)),
  };

  readonly ai: AiGenerationRepository = {
    reserve: async (userId, day, limit) => {
      if (!this.userRows.has(userId)) throw new ForeignKeyViolation('ai_quota_usage.user_id');
      const key = `${userId}|${day}`;
      const used = this.quota.get(key) ?? 0;
      if (used >= limit) return null;
      this.quota.set(key, used + 1);
      return used + 1;
    },
    release: async (userId, day) => {
      const key = `${userId}|${day}`;
      this.quota.set(key, Math.max(0, (this.quota.get(key) ?? 0) - 1));
    },
    insert: async (row, { spend = true } = {}) => {
      this.aiRows.push({ ...row });
      if (!spend) return;
      const key = `${row.createdAt.toISOString().slice(0, 10)}|${row.provider}`;
      this.spend.set(key, (this.spend.get(key) ?? 0) + row.estimatedCostUsd);
    },
    // No await inside: atomic on the single JS thread, like the serialised PostgreSQL transaction.
    reserveSpend: async ({ day, provider, plan, usd, limits }) => {
      const month = `${day.slice(0, 8)}01`;
      let dayTotal = 0;
      let monthTotal = 0;
      let providerDay = 0;
      for (const [key, spent] of this.spend) {
        const [d, who] = key.split('|') as [string, string];
        if (d >= month) monthTotal += spent;
        if (d === day) dayTotal += spent;
        if (d === day && who === provider) providerDay += spent;
      }
      const over = (spent: number, limit: number | undefined): boolean => limit !== undefined && spent + usd > limit + 1e-9;
      if (over(dayTotal, limits.dailyUsd)) return { ok: false, exceeded: 'daily' };
      if (over(monthTotal, limits.monthlyUsd)) return { ok: false, exceeded: 'monthly' };
      if (over(providerDay, limits.providerDailyUsd)) return { ok: false, exceeded: 'provider' };
      if (over(this.planSpend.get(`${day}|${plan}`) ?? 0, limits.planDailyUsd)) return { ok: false, exceeded: 'plan' };
      const key = `${day}|${provider}`;
      this.spend.set(key, (this.spend.get(key) ?? 0) + usd);
      this.planSpend.set(`${day}|${plan}`, (this.planSpend.get(`${day}|${plan}`) ?? 0) + usd);
      return { ok: true };
    },
    adjustSpend: async ({ day, provider, plan, deltaUsd }) => {
      const key = `${day}|${provider}`;
      this.spend.set(key, Math.max(0, (this.spend.get(key) ?? 0) + deltaUsd));
      const planKey = `${day}|${plan}`;
      this.planSpend.set(planKey, Math.max(0, (this.planSpend.get(planKey) ?? 0) + deltaUsd));
    },
    spentUsd: async (sinceDay, provider) => {
      let total = 0;
      for (const [key, usd] of this.spend) {
        const [day, who] = key.split('|') as [string, string];
        if (day >= sinceDay && (provider === undefined || who === provider)) total += usd;
      }
      return Math.round(total * 1e6) / 1e6;
    },
  };

  readonly cloud: CloudDataRepository = {
    // No await between the existence check and the removals: atomic on the single JS thread, like the Postgres transaction.
    deleteData: async (userId, { devices = false } = {}) => {
      if (!this.userRows.has(userId)) return null;
      const counts = this.eraseCloudRows(userId);
      // Rows that reference a device are already gone, so removing the devices cascades into nothing.
      if (devices) counts.devices = removeWhere(this.deviceRows, (d) => d.userId === userId);
      return counts;
    },
    exportData: async (userId, max): Promise<CloudExportData | null> => {
      const user = this.userRows.get(userId);
      if (!user) return null;
      const mine = <T extends { userId: string }>(rows: Iterable<T>): T[] => [...rows].filter((r) => r.userId === userId).map((r) => ({ ...r }));
      const devices = newest(mine(this.deviceRows.values()).sort(by((d) => d.createdAt.getTime(), (d) => d.id)), max);
      const dailyUsage = newest(mine(this.usageRows.values()).sort(by((u) => u.date, (u) => u.deviceId)), max);
      const chargingSummaries = newest(mine(this.chargingRows.values()).sort(by((c) => c.startedAt.getTime(), (c) => c.deviceId)), max);
      const monthlySummaries = newest(mine(this.monthlyRows.values()).sort(by((m) => m.month)), max);
      const aiGenerations = newest(mine(this.aiRows).sort(by((a) => a.createdAt.getTime())), max);
      const subscriptions = newest(mine(this.subscriptionRows.values()).sort(by((s) => s.createdAt.getTime(), (s) => s.productId)), max);
      const settings = this.settingsRows.get(userId);
      return {
        account: { id: user.id, email: user.email, displayName: user.displayName, plan: user.plan, createdAt: user.createdAt },
        settings: settings ? { ...settings } : null,
        devices: devices.rows,
        dailyUsage: dailyUsage.rows,
        chargingSummaries: chargingSummaries.rows,
        monthlySummaries: monthlySummaries.rows,
        aiGenerations: aiGenerations.rows,
        subscriptions: subscriptions.rows,
        truncated: {
          devices: devices.truncated,
          dailyUsage: dailyUsage.truncated,
          chargingSummaries: chargingSummaries.truncated,
          monthlySummaries: monthlySummaries.truncated,
          aiGenerations: aiGenerations.truncated,
          subscriptions: subscriptions.truncated,
        },
      };
    },
  };

  /**
   * Writers for tables no API route fills yet (charging and monthly summaries, store subscriptions),
   * so tests can put rows there. The PostgreSQL tests insert the same rows with SQL.
   */
  readonly seed = {
    chargingSummary: (row: ChargingSummaryRow): void => {
      this.requireUser(row.userId, 'charging_summaries.user_id');
      this.chargingRows.set(`${row.userId}|${row.deviceId}|${row.startedAt.toISOString()}`, { ...row });
    },
    monthlySummary: (row: MonthlySummaryRow): void => {
      this.requireUser(row.userId, 'monthly_summaries.user_id');
      this.monthlyRows.set(`${row.userId}|${row.month}`, { ...row });
    },
    subscription: (row: SubscriptionRow): void => {
      this.requireUser(row.userId, 'subscriptions.user_id');
      this.subscriptionRows.set(`${row.store}|${row.originalTransactionId}`, { ...row });
    },
  };

  private requireUser(userId: string, constraint: string): void {
    if (!this.userRows.has(userId)) throw new ForeignKeyViolation(constraint);
  }

  /** Removes the rows that belong to cloud sync and the AI log (everything but account, sessions, subscriptions, settings, devices). */
  private eraseCloudRows(userId: string): CloudDeleteCounts {
    const aiBefore = this.aiRows.length;
    this.aiRows = this.aiRows.filter((r) => r.userId !== userId);
    // The quota counters stay (abuse prevention, see postgres.ts); only account deletion removes them.
    return {
      dailyUsage: removeWhere(this.usageRows, (u) => u.userId === userId),
      chargingSummaries: removeWhere(this.chargingRows, (c) => c.userId === userId),
      monthlySummaries: removeWhere(this.monthlyRows, (m) => m.userId === userId),
      aiGenerations: aiBefore - this.aiRows.length,
      devices: 0,
    };
  }

  readonly loginThrottle: LoginThrottleRepository = {
    status: async (key, now) => {
      const row = this.throttle.get(key);
      return { lockedUntil: row?.lockedUntil && row.lockedUntil > now ? row.lockedUntil : null };
    },
    recordFailure: async (key, now) => {
      const row = this.throttle.get(key);
      const expired = !row || now.getTime() - row.updatedAt.getTime() > FAILURE_WINDOW_SEC * 1000;
      const failures = expired ? 1 : row.failures + 1;
      const seconds = lockSeconds(failures);
      const lockedUntil = seconds > 0 ? new Date(now.getTime() + seconds * 1000) : null;
      this.throttle.set(key, { failures, lockedUntil, updatedAt: now });
      return { failures, lockedUntil };
    },
    clear: async (key) => void this.throttle.delete(key),
    purge: async (before) => removeWhere(this.throttle, (r) => r.updatedAt < before),
  };

  async ping(): Promise<boolean> {
    return true;
  }

  async close(): Promise<void> {}
}

function removeWhere<V>(map: Map<string, V>, predicate: (value: V) => boolean): number {
  let removed = 0;
  for (const [key, value] of map) {
    if (predicate(value)) {
      map.delete(key);
      removed += 1;
    }
  }
  return removed;
}

/** Comparator: by the first key, then the following ones (numbers and strings ascending). */
function by<T>(...keys: ((row: T) => string | number)[]): (a: T, b: T) => number {
  return (a, b) => {
    for (const key of keys) {
      const [x, y] = [key(a), key(b)];
      if (x < y) return -1;
      if (x > y) return 1;
    }
    return 0;
  };
}

/** Keeps the last `max` rows of an ascending list (the newest) and says whether anything was cut. */
function newest<T>(rows: T[], max: number): { rows: T[]; truncated: boolean } {
  return rows.length > max ? { rows: rows.slice(rows.length - max), truncated: true } : { rows, truncated: false };
}

/** Mirrors Postgres unique-constraint failures so services handle both the same way. */
export class UniqueViolation extends Error {
  constructor(readonly constraint: string) {
    super(`unique violation: ${constraint}`);
    this.name = 'UniqueViolation';
  }
}

/** Mirrors a PostgreSQL foreign-key failure (SQLSTATE 23503), e.g. a token of a deleted account. */
export class ForeignKeyViolation extends Error {
  constructor(readonly constraint: string) {
    super(`foreign key violation: ${constraint}`);
    this.name = 'ForeignKeyViolation';
  }
}
