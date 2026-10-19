# Cloud sync: who owns what

Why a day is "synced" for an account and not for the phone, how the opt-in works, how
often and how persistently the app talks to the server, and what happens on sign-out,
account switch and account deletion. Code: `apps/mobile/lib/sync/`,
`lib/storage/database.dart`, `lib/api/`, `lib/cloud_providers.dart`,
`lib/background/foreground_refresh.dart`. Status words follow `docs/FIX_REPORT.md`; the
last section lists what was actually run.

## The problem this replaces

Before schema v5 the sync queue marked a day `synced` globally and remembered one
"queue owner". When another account signed in on the same phone the app silently put
**everything** back in the queue for the new account. On a shared phone that uploads
user A's history into user B's account without A or B ever agreeing, and "synced"
meant nothing once the device could change user (simulator report, errors 9 and 10).

## Policy

1. **Local history is device-local.** `daily_data`, `charging_sessions` and the
   payloads in `sync_queue` have no account owner. They survive sign-out, account
   switches and account deletion. "Reset statistics" is the only way to erase them.
2. **A cloud copy belongs to an account only after an upload to that account.** What was
   uploaded is recorded per account, in `sync_receipts(day, account_key, fingerprint,
   synced_at_ms)`, primary key `(day, account_key)`.
   * `account_key` = first 32 hex digits of `sha256(installationId + ':' + userId)`. It
     is stable for one account on one installation, different for every other
     account and every other installation, and cannot be turned back into the user id
     or e-mail. **Neither the e-mail nor the raw user id is written to any new table or
     `meta` key.**
   * `fingerprint` = SHA-256 of the canonical JSON of the uploaded `DailyAggregate`
     (every field, keys sorted).
   * A day needs uploading for account X **iff** it has no receipt for (day, X) or the
     receipt's fingerprint differs from the current aggregate's, **and** the day is
     inside X's scope. A changed day re-uploads separately for each account; an
     unchanged day never re-uploads.
3. **Cloud sync is an explicit per-account opt-in, default OFF** for every account that
   never enabled it on this phone, including a second user of the same phone. The switch
   and its scope are stored per account key (`meta`: `sync_account:<accountKey>`).
   * scope `history`: every local day; scope `fromNow`: only days from the day sync was
     enabled.
   * `SyncService.enable(SyncScope scope)` takes the scope as a **required positional
     argument**: there is no default that uploads a phone's history to an account.
   * `daysWithoutReceipt` / `CloudSync.historyBacklog()` answer "how many local days
     older than the enable day have no receipt for this account", so the UI can ask
     "Upload this phone's N days of history to &lt;account&gt;?" only when N &gt; 0.
4. **Switch, logout, restore never mark, requeue or upload for another account.**
   Receipts are kept on logout, so signing back in uploads only the delta. Every run
   captures `SessionManager.accountEpoch` (and an epoch bumped by account deletion) and
   the account key when it starts, and checks them again right before it writes; a
   response that arrives after the account changed writes **nothing** (no receipts, no
   rejections, no schedule, no device id). A request prepared for account A can never go
   out with B's token (`SessionManager.authorized(userId:)` refuses it). A token refresh
   that outlives its session no longer signs the old account back in or signs the new
   one out.
5. **Delete account** removes that account's receipts, rejections, sync switch and
   schedule and its cached server device id (and the legacy spelling that contained the
   raw user id), keeps local data, and cancels the account's in-flight results.
   `AuthController.deleteAccount` calls `accountDeletedHookProvider` after the server
   said yes (never after a failure) and before the session is cleared; a failing hook is
   reported and cannot keep a deleted account signed in.
6. **Migration** from schema v4 and the global `wb.cloudSync` preference: below.
7. **The server needs nothing new.** Devices are per (user, installation), so one phone
   in two accounts is two device rows and `usage/sync` upserts by (user, device, date).

## Where it lives

