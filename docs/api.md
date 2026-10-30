# API (`apps/api`)

Base path `/api/v1`; operational endpoints at the root. Full schema:
`packages/contracts/openapi/openapi.json` or `GET /openapi.json` on a running server.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | – | liveness: version, uptime; never touches the database |
| GET | `/ready` | – | readiness: runs `SELECT 1` (timeout `READY_DB_TIMEOUT_MS`); 200 `{status:"ok",database:"ok"}`, else 503 `{status:"degraded",database:"unavailable"}`; lists configured AI providers |
| GET | `/api/v1/config` | – | `{ environment, features: { ai, subscriptions, cloudSync }, ai: { dailyLimits: { free, premium } } }` from the server's environment (`AppConfigDto`); nothing secret, no cache |
| POST | `/api/v1/auth/register` | – | email + password (scrypt N=2¹⁶) → user + tokens, 409 if taken |
| POST | `/api/v1/auth/login` | – | 401 `invalid_credentials` |
| POST | `/api/v1/auth/refresh` | – | rotates the refresh token; reuse revokes every session (`refresh_token_reused`) |
| POST | `/api/v1/auth/logout` | – | revokes, idempotent, 204 |
| POST | `/api/v1/auth/apple`, `/auth/google` | – | 501 `not_configured` until provider credentials exist |
| GET / PATCH / DELETE | `/api/v1/me` | bearer | DELETE erases the account and all cloud rows |
| GET / PUT | `/api/v1/me/settings` | bearer | account-bound preferences: `countryCode`, `currencyCode`, `electricityPriceMode`, `manualElectricityPrice`, each with the origin of its value (`countryCodeSource`, `currencyCodeSource`, `electricityPriceSource`: `detected`, `manual`, `migratedManual` or `null` = unknown; `accountSynced` is refused). PUT merges; `manual` needs a price; an origin that is not sent survives only while its value is unchanged (`docs/SETTING_SOURCES.md`) |
| DELETE | `/api/v1/me/cloud-data` | bearer | deletes the synced data but keeps the account: daily usage, charging and monthly summaries and the AI log, in one transaction; keeps sessions, settings, subscriptions, devices and the per-day AI quota counters (`?devices=true` removes the devices too). Idempotent, answers `{ deleted: { dailyUsage, chargingSummaries, monthlySummaries, aiGenerations, devices } }`; 10 / minute / IP. See `docs/CLOUD_DATA.md` |
| GET | `/api/v1/me/export` | bearer | everything stored about the account as a JSON attachment `wattbyte-export-YYYY-MM-DD.json` (`schemaVersion`, account, settings, devices with design capacity and estimated full-charge capacity, daily usage, summaries, AI metadata, subscriptions; never the password hash or sessions); `?format=csv` returns the daily usage as RFC 4180 CSV; at most 10 000 rows per collection, a cut is flagged in `limits.truncated`; 6 / minute / IP. See `docs/CLOUD_DATA.md` |
| GET / POST | `/api/v1/devices` | bearer | POST is idempotent per `installationId`. Battery capacity travels as two groups, stored atomically: **design capacity** `designCapacityMah`, `designCapacityWh`, `designCapacitySource` (`manufacturerSpecification`, `localDeviceDatabase`, `backendDeviceDatabase`, `manual`, `unknown`) and **estimated full-charge capacity** `estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`, `fullChargeCapacitySource` (`androidChargeCounter`, `unknown`), `fullChargeCapacityConfidence` (`low`, `medium`, `high`). A group whose source is given replaces the stored group as a whole, nulls included; a `null` source keeps it; all fields `null` change nothing. 400 `validation`: a number without a source, `unknown` with numbers, a design source other than `unknown` without `designCapacityMah`, Wh without mAh, an estimate without confidence, a confidence or measured source without `estimatedFullChargeCapacityMah` (bounds: mAh 0.1 to 30 000, Wh 0.001 to 200). A measurement can not be sent as design capacity (no such source). `fullChargeCapacitySource: unknown` / `designCapacitySource: unknown` without numbers is valid and clears the group. See `docs/BATTERY_CAPACITY.md` |
| DELETE | `/api/v1/devices/:id` | bearer | |
| GET | `/api/v1/devices/specifications/:identifier` | – | design (nominal) capacity of the model from the shared catalog (`packages/device-specs`): `designCapacityMah`, `designCapacityWh`, `nominalVoltage`, `catalogVersion`; never a measurement; 404 `device_specification_unknown` |
| GET | `/api/v1/electricity-price?country=PL` | bearer | household average per kWh (Eurostat `nrg_pc_204`, band DC, taxes included), cached; 404 `electricity_price_unavailable`; see `docs/AUTO_SETUP.md` |
| GET | `/api/v1/region` | – | `{ countryCode, source }` from the `COUNTRY_HEADER` proxy header, `null` when unset |
| POST | `/api/v1/usage/sync` | bearer | `{ installationId, days[] }`, upsert keyed by (user, device, date); 503 `feature_disabled` when `FEATURE_CLOUD_SYNC=0` |
| GET | `/api/v1/usage/daily?from&to` | bearer | merged across devices, ≤ 366 days; 503 `feature_disabled` when `FEATURE_CLOUD_SYNC=0` |
| POST | `/api/v1/ai/insight` · `weekly-summary` · `monthly-summary` · `roast` | bearer | quota per UTC day (free 3 / premium 50 by default, see `/config`), 429 `ai_quota_exceeded` (+ `retry-after`), 503 `ai_unavailable` (provider failure, nothing configured or a spend limit used up; no detail is sent), 503 `feature_disabled` when `FEATURE_AI=0`. The provider and model are chosen by the server, never by the request |
| GET | `/api/v1/ai/status` | bearer | operator view of the AI layer, not part of the app contract (hidden from OpenAPI): which providers are configured, cooldowns, default provider, fallback / retry / timeout settings, whether a spend limit is enforced. No provider is called, no key or model name is shown; 20 / minute / IP. See `docs/ai.md` |

