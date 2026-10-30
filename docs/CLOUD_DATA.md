# Cloud data: delete, export, delete account

What the server holds about an account, how to erase part of it (`DELETE /api/v1/me/cloud-data`),
how to take a copy (`GET /api/v1/me/export`), what `DELETE /api/v1/me` removes, and what none of
them can reach. Status words follow `docs/VERIFICATION_STATUS.md`.

**In the app** (Account screen, "Your data in the cloud"; `lib/features/auth/presentation/cloud_data_section.dart`,
`lib/sync/cloud_data_service.dart`): *Download a copy* fetches `GET /me/export` and hands the JSON exactly as the server sent it
(file `wattbyte-cloud-export-YYYY-MM-DD.json`) to the share sheet; *Erase my cloud data* asks, calls `DELETE /me/cloud-data` (devices
stay) and then switches cloud sync off, so the next pass does not upload the same days again; *Devices in the cloud* lists
`GET /devices` and removes one with `DELETE /devices/:id` after a confirmation that says the phone's own data is not touched. A failed
call changes nothing and says so. Not in the app: erasing together with the devices (`?devices=true`), the CSV export, and any
automatic removal of stale devices (BLOCKERS B-8).

## What is stored

| Table | Holds | Written by |
|---|---|---|
| `users` | e-mail, password hash (scrypt), display name, plan | register, `PATCH /me` |
| `sessions` | `sha256` of each refresh token, expiry, revocation | login, refresh |
| `user_settings` | country, currency, price mode, manual price, and where each came from (detected, chosen by the user, migrated) | `PUT /me/settings` |
| `devices` | installation id, platform, model, the design capacity of the model and an estimate of this battery's full-charge capacity, each with where it came from (the estimate also with a confidence) | `POST /devices` |
| `daily_usage` | one row per device and day: bytes, Wh, sessions, estimated cost, flags | `POST /usage/sync` |
| `charging_summaries`, `monthly_summaries` | optional per-session and per-month detail | no route writes them yet |
| `ai_generations` | task, mode, provider, model, token counts, cost, latency, time (never prompt or answer) | AI routes |
| `ai_quota_usage` | one counter per user and UTC day | AI routes |
| `subscriptions` | store, product, store transaction id, status, expiry | future receipt verification |

Raw battery samples, per-app usage and session timestamps never leave the phone (`docs/privacy.md`).

## Delete the cloud data, keep the account

`DELETE /api/v1/me/cloud-data` (bearer). One transaction removes the user's rows in `daily_usage`,
`charging_summaries`, `monthly_summaries` and `ai_generations`. Everything else
stays: the account, its sessions (the app stays signed in), `subscriptions`, `user_settings` and the
registered devices, so the next sync works without registering again.

`?devices=true` also removes the devices (and, by cascade, anything still referencing them).
After that the app must register its device again before it can sync. Anything but `true` or `false`
is a 400.

```json
{ "deleted": { "dailyUsage": 31, "chargingSummaries": 0, "monthlySummaries": 0, "aiGenerations": 12, "devices": 0 } }
```

* **Idempotent**: a second call finds nothing and answers zeros. An account that never synced
  anything is the same. The counts come from the rows the statements removed.
* **All or nothing**: a failure on any table rolls the others back (`tests/db/cloud-data.integration.test.ts`
  makes the last table, and a middle one, fail and checks that every table is intact).
* **Never another user's rows**: every statement is scoped by `user_id`; the tests compare the whole
  export of a second account before and after.
* **A deleted account** (valid token, account gone) is `401 account_not_found`, not a 200 with zeros.
* **AI quota counters are kept.** `ai_quota_usage` (one number per user and UTC day, no content, purged after
  7 days by the retention job) is not erased by this route: erasing it would let a user reset the daily AI
  allowance by deleting their cloud data. Deleting the *account* removes it (CASCADE).

## Export

`GET /api/v1/me/export` (bearer) returns one JSON document as an attachment
`wattbyte-export-YYYY-MM-DD.json` (UTC date). Read from a single `REPEATABLE READ` snapshot, so the
collections agree with each other even while syncs keep running.

