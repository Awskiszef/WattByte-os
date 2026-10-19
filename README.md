# WattByte

Local-first mobile app that shows how much data and energy a phone uses, plus a
small TypeScript backend for accounts, aggregate sync and AI summaries.

```
wattbyte/
├── apps/
│   ├── mobile/        Flutter app (Android + iOS) + local plugin packages/wattbyte_system
│   ├── api/           TypeScript REST API (Fastify, PostgreSQL, Zod, OpenAPI)
│   └── ai/            AI Gateway library (OpenAI / Anthropic / Google / xAI: routing, retry, fallback, spend limits)
├── packages/
│   └── contracts/     Zod contracts shared by the API + generated openapi/openapi.json
├── infrastructure/docker/   local PostgreSQL
├── scripts/           generate-dart-client.mjs (OpenAPI -> Dart), secret-scan.mjs, wait-for-db.mjs
├── docs/              architecture, API, AI, privacy, security, status report
└── .github/workflows/ ci.yml (CI), release.yml (manual, signed builds)
```

Boundaries (see `docs/architecture.md`):

- **Flutter** owns system APIs, calculations, local storage, offline-first behaviour and sync queueing.
- **API** owns accounts, auth, cloud sync of per-day aggregates, quotas and AI access.
- **AI** only interprets already computed numbers (insights, summaries, roast). It never calculates.

## Prerequisites

- Flutter stable ≥ 3.35 (built with 3.47.7), Java 17+, Android SDK; Xcode for iOS.
- Node 22+, pnpm 11+ (`corepack enable`), Docker for local PostgreSQL.

## Configuration (mobile)

Every WattByte build needs a backend. Its address is compiled in with `--dart-define=API_BASE_URL=...`, and the
normal flow is always

```
Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard
```

A build **without** an API address is not a "local app": it is an **invalid configuration** and never reaches the
account-free setup. The only way to run without a backend is an explicit development mode, `LOCAL_ONLY_DEV=true`,
and it exists in **debug builds only**. Nothing is inferred from "debug": a plain `flutter run` without defines
stops at a configuration error screen.

The whole decision is one pure function, `validateBackendConfig` (`apps/mobile/lib/config/backend_config.dart`),
reached through `AppConfig`. No screen looks at `API_BASE_URL` itself.

| Define | Needed | Meaning |
|---|---|---|
| `API_BASE_URL` | always, except in debug + `LOCAL_ONLY_DEV=true` | the API, an absolute `http(s)` URL. Under the `staging` and `production` rules (see `APP_ENV`) `https` only and no `.invalid` placeholder host |
| `LOCAL_ONLY_DEV` | never (default `false`) | `true` runs a debug build without a backend and without an account. Any spelling other than `true` / `false` is an error; `true` in a profile or release build is an error, and so is `true` together with `APP_ENV=staging` or `production` (or a typo), even in a debug build |
| `APP_ENV` | optional | `development`, `staging` or `production`: the rule set for the address (https, no `.invalid` placeholder hosts). Unset means `development` in a **debug** build and `production` in a **profile or release** build (the strictest set: a build that ships never accepts cleartext because a define was forgotten). An explicit value is honoured in every mode; a typo such as `prod` counts as `production` |
| `PRIVACY_POLICY_URL` | store builds | public https page of the privacy policy; not part of the backend rule |

`FEATURE_AI`, `FEATURE_SUBSCRIPTIONS` and `FEATURE_CLOUD_SYNC` are optional build defaults for the feature switches
(`docs/CONFIGURATION_MOBILE.md`).

What a build does, by build mode:

| Build mode | `API_BASE_URL` | `LOCAL_ONLY_DEV` | Result |
|---|---|---|---|
| debug | valid | unset / `false` | **online**: full Flutter → API → account flow |
| debug | missing | `true` | **local-only development**: no account, banner `LOCAL ONLY DEVELOPMENT MODE` (only with `APP_ENV` unset or `development`; with `staging`, `production` or a typo it is invalid) |
| debug | missing | unset / `false` | **invalid**: "Invalid build configuration" screen |
| debug | valid | `true` | **invalid**: the two contradict each other |
| profile, release | valid | unset / `false` | **online** (validated as `production` unless `APP_ENV` says otherwise) |
| profile, release | missing | any | **invalid**: does not compile, `[WB-CONFIG-001]` |
| profile, release | any | `true` | **invalid**: does not compile, `[WB-CONFIG-002]` (with the address missing as well, the guard names `[WB-CONFIG-001]` first) |
| any | present but unusable (malformed, `.invalid` placeholder, `http` under the staging / production rules, credentials in it) | any | **invalid**: start-up error screen. A wrong address is never treated as "no backend" |

Profile and release builds are protected three times.

