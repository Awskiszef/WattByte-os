# Setting sources: why a setting has its value

How the app remembers *where* a setting came from, how local choices, the user's
account and fresh detection are ranked, what travels to other devices, what must
never reach another user of the same phone, and what happens to values written by
older versions. Code: `apps/mobile/lib/settings/setting_source.dart`,
`lib/settings/settings.dart`, `lib/setup/account_settings.dart`,
`lib/setup/setup_controller.dart`, `lib/providers.dart` (`SettingsNotifier`),
`lib/cloud_providers.dart` (`AccountSettingsController`); API:
`apps/api/src/modules/users/routes.ts`, migration `0007_setting_sources.sql`.
Status words follow `docs/FIX_REPORT.md`; the last section says what was run.

## The problem this replaces

Before this change one word, "manual", meant two different things:

* *the user chose this value on this phone*;
* *this value was copied from the user's account* (`AutoSetup.apply` called
  `withManualCurrency` / `withManualPrice` for what the account returned).

A currency fetched from the account on a second device was therefore stored as a
conscious local choice. It was never refreshed by detection, and it could not follow
a later change made on the first device.

## The model

`SettingSource` (`lib/settings/setting_source.dart`):

| Value | Meaning |
|---|---|
| `detected` | Found by WattByte: the device region, the catalog, a default. |
| `manual` | The user set it on purpose, on this device. |
| `accountSynced` | It arrived from the user's account. How the account got it is the setting's **original source**. |
| `migratedManual` | A value the old onboarding asked the user for, carried over by the migration. Treated like `manual`. |

`isConscious` is true for `manual` and `migratedManual`: automatic detection never
replaces such a value.

Three groups follow the account (`SettingGroup`); each has a `…Source` and, next to
an `accountSynced` source, an `…OriginalSource`:

| Group | Fields in `Settings` | On the account |
|---|---|---|
| region | `countryCode`, `regionSource`, `regionOriginalSource` (+ `regionDetection`: `deviceRegion`, `deviceLocale`, `backendCountry`, display only) | `countryCode`, `countryCodeSource` |
| currency | `currency`, `currencySource`, `currencyOriginalSource` | `currencyCode`, `currencyCodeSource` |
| price decision | `priceMode`, `manualPricePerKwh`, `priceSource`, `priceOriginalSource` | `electricityPriceMode`, `manualElectricityPrice`, `electricityPriceSource` |

The **household average** (`autoPrice`, from `ElectricityPriceService`) is data, not a
decision: refreshing it changes the number and never a source. The price source
describes who chose the *mode and the tariff*.

The **original source** is one of `detected`, `manual`, `migratedManual`, or unknown
(`null`: the account does not say, and it is never guessed). `accountSynced` is never
an original source: it says how a value reaches a device, not how the account got it.
`Settings.sanitized()` drops an original that does not belong (next to a local
source, or `accountSynced` itself).

Example:

```
Phone A    PLN detected          →  account: PLN, currencyCodeSource = detected
Phone B    PLN accountSynced, originalSource = detected

Phone A    user picks EUR   →  EUR manual (stays manual on A)
                            →  account: EUR, currencyCodeSource = manual
Phone B    EUR accountSynced, originalSource = manual
```

## Priorities

When the setup runs, and again when the app starts or returns to the foreground
(`AccountSettingsController.reconcile`), every group is resolved in this order:

1. **an own conscious choice the account has not acknowledged yet** (`manual`,
   `migratedManual`, not in `accountInSync`);
2. **the account's value**, recorded as `accountSynced` with the account's origin as
   original source (whatever that origin is: an account value is never turned into
   `manual`, and `detected` on the account is not "fresher detection");
3. **fresh detection**, only for a group nobody decided (`detected`, or empty);
4. **the fallback**: what the phone already has.

`accountSynced` is never turned into `manual` because it outranks detection. Reading a
value back from the account never changes the source of a value this phone wrote:
Phone A's manual EUR stays manual when A reads EUR from the account.

### Why "has the account acknowledged it?" (`accountInSync`)

"An own manual choice always wins" would let two devices that both have a manual value
overwrite each other at every start: B pushes GBP over A's newer EUR, A pushes EUR
back, and so on. The phone therefore records, per group, that the account holds the
value as it is here (`Settings.accountInSync`: the upload was acknowledged, or the value
came from the account). A conscious value *not* in that set has never reached the
account (an offline edit, an upgrade) and wins. One that is in it is only as new as the
last time the account agreed: if the account says something else now, another device
changed it since, and the account wins. If both changed, the unacknowledged local
choice wins. The set is part of the account's settings on the phone (see "Account
switching").

