# Mobile runtime configuration

How a WattByte build learns which backend it talks to (or that it deliberately
has none: the debug-only `LOCAL_ONLY_DEV` mode), which features are on, and
where the privacy policy lives. Everything is decided at build time with
`--dart-define`; the only runtime input is the server's public
`GET /api/v1/config`, which can switch features **off** but never on past the
build. Code: `apps/mobile/lib/config/`, `apps/mobile/lib/api/api_config.dart`,
`apps/mobile/lib/core/error_log.dart`, `apps/mobile/lib/main.dart`; the build
checks are `apps/mobile/tool/check_backend_config.dart` and
`apps/mobile/tool/check_release_guard.sh`.

Status words in this file follow the repository convention (IMPLEMENTED, TESTED,
NOT IMPLEMENTED, BLOCKED ...). The verification section lists what was really run.

## Build defines

| Define | Values | Default | Meaning |
|---|---|---|---|
| `APP_ENV` | `development`, `staging`, `production` | unset: `development` in a **debug** build, `production` in a **profile or release** build | rule set the other values are validated against. An explicit `staging` or `production` is honoured in every build mode; `development` is **refused in a profile or release build** (a build that ships is never a development build, F-14); a typo (`prod`) is reported and treated as `production`, the strictest set (see "Which rules apply") |
| `API_BASE_URL` | absolute URL | empty | the API. **Required**, unless the build is a debug build with `LOCAL_ONLY_DEV=true`; empty is otherwise an invalid configuration, not a "local build" (see "Backend mode and the release guard") |
| `LOCAL_ONLY_DEV` | `true`, `false` | unset (= `false`) | the explicit development mode without a backend and without an account. Valid only in a **debug** build, in the `development` environment, without `API_BASE_URL`; any other spelling is an error; `true` in a profile or release build does not compile, and `true` with `APP_ENV=staging` or `production` (or a typo) is an error even in a debug build |
| `PRIVACY_POLICY_URL` | public `https` URL | empty | the privacy-policy page (see below) |
| `FEATURE_AI` | `true`/`false` (also `1/0`, `yes/no`, `on/off`) | `true` | build default of the AI switch |
| `FEATURE_SUBSCRIPTIONS` | same | `false` | build default of the subscriptions switch |
| `FEATURE_CLOUD_SYNC` | same | `true` | build default of the cloud-sync switch |

Dart defines are compiled into the binary and can be read out of it: **never put
a secret in them.** Nothing in the mobile app needs one: the API authenticates
with the user's tokens, which live in the platform keychain.

No production or staging address is hardcoded anywhere in `lib/`. The only URL
literals left in hand-written sources are comments and the `startsWith('https://')`
scheme check (`test/app_config_test.dart` fails the build if another one appears,
in `.dart` or `.arb` files).

## Environments

```
flutter run   --dart-define-from-file=config/development.json
flutter run   --dart-define-from-file=config/local-only-dev.json    # debug only, no backend
flutter build ipa       --dart-define-from-file=config/production.json
flutter build appbundle --dart-define-from-file=config/production.json
# or define by hand
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080    # Android emulator, API on the host
flutter run --dart-define=LOCAL_ONLY_DEV=true                  # debug only, no backend, no account
```

`apps/mobile/config/{development,local-only-dev,staging,production}.example.json`
are the templates (`/config/*.json` is git-ignored, only `*.example.json` is
tracked). `development` points at `http://127.0.0.1:8080`; `local-only-dev` carries
`APP_ENV=development` and `LOCAL_ONLY_DEV` and no address, and is valid for debug builds only. Staging and
production use placeholder hosts under the reserved `.invalid` TLD on purpose:
copy a template to `config/<env>.json`, put the real hosts in, and keep that file
out of version control. A template used unchanged does not silently "work": the
placeholder is rejected (below), so the configuration is **invalid**. The compile-time
guard cannot see it (the address is not empty), the start-up check refuses to run
the app, and `tool/check_backend_config.dart` rejects it before any build is made.
The `_NOTE` key in the templates is passed along as a harmless unused define.
`API_BASE_URL` is not a secret, and it is never hardcoded: it is set per
environment by `--dart-define`, `--dart-define-from-file` or, in CI, the release
workflow's `api_base_url` input.

