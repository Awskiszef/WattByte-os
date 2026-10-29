import { randomUUID } from 'node:crypto';

import pg from 'pg';

import { DEFAULT_POOL_TUNING, poolSettings } from './connection.js';
import { BASE_LOCK_SEC, FAILURE_WINDOW_SEC, LOCK_AFTER, MAX_LOCK_SEC } from '../modules/auth/login-throttle.js';
import { DeviceLimitReached, ForeignKeyViolation, UniqueViolation } from './memory.js';
import type {
  LoginThrottleRepository,
  AiGenerationRepository,
  AiGenerationRow,
  ChargingSummaryRow,
  CloudDataRepository,
  CloudDeleteCounts,
  CloudExportData,
  MonthlySummaryRow,
  SubscriptionRow,
  DailyUsageRow,
  DeviceRepository,
  DeviceRow,
  ElectricityPriceRepository,
  ElectricityPriceRow,
  Repositories,
  RotateResult,
  SessionRepository,
  SessionRow,
  UsageRepository,
  UserRepository,
  UserRow,
  UserSettingsRepository,
  UserSettingsRow,
} from './repositories.js';

type Row = Record<string, unknown>;

const num = (v: unknown): number => (typeof v === 'number' ? v : Number(v));
const numOrNull = (v: unknown): number | null => (v == null ? null : num(v));

function toUser(r: Row): UserRow {
  return {
    id: r.id as string,
    email: r.email as string,
    passwordHash: (r.password_hash as string | null) ?? null,
    displayName: (r.display_name as string | null) ?? null,
    plan: r.plan as UserRow['plan'],
    createdAt: r.created_at as Date,
    tokensValidAfter: (r.tokens_valid_after as Date | null) ?? null,
  };
}

function toSession(r: Row): SessionRow {
  return {
    id: r.id as string,
    userId: r.user_id as string,
    refreshHash: r.refresh_hash as string,
    expiresAt: r.expires_at as Date,
    revokedAt: (r.revoked_at as Date | null) ?? null,
    replacedBy: (r.replaced_by as string | null) ?? null,
    createdAt: r.created_at as Date,
    familyId: r.family_id as string,
    familyStartedAt: r.family_started_at as Date,
  };
}

function toDevice(r: Row): DeviceRow {
  return {
    id: r.id as string,
    userId: r.user_id as string,
    installationId: r.installation_id as string,
    platform: r.platform as DeviceRow['platform'],
    model: (r.model as string | null) ?? null,
    modelIdentifier: (r.model_identifier as string | null) ?? null,
    designCapacityMah: numOrNull(r.design_capacity_mah),
    designCapacityWh: numOrNull(r.design_capacity_wh),
    designCapacitySource: (r.design_capacity_source as DeviceRow['designCapacitySource']) ?? null,
    estimatedFullChargeCapacityMah: numOrNull(r.estimated_full_charge_capacity_mah),
    estimatedFullChargeCapacityWh: numOrNull(r.estimated_full_charge_capacity_wh),
    fullChargeCapacitySource: (r.full_charge_capacity_source as DeviceRow['fullChargeCapacitySource']) ?? null,
    fullChargeCapacityConfidence: (r.full_charge_capacity_confidence as DeviceRow['fullChargeCapacityConfidence']) ?? null,
    createdAt: r.created_at as Date,
    lastSeenAt: r.last_seen_at as Date,
  };
}

function toSettings(r: Row): UserSettingsRow {
  return {
    userId: r.user_id as string,
    countryCode: (r.country_code as string | null) ?? null,
    countryCodeSource: (r.country_code_source as UserSettingsRow['countryCodeSource']) ?? null,
    currencyCode: (r.currency as string | null) ?? null,
    currencyCodeSource: (r.currency_source as UserSettingsRow['currencyCodeSource']) ?? null,
    electricityPriceMode: r.electricity_price_mode as UserSettingsRow['electricityPriceMode'],
    manualPricePerKwh: numOrNull(r.manual_price_per_kwh),
    electricityPriceSource: (r.electricity_price_source as UserSettingsRow['electricityPriceSource']) ?? null,
    updatedAt: r.updated_at as Date,
  };
}

function toPrice(r: Row): ElectricityPriceRow {
  return {
    countryCode: r.country_code as string,
    currency: r.currency as string,
    pricePerKwh: num(r.price_per_kwh),
    period: r.period as string,
    source: r.source as ElectricityPriceRow['source'],
    includesTaxes: (r.includes_taxes as boolean | null) ?? null,
    includesNetworkCosts: (r.includes_network_costs as boolean | null) ?? null,
    fetchedAt: r.fetched_at as Date,
  };
}

function toUsage(r: Row): DailyUsageRow {
  return {
    userId: r.user_id as string,
    deviceId: r.device_id as string,
    date: r.date as string,
    mobileBytes: num(r.mobile_bytes),
    wifiBytes: num(r.wifi_bytes),
    chargedWh: num(r.charged_wh),
    wallWh: num(r.wall_wh),
    chargingSessions: num(r.charging_sessions),
    estimatedCost: num(r.estimated_cost),
    currency: r.currency as string,
    dataEstimated: r.data_estimated as boolean,
    energyEstimated: r.energy_estimated as boolean,
  };
}