1. **The Dart compiler** refuses them when `API_BASE_URL` is empty (`[WB-CONFIG-001]`) or `LOCAL_ONLY_DEV` is anything
   but unset or exactly `false` (`[WB-CONFIG-002]`: in a profile or release build `LOCAL_ONLY_DEV=true` is a debug-only
   mode, and a spelling such as `TRUE` or ` false` does not compile either: fail closed, because the runtime validator
   trims whitespace and a compile-time constant cannot). A compile-time constant cannot parse a URL, so this layer
   covers exactly those two mistakes.
2. **The start-up check**: `main()` runs the full check before it opens storage, a session or the account flow. It
   validates for the build mode the binary really runs in: the app learns its mode from the `dart.vm.product` /
   `dart.vm.profile` constants, which a command line can override, so a binary that claims "debug" but runs without
   assertions (assertions run only in debug JIT builds and in `flutter test`, i.e. it is a profile or release AOT
   binary) is validated as release.
3. **`tool/check_backend_config.dart`** (CI and the release workflow) before a build exists; it rejects any define named
   `dart.vm.*`.

The compile-time guard itself cannot see a `dart.vm.*` override; the start-up check does. Debug builds are only
checked at start-up, because `flutter test` and `flutter analyze` compile without defines. An invalid build that does
compile shows the controlled "Invalid build configuration" screen (English, developer-facing; no address or credential
is ever printed) and stops. The two development hints on it (the `flutter run` commands that fix the problem) appear
only when `kBuildMode == BuildMode.debug` at run time; the validator's own error messages, which mention
`LOCAL_ONLY_DEV`, are in every binary.

### Development online

The normal way to work. Start the API first (see Backend below), then:

```bash
cd apps/mobile
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080       # iOS simulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080        # Android emulator → API on the host machine
flutter run --dart-define=API_BASE_URL=http://<lan-ip>:8080        # a real phone on the same Wi-Fi (docs/DEVICE_TEST_PLAN.md)
flutter run --dart-define-from-file=config/development.json        # the same, from a copy of config/development.example.json
```

* Defines: `API_BASE_URL` (plain `http` is accepted because `APP_ENV` is unset in a debug build, i.e. `development`;
  the same address in a profile or release build would be validated as `production` and refused). Do not set
  `LOCAL_ONLY_DEV`.
* Launch: Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard. The account is required
  even though this is a debug build. No banner.
* Wrong configuration (no address, a malformed one, `LOCAL_ONLY_DEV=true` together with an address): the "Invalid
  build configuration" screen lists the broken rules and the two commands that fix them. Nothing is loaded.

On the Android emulator `localhost` is the emulator itself; `10.0.2.2` is its alias for the machine it runs on.

### Development local-only

For working on the app without any backend. **Debug builds only.**

```bash
cd apps/mobile
flutter run --dart-define=LOCAL_ONLY_DEV=true
flutter run --dart-define-from-file=config/local-only-dev.json     # copy of config/local-only-dev.example.json
```

* Defines: `LOCAL_ONLY_DEV=true` and nothing else (`APP_ENV`, if given, must be `development`). Do **not** add
  `API_BASE_URL` (the combination is rejected).
* Launch: no Welcome, no Register / Login: Automatic Setup → Permissions → Dashboard. There is no account and no
  cloud feature, because there is no backend to talk to. A red strip with **`LOCAL ONLY DEVELOPMENT MODE`** stays
  above every screen, and the same text is written to the debug log at start-up. It exists only in this mode and
  never appears in a normal build: the strip is built only when `kBuildMode == BuildMode.debug` and the build is
  validated as local-only, and the text itself is a constant that is empty outside debug builds, so the literal is
  absent from profile and release binaries (`tool/check_release_guard.sh --builds` greps a real release binary for it).
  The strip is a visual developer aid: VoiceOver and TalkBack do not read it out.
* Wrong configuration: `LOCAL_ONLY_DEV=false` or unset without an address in a debug build shows the error screen, and
  so does `LOCAL_ONLY_DEV=true` with `APP_ENV=staging` or `production` (or a typo); `--profile` and `--release` with
  `LOCAL_ONLY_DEV=true` do not compile (`[WB-CONFIG-001]` without an address, `[WB-CONFIG-002]` with one).

### Staging

A release-mode build against the staging API. The addresses live in a git-ignored file, not in the source tree.

```bash
cd apps/mobile
cp config/staging.example.json config/staging.json    # put the real https hosts in
flutter build appbundle --dart-define-from-file=config/staging.json
flutter build ipa       --dart-define-from-file=config/staging.json
```

* Defines: `APP_ENV=staging`, `API_BASE_URL=https://…` (https only), optionally `PRIVACY_POLICY_URL`. Never
  `LOCAL_ONLY_DEV`.
