# Architecture

```
┌──────────────────────┐
│ Android / iOS APIs   │  NetworkStatsManager, BatteryManager, WorkManager /
└──────────┬───────────┘  getifaddrs, UIDevice, BGTaskScheduler, WidgetKit
           ▼
┌──────────────────────┐
│ Native bridge        │  apps/mobile/packages/wattbyte_system (Kotlin / Swift)
│ MethodChannel        │  "wattbyte/system": capabilities, queryDataDaily, queryAppData,
└──────────┬───────────┘  batterySnapshot, interfaceCounters, drainSamples, ...
           ▼
┌──────────────────────┐
│ Flutter WattByte     │  Riverpod · sqflite · calculations · analytics · sync queue
│ (apps/mobile)        │  Offline-first: every screen works without a backend.
└──────────┬───────────┘
           │ HTTPS (generated Dart client, bearer JWT, refresh rotation)
           ▼
┌──────────────────────┐
│ WattByte API         │  apps/api: Fastify 5 + Zod + OpenAPI
│                      │  auth · devices · usage sync · quotas · AI access
└───────┬────────┬─────┘
        ▼        ▼
   PostgreSQL   AI Gateway (apps/ai, in-process library)
                  router → provider (OpenAI / Anthropic / Google / xAI): retry, one fallback, spend limits
```

## Mobile layers

| Layer | Directory | Rule |
|---|---|---|
| System APIs | `packages/wattbyte_system` | Only public platform APIs; returns `null`, never invented numbers |
| Collection | `lib/collection` | Raw readings → `DailyData`, `BatterySample`, `ChargingSession` (SQLite) |
| Calculations | `lib/calc` | Pure; Wh = mAh×V/1000, wall = Wh/efficiency, cost = kWh×price |
| Analytics | `lib/analytics` | Stats, records, insights, notification rules (pure, tested) |
| Sync | `lib/sync` | `DailyAggregate` per day, queued idempotently, uploaded to `POST /api/v1/usage/sync` for a signed-in account while cloud sync is on (`docs/SYNC_OWNERSHIP.md`, `docs/CLOUD_DATA.md`) |
| Settings | `lib/settings` | SharedPreferences; tokens live only in `features/auth` secure storage |
| Setup | `lib/setup` | Region, device/battery and electricity-price detection with sources; routing rule for launch (`docs/AUTO_SETUP.md`) |
| UI | `lib/ui`, `lib/features/*/presentation` | Reacts to `SystemCapabilities`; estimates carry `~` and a badge |

## Data flow

```
Native system data → Collector → SQLite → calculations → DashboardModel
                                              └→ SyncQueue (per-day aggregates) → POST /api/v1/usage/sync
```

What leaves the phone, to whom and how it is erased: `docs/CLOUD_DATA.md` and `docs/privacy.md`. Who owns which setting
once an account exists: `docs/SYNC_OWNERSHIP.md`, `docs/SETTING_SOURCES.md`.

Sync properties (`lib/sync`): offline-first (queue in SQLite), idempotent (one
row per day, replaced only when the aggregate changes), retryable (state
`pending → syncing → synced | failed`, attempts counter), and the server upsert
is keyed by `(user, device, date)` so a repeated request is harmless.

## Backend modules

`apps/api/src/modules/{auth,users,devices,usage,cloud,electricity,region,ai,config,health}`; persistence behind
`database/repositories.ts` with `postgres.ts` (production) and `memory.ts`
(tests, OpenAPI export). Errors are uniform `{ error: { code, message } }`.

## Contracts

`packages/contracts` holds the Zod schemas used by every route; the API renders
them into `packages/contracts/openapi/openapi.json` (`pnpm openapi`), and
`scripts/generate-dart-client.mjs` turns that into `apps/mobile/lib/generated/api`.
No DTO is maintained twice.