function toCharging(r: Row): ChargingSummaryRow {
  return {
    userId: r.user_id as string,
    deviceId: r.device_id as string,
    startedAt: r.started_at as Date,
    endedAt: r.ended_at as Date,
    startPercent: num(r.start_percent),
    endPercent: num(r.end_percent),
    mah: num(r.mah),
    mahEstimated: r.mah_estimated as boolean,
    batteryWh: num(r.battery_wh),
    wallWh: num(r.wall_wh),
    estimatedCost: num(r.estimated_cost),
    createdAt: r.created_at as Date,
  };
}

function toMonthly(r: Row): MonthlySummaryRow {
  return {
    userId: r.user_id as string,
    month: r.month as string,
    mobileBytes: num(r.mobile_bytes),
    wifiBytes: num(r.wifi_bytes),
    wallWh: num(r.wall_wh),
    chargingSessions: num(r.charging_sessions),
    estimatedCost: num(r.estimated_cost),
    currency: r.currency as string,
    computedAt: r.computed_at as Date,
  };
}

function toAiGeneration(r: Row): AiGenerationRow {
  return {
    userId: r.user_id as string,
    task: r.generation_type as string,
    mode: r.mode as string,
    provider: r.provider as string,
    model: r.model as string,
    inputTokens: num(r.input_tokens),
    outputTokens: num(r.output_tokens),
    estimatedCostUsd: num(r.estimated_cost_usd),
    costBasis: ((r.cost_basis as string | undefined) ?? 'provider_estimate') as AiGenerationRow['costBasis'],
    usageReported: (r.usage_reported as boolean | undefined) ?? true,
    latencyMs: num(r.latency_ms),
    createdAt: r.created_at as Date,
  };
}

function toSubscription(r: Row): SubscriptionRow {
  return {
    userId: r.user_id as string,
    store: r.store as SubscriptionRow['store'],
    productId: r.product_id as string,
    originalTransactionId: r.original_tx_id as string,
    status: r.status as SubscriptionRow['status'],
    expiresAt: (r.expires_at as Date | null) ?? null,
    createdAt: r.created_at as Date,
    updatedAt: r.updated_at as Date,
  };
}

/** Serialises spend reservations across all API instances (pg advisory lock key, distinct from the retention job's). */
const AI_SPEND_LOCK_KEY = 727_276;

/** Tables `deleteData` empties for a user; a closed list, because the names are spliced into SQL. */
type CloudTable = 'daily_usage' | 'charging_summaries' | 'monthly_summaries' | 'ai_generations' | 'devices';

function translate(e: unknown): never {
  const code = e && typeof e === 'object' ? (e as { code?: string }).code : undefined;
  const constraint = (e as { constraint?: string } | null)?.constraint;
  if (code === '23505') throw new UniqueViolation(constraint ?? 'unique');
  if (code === '23503') throw new ForeignKeyViolation(constraint ?? 'foreign_key');
  throw e;
}

/** PostgreSQL implementation; `pg` returns DATE columns as strings via the type parser below. */
export class PostgresRepositories implements Repositories {
  private readonly pool: pg.Pool;
  private readonly onError?: (e: Error) => void;

  constructor(
    connectionString: string,
    options: { max?: number; ssl?: pg.PoolConfig['ssl']; statementTimeoutMs?: number; onError?: (e: Error) => void } = {},
  ) {
    pg.types.setTypeParser(1082, (v) => v); // DATE -> 'YYYY-MM-DD'
    this.onError = options.onError;
    this.pool = new pg.Pool({
      connectionString,
      ssl: options.ssl,
      ...poolSettings({ max: options.max ?? DEFAULT_POOL_TUNING.max, statementTimeoutMs: options.statementTimeoutMs ?? DEFAULT_POOL_TUNING.statementTimeoutMs }),
    });
    // An idle client can be dropped by the server or a proxy; without a listener
    // the 'error' event would crash the whole process.
    this.pool.on('error', (e) => this.reportError(e));
  }

  private reportError(error: Error): void {
    // Logging must not turn a handled connection failure into an uncaught exception.
    try {
      this.onError?.(error);
    } catch {
      // The transaction still rejects with the original database error.
    }
  }

  private async withTransaction<T>(run: (client: pg.PoolClient) => Promise<T>, begin = 'BEGIN'): Promise<T> {
    const client = await this.pool.connect();
    let connectionError: Error | undefined;
    let rollbackFailed = false;
    const onClientError = (error: Error): void => {
      connectionError ??= error;
      this.reportError(error);
    };
    // pg-pool only listens while a client is idle in the pool, not during checkout.
    client.on('error', onClientError);
    try {
      await client.query(begin);
      if (connectionError) throw connectionError;
      const result = await run(client);
      if (connectionError) throw connectionError;
      await client.query('COMMIT');
      // The commit was acknowledged: a connection that drops now still leaves the data written.
      // The result is returned and the client is discarded on release below.
      return result;
    } catch (error) {
      // A failed rollback must neither replace the cause nor return an open transaction to the pool.
      await client.query('ROLLBACK').catch(() => { rollbackFailed = true; });
      throw connectionError ?? error;
    } finally {
      // release reinstalls pg-pool's idle listener before ours is removed.
      client.release(connectionError ?? (rollbackFailed || undefined));
      client.removeListener('error', onClientError);
    }
  }

