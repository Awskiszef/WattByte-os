# Development guide

How to run, test and check WattByte on a developer machine. The README has the short version; this page is the canonical one.
Reference material lives elsewhere and is linked, not repeated: API environment variables `docs/CONFIGURATION.md`, mobile build
defines `docs/CONFIGURATION_MOBILE.md`, CI `docs/CI.md`, release `docs/RELEASE.md`, running the API `docs/OPERATIONS.md`.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node | **22.9 or newer** (`.nvmrc` says 22; CI runs 22 and 24) | `--env-file-if-exists`, used by the API scripts, needs 22.9+ |
| pnpm | 11.9.0 (`packageManager` in `package.json`) | `corepack enable` works on Node up to 24. Node 25 and newer no longer ship corepack: `npm install -g pnpm@11.9.0`, or run every command as `npx pnpm@11.9.0 <command>` |
| Docker | any recent | local PostgreSQL 16 (`pnpm db:up`) |
| Flutter | stable 3.41.6 (CI), Dart 3.11 | Java 17+ and the Android SDK for Android, Xcode for iOS |
| Java | 17+ | the OpenAPI generator (`pnpm dart-client`) and Gradle |

Toolchain the project was last verified with: Flutter 3.41.6, Dart 3.11.4, Java 17+, Xcode 27, Node 22+ (26 locally), pnpm 11.9.

## Backend: first run

```bash
pnpm install
pnpm db:up                                   # PostgreSQL in Docker (waits until healthy); creates wattbyte and wattbyte_test
cp apps/api/.env.example apps/api/.env       # works as it is: placeholder JWT secret and the mock AI provider are allowed in development
pnpm db:migrate                              # reads apps/api/.env
pnpm --filter @wattbyte/api dev              # http://localhost:8080/health, /ready, /openapi.json
```

* Port 5432 taken? `WB_PG_PORT=55432 pnpm db:up`, and put the same port in `DATABASE_URL` in `apps/api/.env`.
* `dev`, `migrate` and `retention` load `apps/api/.env` themselves (`node --env-file-if-exists=.env`); a variable that is
  already set in your shell wins, so CI and one-off overrides are unaffected. `AI_MOCK=1` is the template's default: no provider key
  is needed. Real providers: set `AI_MOCK=0` and a key, then `pnpm --filter @wattbyte/ai smoke:ai` (it prints
  `NOT VERIFIED - API KEY MISSING` for a provider without a key and exits 0).
* A volume created before `infrastructure/docker/initdb` existed has no `wattbyte_test`; `pnpm test:db` creates it.
* `pnpm db:wait "$DATABASE_URL"` polls until a real query succeeds.

## Tests

```bash
pnpm lint && pnpm typecheck && pnpm build        # every TypeScript package
pnpm test                                        # without a database: the PostgreSQL suites are SKIPPED and say so
pnpm test:db                                     # the API suite WITH the PostgreSQL suites (creates wattbyte_test, requires it)
pnpm test:scripts                                # the repository scripts (secret scan, generator pin, workflow checks, smoke helpers)
pnpm secret-scan                                 # no keys, private keys, JWTs or credentials in what would be committed
pnpm ci:local                                    # secret scan, workflow checks, script tests, lint, typecheck, OpenAPI drift, tests, build, device catalog
```

`pnpm test` prints one line when it skips the PostgreSQL suites, and **fails** when `CI=true` or `REQUIRE_PG_TESTS=1` is set
without `TEST_DATABASE_URL` (a pipeline must not go green by skipping them).

`pnpm ci:local` is **not** all of CI. It covers: secret scan, workflow pin/gate check, script tests, lint, typecheck, OpenAPI drift
(`pnpm openapi:check`), the unit tests (the PostgreSQL suites only if `TEST_DATABASE_URL` is exported, so prefer `pnpm test:db`),
build and the device catalog check. It does **not** run: `pnpm audit`, `pnpm dart-client:check` (needs Java and network
once), the compiled-output smoke test (`pnpm smoke:prod`), any Flutter, Kotlin, Android, iOS or end-to-end job. The table in
`docs/CI.md` lists the local command for each CI job.