## Errors and request ids

Every failure is `{ "error": { "code", "message" } }`; branch on the status and `code`, never on
`message`. The table of codes (404 `not_found`, 405 `method_not_allowed` + `allow`, 413
`payload_too_large`, 415 `unsupported_media_type`, 429 + `retry-after`, 500 `internal`, ...) is in
`docs/security.md`. Every response, errors included, carries `x-request-id`; send your own
(`^[A-Za-z0-9._-]{8,64}$`) to correlate a request with the server log, otherwise one is generated.
Unauthenticated calls to any non-public route are `401 unauthorized`.

## Tokens

- Access: HS256 JWT, 15 min, claims `sub` (user id) and `plan`; issuer `wattbyte`, audience `wattbyte-mobile`. The server also requires the account to exist and takes the plan from the account row, not from the claim.
- Refresh: 32 random bytes (base64url), only `sha256` stored in `sessions`, 30 days, rotated on every refresh, revocable. A rotated token presented again less than `REFRESH_REUSE_GRACE_SEC` (10 s) later is a rejected retry; at 10 s or later it revokes every session (`docs/security.md`). Treat `refresh_token_reused` as "sign in again".
- The mobile app keeps both in Keychain / Keystore (`SecureTokenStore`), never in SharedPreferences.

## Rate limiting

Global 120 requests / minute / IP (unknown paths included); each credential endpoint 10 / minute; AI endpoints 20 / minute. A blocked call is `429 rate_limited` with `retry-after`.

## Database

`src/database/migrations/0001_init.sql`: `users`, `sessions`, `devices`, `user_settings`,
`daily_usage` (unique `(user_id, device_id, date)`), `charging_summaries`,
`monthly_summaries`, `ai_generations` (cost log), `subscriptions`.
`0003_auto_setup.sql`: device-bound battery columns on `devices`, region /
price-mode columns on `user_settings`, `electricity_prices` cache.
`0006_battery_capacity_semantics.sql`: splits the `devices` battery columns into the design
capacity group (`design_capacity_mah|wh|source`) and the estimated full-charge group
(`estimated_full_charge_capacity_mah|wh`, `full_charge_capacity_source|confidence`), with a CHECK per
rule; old `system` / `estimated` measurements move to the estimate columns and are never kept as design
capacity (mapping table in `docs/BATTERY_CAPACITY.md`). The old API field names are gone, and the column rename is not
zero-downtime: stop the old API, migrate, start the new one. Apply with
`pnpm db:migrate` (`DATABASE_URL` required).

## Running

```bash
pnpm db:up && pnpm db:migrate
cp apps/api/.env.example apps/api/.env
pnpm --filter @wattbyte/api dev
```