  private async one<T>(sql: string, params: unknown[], map: (r: Row) => T): Promise<T | null> {
    const res = await this.pool.query(sql, params).catch(translate);
    return res.rows[0] ? map(res.rows[0] as Row) : null;
  }

  private async many<T>(sql: string, params: unknown[], map: (r: Row) => T): Promise<T[]> {
    const res = await this.pool.query(sql, params).catch(translate);
    return (res.rows as Row[]).map(map);
  }

  readonly users: UserRepository = {
    create: async ({ email, passwordHash, displayName }) =>
      (await this.one(
        'INSERT INTO users(email, password_hash, display_name) VALUES ($1, $2, $3) RETURNING *',
        [email.toLowerCase(), passwordHash, displayName ?? null],
        toUser,
      ))!,
    // lower(email) on BOTH sides: that is the expression users_email_key indexes (a plain `email = lower($1)` scans the table).
    findByEmail: (email) => this.one('SELECT * FROM users WHERE lower(email) = lower($1)', [email], toUser),
    findById: (id) => this.one('SELECT * FROM users WHERE id = $1', [id], toUser),
    updateDisplayName: (id, displayName) =>
      this.one('UPDATE users SET display_name = $2, updated_at = now() WHERE id = $1 RETURNING *', [id, displayName], toUser),
    setPasswordHash: (id, passwordHash) =>
      this.one('UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1 RETURNING *', [id, passwordHash], toUser),
    invalidateTokensBefore: async (id, at) => {
      await this.pool.query('UPDATE users SET tokens_valid_after = $2 WHERE id = $1', [id, at]).catch(translate);
    },
    delete: async (id) => {
      await this.pool.query('DELETE FROM users WHERE id = $1', [id]);
    },
  };

  readonly loginThrottle: LoginThrottleRepository = {
    status: async (key, now) => {
      const res = await this.pool.query('SELECT locked_until FROM login_throttle WHERE key = $1 AND locked_until > $2', [key, now]).catch(translate);
      return { lockedUntil: (res.rows[0]?.locked_until as Date | undefined) ?? null };
    },
    // One statement, so concurrent failures from any number of instances all count (no read-modify-write race).
    recordFailure: async (key, now) => {
      const next = `CASE WHEN login_throttle.updated_at < $2::timestamptz - make_interval(secs => $3) THEN 1 ELSE login_throttle.failures + 1 END`;
      const res = await this.pool
        .query(
          `INSERT INTO login_throttle(key, failures, locked_until, updated_at) VALUES ($1, 1, NULL, $2)
           ON CONFLICT (key) DO UPDATE SET
             failures = ${next},
             locked_until = CASE WHEN ${next} >= $4
               THEN $2::timestamptz + make_interval(secs => LEAST($6::double precision, $5::double precision * power(2, LEAST(${next} - $4, 20))))
               ELSE NULL END,
             updated_at = $2
           RETURNING failures, locked_until`,
          [key, now, FAILURE_WINDOW_SEC, LOCK_AFTER, BASE_LOCK_SEC, MAX_LOCK_SEC],
        )
        .catch(translate);
      const row = res.rows[0] as Row;
      return { failures: row.failures as number, lockedUntil: (row.locked_until as Date | null) ?? null };
    },
    clear: async (key) => {
      await this.pool.query('DELETE FROM login_throttle WHERE key = $1', [key]).catch(translate);
    },
    purge: async (before) => {
      const res = await this.pool.query('DELETE FROM login_throttle WHERE updated_at < $1', [before]).catch(translate);
      return res.rowCount ?? 0;
    },
  };