### What is uploaded

Only the groups this phone decided and the account does not hold yet
(`groupsToPush`): a source other than `accountSynced`, not acknowledged, with a value
(an untouched price default decides nothing). Never an account value: it could only
undo a newer change made elsewhere. The generated client sends an unset field as
`null`, which the API reads as "clear" for country and currency, so every upload
**echoes the account's current value** for the groups it does not own (the account is
read first, and the `PUT` is made from that answer, never from a stale copy). The
origin sent with a group is its local source (`detected`, `manual`, `migratedManual`).
After the answer, a group is marked acknowledged only if it still has the value that
was uploaded (a group edited meanwhile is not acknowledged).

### Electricity price

* `electricityPriceMode`: `automatic` or `manual`; the decision (mode + tariff) has one
  source and one original source.
* A manual tariff of 0.95 chosen on A reaches B as mode `manual`, 0.95,
  `accountSynced`, original `manual`.
* An account in `automatic` mode keeps its (older) tariff for the way back. B stays
  `automatic`: the kept tariff is stored, never applied, and the effective price is the
  household average of B's own `autoPrice`. The old tariff does not become a permanent
  manual override.
* A fresh account has `automatic` mode by default; that decides nothing
  (`hasPriceDecision` needs a manual tariff or an explicit origin).
* `ElectricityPriceService` keeps refreshing the average; `withAutoPrice` touches
  neither the mode nor any source.

### Device-bound values

Battery capacity, device model and battery measurements belong to the device and travel
with the device registration (`POST /devices`), never through `/me/settings`; the
account settings body has exactly the seven fields above. An iPhone's capacity can never
arrive on an Android phone as a manual capacity. (`docs/BATTERY_CAPACITY.md`
is unchanged.)

## Account switching

The preferences used to be one set per install, so a second user of a phone inherited
the first one's manual currency and tariff, and `onboarded` skipped the second user's
setup, so their account settings were never loaded.

Now the account-bound preferences (region, currency, price decision, their sources,
`accountInSync`, the cached household price and `onboarded`) belong to **one account at
a time**:

* `SettingsStore.accountOwner` (`wb.settingsOwner`) is the one-way account key
  (`accountKeyFor(installationId, userId)`, the same key as the sync ledger, never the
  user id or the e-mail) whose settings are in the live preferences.
* When another account signs in (`SettingsNotifier._bind`), the live settings are put
  away under their owner's key (`wb.acct.<key>.…`), those of the new account are brought
  back, or nothing for an account that was never here: it starts with no currency, no
  tariff, `onboarded = false`, and the setup loads its own account.
* Until that has happened `settingsBoundProvider` is false and the start gate shows the
  splash, so nothing of the previous user is shown, and nothing is detected or uploaded
  from it.
* Local to the phone, and **not** swapped: efficiency, units, theme, notifications,
  the data switch, the phone model and its capacity.
* Deleting an account on the server erases its settings from the phone, the live ones
  too (`accountDeletedHookProvider`), so the next account cannot inherit them.
* Signing out leaves the settings on the phone (as the local history, which also
  survives): they are put away when someone else signs in, and found again when the
  same account does.

The first account that signs in on a phone adopts what is on it (see "Migration").

Limitation: the sync queue's payloads are device-local and carry the estimated cost,
computed from the *current* settings. Two accounts on one phone with different tariffs
rewrite each other's costs when they enqueue (`docs/SYNC_OWNERSHIP.md`).

## Offline

An account that cannot be reached changes nothing on the phone. `pull()` returns `null`
for "unreachable" and an answer with empty fields for "reachable, nothing saved", and
`mergeAccountSettings(s, null)` returns `s` unchanged: the last value keeps working and
**its source is not touched**. A setup run offline does not turn an account value into a
detection. A choice made offline stays a choice and is not acknowledged; the next
`reconcile` (app start, return to the foreground) uploads it. After recovery the normal
priorities apply.

## Migration

Preferences written by older versions are read once, when the store loads, and written
back in the new form by the next save:

| Stored by | Read as |
|---|---|
| the old onboarding (no `wb.currencySource`): a currency | currency `migratedManual` |
| the old onboarding (no `wb.priceMode`): a price above 0 | price decision `manual` mode, `migratedManual`, tariff kept |
| a build with the automatic setup, `wb.currencySource = manual` | `manual` |
| the same, `automatic` | `detected` |
| the same, `wb.priceMode = manual` without a source | `manual` |
| the same, `wb.priceMode = automatic` without a source | `detected` |
| `wb.regionSource` = `deviceRegion` / `deviceLocale` / `backendCountry` | `detected`, the old word kept as `regionDetection` |
| `wb.regionSource = manual` | `manual` |
| an unreadable source | the old onboarding's rule (a stored value was given by the user) |