```
sync_queue       day PK, payload, ...        device-local latest aggregate per day
                                              (state/attempts/next_retry columns are
                                              legacy: always 'pending'/0 from v5 on)
sync_receipts    (day, account_key) PK        uploaded: fingerprint, synced_at_ms
sync_rejections  (day, account_key) PK        refused for good: fingerprint, error code
meta             sync_account:<key>           JSON: enabled, scope, enabledOn, lastSuccessMs,
                                              attempts, limitedFailures, permanentFailures,
                                              nextRetryMs, retryDelayMs, lastError, halted
meta             server_device_id:<key>       the server's id of this phone in that account
meta             installation_id              random, per installation
```

`SyncOwnership` (`lib/sync/sync_ownership.dart`) is the only writer of the account
records; every update is an atomic read-modify-write (`WattByteDb.mutateMeta`), so an
upload that finishes while the user flips the switch cannot undo the switch.

**Reset statistics** wipes statistics, samples, sessions, the queue, receipts and
rejections and the interface counters, but keeps `installation_id`, the per-account
sync records and device ids. They are consent and identity, not statistics: wiping them
would silently switch sync off for everybody and register the phone as a new device in
every account.

`Settings.cloudSync` is a **view**, not the consent: while an account is signed in,
`settingsProvider` sets it from that account's record; nothing that sends data may read
it (`SyncService` asks the ledger itself, `RefreshService` no longer looks at it).

The account-bound **preferences** (region, currency, price decision, the setup flag) follow
the same rule as the ledger: they belong to one account at a time, under the same one-way
account key, and are swapped when another account signs in (`docs/SETTING_SOURCES.md`,
"Account switching"). One consequence for sync: the queue's payloads are device-local and
carry the estimated cost, which is computed from the *current* settings, so two accounts on
one phone with different tariffs rewrite each other's costs when they enqueue. An account
that has not finished its setup has no currency and uploads nothing.

## What happens when

| Event | Receipts | Sync switch | Timer / schedule |
|---|---|---|---|
| sign-in as A, A never enabled sync | none | off | automatic runs return `notEnabled` without a request |
| A enables (history) | one per uploaded day, after the server confirmed those dates | A on | first upload at once, then every >= 5 min |
| A signs out | kept | kept | foreground loop stops |
| B signs in on the same phone | A's untouched, B has none | B off | B's own throttle and backoff, A's are not consulted |
| B enables fromNow | B: today only | B on, scope fromNow | |
| B uploads history (`uploadHistory`) | B: the other days | scope history, enable day kept | |
| A signs in again | A's still match: 0 uploads | A still on | only changed days go up |
| a day changes | each account with sync on: exactly 1 upload of that day | | |
| A deletes the account (server said yes) | A's removed, B's kept | A's removed | loop stops (signed out) |
| response arrives after a switch / deletion | nothing written | | dropped |
| Reset statistics | wiped | kept | |

## How often

* `RefreshService.run` (60 s foreground tick, resume, pull to refresh) collects,
  updates the device-local queue, then calls `SyncService.syncIfDue()`. The background
  isolate has no sync service.
* **Automatic runs** (`syncIfDue`): nothing for an account without sync; at most one
  upload per 5 minutes per account (last SUCCESS persisted in the account record, so it
  survives a restart); nothing while a failed attempt waits out its backoff; nothing
  after the retries were given up (`halted`). A changing current day therefore costs at
  most 12 uploads an hour.
* **Manual "Sync now"** (`syncNow`) ignores the interval, the backoff and a halt, is
  single-flight (concurrent taps share one run), and sends at most
  `maxBatchesPerRun` (12) requests of at most 92 days. When nothing changed it sends
  nothing. `syncNow(retryFailed: true)` also takes refused days back.
* **Enqueueing never resets a schedule.** Backoff and last success live in the account
  record, not on the queue rows, so rewriting today's row every minute cannot defeat
  them (before: every enqueue reset `attempts` and `next_retry`, which is why an
  offline phone tried again on every tick).