  readonly sessions: SessionRepository = {
    create: async ({ userId, refreshHash, expiresAt, familyId, familyStartedAt }) => {
      const id = randomUUID();
      return (await this.one(
        // A new sign-in starts its own family (family_id = its own id) unless it continues one.
        `INSERT INTO sessions(id, user_id, refresh_hash, expires_at, family_id, family_started_at)
         VALUES ($1, $2, $3, $4, $5, COALESCE($6::timestamptz, now())) RETURNING *`,
        [id, userId, refreshHash, expiresAt, familyId ?? id, familyStartedAt ?? null],
        toSession,
      ))!;
    },
    findByHash: (hash) => this.one('SELECT * FROM sessions WHERE refresh_hash = $1', [hash], toSession),
    revoke: async (id, replacedBy) => {
      await this.pool.query('UPDATE sessions SET revoked_at = now(), replaced_by = $2 WHERE id = $1', [id, replacedBy ?? null]);
    },
    revokeFamily: async (familyId) => {
      await this.pool.query('UPDATE sessions SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL', [familyId]);
    },
    revokeAllForUser: async (userId) => {
      await this.pool.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
    },
    familyLive: async (familyId, now) => {
      const res = await this.pool.query('SELECT 1 FROM sessions WHERE family_id = $1 AND revoked_at IS NULL AND expires_at > $2 LIMIT 1', [familyId, now]);
      return (res.rowCount ?? 0) > 0;
    },
    listFamilies: async (userId, now) => {
      const res = await this.pool.query(
        `SELECT family_id, family_started_at, created_at, expires_at FROM sessions
         WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > $2 ORDER BY created_at DESC`,
        [userId, now],
      );
      return res.rows.map((r: Row) => ({
        id: r.family_id as string,
        startedAt: r.family_started_at as Date,
        lastRotatedAt: r.created_at as Date,
        expiresAt: r.expires_at as Date,
      }));
    },
    rotate: async ({ oldHash, newHash, newExpiresAt, now, graceMs, absoluteLifetimeMs }): Promise<RotateResult> => {
      return this.withTransaction<RotateResult>(async (client) => {
        // The row lock serialises concurrent presentations of the same token:
        // the first one consumes it, the others wake up and see it revoked.
        const found = await client.query('SELECT * FROM sessions WHERE refresh_hash = $1 FOR UPDATE', [oldHash]);
        const old = found.rows[0] ? toSession(found.rows[0] as Row) : null;
        if (!old) {
          return { status: 'invalid' };
        }
        if (old.revokedAt) {
          // Revoked without a successor (logout, sign out everywhere, an earlier family revocation): a plain 401.
          if (old.replacedBy === null) return { status: 'revoked' };
          const successor = (await client.query('SELECT refresh_hash, revoked_at FROM sessions WHERE id = $1', [old.replacedBy])).rows[0] as Row | undefined;
          const retry = now.getTime() - old.revokedAt.getTime() < graceMs && successor !== undefined && successor.revoked_at === null && successor.refresh_hash === newHash;
          if (retry) return { status: 'replayed', userId: old.userId, familyId: old.familyId };
          await client.query('UPDATE sessions SET revoked_at = $2 WHERE family_id = $1 AND revoked_at IS NULL', [old.familyId, now]);
          return { status: 'reused', userId: old.userId, familyRevoked: true };
        }
        if (old.expiresAt <= now) {
          return { status: 'expired' };
        }
        if (old.familyStartedAt.getTime() + absoluteLifetimeMs <= now.getTime()) {
          return { status: 'expired' };
        }
        const created = await client.query(
          'INSERT INTO sessions(user_id, refresh_hash, expires_at, family_id, family_started_at, created_at) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id',
          [old.userId, newHash, newExpiresAt, old.familyId, old.familyStartedAt, now],
        );
        // revoked_at is stamped with the API clock (`now`), the same clock the grace window is compared with:
        // the database clock may differ between hosts and would shift the window by the skew.
        await client.query('UPDATE sessions SET revoked_at = $3, replaced_by = $2 WHERE id = $1', [old.id, (created.rows[0] as Row).id, now]);
        return { status: 'ok', userId: old.userId, familyId: old.familyId };
      }).catch(translate);
    },
  };