| Key | Content |
|---|---|
| `schemaVersion` | `1`; bumped on incompatible changes |
| `exportedAt` | ISO 8601, UTC |
| `account` | `id`, `email`, `displayName`, `plan`, `createdAt` (the `UserDto`) |
| `settings` | `countryCode`, `countryCodeSource`, `currencyCode`, `currencyCodeSource`, `electricityPriceMode`, `manualElectricityPrice`, `electricityPriceSource`, `updatedAt` (`null` while never saved; defaults before the first save). A `…Source` is `detected`, `manual` or `migratedManual`, or `null` when the origin is unknown (`docs/SETTING_SOURCES.md`) |
| `devices` | the `DeviceDto`: installation id, platform, model, `modelIdentifier`, design capacity (`designCapacityMah`, `designCapacityWh`, `designCapacitySource`), estimated full-charge capacity (`estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`, `fullChargeCapacitySource`, `fullChargeCapacityConfidence`), timestamps |
| `dailyUsage` | one row per device and day as stored (devices are not merged), with `deviceId` |
| `chargingSummaries`, `monthlySummaries` | as stored |
| `aiGenerations` | metadata only: `task`, `mode`, `provider`, `model`, token counts, `estimatedCostUsd`, `latencyMs`, `createdAt` |
| `subscriptions` | `store`, `productId`, `originalTransactionId`, `status`, `expiresAt`, timestamps |
| `limits` | `maxRowsPerCollection` and `truncated` per collection |

**Never in it**: the password hash, refresh tokens or their hashes, any session row, access tokens,
the AI prompt or answer (not stored), and anything of another user. The document is assembled field
by field in `src/modules/cloud/export.ts`, and the repository query names its columns, so a column
added to a table later reaches an export only when someone adds it. `tests/cloud-suite.ts` searches
the JSON and the CSV for the password hash, both tokens, the refresh hash, the password and a second
account's id, e-mail, device and tokens.

**Row cap**: at most **10 000 rows per collection** (`CLOUD_EXPORT_MAX_ROWS`; one device for 27
years of days). A collection above the cap is cut to its **newest** rows and flagged in
`limits.truncated`; it is never cut silently. The newest rows come first from the database, the
document lists each collection oldest first. The cap keeps one response to a few megabytes.

**Rate limit**: 6 requests / minute / IP (global: 120). Responses are `Cache-Control: no-store`.

### CSV

`GET /api/v1/me/export?format=csv` returns only `dailyUsage` as `text/csv; charset=utf-8`
(`wattbyte-export-YYYY-MM-DD.csv`): RFC 4180, CRLF line ends, a header row, no byte order mark.

```
date,deviceId,mobileBytes,wifiBytes,chargedWh,wallWh,chargingSessions,estimatedCost,currency,dataEstimated,energyEstimated
```

Every column is a number, a flag, an ISO date, a UUID or a currency code, so no cell holds typed text
and none can start a spreadsheet formula. The writer still quotes and doubles quotes correctly for any
text (`tests/cloud-csv.test.ts` round-trips commas, quotes, CR/LF, `=SUM(...)`, Polish, Japanese and
emoji through an independent strict reader). A cut `dailyUsage` is flagged with the response header
`x-wattbyte-truncated: dailyUsage`. Any other `format` is a 400.

In the OpenAPI document the 200 response is the JSON document; the generated Dart client decodes it
as `CloudExportDocument` (its `account` and `devices` reuse `UserDto` and `DeviceDto`). Use `?format=csv`
from a browser or a plain HTTP call, not from the generated client.

## Delete the account

`DELETE /api/v1/me` removes the `users` row. Every other table has `user_id ... REFERENCES users(id)
ON DELETE CASCADE`, so PostgreSQL removes sessions, settings, devices, daily usage, summaries, AI log,
quota counters and subscription rows in the same statement.

`tests/db/delete-account.integration.test.ts` checks it against a real database:

* from `information_schema`, **every table that has a `user_id` column** has zero rows for the user
  afterwards, and has a foreign key to `users` with `ON DELETE CASCADE`. A table added later is
  covered without editing the test; a table without `user_id` that is not on a short list of known
  non-user tables (`electricity_prices`, `schema_migrations`, `users`) fails the test, so nobody can
  store per-user data under another name by accident;
* a second, fully populated user is untouched, row for row, and still signs in and refreshes;
* the old access token answers **401 on every authenticated route** (the route list comes from the
  OpenAPI document; a route without a sample request, or one that is neither authenticated nor on
  the public list, fails the suite), every refresh token of the account is rejected
  (`invalid_refresh_token`), and the credentials no longer work;
* deleting twice is `401 account_not_found` (or 204), never an error; the e-mail can be registered again
  and the new account is empty.

The same behaviour is checked on the in-memory repositories (`tests/cloud-delete-account.test.ts`).

### What deleting the account cannot do

* **Store subscriptions are not cancelled.** The `subscriptions` rows disappear, but the App Store or
  Google Play keeps billing until the user cancels in the store (iOS: Settings > Apple ID >
  Subscriptions; Android: Play Store > Payments & subscriptions). The app should say so before
  deleting an account that has an active subscription.
* **Data on the phone stays**: SQLite statistics, the sync queue, settings and the stored tokens are
  the app's to wipe (sign-out clears the tokens; "reset statistics" the rest).
* **Backups and replicas**: copies in database backups, WAL archives and replicas disappear when
  those expire. The operator must set and publish that retention; the API cannot reach it.
* **A copy the user already exported** is theirs.
* **AI providers** received only aggregated numbers with no identifier (`docs/privacy.md`); whatever
  retention they apply to those requests is theirs.
* **Access tokens** are signed and cannot be recalled, but the server checks on every request that the
  account still exists, so a token of a deleted account is refused everywhere (`account_not_found`)
  although it has not expired.
* **Logs** hold request ids and routes, no e-mail, token or password (`docs/security.md`); they are not
  searched or rewritten on deletion.

## Tests

| File | Covers |
|---|---|
| `apps/api/tests/cloud-data.test.ts`, `tests/db/cloud-data.integration.test.ts` | one suite (`cloud-suite.ts`) on the memory and the PostgreSQL repositories: delete (counts, kept data, `devices=true`, idempotence, other user, auth, rate limit, sync resumes), export (content, secrets, CSV, cap, auth, rate limit), repository contract; PostgreSQL only: atomicity with failing triggers, quota rows, snapshot consistency under a concurrent delete |
| `apps/api/tests/cloud-delete-account.test.ts`, `tests/db/delete-account.integration.test.ts` | account deletion as above |
| `apps/api/tests/cloud-csv.test.ts` | the CSV writer against a strict RFC 4180 reader |
| `apps/api/tests/cloud-contract.test.ts` | the export contracts match `UserDto` / `DeviceDto` (compile-time), OpenAPI components |
| `apps/api/tests/contract-nulls.test.ts` | explicit `null` for every optional field of every request body, on both repositories |
| `apps/mobile/test/generated_client_contract_test.dart`, `test/e2e/contract_e2e_test.dart` | the generated Dart client, and the same null-optional requests through it against a live API |
| `scripts/check-generated-client.mjs` (`pnpm dart-client:check`) | the committed Dart client equals what the OpenAPI document generates |

## Operations

* The PostgreSQL suites of these tests each use their own schema (`wb_cloud_data`, `wb_cloud_account`,
  `wb_cloud_nulls`, created and migrated on first use) in the `TEST_DATABASE_URL` database, because they
  write and delete thousands of rows while other test files count whole tables in `public`.
* Adding a table with per-user data: give it `user_id uuid NOT NULL REFERENCES users(id) ON DELETE
  CASCADE`, add it to `deleteData` / `exportData` (both repositories) and to the export document, or the
  delete-account test and the export tests will say what is missing.
