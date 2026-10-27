import pg from 'pg';

import { ForeignKeyViolation, UniqueViolation } from './memory.js';
import type {
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
    options: { max?: number; ssl?: pg.PoolConfig['ssl']; onError?: (e: Error) => void } = {},
  ) {
    pg.types.setTypeParser(1082, (v) => v); // DATE -> 'YYYY-MM-DD'
    this.onError = options.onError;
    this.pool = new pg.Pool({ connectionString, max: options.max ?? 10, ssl: options.ssl, statement_timeout: 15_000, connectionTimeoutMillis: 5_000 });
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
    findByEmail: (email) => this.one('SELECT * FROM users WHERE email = lower($1)', [email], toUser),
    findById: (id) => this.one('SELECT * FROM users WHERE id = $1', [id], toUser),
    updateDisplayName: (id, displayName) =>
      this.one('UPDATE users SET display_name = $2, updated_at = now() WHERE id = $1 RETURNING *', [id, displayName], toUser),
    delete: async (id) => {
      await this.pool.query('DELETE FROM users WHERE id = $1', [id]);
    },
  };

  readonly sessions: SessionRepository = {
    create: async ({ userId, refreshHash, expiresAt }) =>
      (await this.one(
        'INSERT INTO sessions(user_id, refresh_hash, expires_at) VALUES ($1, $2, $3) RETURNING *',
        [userId, refreshHash, expiresAt],
        toSession,
      ))!,
    findByHash: (hash) => this.one('SELECT * FROM sessions WHERE refresh_hash = $1', [hash], toSession),
    revoke: async (id, replacedBy) => {
      await this.pool.query('UPDATE sessions SET revoked_at = now(), replaced_by = $2 WHERE id = $1', [id, replacedBy ?? null]);
    },
    revokeAllForUser: async (userId) => {
      await this.pool.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
    },
    rotate: async ({ oldHash, newHash, newExpiresAt, now, graceMs }): Promise<RotateResult> => {
      return this.withTransaction<RotateResult>(async (client) => {
        // The row lock serialises concurrent presentations of the same token:
        // the first one consumes it, the others wake up and see it revoked.
        const found = await client.query('SELECT * FROM sessions WHERE refresh_hash = $1 FOR UPDATE', [oldHash]);
        const old = found.rows[0] ? toSession(found.rows[0] as Row) : null;
        if (!old) {
          return { status: 'invalid' };
        }
        if (old.revokedAt) {
          const rotatedRecently = old.replacedBy !== null && now.getTime() - old.revokedAt.getTime() < graceMs;
          if (!rotatedRecently) {
            await client.query('UPDATE sessions SET revoked_at = $2 WHERE user_id = $1 AND revoked_at IS NULL', [old.userId, now]);
          }
          return { status: 'reused', userId: old.userId, familyRevoked: !rotatedRecently };
        }
        if (old.expiresAt <= now) {
          return { status: 'expired' };
        }
        const created = await client.query(
          'INSERT INTO sessions(user_id, refresh_hash, expires_at) VALUES ($1, $2, $3) RETURNING id',
          [old.userId, newHash, newExpiresAt],
        );
        // revoked_at is stamped with the API clock (`now`), the same clock the grace window is compared with:
        // the database clock may differ between hosts and would shift the 10 s window by the skew.
        await client.query('UPDATE sessions SET revoked_at = $3, replaced_by = $2 WHERE id = $1', [
          old.id,
          (created.rows[0] as Row).id,
          now,
        ]);
        return { status: 'ok', userId: old.userId };
      }).catch(translate);
    },
  };

  readonly devices: DeviceRepository = {
    upsert: async (d) =>
      (await this.one(
        // Each battery group (design / estimate) is replaced as a whole, nulls included, when its SOURCE is
        // given; with a null source the stored group stays untouched. A per-column COALESCE would mix a new
        // value with a stale one (a design figure of one source next to a number of another).
        `INSERT INTO devices(user_id, installation_id, platform, model, model_identifier,
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
         RETURNING *`,
        [
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
        ],
        toDevice,
      ))!,
    findForUser: (userId, installationId) =>
      this.one('SELECT * FROM devices WHERE user_id = $1 AND installation_id = $2', [userId, installationId], toDevice),
    listForUser: (userId) => this.many('SELECT * FROM devices WHERE user_id = $1 ORDER BY created_at', [userId], toDevice),
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
      return this.withTransaction(async (client) => {
        for (const r of rows) {
          await client.query(
            `INSERT INTO daily_usage(user_id, device_id, date, mobile_bytes, wifi_bytes, charged_wh, wall_wh,
               charging_sessions, estimated_cost, currency, data_estimated, energy_estimated)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
             ON CONFLICT (user_id, device_id, date) DO UPDATE SET
               mobile_bytes = EXCLUDED.mobile_bytes, wifi_bytes = EXCLUDED.wifi_bytes,
               charged_wh = EXCLUDED.charged_wh, wall_wh = EXCLUDED.wall_wh,
               charging_sessions = EXCLUDED.charging_sessions, estimated_cost = EXCLUDED.estimated_cost,
               currency = EXCLUDED.currency, data_estimated = EXCLUDED.data_estimated,
               energy_estimated = EXCLUDED.energy_estimated, updated_at = now()`,
            [
              r.userId,
              r.deviceId,
              r.date,
              r.mobileBytes,
              r.wifiBytes,
              r.chargedWh,
              r.wallWh,
              r.chargingSessions,
              r.estimatedCost,
              r.currency,
              r.dataEstimated,
              r.energyEstimated,
            ],
          );
        }
        return rows.length;
      });
    },
    listDaily: (userId, from, to) =>
      this.many(
        'SELECT * FROM daily_usage WHERE user_id = $1 AND date BETWEEN $2 AND $3 ORDER BY date, device_id',
        [userId, from, to],
        toUsage,
      ),
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
    insert: async (r) => {
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

  async ping(): Promise<boolean> {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  close(): Promise<void> {
    return this.pool.end();
  }
}