  readonly devices: DeviceRepository = {
    upsert: async (d, options = {}) => {
        // Each battery group (design / estimate) is replaced as a whole, nulls included, when its SOURCE is
        // given; with a null source the stored group stays untouched. A per-column COALESCE would mix a new
        // value with a stale one (a design figure of one source next to a number of another).
      const sql = `INSERT INTO devices(user_id, installation_id, platform, model, model_identifier,
                             design_capacity_mah, design_capacity_wh, design_capacity_source,
                             estimated_full_charge_capacity_mah, estimated_full_charge_capacity_wh,
                             full_charge_capacity_source, full_charge_capacity_confidence)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
         ON CONFLICT (user_id, installation_id) DO UPDATE
           SET platform = EXCLUDED.platform,
               model = COALESCE(EXCLUDED.model, devices.model),
               model_identifier = COALESCE(EXCLUDED.model_identifier, devices.model_identifier),
               design_capacity_mah = CASE WHEN EXCLUDED.design_capacity_source IS NOT NULL
                                          THEN EXCLUDED.design_capacity_mah ELSE devices.design_capacity_mah END,
               design_capacity_wh = CASE WHEN EXCLUDED.design_capacity_source IS NOT NULL
                                         THEN EXCLUDED.design_capacity_wh ELSE devices.design_capacity_wh END,
               design_capacity_source = CASE WHEN EXCLUDED.design_capacity_source IS NOT NULL
                                             THEN EXCLUDED.design_capacity_source ELSE devices.design_capacity_source END,
               estimated_full_charge_capacity_mah = CASE WHEN EXCLUDED.full_charge_capacity_source IS NOT NULL
                                                         THEN EXCLUDED.estimated_full_charge_capacity_mah
                                                         ELSE devices.estimated_full_charge_capacity_mah END,
               estimated_full_charge_capacity_wh = CASE WHEN EXCLUDED.full_charge_capacity_source IS NOT NULL
                                                        THEN EXCLUDED.estimated_full_charge_capacity_wh
                                                        ELSE devices.estimated_full_charge_capacity_wh END,
               full_charge_capacity_source = CASE WHEN EXCLUDED.full_charge_capacity_source IS NOT NULL
                                                  THEN EXCLUDED.full_charge_capacity_source
                                                  ELSE devices.full_charge_capacity_source END,
               full_charge_capacity_confidence = CASE WHEN EXCLUDED.full_charge_capacity_source IS NOT NULL
                                                      THEN EXCLUDED.full_charge_capacity_confidence
                                                      ELSE devices.full_charge_capacity_confidence END,
               last_seen_at = now()
         RETURNING *`;
      const params = [
          d.userId,
          d.installationId,
          d.platform,
          d.model ?? null,
          d.modelIdentifier ?? null,
          // Values of a group whose source is not given are dropped here too, so a brand-new row behaves
          // like the update path (and like the in-memory repository) instead of tripping the CHECKs.
          ...(d.designCapacitySource != null
            ? [d.designCapacityMah ?? null, d.designCapacityWh ?? null, d.designCapacitySource]
            : [null, null, null]),
          ...(d.fullChargeCapacitySource != null
            ? [d.estimatedFullChargeCapacityMah ?? null, d.estimatedFullChargeCapacityWh ?? null, d.fullChargeCapacitySource, d.fullChargeCapacityConfidence ?? null]
            : [null, null, null, null]),
        ];
      if (options.maxDevices === undefined) return (await this.one(sql, params, toDevice))!;
      const max = options.maxDevices;
      return this.withTransaction(async (client) => {
        // One account registers one new installation at a time, so two concurrent registrations cannot both pass the count.
        await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text, 727276))', [d.userId]);
        const known = await client.query('SELECT 1 FROM devices WHERE user_id = $1 AND installation_id = $2', [d.userId, d.installationId]);
        if (known.rowCount === 0) {
          const held = (await client.query('SELECT count(*)::int AS n FROM devices WHERE user_id = $1', [d.userId])).rows[0] as { n: number };
          if (held.n >= max) throw new DeviceLimitReached(max);
        }
        return toDevice((await client.query(sql, params)).rows[0] as Row);
      }).catch(translate);
    },
    findForUser: (userId, installationId) =>
      this.one('SELECT * FROM devices WHERE user_id = $1 AND installation_id = $2', [userId, installationId], toDevice),
    // LIMIT: an account above the cap (rows from before the cap existed) cannot make this response unbounded.
    listForUser: (userId) => this.many('SELECT * FROM devices WHERE user_id = $1 ORDER BY created_at LIMIT 500', [userId], toDevice),
    delete: async (userId, id) => {
      const res = await this.pool.query('DELETE FROM devices WHERE user_id = $1 AND id = $2', [userId, id]);
      return (res.rowCount ?? 0) > 0;
    },
  };

  readonly settings: UserSettingsRepository = {
    get: (userId) => this.one('SELECT * FROM user_settings WHERE user_id = $1', [userId], toSettings),
    update: async (userId, p) => {
      try {
        return (await this.one(
          // Undefined = "leave as is": the COALESCE keeps the stored value when the patch omits a field.
          `INSERT INTO user_settings(user_id, country_code, country_code_source, currency, currency_source,
                                     electricity_price_mode, manual_price_per_kwh, electricity_price_source)
           VALUES ($1, $2, $9, $3, $10, COALESCE($4, 'automatic'), $5, $11)
           ON CONFLICT (user_id) DO UPDATE
             SET country_code = CASE WHEN $6 THEN $2 ELSE user_settings.country_code END,
                 country_code_source = CASE WHEN $12 THEN $9 ELSE user_settings.country_code_source END,
                 currency = CASE WHEN $7 THEN $3 ELSE user_settings.currency END,
                 currency_source = CASE WHEN $13 THEN $10 ELSE user_settings.currency_source END,
                 electricity_price_mode = COALESCE($4, user_settings.electricity_price_mode),
                 manual_price_per_kwh = CASE WHEN $8 THEN $5 ELSE user_settings.manual_price_per_kwh END,
                 electricity_price_source = CASE WHEN $14 THEN $11 ELSE user_settings.electricity_price_source END,
                 updated_at = now()
           RETURNING *`,
          [
            userId,
            p.countryCode ?? null,
            p.currencyCode ?? null,
            p.electricityPriceMode ?? null,
            p.manualPricePerKwh ?? null,
            p.countryCode !== undefined,
            p.currencyCode !== undefined,
            p.manualPricePerKwh !== undefined,
            p.countryCodeSource ?? null,
            p.currencyCodeSource ?? null,
            p.electricityPriceSource ?? null,
            p.countryCodeSource !== undefined,
            p.currencyCodeSource !== undefined,
            p.electricityPriceSource !== undefined,
          ],
          toSettings,
        ))!;
      } catch (e) {
        translate(e);
      }
    },
  };

  readonly prices: ElectricityPriceRepository = {
    get: (countryCode) => this.one('SELECT * FROM electricity_prices WHERE country_code = $1', [countryCode], toPrice),
    set: async (r) => {
      await this.pool.query(
        `INSERT INTO electricity_prices(country_code, currency, price_per_kwh, period, source, includes_taxes, includes_network_costs, fetched_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (country_code) DO UPDATE
           SET currency = EXCLUDED.currency, price_per_kwh = EXCLUDED.price_per_kwh, period = EXCLUDED.period,
               source = EXCLUDED.source, includes_taxes = EXCLUDED.includes_taxes,
               includes_network_costs = EXCLUDED.includes_network_costs, fetched_at = EXCLUDED.fetched_at`,
        [r.countryCode, r.currency, r.pricePerKwh, r.period, r.source, r.includesTaxes, r.includesNetworkCosts, r.fetchedAt],
      );
    },
  };

  readonly usage: UsageRepository = {
    upsertDaily: async (rows) => {
      if (rows.length === 0) return 0;
      // One statement for the whole batch (was one INSERT per row on one pooled connection, up to 92 per request). A date
      // repeated in the batch would make ON CONFLICT touch a row twice, so the last occurrence wins, as it did before.
      const last = new Map<string, DailyUsageRow>();
      for (const r of rows) last.set(`${r.userId}|${r.deviceId}|${r.date}`, r);
      const u = [...last.values()];
      await this.pool
        .query(
          `INSERT INTO daily_usage(user_id, device_id, date, mobile_bytes, wifi_bytes, charged_wh, wall_wh,
             charging_sessions, estimated_cost, currency, data_estimated, energy_estimated)
           SELECT * FROM unnest($1::uuid[], $2::uuid[], $3::date[], $4::bigint[], $5::bigint[], $6::numeric[], $7::numeric[],
             $8::int[], $9::numeric[], $10::text[], $11::boolean[], $12::boolean[])
           ON CONFLICT (user_id, device_id, date) DO UPDATE SET
             mobile_bytes = EXCLUDED.mobile_bytes, wifi_bytes = EXCLUDED.wifi_bytes,
             charged_wh = EXCLUDED.charged_wh, wall_wh = EXCLUDED.wall_wh,
             charging_sessions = EXCLUDED.charging_sessions, estimated_cost = EXCLUDED.estimated_cost,
             currency = EXCLUDED.currency, data_estimated = EXCLUDED.data_estimated,
             energy_estimated = EXCLUDED.energy_estimated, updated_at = now()`,
          [
            u.map((r) => r.userId),
            u.map((r) => r.deviceId),
            u.map((r) => r.date),
            u.map((r) => r.mobileBytes),
            u.map((r) => r.wifiBytes),
            u.map((r) => r.chargedWh),
            u.map((r) => r.wallWh),
            u.map((r) => r.chargingSessions),
            u.map((r) => r.estimatedCost),
            u.map((r) => r.currency),
            u.map((r) => r.dataEstimated),
            u.map((r) => r.energyEstimated),
          ],
        )
        .catch(translate);
      return rows.length;
    },
    listDaily: (userId, from, to) =>
      this.many(
        'SELECT * FROM daily_usage WHERE user_id = $1 AND date BETWEEN $2 AND $3 ORDER BY date, device_id',
        [userId, from, to],
        toUsage,
      ),
    listDailyTotals: async (userId, from, to) => {
      const res = await this.pool
        .query(
          `SELECT date,
                  SUM(mobile_bytes) AS mobile_bytes, SUM(wifi_bytes) AS wifi_bytes,
                  ROUND(SUM(charged_wh), 3) AS charged_wh, ROUND(SUM(wall_wh), 3) AS wall_wh,
                  SUM(charging_sessions) AS charging_sessions, ROUND(SUM(estimated_cost), 4) AS estimated_cost,
                  (array_agg(currency ORDER BY device_id))[1] AS currency,
                  bool_or(data_estimated) AS data_estimated, bool_or(energy_estimated) AS energy_estimated
           FROM daily_usage WHERE user_id = $1 AND date BETWEEN $2 AND $3
           GROUP BY date ORDER BY date`,
          [userId, from, to],
        )
        .catch(translate);
      return (res.rows as Row[]).map((r) => ({
        date: r.date as string,
        mobileBytes: num(r.mobile_bytes),
        wifiBytes: num(r.wifi_bytes),
        chargedWh: num(r.charged_wh),
        wallWh: num(r.wall_wh),
        chargingSessions: num(r.charging_sessions),
        estimatedCost: num(r.estimated_cost),
        currency: (r.currency as string).trim(),
        dataEstimated: r.data_estimated as boolean,
        energyEstimated: r.energy_estimated as boolean,
      }));
    },
  };

  readonly ai: AiGenerationRepository = {
    // One statement: the WHERE on the conflict branch makes the limit check and
    // the increment atomic, so N concurrent callers can never exceed `limit`.
    reserve: async (userId, day, limit) => {
      const res = await this.pool
        .query(
          `INSERT INTO ai_quota_usage(user_id, day, used) SELECT $1::uuid, $2::date, 1 WHERE $3::int > 0
           ON CONFLICT (user_id, day) DO UPDATE SET used = ai_quota_usage.used + 1
             WHERE ai_quota_usage.used < $3::int
           RETURNING used`,
          [userId, day, limit],
        )
        .catch(translate);
      return res.rows[0] ? num((res.rows[0] as Row).used) : null;
    },
    release: async (userId, day) => {
      await this.pool.query('UPDATE ai_quota_usage SET used = GREATEST(used - 1, 0) WHERE user_id = $1 AND day = $2', [userId, day]);
    },
    // One statement: the answer is logged and its cost added to the day's spend or neither happens.
    insert: async (r, { spend = true } = {}) => {
      if (!spend) {
        await this.pool
          .query(
            `INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, input_tokens, output_tokens,
               estimated_cost_usd, cost_basis, usage_reported, latency_ms, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
            [r.userId, r.task, r.mode, r.provider, r.model, r.inputTokens, r.outputTokens, r.estimatedCostUsd, r.costBasis, r.usageReported, r.latencyMs, r.createdAt],
          )
          .catch(translate);
        return;
      }
      await this.pool
        .query(
          `WITH logged AS (
             INSERT INTO ai_generations(user_id, generation_type, mode, provider, model, input_tokens, output_tokens,
               estimated_cost_usd, cost_basis, usage_reported, latency_ms, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
             RETURNING provider, estimated_cost_usd, created_at
           )
           INSERT INTO ai_spend_daily(day, provider, requests, cost_usd)
           SELECT (created_at AT TIME ZONE 'UTC')::date, provider, 1, estimated_cost_usd FROM logged
           ON CONFLICT (day, provider) DO UPDATE
             SET requests = ai_spend_daily.requests + 1, cost_usd = ai_spend_daily.cost_usd + EXCLUDED.cost_usd`,
          [r.userId, r.task, r.mode, r.provider, r.model, r.inputTokens, r.outputTokens, r.estimatedCostUsd, r.costBasis, r.usageReported, r.latencyMs, r.createdAt],
        )
        .catch(translate);
    },
    // One transaction under an advisory lock: the three sums and the increment cannot interleave with another
    // reservation, so concurrent callers never exceed a limit together. AI calls are slow and rare; the lock is cheap.
    reserveSpend: async ({ day, provider, plan, usd, limits }) => {
      return this.withTransaction(async (client) => {
        await client.query('SELECT pg_advisory_xact_lock($1)', [AI_SPEND_LOCK_KEY]);
        const month = `${day.slice(0, 8)}01`;
        const sums = (
          await client.query(
            `SELECT COALESCE(SUM(cost_usd) FILTER (WHERE day = $1::date), 0) AS day_total,
                    COALESCE(SUM(cost_usd), 0) AS month_total,
                    COALESCE(SUM(cost_usd) FILTER (WHERE day = $1::date AND provider = $3), 0) AS provider_day
             FROM ai_spend_daily WHERE day >= $2::date AND day < ($2::date + interval '1 month')`,
            [day, month, provider],
          )
        ).rows[0] as Row;
        const over = (spent: number, limit: number | undefined): boolean => limit !== undefined && spent + usd > limit + 1e-9;
        if (over(num(sums.day_total), limits.dailyUsd)) return { ok: false as const, exceeded: 'daily' as const };
        if (over(num(sums.month_total), limits.monthlyUsd)) return { ok: false as const, exceeded: 'monthly' as const };
        if (over(num(sums.provider_day), limits.providerDailyUsd)) return { ok: false as const, exceeded: 'provider' as const };
        const planRow = (await client.query('SELECT cost_usd FROM ai_spend_plan_daily WHERE day = $1::date AND plan = $2', [day, plan])).rows[0] as Row | undefined;
        if (over(planRow ? num(planRow.cost_usd) : 0, limits.planDailyUsd)) return { ok: false as const, exceeded: 'plan' as const };
        await client.query(
          `INSERT INTO ai_spend_plan_daily(day, plan, cost_usd) VALUES ($1::date, $2, $3)
           ON CONFLICT (day, plan) DO UPDATE SET cost_usd = ai_spend_plan_daily.cost_usd + EXCLUDED.cost_usd`,
          [day, plan, usd],
        );
        await client.query(
          `INSERT INTO ai_spend_daily(day, provider, requests, cost_usd) VALUES ($1::date, $2, 1, $3)
           ON CONFLICT (day, provider) DO UPDATE SET requests = ai_spend_daily.requests + 1, cost_usd = ai_spend_daily.cost_usd + EXCLUDED.cost_usd`,
          [day, provider, usd],
        );
        return { ok: true as const };
      }).catch(translate);
    },
    adjustSpend: async ({ day, provider, plan, deltaUsd, deltaRequests }) => {
      await this.withTransaction(async (client) => {
        // Same row order as reserveSpend (plan row, then provider row): the reverse order deadlocked against a reservation
        // running at the same time, and PostgreSQL aborted one of the two. Both statements stay in one transaction.
        await client.query('UPDATE ai_spend_plan_daily SET cost_usd = GREATEST(cost_usd + $3, 0) WHERE day = $1::date AND plan = $2', [day, plan, deltaUsd]);
        await client.query('UPDATE ai_spend_daily SET cost_usd = GREATEST(cost_usd + $3, 0), requests = GREATEST(requests + $4, 0) WHERE day = $1::date AND provider = $2', [day, provider, deltaUsd, deltaRequests]);
      }).catch(translate);
    },
    spentUsd: async (sinceDay, provider) => {
      const res = await this.pool.query(
        'SELECT COALESCE(SUM(cost_usd), 0) AS spent FROM ai_spend_daily WHERE day >= $1::date AND ($2::text IS NULL OR provider = $2)',
        [sinceDay, provider ?? null],
      );
      return num((res.rows[0] as Row).spent);
    },
  };

  readonly cloud: CloudDataRepository = {
    deleteData: async (userId, { devices = false } = {}): Promise<CloudDeleteCounts | null> => {
      return this.withTransaction(async (client) => {
        const account = await client.query('SELECT 1 FROM users WHERE id = $1', [userId]);
        if (account.rowCount === 0) {
          return null;
        }
        const erase = async (table: CloudTable): Promise<number> =>
          (await client.query(`DELETE FROM ${table} WHERE user_id = $1`, [userId])).rowCount ?? 0;
        // Children before the devices they reference; a failure anywhere rolls every table back.
        const counts: CloudDeleteCounts = {
          dailyUsage: await erase('daily_usage'),
          chargingSummaries: await erase('charging_summaries'),
          monthlySummaries: await erase('monthly_summaries'),
          aiGenerations: await erase('ai_generations'),
          devices: 0,
        };
        // ai_quota_usage is NOT erased on purpose: it is an abuse-prevention counter (a number per user and
        // UTC day, no content, purged after 7 days by the retention job). Erasing it here would let a user
        // reset the daily AI allowance by deleting their cloud data. Account deletion removes it (CASCADE).
        if (devices) counts.devices = await erase('devices');
        return counts;
      }).catch(translate);
    },

    exportData: async (userId, max): Promise<CloudExportData | null> => {
      // One snapshot for every table, so the document is internally consistent while syncs keep running.
      return this.withTransaction(async (client) => {
        // Named columns: the password hash is never read.
        const account = await client.query('SELECT id, email, display_name, plan, created_at FROM users WHERE id = $1', [userId]);
        const a = account.rows[0] as Row | undefined;
        if (!a) {
          return null;
        }
        const settings = await client.query('SELECT * FROM user_settings WHERE user_id = $1', [userId]);
        // The newest `max` rows (one more to detect a cut), oldest first. `from`, `asc` and `desc` are constants below.
        const collect = async <T>(from: string, asc: string, desc: string, map: (r: Row) => T): Promise<{ rows: T[]; truncated: boolean }> => {
          const res = await client.query(
            `SELECT * FROM (SELECT * FROM ${from} WHERE user_id = $1 ORDER BY ${desc} LIMIT $2) newest ORDER BY ${asc}`,
            [userId, max + 1],
          );
          const rows = (res.rows as Row[]).map(map);
          return rows.length > max ? { rows: rows.slice(1), truncated: true } : { rows, truncated: false };
        };
        const devices = await collect('devices', 'created_at, id', 'created_at DESC, id DESC', toDevice);
        const dailyUsage = await collect('daily_usage', 'date, device_id', 'date DESC, device_id DESC', toUsage);
        const chargingSummaries = await collect('charging_summaries', 'started_at, device_id', 'started_at DESC, device_id DESC', toCharging);
        const monthlySummaries = await collect('monthly_summaries', 'month', 'month DESC', toMonthly);
        const aiGenerations = await collect('ai_generations', 'created_at, id', 'created_at DESC, id DESC', toAiGeneration);
        const subscriptions = await collect('subscriptions', 'created_at, id', 'created_at DESC, id DESC', toSubscription);
        return {
          account: {
            id: a.id as string,
            email: a.email as string,
            displayName: (a.display_name as string | null) ?? null,
            plan: a.plan as CloudExportData['account']['plan'],
            createdAt: a.created_at as Date,
          },
          settings: settings.rows[0] ? toSettings(settings.rows[0] as Row) : null,
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
      }, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY').catch(translate);
    },
  };

  async schemaVersion(): Promise<string | null> {
    const res = await this.pool.query('SELECT max(name) AS latest FROM schema_migrations');
    return ((res.rows[0] as { latest: string | null } | undefined)?.latest) ?? null;
  }

  async ping(): Promise<boolean> {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  private closing?: Promise<void>;

  /** Idempotent: a second call returns the first one's promise (pg rejects a second `pool.end()`). */
  close(): Promise<void> {
    this.closing ??= this.pool.end();
    return this.closing;
  }
}
