# Continuous integration

**CI CONFIGURED — NOT REMOTELY VERIFIED**

The workflows in `.github/workflows/` have never run on GitHub: when they were written the project had no
GitHub remote (see [REPOSITORY.md](REPOSITORY.md)). What was checked locally, and what was not:

| Check | Result (2026-10-13) |
|---|---|
| Both workflow files and `dependabot.yml` parse as YAML | PASS with Ruby's Psych (`YAML.safe_load`, YAML 1.1) and the `yaml` npm package (YAML 1.2, strict). `python3` has no PyYAML on this Mac, so the `python3 -c "import yaml"` route could not be used |
| Policy check of every workflow | PASS: top-level `permissions: contents: read`, `concurrency` set, every job has `runs-on` and `timeout-minutes`, every `needs:` names an existing job, every `uses:` is pinned to a version tag (no `@main` / `@master`) |
| Syntax of every `run:` block | PASS: each script was extracted (with `${{ … }}` replaced by a token) and passed through `bash -n` |
| `actionlint` | NOT RUN: not installed on this Mac and deliberately not downloaded. Expression typos, unknown inputs of third-party actions and shell problems that `bash -n` cannot see are therefore not covered |
| The release configuration guard (added 2026-10-14: job `mobile-config-guard`, the `--builds` step of the `android` job, the `Check the release build configuration` step of both release jobs) | The static checks were re-run on 2026-10-14, after the review round, over both workflow files by the documentation pass: both files and `dependabot.yml` parse (Ruby Psych, `YAML.safe_load`); the policy check passes (top-level `permissions: contents: read`, `concurrency` set, every job has `runs-on` and `timeout-minutes`, every `needs:` names an existing job, every `uses:` is pinned to a version tag); every `run:` block, the new ones included, passes `bash -n` (with `${{ … }}` replaced by a token), and so does `tool/check_release_guard.sh`. `actionlint` was not run. The commands behind the steps are run locally as described in "The release configuration guard" below; their results are in the final report of the change and in `docs/STATUS.md`. Nothing of it has run on GitHub |
| The commands inside the steps | Run locally, one by one, with the table below (the iOS builds, the Android builds, the e2e job and the signed release jobs excepted: see the last column) |
| GitHub-side behaviour (service containers, runner labels, caching, `environment: release`, secrets) | NOT VERIFIED |

Re-run the static checks after editing a workflow:

```bash
ruby -ryaml -e 'ARGV.each { |f| YAML.safe_load(File.read(f), aliases: false); puts "#{f}: YAML OK" }' .github/workflows/*.yml .github/dependabot.yml
actionlint        # when installed: brew install actionlint
```

## Workflows

| File | Trigger | Purpose |
|---|---|---|
| `.github/workflows/ci.yml` | push to `main`, every pull request, manual | everything below |
| `.github/workflows/release.yml` | manual only (`workflow_dispatch`) | signed Android AAB and signed iOS archive; refuses to run without signing secrets, and refuses a configuration that is not a valid release configuration (below) |
| `.github/dependabot.yml` | weekly | pull requests for GitHub Actions, the pnpm workspace and the Flutter app's pub packages |

Cross-cutting rules in `ci.yml`: `permissions: contents: read` (nothing writes to the repository), a
`concurrency` group per branch / pull request with `cancel-in-progress: true`, `timeout-minutes` on every job,
`persist-credentials: false` on every checkout, all third-party actions pinned to a major tag, and a final
`CI result` job that fails unless every other job succeeded (skipped and cancelled count as failures). Make
**`CI result`** the single required status check in branch protection.

## Jobs and the local commands that mirror them

Run from the repository root unless a `cd` says otherwise. On the development Mac the toolchain is not on the
default `PATH`: use `npx pnpm …` for `pnpm`, `~/.docker/bin/docker` for Docker and
`~/.gradle/wrapper/dists/gradle-9.3.1-bin/*/gradle-9.3.1/bin/gradle … --offline` for Gradle.
`WB_PG_PORT=55432` is used here because another PostgreSQL owns port 5432; create your own database
(`CREATE DATABASE wb_mine`) instead of sharing `wattbyte_test` when several people test at once.