What cannot be known is **not guessed**:

* A `manual` currency, price or region written by a build of the previous version may
  have been an account value that build wrongly stored as manual. It cannot be told
  apart from a real choice, so it is kept as a conscious choice. Its worst effect is
  that it is uploaded once (it is not acknowledged), and the value it holds is what
  the account gave.
* Values the account holds without an origin (saved by an older client) have an unknown
  origin (`null`), shown as a synced value that is not a known choice.
* Nothing is inferred for rows already in PostgreSQL (migration `0007` adds three
  nullable columns, existing rows keep `NULL`).

Battery capacity keeps the migration of `docs/BATTERY_CAPACITY.md`; this change does not
touch it.

The **first account that signs in after the upgrade adopts** what is on the phone
(`SettingsStore.adoptAccount`): in the old onboarding there was no account, so the
answers belong to the phone's owner, who is the first to sign in or register. They are
uploaded as `migratedManual` and reach that user's other devices with the original
source `migratedManual`. A second account on the phone does not receive them.

## API and database

`GET` / `PUT /api/v1/me/settings` gain three nullable fields next to the old four:
`countryCodeSource`, `currencyCodeSource`, `electricityPriceSource`, each
`detected | manual | migratedManual | null`. The change is additive.

* A client that sends no origins keeps working. An origin that is not sent survives only
  while the value it describes is unchanged; a value that changes without one gets an
  unknown origin (`null`); a cleared value has none. Generated clients send an unset
  field as `null`, which means "not given" for an origin.
* `accountSynced` (and any other name) is a `400 validation`, and the columns have
  `CHECK` constraints for the same three values.
* The export (`GET /me/export`, `settings`) carries the three fields; `schemaVersion`
  stays `1` (an addition).
* Migration: `apps/api/src/database/migrations/0007_setting_sources.sql`, a **new**
  migration (older ones are untouched): three nullable `text` columns on `user_settings`.

OpenAPI (`packages/contracts/openapi/openapi.json`) was regenerated, and so was the Dart
client (`apps/mobile/lib/generated/api`); `pnpm dart-client:check` proves the committed
client equals a regeneration.

## What the user sees

Settings and the setup review explain a value in words, never with a name from the
code:

| State | Text |
|---|---|
| `detected` | "Detected automatically" ("Detected from your connection" for a region found from the network) |
| `manual`, `migratedManual` | "Chosen manually" |
| `accountSynced` | "Synced from your account" |
| `accountSynced`, original `manual` / `migratedManual` | "Synced from your account · Chosen manually" |
| price | "Custom price", "Automatic · Poland household average · Updated …", each followed by "· Synced from your account" when the account decided |

"Use detected currency (XXX)" is offered when the currency is a choice of the user, here
or on another device.

## Tests

* `apps/mobile/test/setting_source_test.dart`: the model; the priorities; the two-phone
  scenarios (A detects PLN, B gets PLN `accountSynced`; A selects EUR, B gets EUR
  `accountSynced` / original `manual`; a manual tariff reaches B as a manual tariff;
  automatic mode stays automatic; a stale phone never undoes a newer change; offline;
  restart; a new install of the same account); account switching (A → logout → B: no
  leakage of a manual currency, a manual tariff or the `accountSynced` state; A comes
  back and finds its own; deletion erases); legacy migration; the one-way storage key.
  Two phones are two `ProviderContainer`s with their own preferences and SQLite
  (`test/support/phone_rig.dart`) talking to a fake account server that follows the rules
  of the real API (`test/support/fake_account_settings.dart`).
* `apps/mobile/test/e2e/setting_source_e2e_test.dart`: the same scenarios against a
  running API and PostgreSQL, with real login (`WATTBYTE_E2E_API_URL`).
* `apps/mobile/test/setup_flow_test.dart`, `settings_persistence_test.dart`
  (every `Settings` field round-trips, the legacy cases), `settings_store_test.dart`,
  `generated_client_contract_test.dart`, `accessibility/settings_a11y_test.dart`.
* `apps/api/tests/setting-source-suite.ts` (run on the in-memory repositories and on
  PostgreSQL), `tests/db/setting-source.integration.test.ts` (migration `0007` applied
  to a legacy database and to an empty one).