`ApiConfig` (`lib/api/api_config.dart`, same constructor as before) validates the
address against the environment that applies (`APP_ENV`; unset means `development`
in a debug build and `production` in a profile or release build, see "Which rules
apply"):

| Rule | development | staging / production |
|---|---|---|
| empty address | `ApiConfig`: not configured, no problem of its own. The build rule below then makes the build **invalid**, unless it is a debug build with `LOCAL_ONLY_DEV=true` | same |
| scheme | `http` or `https` | **`https` only** |
| host | valid DNS name, IPv4 or IPv6 | same, and not a `.invalid` placeholder |
| port | 1-65535 if present | same |
| user info (`user:pw@`), query, fragment | refused | refused |
| whitespace, relative URL, other scheme | refused | refused |

An address that fails any rule is unusable: `baseUrl` is empty, `isConfigured` is
false and `ApiConfig.problem` / `AppConfig.problems` say why (never echoing the
value, which may contain credentials), so no request can ever leave for a wrong or
cleartext address. It is **not** "no backend", though: `validateBackendConfig`
reports it as an error, the build is invalid and does not run, and not even
`LOCAL_ONLY_DEV=true` turns it into a local-only build (the case is tested with a
malformed address and the flag in a debug build). Trailing slashes and surrounding
whitespace are trimmed. The native layers enforce the same on their own: Android release has
`usesCleartextTraffic="false"` (cleartext only in the debug manifest), iOS keeps
App Transport Security with no exception.

`AppConfig.fromEnvironment.problems` is logged, one line each and without values,
at startup of debug builds only.

## Backend mode and the release guard

The rule, stated once: **`API_BASE_URL` is required, unless the build is a debug
build with `LOCAL_ONLY_DEV=true`.** Going without an account is possible only for
`debug && LOCAL_ONLY_DEV == true` (and only in the `development` environment);
nothing else (no missing address, no broken address, not "debug" by itself) skips
Welcome and Register / Login. Earlier builds ran without an account whenever the
address was missing; that behaviour is gone.

The normal flow of every valid build except the development mode:

```
Launch → Welcome → Register / Login → Automatic Setup → Permissions → Dashboard
```

### The verdict: `validateBackendConfig`

`validateBackendConfig({buildMode, apiBaseUrl, localOnlyDev, environment})` in
`lib/config/backend_config.dart` is pure Dart (no Flutter import), so the unit
tests, the command-line check and the app run the same code. It returns a
`BackendConfigCheck`: either `mode` (`BackendMode.online` or
`BackendMode.localOnlyDev`) or a list of `errors`, one line per violated rule,
never containing a define's value. `AppConfig.fromDefines` calls it and exposes
`buildMode`, `backend`, `backendMode` (`null` when invalid), `isValid`,
`isLocalOnlyDev` and, in `problems`, the errors. `AppConfig.fromEnvironment` is
the only run-time reader of the backend defines (the compile-time guard in the same
file reads `API_BASE_URL` and `LOCAL_ONLY_DEV` itself and `FlagDefines` reads `FEATURE_*`;
`ApiConfig.fromEnvironment` and `AppEnvironment.fromEnvironment` no longer exist). `localOnlyDev` is the **raw
define text** (`''` unset, `true`, `false`); any other spelling is an error,
because a safety switch is never guessed.

| Build mode | `API_BASE_URL` | `LOCAL_ONLY_DEV` | Verdict |
|---|---|---|---|
| any | valid for the environment that applies | unset / `false` | `online` |
| debug | missing | `true` | `localOnlyDev` |
| debug | missing | `true`, `APP_ENV` staging, production or a typo | **invalid**: `LOCAL_ONLY_DEV=true is only allowed in the development environment` |
| debug | missing | unset / `false` | **invalid**: `API_BASE_URL is required` |
| profile | missing | any | **invalid** |
| release | missing | any | **invalid** |
| profile, release | any, also a valid one | `true` | **invalid**: `LOCAL_ONLY_DEV=true is only allowed in debug builds` |
| debug | valid | `true` | **invalid**: `cannot be combined with API_BASE_URL` |
| any | present but unusable (see the rules above) | any | **invalid**, with the address problem; never `localOnlyDev` |
| any | any | anything but unset / `true` / `false` | **invalid**: `LOCAL_ONLY_DEV must be true or false` |

The six cases of the specification are the first six tests of
`test/config/backend_config_test.dart` (debug + API → online; debug + no API +
`LOCAL_ONLY_DEV=true` → local-only; debug + no API + `false` → invalid; release +
API → valid; release + no API → invalid; release + `LOCAL_ONLY_DEV=true` →
invalid). The same file runs the whole cross-product of build mode, address and
flag against this table and asserts that `localOnlyDev` comes out only for debug +
no address + `true`.

### Which rules apply: the environment and the build mode

Two inputs are resolved before the verdict is computed. Both are pure functions in
`lib/config/backend_config.dart`, fed by `AppConfig` and by the command-line check.

* **The environment** (`effectiveEnvironment`). Without `APP_ENV`, a **debug**
  build is `development` (a plain `flutter run`; `http` is accepted) and a
  **profile or release** build is `production` (https only, no `.invalid`
  placeholder host): a build that ships never accepts cleartext because a define was
  forgotten. An explicit `APP_ENV` is honoured, except that `development` is an
  error in a profile or release build (F-14), and a typo means `production`. The release workflow passes `API_BASE_URL` only, so its check and
  the app it builds both apply the production rules to that address.
* **The build mode** (`effectiveBuildMode`). The app learns its mode from the
  `dart.vm.product` / `dart.vm.profile` constants (`kBuildMode`). A command line can
  override them (`--dart-define=dart.vm.*`, `--extra-front-end-options`), which
  would let a profile or release binary claim to be a debug build and unlock
  `localOnlyDev`. Flutter runs `assert` only in debug (JIT) builds and in
  `flutter test`, so a binary that says "debug" but runs without assertions is a
  profile or release AOT binary and is validated as **release**. `AppConfig.fromEnvironment`
  passes this effective mode explicitly. The command-line check rejects any define
  named `dart.vm.*` (exit 1).

### Three layers

1. **Compile time** (`kBuildConfigurationGuard`, `lib/config/app_config.dart`).
   A constant whose constructor has two `assert`s; the compiler evaluates it in
   every build, and a failed `assert` in a constant constructor is a compile error
   whether or not assertions are on at run time. A profile or release build with an
   empty `API_BASE_URL` fails with `[WB-CONFIG-001]`, with `LOCAL_ONLY_DEV` set to
   anything but unset / `false` with `[WB-CONFIG-002]` (the first one is named when
   both apply). The message in the build output reads
   `This assertion failed with message: [WB-CONFIG-001] INVALID BUILD CONFIGURATION: a profile or release build needs --dart-define=API_BASE_URL=...`,
   and for the second code: in a profile or release build `LOCAL_ONLY_DEV` must be
   unset or exactly `false` (`LOCAL_ONLY_DEV=true` is a debug-only mode). The check
   is exact and fails closed: `TRUE` or `" false"` does not compile either, although
   the runtime validator trims whitespace (a compile-time constant cannot). A
   constant cannot parse a URL, so this layer covers exactly those two mistakes.
   It does not stop debug builds, because `flutter test` and `flutter analyze`
   compile without defines. It also cannot see a `dart.vm.*` override: it takes
   "is this an optimised build" from the same constants, so an override that
   defeats it is caught by layer 2 (and, before a build, by layer 3).
2. **Start-up check** (`main()`, `lib/config/config_error_app.dart`). `main()` builds
   `AppConfig.fromEnvironment` (validated for the effective build mode and
   environment, above), logs it in debug builds, and when `!config.isValid`
   runs `ConfigErrorApp(config: config)` and returns, **before** the orientation
   lock, `SharedPreferences`, the database and the background registration. The
   screen is titled "Invalid build configuration", says that nothing was loaded,
   lists the errors one bullet each (never the address) and, only when
   `kBuildMode == BuildMode.debug` at run time, the two commands that fix it
   (`flutter run --dart-define=API_BASE_URL=...`,
   `flutter run --dart-define=LOCAL_ONLY_DEV=true`). The validator's own error
   messages, which mention `LOCAL_ONLY_DEV`, are in every binary. The screen has no
   sign-in form, no setup and no button into the app, and is English and
   developer-facing on purpose: a broken configuration cannot be expected to bring
   the localisation along. This layer covers everything the compiler cannot:
   address syntax, `https` where the environment demands it, placeholder hosts, a
   malformed flag, the debug contradictions. Routing follows the same flag:
   `StartGate` passes `AppConfig.isLocalOnlyDev` to `startDestination(localOnlyDev: ...)`,
   which skips the account only when it is `true` and otherwise requires a session
   whatever the address says (fail closed). An auth state that is an error without a
   value (a failed session restore) routes to Welcome instead of throwing inside
   `StartGate`.
3. **CI and the release workflow** (before a build exists).
   `tool/check_backend_config.dart` (logic in `lib/config/backend_config_cli.dart`,
   unit-tested) applies the verdict from the command line. It takes the options of
   `flutter build`: `--build-mode=<debug|profile|release>`, repeatable
   `--dart-define=KEY=VALUE` and `--dart-define-from-file=<json>`; later values
   replace earlier ones and `--dart-define` beats a file, like Flutter. It reads
   `API_BASE_URL`, `LOCAL_ONLY_DEV` and `APP_ENV` only (a profile or release check
   without `APP_ENV` is a production check, like the app's) and rejects any define
   named `dart.vm.*`. Exit code 0 = valid (`OK: online (release)`), 1 = invalid
   (`INVALID BUILD CONFIGURATION (release)` and one `  - <error>` line each, on
   stderr), 64 = unusable arguments. It never prints a define's value.
   `tool/check_release_guard.sh` runs it over **26 combinations: 18 must be rejected
   and 8 accepted**. Rejected: release without an address (with `LOCAL_ONLY_DEV`
   unset, `false` and `true`), profile without an address, `LOCAL_ONLY_DEV=true`
   with an https address (release and profile), an `http` or `.invalid` address for release, with
   and without `APP_ENV=production`, a `dart.vm.*` define (also the spoofed
   "profile as debug" local-only build), the unedited `config/production.example.json`,
   the debug-only `config/local-only-dev.example.json` in a release check, debug
   without an address and without the flag (unset and `false`), debug with the flag
   and `APP_ENV=production`, a malformed address in debug with the flag. Accepted:
   release with an https address (the defines of the release workflow, also with
   `APP_ENV=production` or `LOCAL_ONLY_DEV=false`), profile with an https address,
   debug with `LOCAL_ONLY_DEV=true` (by hand and from `config/local-only-dev.example.json`),
   debug against `http://127.0.0.1:8080`, `config/development.example.json`. A
   verdict is only accepted as a rejection if the exit code is exactly 1 and the
   `INVALID BUILD CONFIGURATION` header is there, so a crashing checker can never
   look like a rejection. The fixture host is `https://api.ci-guard.test`.
   With `--builds` the script additionally makes **three real
   `flutter build apk --release -v` runs** (no signing key needed,
   `WATTBYTE_ALLOW_UNSIGNED_RELEASE=1`):
   * without `API_BASE_URL` it must fail and the log must contain `[WB-CONFIG-001]`;
   * with an address and `LOCAL_ONLY_DEV=true` it must fail with `[WB-CONFIG-002]`
     (a build that fails for any other reason fails the script: the marker proves
     which guard fired);
   * with a valid, made-up https address (arm64 only, unsigned) it must **build**
     (the positive control: a guard that refused everything would pass the first
     two), and the script then unpacks `lib/arm64-v8a/libapp.so` from that APK,
     requires a control string of the release binary (the "Invalid build
     configuration" title) to be present, so that "no hit" means something, requires
     the development banner text to be absent, and deletes the APK.

   `ci.yml` runs the matrix in the job `mobile-config-guard`, together with
   `test/config/define_wiring_test.dart` run twice with real compile-time defines
   (`--dart-define=API_BASE_URL=...`, then `--dart-define=LOCAL_ONLY_DEV=true`): the
   one link no plain `flutter test` can see, that the real defines reach
   `AppConfig.fromEnvironment`. The three builds run in a step of the `android` job,
   which therefore now also builds a release APK (Gradle; the job's
   `timeout-minutes` is 40; the whole script took 44 s on a developer Mac with warm
   caches, and how long the step takes on a cold runner is not known, because the job
   has never run). `release.yml` runs the checker with its own defines
   before it analyses, tests or signs. Details: `docs/CI.md`.

```
cd apps/mobile        # after flutter pub get
dart run tool/check_backend_config.dart --build-mode=release --dart-define=API_BASE_URL=https://<api host>
bash tool/check_release_guard.sh [--builds]
```

### The development banner

`LOCAL ONLY DEVELOPMENT MODE` (`kLocalOnlyDevBannerText`,
`lib/config/local_only_banner.dart`) is a thin red strip above the whole app
(`LocalOnlyDevBanner`) plus one line in the debug log (`logStartupConfiguration`).
Both exist only when `kBuildMode == BuildMode.debug && appConfig.isLocalOnlyDev`,
so no normal build can show them. The text itself is the constant
`kDebugMode ? 'LOCAL ONLY DEVELOPMENT MODE' : ''`: in a profile or release build it
is the empty string, so the literal itself is not in those binaries, independent of
how the compiler treats the code around it. `tool/check_release_guard.sh --builds`
is the check that greps a real release binary for it (above). It is not localised on purpose. The error screen never shows it.
`test/config/backend_config_invariants_test.dart` keeps the sources honest at
source level (the text is spelled out once, used by the widget and the debug log
only, built in `lib/app.dart` behind the debug condition).

### Rules that are stricter than the minimum

The specification asks for: `API_BASE_URL` required unless debug +
`LOCAL_ONLY_DEV=true`, and the four forbidden cases rejected. These rules go
beyond it on purpose. The owner may want to relax any of them; each lives in one
place.

| Rule | Where | Why it is there |
|---|---|---|
| debug + a valid `API_BASE_URL` + `LOCAL_ONLY_DEV=true` is rejected | `validateBackendConfig` | the two settings contradict each other: which backend does the developer mean? |
| `LOCAL_ONLY_DEV` spellings other than `true` / `false` (`TRUE`, `1`, `yes`) are rejected, and the compile-time layer accepts only unset or exactly `false` in profile and release | `validateBackendConfig`, `BuildConfigurationGuard` | a safety switch is never guessed, and a typo must not read as "off" |
| `LOCAL_ONLY_DEV=true` needs the `development` environment (an error with `APP_ENV=staging`, `production` or a typo, even in a debug build) | `validateBackendConfig` | a configuration that names a real environment must not also say "no backend" |
| profile and release builds without `APP_ENV` are validated as `production` (https only, no `.invalid` host) | `effectiveEnvironment` | a forgotten define must not switch cleartext on in a build that ships. Consequence: a profile or release build always needs a public `https` host; a profile build against an `http` LAN address is not possible any more (use a debug build, or a staging host) |
| the command-line check rejects any define named `dart.vm.*` | `lib/config/backend_config_cli.dart` | such a define overrides the build mode the app detects itself by; no real build sets one by hand |

### Limits

* A **debug build made without defines compiles**, and only the app it produces
  stops at the error screen, so a green `flutter build ... --debug` (CI builds one)
  does not mean the app starts. Debug builds are checked at start-up, not at
  compile time, because `flutter test` and `flutter analyze` compile without defines.
* On **iOS the compile error is easy to miss**: `flutter build ios --release --no-codesign`
  without `API_BASE_URL` fails (exit 1), but without `-v` Flutter prints its "Development
  Team" hint instead of `[WB-CONFIG-001]`; with `-v` the Dart compile error is in the
  output. Run `dart run tool/check_backend_config.dart` first (the release workflow does).
* The **compile-time guard cannot see a `dart.vm.*` override** (a
  `--dart-define=dart.vm.*` or `--extra-front-end-options` on the command line); the
  start-up check can, because it also asks whether assertions run. The command-line
  check sees only defines, not front-end options.
* The compile-time guard compares exactly: in a profile or release build
  `LOCAL_ONLY_DEV` must be unset, empty or `false` there (the start-up check also
  ignores surrounding whitespace, so `" false "` passes it but not the compiler), and
  a whitespace-only `API_BASE_URL` is not empty for the compiler but is "missing" for
  the start-up check. Conversely, **debug + `LOCAL_ONLY_DEV=true` with a
  whitespace-only `API_BASE_URL` counts as "no address"** and is valid local-only
  development.
* **F-14.** In a profile or release build `APP_ENV=development` is an error
  (`APP_ENV=development is not allowed in <mode> builds`), and `API_BASE_URL` must be
  a public host: `localhost`, an IP address, a single-label name and the reserved
  top-level names (`.invalid`, `.example`, `.test`, `.localhost`, `.local`, `.internal`, `.lan`, `.home`, `.corp`, `.intranet`) and
  `example.com` / `.net` / `.org` are
  refused (`API_BASE_URL must be a public host in <mode> builds`). Both are checked
  by the app at start-up, by `tool/check_backend_config.dart` and by
  `tool/check_release_guard.sh` (26 combinations). The rule looks at the shape of the
  name only: a public-looking name that does not resolve is not detected. The compile
  time guard cannot parse a URL and still checks only that an address exists.
* In a **debug** build an IP-literal or single-label host still passes the https rule
  of `APP_ENV=staging|production` (https only, a valid host, no `.invalid` placeholder),
  because a developer may point a debug build at a staging box by address. In a
  profile or release build the F-14 rule above refuses it.
* The development banner is **not read out by VoiceOver or TalkBack**: a route's
  `BlockSemantics` hides it. It is a visual developer aid, not part of the app a
  user can reach.
* The **WorkManager / BGTask background refresh is local-only by design** (its pipeline has
  no sync service) and is not gated by the configuration. Dart schedules it only after
  the start-up check (`main()` returns before `registerBackgroundRefresh()` when the
  configuration is invalid); on iOS the task handler is registered natively in
  `AppDelegate` at launch regardless, and a task scheduled by an earlier valid build
  can still fire.
* `release.yml` still **does not pass `PRIVACY_POLICY_URL`**, so a build made by the
  workflow has no privacy-policy URL compiled in (see "Privacy-policy URL" below).
  It passes `API_BASE_URL` only; the address is validated as `production` because no
  `APP_ENV` is given.
* Status: IMPLEMENTED and TESTED (`docs/REGRESSION_TESTS.md`, "Backend
  configuration and the release guard"). The CI jobs and the release-workflow step
  are CONFIGURED, NOT REMOTELY VERIFIED. No run on a device or a simulator is
  claimed for this change.

## Privacy-policy URL

`AppConfig.privacyPolicyUrl` is a `Uri?`: non-null only for a **public https
URL** (a real, resolvable host: not `localhost`, an IP literal, a single-label
name, `.local`/`.test`/`.invalid`/`.example`, `example.com`, and without
credentials). Anything else yields `null` and a problem line.
`AppConfig.hasPrivacyPolicyUrl` is the boolean.

Until a valid URL is configured the status is

> **BLOCKED — PUBLIC URL REQUIRED**

(`kPrivacyPolicyBlockedStatus`, `AppConfig.privacyPolicyStatus`). It is a
diagnostic: it appears in this document and in the debug-only startup log line,
not in the user interface. The store listings and the in-app link need the
policy published on a public https page; this repository cannot provide that.
`release.yml` does not pass `PRIVACY_POLICY_URL` (it passes `API_BASE_URL` only), so
a build made by the workflow has no policy URL compiled in; one with it is the local
`--dart-define-from-file=config/production.json` build (`docs/CI.md`).
**Status today: BLOCKED — PUBLIC URL REQUIRED.** The UI that shows the link
(Account / Settings) is not wired to `hasPrivacyPolicyUrl` yet (NOT IMPLEMENTED
in this change; the API is in place).

## Feature flags

`FeatureFlags {ai, subscriptions, cloudSync}` exists in three roles: the build
defaults (`FEATURE_*`), the server's `features` object, and the effective result.

```
effective.flag = build.flag AND server.flag          server configuration known
effective.ai = build.ai, effective.cloudSync = build.cloudSync,
effective.subscriptions = false                      server configuration never fetched
```

"Server configuration known" means: the one just fetched, otherwise the last one
cached in SharedPreferences (key `wb.serverConfig.v1`; no expiry, it carries
`fetchedAt`). A paid feature never switches on before the server has said so;
a server flag can only narrow what the build allows.

`mergeFeatureFlags` and `effectiveServerConfig` are pure
(`lib/config/feature_flags.dart`); the Riverpod side is
`lib/config/config_providers.dart`:

| Provider | Value |
|---|---|
| `appConfigProvider` | the build's `AppConfig` |
| `featureFlagsProvider` | **the effective flags**: what UI and services must obey |
| `aiDailyLimitsProvider` | `AiDailyLimits(free, premium)` from the server, or `null` until the server has told the app (plan limits are never hardcoded) |
| `serverConfigProvider` | the last known `ServerFeatureConfig?`; `.notifier.refresh()` fetches |
| `serverConfigFetcherProvider` | **the seam** (below) |

`ServerFeatureConfig` mirrors `AppConfigDto` of `packages/contracts`
(`environment`, `features`, `ai.dailyLimits`) and is parsed strictly: a missing
or mistyped flag or limit makes the whole document unusable instead of
defaulting a switch; unknown extra fields are ignored. A damaged cache is
reported to the local error log and treated as "never fetched".

### Plugging in the remote fetch

Not done yet by design: no generated-client call exists. When
`GET /api/v1/config` is in `lib/generated/api` (it is public, no token needed),
override one provider:

```dart
serverConfigFetcherProvider.overrideWithValue(() async {
  try {
    final dto = await ConfigApi(ref.read(apiFactoryProvider).anonymous()).apiV1ConfigGet();
    return dto == null
        ? null
        : ServerFeatureConfig.fromServerJson(dto.toJson(), fetchedAt: DateTime.now());
  } on ApiException {
    return null;               // server unreachable: the cache stays in effect
  }
});
```

(names of the generated class and method depend on the generator). With a
fetcher wired, the first read of `serverConfigProvider` starts one refresh by
itself, concurrent `refresh()` calls share one request, a `null` result or an
`Exception` keeps the cache (the exception is reported), and a result that lands
after the provider is disposed is dropped. A route the server has switched off
answers 503 `feature_disabled`; the app hides the feature instead of calling it.

## Orientation

`main()` awaits `SystemChrome.setPreferredOrientations([portraitUp])` before
`runApp` (`lib/config/startup.dart`). It matches the native projects, which are
portrait-only: iPhone `Info.plist` lists only `UIInterfaceOrientationPortrait`
(the target is iPhone-only, `TARGETED_DEVICE_FAMILY = 1`) and the Android
activity has `screenOrientation="portrait"`. A test maps the Dart list to the
plist's orientation names and requires the two sets to be equal.

## Logging

`lib/core/error_log.dart` is the only place that prints. It keeps a bounded,
in-memory ring of the last 50 errors (nothing is written to disk or sent
anywhere) and **sanitises every message, tag and stack frame before it is stored
or printed** (`sanitizeLogText`):

| Removed | Becomes |
|---|---|
| values of keys containing `password`, `passwd`, `pwd`, `passphrase`, `secret`, `token`, `api key`, `authorization`, `credential`, `cookie` (JSON, Dart maps, query strings, headers, `Basic`/`Bearer` schemes) | `[redacted]` |
| `Bearer <token>` anywhere, `user:password@` in URLs | `Bearer [redacted]`, `[redacted]@` |
| JWT-shaped strings | `[jwt]` |
| e-mail addresses | `[email]` |
| 32+ hex digits | `[hex]` |
| 40+ url-safe characters mixing letters and digits (the API's refresh token is 43) | `[secret]` |
| account name in `/Users/<name>`, `/home/<name>`, `C:\Users\<name>` | `[user]` |

A password value runs to the next whitespace or delimiter even through `&`
(`password=a&b&country=PL` loses the country, not half the password); other
secrets stop at `&` so a query string keeps its other parameters. The sanitiser
over-redacts on purpose, is idempotent, cuts its input at 16 000 characters
before matching and is linear on hostile input (tested with 200 000-character
runs). Entries are clipped to 1 500 characters and 12 stack frames.

Release builds print nothing: printing is gated on `kDebugMode` (`ErrorLog`
takes the switch as a constructor argument, which is how the test covers the
release behaviour). The ring still fills in release builds, for the day a
"copy diagnostics" action exists. `debugLog()` is the debug-only channel for
developer messages; a test fails if any other file in `lib/` calls `print`,
`debugPrint`, `developer.log` or writes to stdout/stderr. Existing user-data
logging: none was found (the only `debugPrint` was the error log's own, now
sanitised). `main()` no longer swallows a failed background-task registration:
it goes to the log.

Not covered by this module: native logging (Kotlin/Swift) and anything the
Flutter framework prints itself in debug mode.

## Verification (what was actually run)

All commands in `apps/mobile`, 2026-10-13, Flutter 3.41.6. This table is the
record of the 2026-10-13 change (environments, URL validation, privacy URL, flags,
logging); it was **not** re-run for the backend-configuration change below, and its
file and test counts predate that change's tests.

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed` on the files of this change | no changes needed |
| `dart analyze lib/config lib/main.dart lib/core lib/api test/app_config_test.dart test/feature_flags_test.dart test/error_log_test.dart` | no issues |
| `flutter test test/app_config_test.dart test/feature_flags_test.dart test/error_log_test.dart` | 80 tests pass (29 + 30 + 21) |
| `flutter test --exclude-tags e2e` (whole suite, other work in progress included) | 283 tests pass (run before the last edit of the orientation test) |
| `flutter test --dart-define-from-file=config/<env>.example.json` with a throw-away probe test, plus a copy with real https hosts and a `--dart-define` typo run | development example configured; staging/production examples rejected as placeholders; the real-host copy configured with `CONFIGURED` privacy status and the flags from the file; the typo run reported three problems and applied the strict rules |
| `grep -rnE "https?://" lib` (hand-written) | 3 hits: two comments and the `startsWith('https://')` scheme check |

TESTED: environments, URL validation, privacy URL, flag merge (all 64
build x server combinations plus the never-fetched rows), cache, providers,
sanitiser, bounded log, orientation call and plist agreement.
IMPLEMENTED but NOT VERIFIED on a device or simulator: the portrait lock on a
rotated device, the debug startup log in a running app. No `flutter build` was
run for this change (BUILD VERIFIED does not apply). No Android or iOS device
was involved.

### Backend configuration and the release guard

Not part of the table above. The results of the verification run for that change
(format, analyze, the whole test suite, the debug builds, `tool/check_release_guard.sh`
with and without `--builds`, the two runs of `test/config/define_wiring_test.dart`
with defines) are in `docs/REGRESSION_TESTS.md`, "Verification (2026-10-14)". In short: 1974 tests pass (38 skipped), format and analyze
are clean, the guard script's 26 checks and its three real release builds behave as
specified, and the debug app was started once on the iOS simulator in each of the two
modes (local-only with the banner; no define with the error screen).

What this page claims about it: IMPLEMENTED; TESTED (the test files and what
each protects are in `docs/REGRESSION_TESTS.md`, "Backend configuration and the
release guard"); the CI job `mobile-config-guard`, the `--builds` step of the
`android` job and the release-workflow step are CONFIGURED, NOT REMOTELY VERIFIED;
nothing was run on a physical device.