## OpenAPI and the Dart client

```bash
pnpm openapi          # writes packages/contracts/openapi/openapi.json from the route schemas
pnpm dart-client      # generates apps/mobile/lib/generated/api with the pinned generator (Java)
pnpm dart-client:check
```

Contract rules for installed apps: `docs/API_COMPATIBILITY.md`.

## Mobile

```bash
cd apps/mobile
flutter pub get && flutter gen-l10n
dart format --set-exit-if-changed lib test packages tool
flutter analyze && flutter test
cd packages/wattbyte_system/android/jvm-tests && gradle test         # Kotlin unit tests (plain JVM)
```

None of these needs a `--dart-define`. To **run** the app give it a backend (the build defines, their rules and the
checks before a release build are in `docs/CONFIGURATION_MOBILE.md`):

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080        # iOS simulator; Android emulator: http://10.0.2.2:8080
flutter run --dart-define=LOCAL_ONLY_DEV=true                        # no backend, no account; debug builds only
```

A plain `flutter run` stops at the "Invalid build configuration" screen on purpose.

End to end (generated Dart client -> API -> PostgreSQL), with the API running on `:18080` (`AI_MOCK=1 AI_FREE_DAILY_LIMIT=4 REFRESH_REUSE_GRACE_SEC=0` and the
per-IP limits raised: `AUTH_RATE_LIMIT_PER_MIN`, `RATE_LIMIT_PER_MIN`, `REFRESH_RATE_LIMIT_PER_MIN`, `AI_RATE_LIMIT_PER_MIN` = 100000, `CLOUD_WRITE_RATE_LIMIT_PER_MIN=10000`): `cd apps/mobile && WATTBYTE_E2E_API_URL=http://127.0.0.1:18080 flutter test test/e2e`, and
`TZ=Europe/Warsaw flutter test test/periods_test.dart` for calendar logic across DST.

### Windows notes

* A project path with non-ASCII characters makes AGP refuse to build; `android/gradle.properties` sets
  `android.overridePathCheck=true`. The `flutter analyze` LSP channel also mis-sizes such paths: run Flutter from an ASCII path
  (a junction such as `mklink /J C:\dev\wattbyte <repo>` works).
* The toolchain's build directories sometimes come back read-only (seen under `Downloads`); `gen-l10n` then fails with
  "doesn't allow reading and writing". Run `powershell -NoProfile -File apps/mobile/tool/clear_readonly.ps1` before building.
* Gradle's test worker cannot load classes from a path with non-ASCII characters, so the Kotlin unit tests need an ASCII
  checkout path. Everything else works in place.

### Signing

Android release signing comes from outside the repository (`apps/mobile/android/key.properties.example`, or the
`WATTBYTE_KEYSTORE_*` variables). Without a key a release build fails with `BLOCKED - RELEASE KEY REQUIRED`; an unsigned artifact
exists only on opt-in (`WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`). iOS: bundle id `pl.wattbyte.app`, App Group `group.pl.wattbyte.app`,
widget target `WattByteWidget`; choose the team in `ios/Flutter/Local.xcconfig`. Details: `docs/RELEASE.md`.

## Maintainer notes (one machine's quirks, not rules)

On the original development Mac the toolchain is not on the default `PATH`: `npx pnpm …` stands in for `pnpm`,
`~/.docker/bin/docker` for Docker, and Gradle is run as `~/.gradle/wrapper/dists/gradle-9.3.1-bin/*/gradle-9.3.1/bin/gradle … --offline`.
Port 5432 is owned by another PostgreSQL there, so `WB_PG_PORT=55432` is exported. When several people test against one
server, create your own database (`CREATE DATABASE wb_mine`) instead of sharing `wattbyte_test`.