## Verification (2026-10-14)

Statuses follow `docs/FIX_REPORT.md`: TESTED = automated tests on this tree; SIMULATOR VERIFIED = observed on the iOS Simulator
against the local API and Docker PostgreSQL. Nothing here was run on a physical phone or on Android.

| Step | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .`, `flutter analyze` (`apps/mobile`) | clean (248 files, 0 changes; 0 issues) |
| `flutter test` with `WATTBYTE_E2E_API_URL` set (unit, widget, accessibility and the whole `test/e2e` against the running API on PostgreSQL) | TESTED: 2087 passed, 2 skipped, 0 failed (without the API: 2039 passed, 38 skipped: the e2e) |
| `test/e2e/setting_source_e2e_test.dart` (9 tests: detect, manual, tariff, automatic, account switching, offline, legacy migration, older client, owner key) | TESTED against the real API and PostgreSQL |
| `pnpm lint`, `pnpm typecheck`, `pnpm build` | clean (`apps/api` build copies 7 migrations) |
| `pnpm test` with `TEST_DATABASE_URL` | TESTED: API 477 (39 files, PostgreSQL integration tests included, migration `0007` on a legacy and on an empty schema), AI 788, device-specs 6 |
| `pnpm openapi`, `pnpm dart-client`, `pnpm dart-client:check` | OpenAPI regenerates byte for byte; "generated Dart client is up to date: 61 files identical"; the client compiles (`flutter analyze`, `generated_client_contract_test`) |
| Upgrade of a clone of the development database (at migration `0003`, 11 users, 3 settings rows) | migrations `0004`..`0007` applied; the 3 existing settings rows keep their values and have `NULL` origins |
| `node scripts/secret-scan.mjs` | 0 findings |
| iOS Simulator (iPhone 18 Pro, iOS 27), fresh install + keychain reset -> Create account -> setup | SIMULATOR VERIFIED: `POST /auth/register` 201 -> `GET /me/settings` -> `PUT /me/settings` -> `POST /devices` 201; the review reads "Detected automatically" for region (US) and currency (USD) |
| ... change the currency by hand to EUR, finish the setup, kill and relaunch | SIMULATOR VERIFIED: the app goes straight to the dashboard; Settings shows "EUR · Chosen manually"; PostgreSQL: `US / detected`, `EUR / manual`, `automatic / NULL`; the edit was `GET /me/settings` then `PUT /me/settings` |
| Second install (app data and keychain wiped), sign in as the same account | SIMULATOR VERIFIED: `POST /auth/login` -> `GET /me/settings` and **no** `PUT` (nothing was uploaded); the review shows region "Synced from your account" and currency "EUR · Synced from your account · Chosen manually" although this install detected US / USD |

Not verified: a physical device or an emulator (Android in particular), a second phone running at the same time (two phones are
two containers in the tests, one simulator was reinstalled in the smoke test), a real Eurostat answer in the e2e of the automatic
mode (the household average is covered by `api_e2e_test.dart`; `setting_source_e2e_test.dart` checks it only when Eurostat could
be reached), the account switch through the sign-out button of the Account screen on the simulator (covered by the provider-level
tests and e2e, which sign out through the same `AuthController`), and the Polish UI on the simulator (covered by the widget test).

## Remaining limitations

* **Mislabelled values of the previous build cannot be recovered.** A phone that already stored an account value as `manual`
  keeps it as a conscious choice (worst case: it is uploaded once, unchanged). Nothing in the preferences says which it was.
* **No timestamps.** Two phones that both hold an *unacknowledged* manual value for the same group (both edited offline) end with
  the one that reconciles last. After an acknowledgement the account's newer word wins on the other phone. The server keeps one
  `updatedAt` per account, not per group, so a finer rule would need a version per group.
* **The first account on a phone adopts what is on it.** A phone that was signed out when the app was upgraded, and then used by a
  different person, hands the old onboarding's answers to that person. The old onboarding had no account, so nothing says whose they are.
* **The sync queue is device-local and carries the cost** computed from the settings in force when it was filled (`docs/SYNC_OWNERSHIP.md`);
  two accounts with different tariffs on one phone rewrite each other's costs. It is not new, it is easier to reach now that the
  second account no longer inherits the first one's tariff.
* A phone that cannot read its own database (`SettingsNotifier._bind` fails) keeps the settings it has and reports the error; it does
  not block the account, and it cannot guarantee the separation in that state.
* The account has one origin per decision, not per field of the price decision (mode and tariff share `electricityPriceSource`).
* Android and the Android native side were not part of this change and were not run.