| CI job | Step | Local command |
|---|---|---|
| `secret-scan` | script unit tests | `node --test scripts/secret-scan.test.mjs scripts/wait-for-db.test.mjs` (`pnpm test:scripts`) |
| | scan the tree | `node scripts/secret-scan.mjs` (`pnpm secret-scan`) |
| `node` | PostgreSQL service with a healthcheck | `WB_PG_PORT=55432 docker compose -f infrastructure/docker/docker-compose.yml up -d --wait` (`pnpm db:up`) |
| | wait until a real query works | `node scripts/wait-for-db.mjs "$TEST_DATABASE_URL" --timeout 60` (`pnpm db:wait`) |
| | lint, typecheck | `pnpm lint` · `pnpm typecheck` |
| | AI gateway tests | `pnpm --filter @wattbyte/ai test` |
| | API + contracts + device-catalog tests, **including the PostgreSQL integration suites** | `TEST_DATABASE_URL=postgres://wattbyte:wattbyte@localhost:55432/wb_mine pnpm --filter '!@wattbyte/ai' test` |
| | build | `pnpm build` |
| | all of the above plus the secret scan in one command | `TEST_DATABASE_URL=… pnpm ci:local` |
| `audit` | production dependencies | `pnpm audit --prod` |
| `contracts` | OpenAPI is generated from the routes and the committed copy is current | `pnpm openapi && git diff --exit-code -- packages/contracts/openapi/openapi.json`. Before the first commit there is no Git: `cp packages/contracts/openapi/openapi.json /tmp/openapi.before && pnpm openapi && diff /tmp/openapi.before packages/contracts/openapi/openapi.json` |
| | device catalog drift | `pnpm device-specs:check` (`pnpm device-specs:sync` repairs it) |
| | committed Dart client = generator output for `openapi.json` | `pnpm dart-client:check` (needs Java 17; the generator is the jar pinned with its SHA-256 in `scripts/openapi-generator.pin.json`, downloaded once into `~/.cache/wattbyte/openapi-generator` or `$WATTBYTE_OPENAPI_GENERATOR_DIR`; to upgrade, change version and hash together, keep `openapitools.json` equal, run `pnpm dart-client`) |
| | the Dart client compiles | `cd apps/mobile && flutter pub get && dart analyze lib/generated/api` (exit code 3 on any compile error, proven on a deliberately broken copy) |
| `flutter-static` | format, analyze | `cd apps/mobile && flutter pub get && flutter gen-l10n && dart format --output=none --set-exit-if-changed lib test packages tool && flutter analyze` |
| `mobile-config-guard` | the configuration matrix: 26 checks, a build without a valid backend configuration is rejected | `cd apps/mobile && flutter pub get && flutter gen-l10n && bash tool/check_release_guard.sh` |
| | the real `API_BASE_URL` define reaches `AppConfig.fromEnvironment` | `cd apps/mobile && flutter test test/config/define_wiring_test.dart --dart-define=API_BASE_URL=https://api.ci-guard.test` |
| | the real `LOCAL_ONLY_DEV=true` define reaches it (debug) | `cd apps/mobile && flutter test test/config/define_wiring_test.dart --dart-define=LOCAL_ONLY_DEV=true` |
| `flutter-test` (3 zones) | whole suite in each zone | `cd apps/mobile && for tz in UTC Europe/Warsaw America/New_York; do TZ=$tz flutter test; done` |
| `e2e` | generated client + app code against a real API on PostgreSQL | start the API (README, "End to end"), then `cd apps/mobile && WATTBYTE_E2E_API_URL=http://127.0.0.1:18080 flutter test test/e2e` |
| `android` | debug APK and AAB | `cd apps/mobile && flutter build apk --debug && flutter build appbundle --debug` |
| | release guard: invalid configurations must not compile, a valid one builds without the development banner | `cd apps/mobile && bash tool/check_release_guard.sh --builds` (the matrix, then three real release builds with Gradle; duration on a runner not measured) |
| `kotlin` | plugin JVM tests | `cd apps/mobile/packages/wattbyte_system/android/jvm-tests && gradle test` |
| `ios` | simulator debug, then device-SDK debug without signing | `cd apps/mobile && flutter build ios --simulator --debug && flutter build ios --debug --no-codesign` |

### Time-zone matrix

`flutter-test` runs the **whole** suite with `TZ=UTC`, `TZ=Europe/Warsaw` and `TZ=America/New_York`
(`fail-fast: false`). The calendar code (`LocalDate`, periods, daily aggregates, the 5-minute current-day sync
throttle) must hold in a zone without daylight saving, in one with it and in one whose transition dates
differ. Before this change only `periods_test` (and `energy_validation_test` in Warsaw) ran outside UTC; the whole
unit-test set was checked locally in all three zones (114 tests in each, all passing). The `e2e`-tagged tests skip
themselves here and run in the `e2e` job.