* Launch: the online flow above, no banner.
* Wrong configuration: no `API_BASE_URL` does not compile (`[WB-CONFIG-001]`); `LOCAL_ONLY_DEV=true` does not compile
  (`[WB-CONFIG-002]`); an `http` address or the unedited `.invalid` placeholder of the example file compiles but the
  app stops at the error screen. Catch it before building with `tool/check_backend_config.dart` (below).

### Production

```bash
cd apps/mobile
cp config/production.example.json config/production.json   # real https hosts and a public privacy-policy URL
flutter build appbundle --release --dart-define-from-file=config/production.json --build-number=<n>
flutter build ipa       --release --dart-define-from-file=config/production.json
```

The signed store builds are made by the manual `release.yml` workflow (`docs/CI.md`, `docs/RELEASE.md`). It takes
the address as the input `api_base_url` (it must start with `https://`), compiles it in as `API_BASE_URL` and runs the
configuration check below before it analyses, tests or signs anything. It passes `API_BASE_URL` only. Without
`APP_ENV` a release build is validated as `production`, so the check and the app apply the production rules (https
only, no `.invalid` placeholder host) to a workflow build as well. `PRIVACY_POLICY_URL` is not passed, so a workflow
build has no privacy-policy URL compiled in; a build with one is the local `config/production.json` build
(`docs/CI.md`, "Release workflow").

* Defines: `APP_ENV=production`, `API_BASE_URL=https://…`, `PRIVACY_POLICY_URL=https://…` (the privacy policy must be
  public before a store submission). Never `LOCAL_ONLY_DEV`.
* Launch: Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard. A production build can
  never skip the account.
* Wrong configuration: as for staging. A release build without a usable backend configuration is refused by the
  compiler or, for the mistakes a compiler cannot see in a string, by the start-up check; it is never an app that
  behaves like a local-only one.

### Checking a configuration before building

```bash
cd apps/mobile                                # after flutter pub get
dart run tool/check_backend_config.dart --build-mode=release --dart-define=API_BASE_URL=https://<api host>
bash tool/check_release_guard.sh            # the whole matrix in seconds: 26 checks, 18 must be rejected, 8 must be accepted
bash tool/check_release_guard.sh --builds   # plus three real release builds (Gradle): two must fail to compile, one must build
```

