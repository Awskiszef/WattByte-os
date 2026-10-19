# WattByte privacy: what the app really does

Working document for the store listings and the privacy policy. It describes the
implementation as it is; if the code changes, change this file. It is not legal advice;
have the final policy reviewed before publishing.

## Local data (always, no account needed)

Stored only in the app's private storage on the phone:

| Data | Where | Why |
|---|---|---|
| Daily mobile and Wi-Fi bytes (download/upload) | SQLite `daily_data` | statistics |
| Battery level, plugged state, charge/energy counters, voltage samples | SQLite `battery_samples` (trimmed to the open session) | build charging sessions |
| Charging sessions (start, end, levels, deltas) | SQLite `charging_sessions` | history, energy and cost |
| Settings (price, currency, efficiency, design battery capacity and its source, theme, notification choices, cloud sync switch) | SharedPreferences | the app's behaviour |
| Region (country code from the device Region/locale setting), device model code (`iPhone16,1`, `Pixel 8`) | SharedPreferences | default currency, lookup of the design battery capacity in the device database — no location, no serial number (`docs/AUTO_SETUP.md`) |
| Estimated full-charge capacity of this battery (Android only): the charge counter extrapolated from the battery level, with the level, a confidence and the time of the reading | SQLite `meta` | the `% -> mAh` estimate when no design capacity is known; shown in Settings as an estimate (`docs/BATTERY_CAPACITY.md`) |
| Sync queue (per-day aggregates, state, attempts) and a random installation id | SQLite `sync_queue`, `meta` | optional cloud sync |

Per-app data usage (Android "Data by app") is read from the system when the screen is
opened and is **not stored**. Android needs the user to grant "Usage access".
iOS gives apps no per-app usage; interface counters are the only network source there.

No analytics SDK, no advertising SDK, no trackers, no crash-reporting service.
Android: app backup is switched off, so this data is not copied to Google or other devices.
The user can export everything (CSV/JSON) and reset all local statistics in Settings.
Turning "Data collection" off stops collection (and, on Android, the charging sampler).

## What leaves the phone, and only if the user chooses

Cloud features exist only in builds configured with an API address, and only after the
user creates an account. Sync is **off by default** and has its own switch.

| Data | When | Sent to |
|---|---|---|
| E-mail, password (hashed with scrypt on the server, never stored in clear), optional display name | creating an account / signing in | WattByte API |
| Random installation id and platform (`android`/`ios`); no device model, IMEI, MAC, advertising id or serial | first sync | WattByte API |
| One row per local day: mobile bytes, Wi-Fi bytes, battery Wh, wall Wh, number of charging sessions, estimated cost, currency, two "estimated" flags | cloud sync switched on | WattByte API, PostgreSQL |
| Totals of the current month (GB, kWh, cost, session count, percentages) | the user taps "Generate insight" or "Roast me" | WattByte API, then one AI provider |
| Device registration: model name and model code (`iPhone16,1`, `Pixel 8`); the **design capacity** of that model (mAh, Wh) with its source (device database, or typed by the user); on Android also the **estimated full-charge capacity** of this battery (mAh, Wh) with its source (`androidChargeCounter`) and a confidence (`low`, `medium`, `high`) | after the account exists (setup, "Detect again", editing the capacity); it does not depend on the cloud sync switch | WattByte API, PostgreSQL (`devices`) |

Never uploaded: raw battery samples (including the raw charge and energy counter readings),
session timestamps, per-app usage, the settings values (price, efficiency), notification choices.
The battery capacity leaves the phone only in the device registration row above.

Access and refresh tokens are kept in the iOS Keychain / Android Keystore-backed storage.

## AI

The AI request contains only the monthly totals above, validated by a strict schema on the
server (any extra field, for example an e-mail, user id, device id or token, is rejected
before a prompt exists). The user id is used only server-side for the daily quota and the
cost log. Providers that may receive the totals: OpenAI, Anthropic, Google, xAI (the
server picks one per request; after a provider outage or a rate limit it may send the same
request to one other provider). OpenAI and xAI are asked not to keep the request
(`store: false`; their APIs keep responses for 30 days by default). The server stores for each
generation: user id, task, mode, provider, model, token counts, estimated cost, latency, time.
It does not store the prompt or the answer. A separate table of daily totals per provider (cost
and number of answers, no user id) feeds the spend limits and is not deleted with an account:
it is not personal data.

## Retention and deletion

* Local data: until the user resets statistics or uninstalls the app.
* Cloud account and per-day rows: until the user deletes the account. **Delete account**
  (Account screen) calls `DELETE /api/v1/me`, which removes the account and, by cascade,
  sessions, devices, daily rows, AI usage records and quota counters.
* Not implemented yet: deleting only the cloud data while keeping the account,
  downloading the cloud copy (the local export covers the same data), and automatic
  expiry of old sessions and AI usage records.
* Turning cloud sync off stops uploads immediately; rows already uploaded stay until the
  account is deleted.

## Permissions

| Platform | Permission | Reason |
|---|---|---|
| Android | `PACKAGE_USAGE_STATS` (Usage access, granted by the user) | mobile/Wi-Fi totals and Data by app |
| Android | `POST_NOTIFICATIONS` | optional alerts |
| Android | `INTERNET` | cloud account, sync and AI |
| iOS | none beyond background refresh | |

## Apple privacy manifest

`ios/Runner/PrivacyInfo.xcprivacy` declares: no tracking; collected data (e-mail address,
other usage data, device id as the random installation id), all linked to the account and
used only for app functionality; required-reason APIs: UserDefaults (settings and the App
Group shared with the widget) and system boot time (detect a reboot, which resets the
interface counters; the value stays on the device).