### The release configuration guard

Background: a build without `API_BASE_URL` must never become an app that skips the account. Local-only operation is
a debug-only development mode (`LOCAL_ONLY_DEV=true`), so a release build with no address, or with that flag, is an
error. The rules live in `apps/mobile/lib/config/backend_config.dart` (`validateBackendConfig`, with
`effectiveEnvironment` and `effectiveBuildMode`); the three layers that enforce them (compile time, start-up, CI)
are described in `docs/CONFIGURATION_MOBILE.md`, "Backend mode and the release guard". CI is the third layer and has
four parts, all in `apps/mobile`:

| Where | What it runs | What a failure means |
|---|---|---|
| job `mobile-config-guard` (`ci.yml`), step "Release without API_BASE_URL, or with LOCAL_ONLY_DEV=true, is rejected" | `bash tool/check_release_guard.sh` | one of 26 combinations got the wrong verdict: 18 must be rejected and 8 must be accepted. Rejected: release without `API_BASE_URL` (with `LOCAL_ONLY_DEV` unset, `false` and `true`), profile without it, `LOCAL_ONLY_DEV=true` with an address (release, profile), `http` or the `.invalid` placeholder for release (with and without `APP_ENV=production`: a release check without `APP_ENV` is a production check), a `dart.vm.*` define (also the spoofed "profile as debug" local-only build), the unedited `config/production.example.json`, the debug-only `config/local-only-dev.example.json` in a release check, debug without the flag, debug with the flag and `APP_ENV=production`, a malformed address in debug with the flag. Accepted: release or profile with an https address (release also with `APP_ENV=production` or `LOCAL_ONLY_DEV=false`), debug with `LOCAL_ONLY_DEV=true` (by hand and from `config/local-only-dev.example.json`), debug against `http://127.0.0.1:8080`, `config/development.example.json`. "Rejected" means exit code 1 plus the `INVALID BUILD CONFIGURATION` header, so a crashing checker (any other exit code) fails the job instead of looking like a rejection. Needs `dart` and `flutter pub get` only: seconds, no Gradle |
| job `mobile-config-guard`, steps "API_BASE_URL reaches the app configuration" and "LOCAL_ONLY_DEV reaches the app configuration (debug)" | `flutter test test/config/define_wiring_test.dart` twice, with `--dart-define=API_BASE_URL=https://api.ci-guard.test` and then with `--dart-define=LOCAL_ONLY_DEV=true` | the real compile-time defines no longer arrive in `AppConfig.fromEnvironment` (a renamed define, a changed `String.fromEnvironment` key). A plain `flutter test` has no defines, so each of the two tests skips itself there and nothing else can see this link |
| job `android`, step "Release guard - invalid configurations must not compile, a valid one builds without the dev banner" | `bash tool/check_release_guard.sh --builds` | after the matrix, **three** real `flutter build apk --release -v` runs, none of which needs a signing key. (1) Without `API_BASE_URL` the output must contain `[WB-CONFIG-001]`; (2) with an address and `LOCAL_ONLY_DEV=true` it must contain `[WB-CONFIG-002]`: a build that **succeeds** fails the step, so does one that fails for any other reason (the marker proves which guard fired). (3) With a valid, made-up https address (`--target-platform android-arm64`) the build must **succeed** (the positive control: a guard that refused everything would pass (1) and (2)); the script then takes `lib/arm64-v8a/libapp.so` out of the APK, requires a control string of the release binary (the "Invalid build configuration" title) to be found so that "no hit" means something, requires the development banner text `LOCAL ONLY DEVELOPMENT MODE` to be absent, and deletes the APK. `WATTBYTE_ALLOW_UNSIGNED_RELEASE=1` keeps a missing signing key from being the reason a build stops; builds (1) and (2) produce no artifact because the Dart compile is what fails, build (3) makes an unsigned arm64 APK with a made-up address that is not kept |
| `release.yml`, step "Check the release build configuration" (both jobs) | `dart run tool/check_backend_config.dart --build-mode=release --dart-define="API_BASE_URL=$API_BASE_URL"` | the `api_base_url` input is not a valid release address (no `APP_ENV` is passed, so it is checked as production: https, no `.invalid` host); the run stops after `flutter pub get` and **before** `flutter analyze`, `flutter test` and any key is touched |