* **The clock.** A "last success" in the future (clock set back) is rebased to "now":
  the next automatic upload is at most one interval away. A "next retry" further away
  than the delay it was computed with is clamped to "now + that delay". A clock moved
  forward simply makes everything due.

## Failures and retries (`lib/api/retry_policy.dart`)

| Failure | Class | Decision |
|---|---|---|
| no connection, DNS, TLS, timeout, HTTP 408 | transient | retry, exponential backoff 30 s x 2^(n-1), +-20 % jitter, capped at 1 h, never given up |
| HTTP 429 (not the AI quota) | transient | retry; waits at least the server's `Retry-After`, never less than the own backoff (header up to 24 h honoured) |
| HTTP 401 after the one refresh + one retry | transient | retry with backoff (`SessionManager.authorized` makes exactly one refresh and one retry per call; a rejected refresh ends the session and no further request is made) |
| HTTP 5xx, other unexpected status, 404, 409 | limited | retry with backoff (and `Retry-After` on a 503); after 8 in a row: stop, `halted`, shown as failed, manual retry continues |
| HTTP 400 | permanent | failed at once, the payload is recorded as rejected and **never retried**; a changed day is a new payload and gets its chance, not sooner than 5 min and not after 3 refusals in a row (then `halted`) |
| AI quota 429 (`ai_quota_exceeded`) | quota | not a transport retry; fails |

**`Retry-After`.** The generated client's `ApiException` carries no headers.
`ApiFactory` wraps its HTTP client in `RetryAfterClient`: for a `429` or `503` response
with the header (seconds or HTTP date, clamped to 24 h) it writes
`error.retryAfterSeconds` **into the body of that very response**, and `ApiFailure.of`
reads it back (`ApiFailure.retryAfter`). The delay travels with exactly the response it
belongs to: no shared field, no correlation id, nothing for concurrent requests to race
on. An absent or unparseable header gives `null` and the exponential floor applies.

## Timers and lifecycle

`lib/background/foreground_refresh.dart` is the foreground loop that used to be a bare
`Timer.periodic` in the shell: 60 s ticks while resumed; cancelled on `hidden`,
`paused`, `detached`; restarted (with an immediate tick) on `resumed`; stopped on
sign-out and on account deletion; restarted with a fresh timer when a different
account signs in; stopped for good on dispose; never two timers alive; a tick that
arrives while the previous one is still running is skipped; a failing tick is reported.
The shell only wires it (`ref.listenManual(authControllerProvider)`, the lifecycle
callback, `dispose`). Nothing else in `lib/` owns a timer; the sync has none (its
backoff is data, polled by the tick).

## Migration (schema v5)

`WattByteDb` upgrades v4 to v5 inside the upgrade transaction (all or nothing):

* creates `sync_receipts` and `sync_rejections`;
* for the queue owner (`meta.queue_user_id`): every `synced` row becomes a receipt with
  the fingerprint of the stored payload, every `failed` row a rejection; the cached
  `server_device_id:<userId>` of every user is re-keyed to `server_device_id:<accountKey>`;
  `last_sync_ms` moves into the owner's account record; the legacy keys are deleted, so
  no raw user id stays behind;
* normalises the legacy state columns of the queue (payloads stay: they are device-local);
* an unreadable payload is dropped (it is rebuilt from `daily_data` on the next pass) and
  reported;
* writes `meta.sync_legacy_owner` = the owner's account key.

The old global preference `wb.cloudSync` lives in SharedPreferences. `SettingsStore`
captures its value when it is created (before anything can overwrite it) and
`SyncAccountNotifier` calls `SyncOwnership.adoptLegacyPreference` once: flag on + known
owner means that account gets sync enabled with scope `history` (the choice the switch
always meant); flag off, or nobody to attribute it to, enables nobody; the marker is
removed so it happens once. The key itself stays as the cached view of the switch.
Fresh installs run the same migration on empty tables and create nothing.

## What the UI has to wire (next phase)