`tool/check_backend_config.dart` applies exactly the rules the app applies at start-up (a profile or release check
without `APP_ENV` is a `production` check). It takes the same `--dart-define` and `--dart-define-from-file` options as
`flutter build`; exit code 0 = valid, 1 = invalid (reasons on stderr, never a define's value), 64 = unusable
arguments. It also rejects any define named `dart.vm.*` (such a define would override the build mode the app detects
itself by). With `--builds` the script makes three real unsigned release builds of the Android app
(`WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`, no key needed): without `API_BASE_URL` it must fail with `[WB-CONFIG-001]`, with
an address and `LOCAL_ONLY_DEV=true` it must fail with `[WB-CONFIG-002]`, and with a valid made-up address (arm64) it
must build, and the development banner text must be absent from the resulting `libapp.so` while a control string of
the release binary is present; the APK is deleted afterwards. CI runs the matrix and two wiring tests (the real
`--dart-define`s reach `AppConfig`) in the job `mobile-config-guard`, the three builds in the `android` job, and the
release workflow runs the checker with its own defines (`docs/CI.md`). Status: CONFIGURED, NOT REMOTELY VERIFIED.

### Addresses are configuration, not secrets

`API_BASE_URL` is **not a secret**: a dart-define is compiled into the app and can be read out of it, so never put a
credential in one. It is still not hardcoded anywhere: set it per environment with `--dart-define`, with
`--dart-define-from-file=config/<env>.json` (git-ignored; only the `*.example.json` templates are tracked) or, in CI,
through the release workflow's `api_base_url` input. In an IDE, pass the same arguments as additional run arguments of
the run configuration. `flutter test` and `flutter analyze` need no defines.

### Signing

Android release signing comes from outside the repo: copy
`apps/mobile/android/key.properties.example` to `key.properties` (git-ignored) or set the
`WATTBYTE_KEYSTORE_*` variables. Without a key a release build fails with `BLOCKED - RELEASE KEY REQUIRED`; an
unsigned artifact is produced only on opt-in (`WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`, `docs/RELEASE.md`).

iOS: `apps/mobile/ios/Podfile` is committed; bundle id `pl.wattbyte.app`, App Group
`group.pl.wattbyte.app`, widget target `WattByteWidget` (see `apps/mobile/tool/ios_setup_project.rb`).
Choose your signing team in Xcode before running on a device.

Toolchain verified with: Flutter 3.41.6, Dart 3.11.4, Java 17+, Xcode 27, Node 22+, pnpm 11.9.

## Mobile

```bash
cd apps/mobile
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed lib test packages tool
flutter analyze
flutter test
flutter build apk --debug
cd packages/wattbyte_system/android/jvm-tests && gradle test   # Kotlin unit tests (plain JVM)
```

None of these needs a `--dart-define`. A debug build made without one compiles, but the app it produces stops at the
"Invalid build configuration" screen when started (see Configuration (mobile)), so a green `flutter build ... --debug`
does not mean the app starts; give it `API_BASE_URL` or `LOCAL_ONLY_DEV=true` to run it. Two tests in
`test/config/define_wiring_test.dart` skip themselves without defines; CI runs that file twice with real defines
(`docs/CI.md`).

Windows notes:

- A project path with non-ASCII characters makes AGP refuse to build;
  `android/gradle.properties` sets `android.overridePathCheck=true`. The
  `flutter analyze` LSP channel also mis-sizes such paths; run Flutter
  commands from an ASCII path (a junction such as `mklink /J C:\dev\wattbyte <repo>` works).
- On some machines the toolchain's build directories come back with the
  ReadOnly attribute (seen under `Downloads`); `gen-l10n` then fails with
  "doesn't allow reading and writing" and Gradle cannot delete old outputs.
  Run `powershell -NoProfile -File apps/mobile/tool/clear_readonly.ps1` before building.
- Gradle's test worker cannot load classes from a path with non-ASCII
  characters (`ClassNotFoundException`), so Kotlin unit tests need an ASCII
  checkout path. Everything else (analyze, Dart tests, APK build) works in place.

End to end (generated Dart client -> API -> PostgreSQL), with the API running on `:18080`
(`AI_MOCK=1 AI_FREE_DAILY_LIMIT=4 AUTH_RATE_LIMIT_PER_MIN=1000`):

```bash
cd apps/mobile && WATTBYTE_E2E_API_URL=http://127.0.0.1:18080 flutter test test/e2e
TZ=Europe/Warsaw flutter test test/periods_test.dart      # calendar logic across DST
```

## Backend

```bash
pnpm install
pnpm lint && pnpm typecheck && pnpm test && pnpm build
# PostgreSQL integration suites run when TEST_DATABASE_URL is set (CI does):
TEST_DATABASE_URL=postgres://wattbyte:wattbyte@localhost:5432/wattbyte_test pnpm test
# Real AI providers: pnpm --filter @wattbyte/ai smoke:ai  (prints 'NOT VERIFIED — API KEY MISSING' per provider without keys; exit 0)
pnpm db:up && pnpm db:migrate            # PostgreSQL via Docker (waits until healthy), then schema
                                         # port 5432 taken? WB_PG_PORT=55432 pnpm db:up (published on 127.0.0.1 only)
pnpm db:wait "$DATABASE_URL"             # poll until a real query succeeds (scripts/wait-for-db.mjs)
cp apps/api/.env.example apps/api/.env   # set JWT_SECRET, DATABASE_URL, AI keys
pnpm --filter @wattbyte/api dev          # http://localhost:8080/health, /openapi.json
```

## OpenAPI → Dart client

```bash
pnpm openapi        # writes packages/contracts/openapi/openapi.json from route schemas
pnpm dart-client    # openapi-generator (Java) -> apps/mobile/lib/generated/api
```

`docs/STATUS.md` records what has been implemented, tested, build-verified and
what is still unverified on a device.

## CI, Git and secrets

```bash
pnpm secret-scan     # no provider keys, private keys, JWTs or credentials in the files that would be committed (masked output)
pnpm ci:local        # secret scan, script tests, lint, typecheck, tests, build, device catalog (set TEST_DATABASE_URL for the PostgreSQL suites)
```

- [docs/CI.md](docs/CI.md): the GitHub Actions pipeline, the local command that mirrors each step and the release
  workflow's secrets. Status: CI CONFIGURED, NOT REMOTELY VERIFIED.
- [docs/REPOSITORY.md](docs/REPOSITORY.md): this folder is not a Git repository yet, what is ignored, what would be
  committed and the commands for the first commit.

## Automatic setup

After the account is created the app detects region, currency, device, the design
(nominal) battery capacity of the model and the average household electricity price
(Eurostat through the API) on its own; see [docs/AUTO_SETUP.md](docs/AUTO_SETUP.md).
What this battery holds today is a separate, always-estimated value on Android;
see [docs/BATTERY_CAPACITY.md](docs/BATTERY_CAPACITY.md).
Where each setting came from (detected, chosen by the user, synced from the account,
migrated from an older version), how local choices, the account and detection are ranked,
and why one user's settings never reach the next user of the same phone:
[docs/SETTING_SOURCES.md](docs/SETTING_SOURCES.md).