`CI result` lists `mobile-config-guard` in its `needs:`, so the single required status check covers it. The checker is
`tool/check_backend_config.dart` (logic in `lib/config/backend_config_cli.dart`): it takes the options of
`flutter build` (`--build-mode`, `--dart-define`, `--dart-define-from-file`), exits 0 / 1 / 64 (valid / invalid /
unusable arguments), rejects any define named `dart.vm.*` (such a define overrides the build mode the app detects
itself by) and never prints a define's value. Fixture hosts in the script are made up (`api.ci-guard.test`,
`.invalid`, `127.0.0.1`), never an address of the product, and nothing in it is a secret.

Run it locally the same way (it needs `flutter pub get` once):

```
cd apps/mobile
bash tool/check_release_guard.sh              # the matrix: 26 checks
bash tool/check_release_guard.sh --builds     # plus three release builds (Gradle): two must fail to compile, one must build
flutter test test/config/define_wiring_test.dart --dart-define=API_BASE_URL=https://api.ci-guard.test
flutter test test/config/define_wiring_test.dart --dart-define=LOCAL_ONLY_DEV=true
dart run tool/check_backend_config.dart --build-mode=release                                    # exit 1, must be rejected
dart run tool/check_backend_config.dart --build-mode=release --dart-define=API_BASE_URL=https://<api host>   # exit 0
```

Status: **CONFIGURED, NOT REMOTELY VERIFIED**, like the rest of the file. The matrix and the checker are
IMPLEMENTED and their rules TESTED (`test/config/backend_config_test.dart`, `test/config/backend_config_cli_test.dart`,
`test/config/define_wiring_test.dart`, `docs/REGRESSION_TESTS.md`); neither the jobs nor the `--builds` step has run on
GitHub. Whether the real Gradle builds fail with the expected marker on a runner (rather than at an earlier point),
and whether the positive-control build and the inspection of its binary (`unzip`, `grep`) work on one, is unverified.
The local results of the guard are in the final report of the change and in `docs/STATUS.md`.

### The iOS job and the CPU architecture

Nothing in the workflow or the project assumes a CPU. `apps/mobile/ios/Flutter/WattByte.xcconfig` chooses the
simulator architecture from the machine that builds (arm64 on Apple Silicon, x86_64 on Intel), and the job
prints `uname -m`, `sw_vers`, `xcodebuild -version` and `flutter --version` into the log. It runs on a matrix
(`fail-fast: false`) so an Intel failure never hides an Apple Silicon result.

What GitHub offers, read from `actions/runner-images` (README, `gh api`, on 2026-10-13):

| Label | OS | CPU |
|---|---|---|
| `macos-latest`, `macos-26` | macOS 26 | arm64 |
| `macos-26-intel` (also listed as `macos-26-large`, `macos-latest-large`) | macOS 26 | x64 |
| `macos-15` | macOS 15 | arm64 |
| `macos-15-intel` (also `macos-15-large`) | macOS 15 | x64 |
| `macos-14`, `macos-14-large` | macOS 14 | arm64, x64: deprecated, "fully unsupported by November 2nd" |

The matrix uses `macos-latest` (Apple Silicon) and `macos-15-intel` (Intel). Honest uncertainty:

- Whether the Intel label is free for this repository's plan and how long it will exist was **not** established
  (GitHub's billing page and retirement announcements were not read; the README only lists the labels). If the
  label is rejected or retired, delete the `macos-15-intel` entry; nothing else changes.
- The runner images carry Xcode 26.x (macOS 26: 26.0.1 to 26.5; macOS 15: up to 26.3). Xcode 27 exists only as a
  public preview on a macOS 27 image. The project is verified locally with Xcode 27 and the iOS 27 simulator
  (docs/IOS_SIMULATOR_REPORT.md), so CI compiles with an older SDK than the one the project is tested with.
  A difference between the two is possible and unverified.
- Neither macOS job runs the app: it compiles it. Launching it needs a simulator, which CI does not start.

### Known limits of this pipeline

- `e2e` also asks the API for a household electricity price, which calls Eurostat over the public internet; a
  Eurostat outage fails the job although the code is fine.
- `contracts` downloads the pinned openapi-generator jar from Maven Central and verifies its SHA-256 (the npm CLI is not used); `audit` needs the npm registry.
  `pnpm audit --prod` can start failing on a new advisory without any change in the repository.
- The secret scan reads every file Git tracks (also one that `.gitignore` says to ignore but that was added with `git add -f`),
  every untracked file `.gitignore` does not hide, UTF-16 files, long lines (in overlapping windows) and the printable strings
  of files that contain a NUL (provider keys, private-key blocks, JWTs and URL passwords only). A file over 32 MB cannot be read
  and is a finding (`file-not-scanned`) until it is allowlisted by name. Besides provider keys it flags literal values assigned
  to secret-like names (typed declarations included), SQL role passwords, `Bearer` tokens and, in configuration files, long
  random-looking strings. It is a pattern scan: a secret under an unusual name, or short and word-like, is not found.
- The secret scan looks at the working tree, not at Git history. Turn on GitHub secret scanning and push
  protection for the repository once it exists.
- The release configuration guard checks the defines a build is given, not the ones a workflow forgets to give:
  `release.yml` passes `API_BASE_URL` only. Without `APP_ENV` a release build is validated as `production` (https only,
  no `.invalid` host), so the check and the app are strict about that address; `PRIVACY_POLICY_URL` is not passed, so a
  build made by the workflow has no privacy-policy URL compiled in (see "Release workflow"). An explicit
  `APP_ENV=development`, or an API host nobody else can reach (`localhost`, an IP address, a single-label name, `.local`,
  `.test`, `.invalid`, `example.com`), is rejected in a release or profile check (F-14).
- The `--builds` step of the `android` job runs three real Gradle release builds: two are meant to fail, one builds an
  unsigned arm64 APK. It adds a release build to that job (`timeout-minutes` is 40; the whole script took 44 s on a developer Mac with warm
  caches, and how long the step takes on a cold runner is unknown, because the job has never run) and is only as good as the markers it looks for (`[WB-CONFIG-001]`,
  `[WB-CONFIG-002]`) and the control string it requires in the release binary. It needs `unzip` and `grep` on the runner.
- Not covered anywhere: Android emulator or device tests, iOS simulator UI tests, real AI providers
  (`pnpm --filter @wattbyte/ai smoke:ai` needs keys and is not run in CI), Play Console or TestFlight upload.

## Release workflow (`release.yml`)

Manual only. Inputs: `platform` (`android`, `ios`, `both`), `api_base_url` (must start with `https://`,
compiled into the app as `API_BASE_URL`), `build_number` (empty = the workflow run number). The workflow compiles
in `API_BASE_URL` only: it does not pass `APP_ENV` or `PRIVACY_POLICY_URL`. Without `APP_ENV` a release build is
validated as `production` (https only, no `.invalid` placeholder host), by the configuration check of both jobs and by
the app at start-up alike; the `https://` check of the first step is a second, earlier barrier. `PRIVACY_POLICY_URL`
is not passed, so a build made here has no privacy-policy URL compiled in. For a build with an explicit
`APP_ENV=production` and a privacy-policy URL use `--dart-define-from-file=config/production.json` locally
(`docs/RELEASE.md`); that is a limitation of the workflow as written.

**Gate (`guard` job, audit E-10).** Every other job `needs` it. It fails unless the run is on the repository's default
branch **and** the exact commit has a successful `CI` workflow run (read with the run's own `GITHUB_TOKEN`, `actions:
read`). A dispatch from a feature branch, or of a commit that CI has not passed, builds nothing and reads no secret.
`scripts/check-workflow-pins.mjs` (in the CI `secret-scan` job) fails the build if a job is added to `release.yml` that does
not depend on `guard`, if a job other than `android-sign` / `ios-archive` reads `secrets.*`, or if any `uses:` is not
pinned to a commit SHA (audit E-09; Dependabot's `github-actions` entry opens the update pull requests).

**Android is split in two jobs (audit E-20).** `android-build` has no environment and no secret: it is where the
whole third-party build graph (pub plugins, Gradle/Maven artifacts) runs, and it uses `WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`
to produce an **unsigned** bundle (artifact `wattbyte-android-unsigned-aab`, one day). `android-sign` (environment
`release`) downloads it and signs with the JDK's `jarsigner` (`SHA256withRSA`), then runs the signer-certificate
comparison below; only first-party `actions/*` and the JDK run next to the keystore. The iOS archive is still signed by
`xcodebuild` with the App Store Connect key in the job that resolves the Pods, so the key is exposed to that build graph
(residual risk; it is decoded only after analyze/test and removed at the end). There is no Gradle dependency verification
or lockfile yet (`gradle/verification-metadata.xml` would need a reviewed first run).

The signing job checks that every signing secret exists. Only whether a secret
is non-empty reaches that step, never its value. If one is missing the job stops with the annotation and job
summary **`BLOCKED — RELEASE KEY REQUIRED`**, lists the missing names and fails. The unsigned bundle is built first
and is not published as a release artifact; nothing is ever debug-signed and nothing falls back. The Android build job
(and the iOS job) run `dart run tool/check_backend_config.dart
--build-mode=release --dart-define="API_BASE_URL=$API_BASE_URL"` (the rules of the release guard, fed with exactly the
defines of the build step; a missing or unusable address stops the run, and so would a `LOCAL_ONLY_DEV` define if one
were ever added to both steps), and then `flutter analyze` and `flutter test`, before touching a key. The build step
itself would refuse to compile a missing address or a `LOCAL_ONLY_DEV` define (`[WB-CONFIG-001]`, `[WB-CONFIG-002]`);
an address that is present but unusable (`http`, a `.invalid` host) compiles, and only this check and the start-up check
of the app catch it. The check says so earlier and in plain words.

Store the secrets as **environment secrets of an environment named `release`** (Settings → Environments), and nowhere
else: required reviewers, deployment branches restricted to the default branch, and **no repository-level secrets with
these names** (those are readable by every workflow, including one on another branch). The workflow cannot check these
settings; they are part of the release checklist (`docs/RELEASE.md`). The signing jobs declare `environment: release`.

| Job | Secret | Content |
|---|---|---|
| `android-sign` | `ANDROID_KEYSTORE_BASE64` | the upload keystore, base64 (`base64 -i upload.jks`; macOS: pipe to `pbcopy`) |
| | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| | `ANDROID_KEY_ALIAS` | key alias (`upload` in `android/key.properties.example`) |
| | `ANDROID_KEY_PASSWORD` | key password |
| `ios-archive` | `IOS_TEAM_ID` | the 10-character Apple Developer Team ID |
| | `ASC_KEY_ID` | App Store Connect API key id |
| | `ASC_ISSUER_ID` | App Store Connect issuer id |
| | `ASC_API_KEY_BASE64` | the downloaded `AuthKey_<id>.p8`, base64 |

Create the Android keystore once and keep it (and its passwords) outside the repository:
`keytool -genkey -v -keystore ~/wattbyte-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.
Losing it means losing the ability to update the app unless Play App Signing holds the app signing key.

How the Android signing job handles the key: the keystore is decoded into `$RUNNER_TEMP` (never into the workspace),
mode 600, handed to `jarsigner` through `-storepass:env` / `-keypass:env` (the `WATTBYTE_KEYSTORE_*` / `WATTBYTE_KEY_*`
variables), never printed, and deleted in an `always()` step. After signing the job compares the SHA-256 of the signer certificate inside the `.aab` with the one in the keystore and fails
if the bundle is unsigned or signed by anything else.

How the iOS job signs: the project uses automatic signing, so the job writes the git-ignored
`apps/mobile/ios/Flutter/Local.xcconfig` (only `DEVELOPMENT_TEAM`), runs `flutter build ios --release --config-only`,
then `xcodebuild archive` and `-exportArchive` with `-allowProvisioningUpdates` and the App Store Connect API key,
so Xcode creates or downloads the distribution certificate and provisioning profiles for the team (cloud
managed) and no `.p12` or `.mobileprovision` is stored in GitHub. Requirements outside this repository:
the bundle id `pl.wattbyte.app`, the widget id `pl.wattbyte.app.WattByteWidget` and the App Group
`group.pl.wattbyte.app` must exist in the Developer account, and the API key needs a role that can manage
certificates (App Manager or Admin). The job verifies that the exported `.ipa` contains the widget extension and
is signed by the expected team, uploads it as an artifact and removes the key. It does **not** upload to
TestFlight; use Transporter or `xcrun altool`.

Status of this workflow: **NOT VERIFIED**. The YAML and shell syntax were validated (above); no signed build
has ever been produced by it, because no signing material is available in this environment. Expect to fix
details (certificate type, export method, profile names) on the first real run.