The Account screen still compiles and behaves safely on the compatibility shims
(`settings.cloudSync`, `cloudSyncProvider.enable()` = scope `fromNow`, `.disable()`,
`.syncNow(retryFailed:)`, `syncSummaryProvider`). To finish the feature it needs:

| Hook | Use |
|---|---|
| `ref.read(cloudSyncProvider).enableWith(SyncScope scope)` | the switch ON: ask for a scope first |
| `ref.read(historyBacklogProvider.future)` / `cloudSync.historyBacklog()` | N of "Upload this phone's N days of history to &lt;account&gt;?"; ask only when N &gt; 0 before `enableWith(history)`; after enabling with `fromNow`, offer it again with `cloudSync.uploadHistory()` |
| `ref.watch(syncAccountProvider)` | `SyncAccountInfo`: `enabled`, `scope`, `enabledOn`, `accountKey` of the signed-in account (what the switch shows) |
| `syncSummaryProvider` | `pending`, `synced`, `failed`, `lastSync` plus `enabled`, `scope`, `halted`, `nextRetryAt` (show "stopped after repeated server errors, tap to retry" when `halted`) |
| `SyncOutcome.skip` | why a manual run did nothing (`notEnabled`, `nothingDue`, `accountChanged`, ...) |

## Verification

Run on 2026-10-13 (macOS, Flutter 3.41.6; the API and PostgreSQL 16 were the project's own
`apps/api` against a private database, nothing mocked on that path).

| What | Result |
|---|---|
| `dart format --set-exit-if-changed` and `dart analyze` on the sync, api, storage, settings, background, provider, auth-controller, shell and plugin Dart paths and on their tests | clean |
| `flutter test` on `test/sync_*.dart`, `retry_policy_test`, `timers_*`, `session_manager_test`, `settings_store_test`, `database_test`, `auth_controller_test` | 245 tests passed (TESTED) |
| `test/accessibility/harness_smoke_test.dart` with the auth, sync and database tests above | 94 passed |
| `test/e2e/account_switch_e2e_test.dart` (two real accounts, one SQLite, real API, PostgreSQL) with the existing e2e files | 21 passed (INTEGRATION VERIFIED) |
| PostgreSQL after that run | deleted account: 0 devices, 0 daily rows; the other account: 1 device, 7 rows, the changed day updated |

Measured request counts (`test/sync_frequency_test.dart`, fake clock, a tick every 60 s
with today changing on every tick; `test/sync_providers_test.dart` runs the same through
the real providers and the real collector):

| Scenario | Ticks | Result |
|---|---|---|
| online, today changes every minute | 60 | 12 uploads, 13 HTTP requests (1 is the device registration), never closer than 5 min |
| the same for 24 h | 1440 | 288 uploads (12 an hour) |
| online, nothing changes | 60 | 1 upload |
| online through the real providers | 60 | 60 collections (no extra refresh), 12 uploads, 13 HTTP requests |
| offline | 60 | 7 attempts at 0, 60, 120, 300, 600, 1080, 1980 s (backoff 30 s x 2^n, +-20 %) |
| offline through the real providers | 60 | 60 collections, 7 HTTP attempts |
| 10 min offline, then online | 30 | 4 failed attempts, first success at 600 s |
| HTTP 500 for 24 h | 1440 | 8 attempts, then halted; a manual retry sends 1 more |
| HTTP 429, `Retry-After: 600` | 30 | attempts at 0, 660, 1320 s |
| HTTP 400, the day keeps changing | 60 | 3 refusals (0, 300, 600 s), then halted |
| HTTP 401 on every request | 60 | 7 attempts, 14 requests, 7 refreshes |
| clock set back 3 h after a success | 30 | first request 300 s later (one interval), 5 uploads |

Not verified: the Android notification channel text (`ChargingNotifier.kt`) and the
`ic_wb_bolt` status-bar icon (no Android toolchain was run here), real background
execution, any physical phone. Nothing in this file is DEVICE VERIFIED.
