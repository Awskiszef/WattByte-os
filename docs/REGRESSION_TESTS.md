# Regression tests

What guards each of the twelve bugs found on the iOS Simulator (an iOS Simulator run), and what else this suite pins. Status words follow `docs/VERIFICATION_STATUS.md` (IMPLEMENTED, TESTED, BUILD VERIFIED,
INTEGRATION VERIFIED, SIMULATOR VERIFIED, DEVICE VERIFIED, NOT VERIFIED, BLOCKED, NOT IMPLEMENTED). Nothing here is DEVICE
VERIFIED. A test of configuration proves that the configuration is what it was; it does not prove that the app builds or
launches: that is the build and the simulator, named in the "Verification" column where it matters.

Run everything: `cd apps/mobile && flutter test`. The two end-to-end suites need a running API and skip themselves
otherwise (see "End to end" below), and the two tests of `config/define_wiring_test.dart` skip themselves without
`--dart-define`s (CI runs that file with them, see "Backend configuration and the release guard").

## The twelve bugs

| # | Bug | Root cause | Test or verification | Status |
|---|---|---|---|---|
| 1 | App crashed at launch on iOS 27 | iOS 27 refuses a UIKit app without the UIScene life cycle: `AppDelegate` used the pre-scene launch and `Info.plist` had no scene manifest | `test/config/native_config_test.dart`, group "iOS: UIScene lifecycle": `UIApplicationSceneManifest` with one `UIWindowScene` whose delegate is `$(PRODUCT_MODULE_NAME).SceneDelegate` and whose storyboard exists; `SceneDelegate` subclasses `FlutterSceneDelegate`; `AppDelegate` adopts `FlutterImplicitEngineDelegate`, registers plugins on `engineBridge.pluginRegistry`, never on `self`; the background-task id is the same in Dart, Swift and the plist. That the app then launches: simulator run in the report | TESTED (config); launch SIMULATOR VERIFIED earlier, not repeated here |
| 2 | Simulator build failed ("does not contain architectures arm64 x86_64") | Xcode 27's `lipo` accepts one architecture after `-verify_arch`, and the build asked for two; the first fix pinned `ARCHS` to a literal `arm64` (broke Intel Macs, replaced Flutter's `EXCLUDED_ARCHS`) | `native_config_test.dart`, group "iOS: simulator architectures": no literal `ARCHS[sdk=iphonesimulator*]` or `EXCLUDED_ARCHS ... x86_64` in `Podfile`, the xcconfigs, `project.pbxproj` and the generated `Pods.xcodeproj`; the lookup table covers `arm64`, `arm64e` (Flutter runs `arch -arm64e`) and `x86_64` in `WattByte.xcconfig` and in the `Podfile`; the rule is conditional on the simulator SDK; the detectors are shown to fire on the old literal lines. The build: `flutter build ios --simulator --debug` | TESTED (config); the build itself BUILD VERIFIED in `docs/PLATFORM_SUPPORT.md`, not re-run by this suite |
| 3 | `cloudSync` was never saved | `SettingsStore.save` did not write `wb.cloudSync`; after a restart sync silently stopped | `test/settings_persistence_test.dart`: one test per `Settings` field ("... is written by save() and read back after a restart", also from a brand-new `SharedPreferences` built from what the old one held), a meta-test that fails when a field is added to `class Settings` without a row, "all of them together survive a restart". `test/settings_persistence_restart_test.dart`: through `settingsProvider`, "every change made through the notifier is on disk when update() returns". `test/settings_store_test.dart` (existing). The sync side of this bug (the switch and the queue after an account change) is the sync agent's | TESTED. Sync side: TODO, covered by the sync agent's tests (see its report) |
| 4 | Share sheet failed (`sharePositionOrigin` zero on iOS 26+); export errors unhandled; local export timestamps | the anchor was `Rect.zero`; the export `try` did not exist; `DateTime.toIso8601String()` on a local time carries no offset | Anchor and error message: `test/share_anchor_test.dart` and `test/accessibility/share_anchor_export_test.dart` (the UI agents'). Timestamps and the data itself: `test/export_csv_test.dart`, `test/export_json_test.dart`, `test/exporter_test.dart` (UTC with `Z` from any zone, DST nights, local day keys, no NaN) | TESTED. Share sheet on a phone: NOT VERIFIED (simulator only) |
| 5 | Dashboard values truncated ("~0.000 ..."), "Measured" under an empty 0 mAh | `Text` with `TextOverflow.ellipsis` in a card; the sub-line did not look at the value | `test/widgets_regression_test.dart`: on the real dashboard (iPhone SE, text scale 1.0 to 3.0) no card text is ellipsized or loses lines; "Measured" only under a real measurement (measured counters yes; empty day, 0 % session and an iPhone estimate no). The widget rules (`BigNumber` shrinks, `Label` wraps, "~" only in front of a number) are in `test/accessibility/shared_widgets_test.dart` (UI agents) | TESTED |
| 6 | Outlined buttons unreadable on light cards | the default outlined foreground is the yellow primary | `test/theme_contrast_test.dart`: the label colour the button really renders with, against the card, the screen and every accent wash, light and dark: >= 4.5:1; it is not the primary. The OUTLINE needs >= 3:1: **it does not reach it today** (`onSurface` at 35 %: 2.2-2.3:1 on the light surfaces, 2.8-3.0:1 on the dark ones) | Label TESTED. Outline BLOCKED: test written and skipped, theme file not owned by this suite (see "Blocked tests") |
| 7 | Accessibility text size overflowed | (the clamp to 1.35x that hid it was removed by the UI work) | not this suite's: the sweeps to text scale 3.0 are `test/accessibility/*`; `widgets_regression_test.dart` repeats the dashboard cards at 1.0, 1.35, 1.6, 2.0 and 3.0 | not in scope here |
| 8 | Account form kept the old e-mail and a stale "Wrong email or password" | the form's state was not reset on mode switch or after sign-in | `test/auth_form_state_test.dart`: switching sign in <-> create account clears the password and the error (also switching back, and again), a new failure shows only its own message, after sign-in / sign-up both fields are empty, same rules on the Account screen and after a sign-out; busy state disables both buttons and both fields and keeps the button's name for a screen reader; each failure (wrong password, e-mail taken, invalid input, rate limit, server error, proxy page, no connection) shows the ARB text in English and Polish and none of the server's words | TESTED |
| 9 | After an account switch, "synced" days were never uploaded to the second account | the queue had no owner | TODO | covered by the sync agent's tests (see its report) |
| 10 | The changing day was uploaded every minute | no throttle | TODO | covered by the sync agent's tests (see its report) |
| 11 | Sync errors vanished | errors were swallowed | TODO | covered by the sync agent's tests (see its report) |
| 12 | "About" and "Data collection" said nothing is ever uploaded; offline with an expired token | wording; the refresh failure while offline was not a "keep the session" case | Wording: `test/l10n_parity_test.dart`, group "privacy wording" (concrete phrases, English and Polish, checked against `docs/privacy.md`, `docs/AUTO_SETUP.md` and the privacy manifest). Two strings still overclaim and are listed in the test with their reason (see "Open issues"). Offline with an expired token, covered by `test/delete_account_auth_cleanup_test.dart` ("offline with an expired token keeps the session ... and restores it once the network is back"), `test/session_manager_test.dart` (existing) | TESTED. Wording: two known overclaims open |

## What else the suite pins

| Area | Files | What is pinned |
|---|---|---|
| Settings persistence | `settings_persistence_test.dart`, `settings_persistence_restart_test.dart` | every field and every enum value round-trips (same instance, new store, and a new `SharedPreferences` built from "disk"), notification switches are independent, bookkeeping (locale, device-spec cache, sent-notification keys capped at 200), corrupt values sanitised (NaN, infinity, negatives, out of range, malformed codes, unknown enum names), boundary values kept, legacy pre-setup preferences (extra cases only: `setup_flow_test.dart` has the main one), the onboarding flag, concurrent updates |
| Exports | `exporter_test.dart`, `export_csv_test.dart`, `export_csv_support.dart`, `export_json_test.dart` | empty, one, many records; RFC 4180 round trip with an independent parser; commas, quotes, CR/LF/CRLF; Polish letters, emoji, combining marks; UTF-8 bytes (and the real `File.writeAsString`), no BOM; UTC `Z` instants, local day keys across DST; dot decimals whatever `Intl.defaultLocale`; no exponent, NaN or Infinity; negative zero; huge and tiny numbers; JSON validity and number types (int stays int, null stays null); settings block free of e-mail, tokens, ids, device and region; formula injection |
| Onboarding | `onboarding_persistence_test.dart` | Welcome asks nothing and calls nothing; Create account -> detection -> review -> permissions -> Get started sets `onboarded`; restart lands on the dashboard without a flash of another screen; interrupted setup resumes; signed out with the flag set still starts at Welcome; the detected values and a manual choice survive the restart; an explicit `LOCAL_ONLY_DEV` debug build (the harness's `apiConfigured: false`) skips the account but still remembers that setup is done |
| Auth form | `auth_form_state_test.dart` | see bug 8 |
| Account deletion and session restore | `delete_account_auth_cleanup_test.dart`, `secure_token_store_test.dart` | success empties the token store and signs out; the request carries a valid (refreshed if needed) token; failure keeps session and records; 401 refreshes once and retries once through the real repository; a restart cannot bring a deleted session back, even from a leftover copy; restore at launch refreshes instead of signing out on a 401 from `/me`, keeps the session offline; a damaged stored record never stops the app from starting |
| API errors | `api_error_handling_test.dart` | `ApiFailure.of` for every status and for HTML, empty, truncated, hostile and huge bodies; unknown error codes; `guarded` timeout; `ApiAuthRepository` and `AiService` mapping for every kind (including 20 s and 90 s timeouts in fake time); no server or database text in any exception or on the AI card, English and Polish |
| Localization | `l10n_parity_test.dart` | same keys, same ICU placeholders and plural/select shape (own parser), plural classes (Polish few/many), metadata only in `app_en.arb`, nothing empty or untranslated, ARB matches the generated class, privacy wording rules |
| Native configuration | `config/native_config_test.dart`, `config/plist.dart` | bugs 1 and 2; iPhone only (`TARGETED_DEVICE_FAMILY = 1` everywhere), portrait only, `UIBackgroundModes` = `fetch`, deployment target 15.0; no ATS exception and no local-network key in any tracked `Info.plist`, the debug-only injection is a build phase that exits before writing for Release; three privacy manifests well formed (no tracking, no advertising purposes, valid reason codes); Android: `allowBackup=false`, data-extraction rules exclude everything, `INTERNET`, cleartext off in main and on only in the debug manifest, portrait, signing material from outside the repository; no keystore, certificate, `key.properties` or `Local.xcconfig` in the tree, ignore rules in place |
| Theme | `theme_contrast_test.dart` | bug 6, plus filled and text buttons, body text, captions and error text on card and screen |
| Generated client | `generated_client_contract_test.dart`, `e2e/contract_e2e_test.dart` | every model round-trips (the new `AppConfigDto*`, `CloudData*`, `CloudExport*` included, with integral numbers), every enum, every route of `openapi.json` has a generated method, every schema a model, fixtures list exactly the schema's properties, client enum values equal the document's |

## Backend configuration and the release guard

What stops a build without a backend from becoming an app that skips the account (`docs/CONFIGURATION_MOBILE.md`, "Backend
mode and the release guard"). The Flutter build mode is fixed by the test runner (`flutter test` is always a debug run, with
assertions on and, unless `--dart-define` is passed, without defines), so the release and profile rules are tested through the pure functions
`validateBackendConfig(buildMode: ...)`, `effectiveEnvironment` and `effectiveBuildMode` and through the command-line tool
that wraps them; the compile-time half is tested through its constant constructor and, with real builds, by
`tool/check_release_guard.sh --builds` (not a unit test). The one link a plain test run cannot see, that real
`--dart-define`s reach `AppConfig.fromEnvironment`, is `define_wiring_test.dart`, which CI runs with defines. Fixture hosts
are made up (`api.sample-company.io`, `api.ci-guard.test`, `127.0.0.1:8080`), never an address of the product.

### New files (`apps/mobile/test/config`)

| File | Groups | What is pinned |
|---|---|---|
| `backend_config_test.dart` | the six cases of the specification (top level); profile builds follow the release rules; release builds; debug builds; a present but invalid address; an absent address; the `LOCAL_ONLY_DEV` spelling; `APP_ENV` decides which addresses are valid; `LOCAL_ONLY_DEV` is a development-environment mode; `effectiveBuildMode`; `effectiveEnvironment`; errors carry no value; the result object; `BuildMode.tryParse`; exhaustive cross-product | the verdict of `validateBackendConfig`: debug + API → online; debug + no API + `LOCAL_ONLY_DEV=true` → local-only; debug + no API + `false` → invalid; release + API → valid; release + no API → invalid; release + `LOCAL_ONLY_DEV=true` → invalid (with or without an address); profile follows release; debug + API + `true` is a contradiction; a malformed, placeholder, credential-carrying or (staging / production) `http` address is invalid in every mode and never degrades to local-only, also with the flag; whitespace and slashes around an address; the flag is exactly `true` / `false` (whitespace ignored, `TRUE`, `1`, `yes` are errors, fail closed); `LOCAL_ONLY_DEV=true` with `APP_ENV` staging or production is invalid even in debug, and valid with the default development environment. `effectiveBuildMode`: a binary that says debug but runs no assertions is validated as release (a spoofed profile / release AOT binary cannot be local-only), a real debug build stays debug, profile and release never become anything else. `effectiveEnvironment`: debug without `APP_ENV` (or whitespace only) is development, profile and release without it are production, an explicit value is honoured in every mode (a release build with an explicit `development` too), a typo is production, so a release build without `APP_ENV` refuses cleartext and `.invalid` hosts. No error repeats an address, a credential or a flag value; `errors` cannot be modified; the whole build mode x address x flag cross-product against one table, and local-only comes out only for debug + no address + `true` |
| `backend_config_cli_test.dart` | the six cases of the specification; the rest of the matrix; define precedence (files first, then `--dart-define`, last wins); `--dart-define-from-file`; a build that ships is checked as production; defines that override the build mode; usage errors exit with 64; no define value is ever printed | `runBackendConfigCheck` (what `tool/check_backend_config.dart` and the CI use): exit 0 / 1 / 64 and the `OK: ...` / `INVALID BUILD CONFIGURATION (...)` output; Flutter's precedence and its stringifying of JSON values (`true` → `true`); the example files behave as documented (`development` valid, the staging and production templates refused as placeholders in profile and release); release and profile without `APP_ENV` refuse `http` and placeholders, debug without it accepts `http`, an explicit `APP_ENV=development` is honoured in a release check; any define named `dart.vm.*` (`product`, `profile`, `true` or `false`, in debug, profile and release, also from a JSON file) is rejected with exit 1, and so is the spoofed "profile as debug" local-only build; an unusable file or argument is a usage error and never "no defines" or "valid"; an address, credential, flag value or file content is never printed |
| `backend_config_invariants_test.dart` | the source scanner; the rules hold for `lib/` (A1-F4); the rules can fail (`lib/` with one deliberate breakage each) | source-level guards so nobody quietly goes around the decision: the banner text is spelled out once, used only by the widget and the debug start-up log (A), built only in `lib/app.dart` behind `kBuildMode == BuildMode.debug` (B), `kBuildMode` is a constant; `main()` checks `config.isValid` and runs `ConfigErrorApp` before any storage work (C); `startDestination` is fed `isLocalOnlyDev` alone and takes a flag, not an address, `StartGate` never reads the address (D); no define is read outside `lib/config/` and `lib/api/`, `LOCAL_ONLY_DEV` is read in one file, the app's address is `AppConfig.api` and there is no second, unvalidated read of the address such as `ApiConfig.fromEnvironment` (that method no longer exists; the rule keeps it from coming back) (E); both guard codes exist, the guard is a `const`, fires with the right code for each mistake (any spelling but unset / `false` is refused in a profile or release build) and lets valid builds through (F). Every rule is also run over `lib/` with one deliberate breakage and must fail, so a guard that cannot fail is caught |
| `define_wiring_test.dart` | `API_BASE_URL` reaches `AppConfig.fromEnvironment`; `LOCAL_ONLY_DEV=true` reaches it (debug build) | the one link no other test can see: the REAL compile-time defines arrive in `AppConfig.fromEnvironment` (an address makes an online build, the flag in a debug build makes local-only). A plain `flutter test` has no defines, so each of the two tests skips itself there and names the command that runs it; CI runs the file twice, with `--dart-define=API_BASE_URL=...` and with `--dart-define=LOCAL_ONLY_DEV=true` (job `mobile-config-guard`, `docs/CI.md`) |
| `define_source_guards_test.dart` | G1-G5 | text-level guards for links a debug-only test run cannot reach: G1 `AppConfig.fromEnvironment` reads `APP_ENV`, `API_BASE_URL`, `LOCAL_ONLY_DEV` and `PRIVACY_POLICY_URL` into the right arguments; G2 it validates for the effective build mode (`effectiveBuildMode(compiled: kBuildMode, assertsEnabled: _assertsEnabled())`), not for a default, so a spoofed AOT binary is not taken for a debug build; G3 the developer hints of the error screen sit behind `kBuildMode == BuildMode.debug`; G4 `main()` logs the start-up configuration before the validity guard; G5 `tool/check_backend_config.dart` turns the checker's verdict into the exit code |
| `app_config_provider_default_test.dart` | `appConfigProvider` (not overridden) is the `AppConfig` `main()` validated | `main()` validates `AppConfig.fromEnvironment` and starts the app without overriding `appConfigProvider`; every other test overrides the provider, so this one pins that its default is that same object (`identical`), i.e. that `StartGate` and the banner use the configuration `main()` checked |
| `main_guard_test.dart` | the real `main()` of an invalid build | runs the real `main()` (a plain `flutter test` is a debug build without defines, hence invalid): the app ends in `ConfigErrorScreen`, `WattByteApp` and `StartGate` are never built, and a recorder on the `shared_preferences` platform channel sees no call (storage is not touched before the guard) |
| `config_error_app_test.dart` | one test per invalid configuration (nine); semantics; the debug hints; layout | what `main()` runs for an invalid build (`ConfigErrorApp`, mounted without a `ProviderScope`): the title and one bullet per error, no Welcome / setup / dashboard / sign-in form / button into the app, no banner, no address or credential text, the two development hints present in a debug run (they are plain text to copy, not buttons); the title is a header and the errors are in the semantics tree; every device size, text scale and brightness lays out |
| `local_only_ui_test.dart` | explicit `LOCAL_ONLY_DEV` mode; normal builds never show it; the banner does not break the layout; fail closed | through the real `WattByteApp`: in the explicit mode the setup opens without Welcome, the strip `LOCAL ONLY DEVELOPMENT MODE` is shown exactly once on both platforms, stays on a pushed screen, and does not break the layout (sizes, light / dark, text scale, Polish); in a normal build (API configured, signed in or out, any setup flag) there is no banner and the account comes first, checked anywhere in the widget tree, painted or not (`skipOffstage: false`); each of twelve invalid configurations, with and without the setup flag, mounted anyway, still asks for an account |
| `start_destination_test.dart` | without `LOCAL_ONLY_DEV` the account is always required; with it the account is skipped | `startDestination(localOnlyDev:, auth:, settings:)`: no auth state but a confirmed session reaches setup or dashboard without the flag; while the session is restored the splash shows; signed out, a failed sign-in and an error while restoring (an `AsyncError` without a value, which `AsyncValue.value` would rethrow) go to Welcome, and the rule does not throw; signed in goes to setup until finished, then the dashboard; with the flag the destination is setup or dashboard, never welcome or splash; the flag is the only input that changes the account requirement |

### Changed files

| File | Change |
|---|---|
| `app_config_test.dart` | no defines is an **invalid** build (`API_BASE_URL is required`), `LOCAL_ONLY_DEV=true` in debug is valid local-only without problems; new group "AppConfig backend rules" (valid online in every build mode, forbidden cases never local-only, a bad address never degrades, `LOCAL_ONLY_DEV` needs the development environment, `diagnostics` name the build mode and the backend verdict; a release build with `LOCAL_ONLY_DEV=true` and no `APP_ENV` reports both reasons, "only in debug builds" and "only in the development environment", because it is validated as production); `config/*.example.json` now includes `local-only-dev` (only that file carries `LOCAL_ONLY_DEV`, valid in debug, invalid in profile and release) and checks that every example works as documented; the "run was started with defines" switch also looks at `LOCAL_ONLY_DEV` |
| `setup_flow_test.dart`, `delete_account_auth_cleanup_test.dart`, `settings_persistence_restart_test.dart` | `startDestination(apiConfigured: ...)` is now `startDestination(localOnlyDev: ...)`; the behaviour asserted is unchanged |
| `support/app_harness.dart` | overrides `appConfigProvider` with `AppConfig.fromDefines(buildMode: debug, ...)`: `apiConfigured: true` is a normal online build, `apiConfigured: false` is the **explicit `LOCAL_ONLY_DEV` mode** (so `onboarding_persistence_test.dart`, which uses it, now tests that mode); new `appConfig:` parameter for any other configuration |

Not covered by a unit test: the compile-time failure of a real release build (`[WB-CONFIG-001]`, `[WB-CONFIG-002]`) and the
absence of the banner text from a real release binary, which need Gradle: they are `tool/check_release_guard.sh --builds`
(three real release builds: two refused, one positive control that is inspected), run by the `android` job (`docs/CI.md`,
CONFIGURED, NOT REMOTELY VERIFIED). Also not covered: a `dart.vm.*` override given through `--extra-front-end-options` (the
command-line check sees defines only; the start-up check catches the effect through `effectiveBuildMode`, which is unit-tested
as a function, not on a real spoofed binary). The banner on a device and the error screen on a device are rows Y6 and Y7 of
`docs/DEVICE_TEST_PLAN.md` (NOT VERIFIED).

### Verification (2026-10-14)

The verification of this change covers the `test/config` files above and `test/app_config_test.dart`;
`dart run tool/check_backend_config.dart` over the combinations of the matrix; `tool/check_release_guard.sh` with and without
`--builds`; `flutter test test/config/define_wiring_test.dart` with each of the two defines; format, analyze, the whole suite
and the debug builds. The results:

| Check (2026-10-14, `apps/mobile`) | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed .` | 243 files, 0 changed, exit 0 |
| `flutter analyze` | No issues found |
| `flutter test --no-pub` (the whole suite, e2e tests skip themselves without `WATTBYTE_E2E_API_URL`) | 1974 passed, 38 skipped, 0 failed |
| `flutter test test/config/define_wiring_test.dart --dart-define=API_BASE_URL=...`, then `--dart-define=LOCAL_ONLY_DEV=true` | each run: its test passes, the other skips |
| `bash tool/check_release_guard.sh` | 26 configuration checks behaved as expected (18 rejected, 8 accepted) |
| `bash tool/check_release_guard.sh --builds` (local, warm Gradle caches) | build 1 refused with `[WB-CONFIG-001]`, build 2 refused with `[WB-CONFIG-002]`, build 3 (valid made-up address) built, `libapp.so`: 0 hits for the banner text, 1 hit for the control string; whole script 44 s. A first run found the banner text in the binary (1 hit); the text became the constant `kDebugMode ? '...' : ''` and the rerun found 0 |
| `flutter build ios --simulator --debug`, `flutter build apk --debug` (no defines) | both built |
| `flutter build ios --release --no-codesign` without `API_BASE_URL` | exit 1; with `-v` the output contains `[WB-CONFIG-001]`, without `-v` Flutter prints a "Development Team" hint instead |
| `flutter build ios --release --no-codesign --dart-define=API_BASE_URL=...` (made-up address) | built; `App.framework/App`: 0 hits for the banner text, 1 hit for the control string |
| iOS simulator, debug app made with `--dart-define=LOCAL_ONLY_DEV=true` / with no define | red strip `LOCAL ONLY DEVELOPMENT MODE` above the dashboard / the "Invalid build configuration" screen |
| `node scripts/secret-scan.mjs` | 0 findings |

Not run: the backend suites (`pnpm lint`, `typecheck`, `test`, `build`), because no shared contract, API or generated client changed;
a physical device; Android release runs of the full app; the GitHub Actions workflows themselves.

## Battery capacity: design versus estimated full charge

Added 2026-10-14. The bug this guards: Android's `BATTERY_PROPERTY_CHARGE_COUNTER` (the charge stored in the battery *now*)
was stored as if it were the nominal capacity of the phone: a reading at 95 % or more replaced even the catalog's published
figure, and a partial reading became the capacity of a model no catalog knew, both stored, shown and uploaded as "the battery
capacity". The model is now two facts (`docs/BATTERY_CAPACITY.md`): the **design capacity** of the model
(sources `manufacturerSpecification`, `localDeviceDatabase`, `backendDeviceDatabase`, `manual`, `unknown`) and an **estimated
full-charge capacity** of this battery (confidence `low`, `medium`, `high`). Every test below is TESTED against fakes, a
simulated charge counter and a synthetic legacy database; none of it is DEVICE VERIFIED (`docs/DEVICE_TEST_PLAN.md`, section
12). The groups are the `group(...)` names in the files.

### App (`apps/mobile/test`)

| File | Groups | What is pinned |
|---|---|---|
| `battery_capacity_test.dart` | enums; estimate from the charge counter; invalid readings never produce an estimate; Wh from the energy counter; DesignCapacity normalisation; DesignCapacity.resolve priority; prefer(); meta table round trip; estimated battery health; Android charge counter != design capacity | the pure domain: the design source enum has no measurement member; `charge / (level / 100)` at 100, 95, 94, 75, 74, 50, 40 and 39 % with the confidence of each; null, zero, negative, NaN, infinite and implausible counters (mAh reported as µAh, an absurdly large one) give no estimate and never throw; Wh only from a valid energy counter (0 to 200 Wh, 2.5 to 5 V); an unusable mAh makes the design capacity `unknown`; local beats backend beats manual; a 45 % reading never overwrites a 100 % one from last week, 30 days is the cut; the meta layout round-trips and the older one still reads; health is `design 4000`, `estimate 3600` = 90 %, none for low confidence, unknown design, ratio outside 0.30 to 1.20 |
| `battery_capacity_regression_test.dart` | Android charge counter != design capacity; where a design capacity comes from; readings that must never become any capacity; the energy calculation; iOS has no charge counter; persistence and installs from before the split; through the real app (setup screen, Settings, device registration) | the regression itself: at every battery level and for every kind of reading the counter never reaches the design capacity, the settings or the registration; catalog, backend and manual sources, manual survives automatic detection and an unknown detection never downgrades a known capacity; the calculator uses the design capacity and falls back to the estimate only when none is known; iOS never has an estimate; old preferences and old meta rows after the upgrade; setup screen, Settings rows (`~X mAh`, confidence, "Battery capacity unavailable"), the registration body and the stored server row end to end, "Detect again" on an unlisted model leaves the design capacity unknown |
| `device_specification_regression_test.dart` | Android charge counter != design capacity (one group per device and reading) | a table of devices and counter readings: whatever the counter says, `detect()` returns the catalog's design capacity or `unknown` |
| `device_specification_test.dart` | local catalog; detect() reads no charge counter; backend database; the cached backend specification (readCache); a broken catalog asset; DeviceSpecification JSON | resolution order and offline cache; the backend answer is always labelled `backendDeviceDatabase`, a cached entry is relabelled whatever it claims and a legacy entry of another source is ignored; unknown model stays unknown on Android and iOS; a damaged catalog or cache is never fatal; the JSON round-trips and never invents a capacity |
| `full_charge_capacity_collector_test.dart` | what a single reading becomes; unsupported, zero, negative and implausible counters; the collector keeps the best estimate it has seen; Wh comes from a valid energy counter only; installs from before the split (the older meta layout); platforms and housekeeping | the collector against an in-memory SQLite (`sqflite_common_ffi`) and a fake system: stored keys, best-reading rule and the 30-day cut, Wh handling, old `meta` rows, iOS stores nothing, "Reset statistics" wipes the estimate, only the four estimate keys are written |
| `setup_flow_test.dart` | AutoSetup.apply; design capacity in the automatic setup; SetupController.run registers the model and the estimate separately; legacy preferences migration | an unknown model never gets a typical value; manual is sticky; the registration carries the design capacity the app keeps and the estimate as separate groups; a failing registration or estimate hook is not a failed setup |
| `settings_store_test.dart`, `settings_persistence_test.dart`, `settings_persistence_restart_test.dart` | the design capacity keys; legacy capacity keys (before design / estimated full-charge); design capacity: the three fields stay one coherent group | `wb.designCapacity*` keys written and the old ones removed; the old sources converted (`system` and `estimated` become unknown with no number, catalog sources renamed, a typed number becomes `manual`), converting twice is converting once, the new keys win over leftovers; `sanitized()` keeps source and numbers coherent |
| `sync_service_test.dart`, `sync_providers_test.dart` | registerDevice: design capacity and estimated full charge; battery capacity on the registration path (real providers) | the request body per source; no estimate sends four `null` fields (never `unknown`); a model in no catalog registers `unknown` with no numbers next to a real estimate; the settings never learn a capacity from the counter |
| `export_json_test.dart` | two capacities, never one: design versus estimate basis | `designCapacityMah` / `designCapacitySource` versus `estimateCapacityMah` / `estimateCapacityBasis`; the old key is gone; NaN, Infinity and negative capacities are `null` |
| `energy_validation_test.dart` | which capacity the calculator is built on | design wins over the estimate (a manual one too); the estimate stands in only when no design capacity is known; neither means no `% -> mAh` estimate |
| `generated_client_contract_test.dart` | battery capacity: design capacity versus estimated full charge | the generated request, device and catalog models have the new names; a `DeviceDto` carries all seven battery keys (`null` when empty); client enums equal the document's; request ranges 0.1 to 30 000 mAh and 0.001 to 200 Wh |
| `accessibility/full_charge_estimate_a11y_test.dart` (and the capacity cases of `accessibility/setup_a11y_test.dart`) | Settings fits every phone, scale, theme and language; wide layouts; no estimate means no row; the tilde is shown but not read; Polish; every confidence is spoken in words; an unknown design capacity next to an estimate; text contrast | the "Estimated full charge capacity" row and the design capacity row stay separate, labelled and readable; an unlisted Android model still reads "Battery capacity unavailable" on the review screen |
| `resolve_missing_design_capacity_test.dart` | an install with no design capacity although its model is in a database (an upgrade dropped the old measured `system` / `estimated` capacity, or an offline first setup) | the gap is filled once at launch from the bundled catalog or the backend catalog and registered as the design group beside the estimate; a manual or known capacity is never replaced; a model no database knows, an unreachable backend and an unfinished setup change nothing and register nothing; the charge-counter reading never becomes the design capacity |
| `battery_capacity_wording_test.dart` | the literal English and Polish wording of the estimate row, the unavailable text and every design-source label | the estimate is always called an estimate and never named like the nominal capacity; each of the five design sources has its own label (only `manual` says "Chosen manually"); the unavailable text does not promise a number the system could give |
| `e2e/api_e2e_test.dart` | (needs a running API; skips itself otherwise) | the registration through the generated client and PostgreSQL: design capacity stored with its source, no estimate when none was sent |

### API and catalog (`apps/api/tests`, `packages/device-specs/tests`)

| File | Groups | What is pinned |
|---|---|---|
| `battery-capacity.test.ts` | validateBatteryCapacityGroups; GET /devices/specifications/:identifier serves design capacity; OpenAPI document of the device battery fields; and the shared suite on the in-memory repositories | every cross-field rule is a 400 `validation` naming the rule and the two groups are judged independently; the catalog endpoint answers `designCapacityMah` / `designCapacityWh` for every entry and 404 for an unknown model; the OpenAPI document has the new fields and enums and none of the old names |
| `battery-capacity-suite.ts` (run by `battery-capacity.test.ts` on memory and by `db/battery-capacity.integration.test.ts` on PostgreSQL) | each group is stored atomically; repository contract | a registration with both groups reads back from `POST`, `GET /devices` and the account export; an estimate alone never produces a design capacity; a design capacity without a source, `unknown` with numbers, a source without mAh, Wh without mAh, a confidence or a measured source without an estimate are 400 and store nothing; a group replaces as a whole, `unknown` clears only its own group, a null source or all-null body changes nothing; one installation never changes another's state |
| `db/battery-capacity-semantics.integration.test.ts` | catalog and manual sources stay design capacity; a system measurement is NEVER a design capacity; the old columns and constraints are gone, the new ones named; the CHECK constraints keep every group coherent | migration 0006 on a synthetic legacy database with a row of every old source and the awkward combinations, next to a fresh install: row count kept, every row mapped as in `docs/BATTERY_CAPACITY.md`, no measurement left in a design column, the same final table on upgrade and fresh install, applied once |
| `setup.test.ts`, `cloud-contract.test.ts`, `contract-nulls.test.ts` (and the shared cloud suite) | device-bound battery capacity; OpenAPI export; a populated battery group is a unit | the registration, the export document and the explicit-`null` behaviour of generated clients use the new fields |
| `packages/device-specs/tests/lookup.test.ts` | catalog lookups | every entry has a plausible design capacity and a matcher; the catalog is design capacity only, with no pre-split key names; unknown, empty and absurd identifiers answer `null`, never a typical value |

### Verification (2026-10-14)

Re-run by the documentation pass, on this tree, Flutter 3.41.6, Node 26 / pnpm 11.9, PostgreSQL 16 in Docker on its own throw-away
database (dropped afterwards):

| Command | Result |
|---|---|
| `flutter test` on `battery_capacity_test`, `battery_capacity_regression_test`, `device_specification_test`, `device_specification_regression_test`, `full_charge_capacity_collector_test`, `setup_flow_test`, `settings_store_test`, `settings_persistence_test`, `settings_persistence_restart_test`, `export_json_test`, `exporter_test`, `sync_service_test`, `energy_validation_test` | 530 passed, 0 failed |
| `vitest run` in `apps/api` on `battery-capacity.test.ts`, `setup.test.ts`, `contract-nulls.test.ts`, `cloud-contract.test.ts`, without a database | 66 passed, 9 skipped (the PostgreSQL variants) |
| `vitest run` on `tests/db/battery-capacity-semantics.integration.test.ts` and `tests/db/battery-capacity.integration.test.ts` against PostgreSQL 16 | 41 passed |
| `pnpm --filter @wattbyte/device-specs test` | 6 passed |

Not run by that pass and not claimed here: the accessibility suite (six of its tests depend on the time of day for a reason that
has nothing to do with this change), `sync_providers_test`, `generated_client_contract_test`, the end-to-end suites, any build,
the iOS Simulator, an Android emulator or a device.

## Setting sources: where a value came from

Added 2026-10-14. The bug this guards: a value fetched from the user's account on a second device was stored as `manual`,
so it counted as a conscious local choice, could not follow a later change made on the first device, and the account-bound
preferences were one set per install, so a second user of a phone inherited the first one's manual currency and tariff
(`docs/SETTING_SOURCES.md`). TESTED against fakes, two phones with their own storage and a fake account server that follows
the rules of the real API, and against a running API on PostgreSQL; the iOS Simulator run is in the document.

| File | Groups | What is pinned |
|---|---|---|
| `apps/mobile/test/setting_source_test.dart` | the model; the priorities (`mergeAccountSettings`); `AutoSetup.apply`: the four priorities; two phones, one account; account switching on one phone; legacy preferences (the old onboarding); the preferences of an account are stored under a one-way key | four sources, only a choice of the user is conscious; an account value is `accountSynced` with the account's origin as `originalSource` (never `manual`), whatever that origin; an own unacknowledged choice beats the account, an acknowledged one gives way to a newer account value, a phone that wrote a value does not relabel it when reading it back; a fresh account decides nothing about the price; a manual tariff arrives as a manual tariff, an automatic mode stays automatic with the old tariff only kept, `withAutoPrice` changes no source; an unreachable account changes nothing, sources included; only own decisions are uploaded and the rest of the account is echoed (a stale phone never undoes a newer change); device-bound values never travel in the account settings; offline then online; a manual currency survives a restart; a second install of the account; an older client's account (origin unknown); A -> logout -> B: nothing of A (manual currency, manual tariff, `accountSynced`, `onboarded`) reaches B, A comes back to its own, deletion erases; the start gate waits for the account's own settings; the old onboarding's answers are `migratedManual`, go up as such and reach the other phone with that original, and never reach a second account |
| `apps/mobile/test/e2e/setting_source_e2e_test.dart` | (needs a running API; skips itself otherwise) | the same scenarios through real login, the generated client, the API and PostgreSQL, with two or three phones |
| `apps/mobile/test/settings_persistence_test.dart` | every Settings field; legacy preferences | the six new fields round-trip; a stored currency alone is `migratedManual`, a stored price alone a `migratedManual` manual tariff, nothing is invented for a fresh install |
| `apps/mobile/test/setup_flow_test.dart` | AutoSetup.apply; legacy preferences migration | account values rank above detection and are `accountSynced` / original; the old onboarding's values are `migratedManual` |
| `apps/mobile/test/accessibility/settings_a11y_test.dart` | Settings say why a value is set | "Synced from your account", "… · Chosen manually", "Custom price · Synced from your account", the Polish label, no enum name on screen |
| `apps/mobile/test/generated_client_contract_test.dart` | request, response and enum tables | the three new fields and their nine enums |
| `apps/api/tests/setting-source-suite.ts` (run by `setting-source.test.ts` on memory and by `db/setting-source.integration.test.ts` on PostgreSQL) | setting sources on /me/settings | detected / manual / migratedManual are stored and read back; `accountSynced` and anything else is a 400; a body without origins still works and leaves them unknown; an origin never carried over to a different value; null origins are "not given"; a cleared value has no origin; origins are per account; the export carries them |
| `apps/api/tests/db/setting-source.integration.test.ts` | migration 0007 | applied to a legacy database (existing settings keep their values and get `NULL` origins) and to an empty one; the columns are nullable and the database refuses `accountSynced` |

Changed on purpose: `apps/mobile/test/support/app_harness.dart` (`HarnessAuthRepository.me()` answers with the user a session
was issued to, as the real API does: one account keeps one id), and the tests that sign a second account in on one phone
(`sync_providers_test.dart`, `e2e/account_switch_e2e_test.dart`, `timers_shell_test.dart`) now give that account the settings a finished
setup would have (the preferences are per account), because an account without a currency uploads nothing.

## Export format decisions

Written on `Exporter` and pinned by the tests; the CSV and JSON files are produced by pure functions and written by
`File.writeAsString`.

* **Encoding: UTF-8 without a byte-order mark.** Every field the exporter writes today is ASCII (numbers, ISO dates,
  `true`/`false`, a currency code), so a BOM would only put an invisible character in front of the first header for
  tools that do not strip it. If free text is ever exported, revisit: Excel needs the BOM for non-ASCII UTF-8.
* **Line endings:** `\n`. A cell with a CR or LF is quoted, so a newline inside a value cannot split a row.
* **Numbers:** dot decimal separator whatever the device locale; CSV fixed decimals (mAh 0, Wh 2, kWh 5, cost 4); JSON the
  shortest round-trip form, which Dart prints without exponent between 1e-6 and 1e21 (outside that range the exponent
  form is valid JSON). Negative zero is written as zero.
* **NaN and infinity:** empty CSV cell, JSON `null`. (`jsonEncode` throws on them, so before this change one such value
  made the whole JSON export fail.) The real `EnergyCalc` rejects them earlier; this is the exporter's own guard.
* **Unknown is not zero:** a design battery capacity or price of 0 means "unknown" in `Settings`. The JSON settings carry
  `null` for them, and a session with neither a measurement nor a capacity to estimate from has empty energy cells
  (`null` in JSON), and no cost without a price.
* **Time:** instants are UTC ISO-8601 with `Z`; days are the local `yyyy-MM-dd` key shown in the app.
* **Text and CSV injection:** the only free-form text is the currency code. A text cell is quoted when it holds a comma,
  quote, CR or LF, and gets a leading `'` when it starts with `=`, `+`, `-`, `@`, a tab or a CR. Everything else is a
  number, a date or `true`/`false` generated by the exporter (asserted for 200 sessions and 50 days), so none can start
  with those characters except as a sign.
* **Settings in the JSON:** `currency`, `pricePerKwh`, `chargingEfficiency`, `designCapacityMah`, `designCapacitySource`,
  `estimateCapacityMah`, `estimateCapacityBasis`, `nominalVoltage`. The capacity is two facts, never one: `designCapacityMah`
  and `designCapacitySource` are the nominal capacity of the phone model (`null` / `"unknown"` when no database or user value
  exists); `estimateCapacityMah` is the capacity the `% -> mAh` energy estimate used and `estimateCapacityBasis` says which it
  was: `"design"` when a design capacity is known (it always wins), `"estimatedFullCharge"` when only an estimate of this
  battery was available (not the nominal capacity), `null` when neither. The previous single capacity key is gone from the
  export. No e-mail, token, id, device model, region or sync state.

## Bugs found by writing these tests

Fixed here (files this suite owns):

1. `lib/export/exporter.dart`: NaN / infinity made `Exporter.json` throw (CSV would have printed `NaN`); a negative zero
   or a tiny negative number printed as `-0.00`; the currency cell was not quoted or neutralised (a comma or newline
   broke the file, a leading `=` was a formula); an unknown capacity or price was exported as a plain `0`.
2. `lib/features/auth/data/secure_token_store.dart`: `read()` threw on an unreadable stored expiry or an unknown plan
   name, which leaves the auth controller in error and the start gate on the splash screen for good; it now treats an
   unreadable expiry as expired (the refresh token recovers the session), an unknown plan as free (the server decides),
   an empty token as no session, and returns `null` instead of `""` for "no display name".

Not fixed here (files owned elsewhere): the tests are written and skipped, see "Blocked tests" and "Open issues" below.

## Blocked tests (written, skipped on purpose)

A skipped test names its reason in the output. Remove the `skip:` (and the constant that feeds it) when the change below
is made; the test then runs unchanged. All five run in `flutter test` as "skipped".

| Test | File | Why it fails today | Exact change wanted |
|---|---|---|---|
| a preference of the wrong type does not stop the app from starting | `settings_persistence_test.dart` (`wrongTypesNotHandled`) | `SettingsStore.load()` reads with `getDouble`/`getBool`/`getInt`/`getString`, which throw `TypeError` when the stored value has another type (`wb.pricePerKwh` = `"abc"` or `5`, `wb.onboarded` = `"yes"`): the app cannot start | `lib/settings/settings.dart`: read every key through a guard, `T? _get<T>(T? Function(String) read, String key) { try { return read(key); } on TypeError catch (e, st) { reportError(e, st, 'settings $key'); return null; } }`, and use `_get(_p.getDouble, _price)` etc. in `load()` |
| a corrupt stored automatic price never becomes the effective price | `settings_persistence_test.dart` (`autoPriceNotSanitised`) | `sanitized()` validates the effective price but not `autoPrice.pricePerKwh`; "Use automatic price" then copies NaN / a negative number into `pricePerKwh` and `energyCalc()` throws | `lib/settings/settings.dart`: drop an `autoPrice` whose price is not finite or outside `0..maxPricePerKwh` in `sanitized()` (or in `_effectiveAutoPrice`) |
| OutlinedButton: outline >= 3:1 on every surface (light and dark: two tests) | `theme_contrast_test.dart` (`outlineBelowThreeToOne`) | `outlinedButtonTheme` draws the outline in `onSurface` at 35 %: 2.23-2.27:1 in light, 2.8-3.0:1 in dark, over the card, the screen and the five accent washes | `lib/ui/theme.dart`: `side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.5))`; computed over the card, the screen and the five accent washes: 3.45-3.55:1 in light, 4.1-5.0:1 in dark |
| after a failed deletion the app still treats the user as signed in | `delete_account_auth_cleanup_test.dart` (`_failedDeleteSignsOut`) | `AuthController.deleteAccount` sets `state = AsyncData(AuthFailure(...))` when the server cannot be reached; the start gate routes every state that is not `SignedIn` to Welcome and the Account screen shows its signed-out form, so a dropped connection throws the user out of the app (the stored session is kept, so a restart restores it) and the message `deleteAccountFailed` is never seen | `lib/features/auth/presentation/auth_controller.dart`: on `AuthException` in `deleteAccount()` just `return false` (keep `SignedIn`); the Account screen already shows `deleteAccountFailed` from the return value |

## Open issues (not blocked tests)

* **Two strings overclaim about uploads** (`l10n_parity_test.dart`, `knownOverclaims`; strings are in the ARB files, which
  this suite does not own):
  * `usageAccessBody` says WattByte "never uploads" the totals it reads (PL: "nigdzie ich nie wysyła"); cloud sync uploads
    exactly these totals (mobile and Wi-Fi bytes per day) when it is on. Wanted: EN "Android shares data totals only with
    apps you allow under Usage access. WattByte reads totals on this device; they leave it only as daily totals if you
    turn on cloud sync." PL "Android udostępnia sumy transferu tylko aplikacjom z uprawnieniem „Dostęp do danych o użyciu”.
    WattByte odczytuje sumy na tym urządzeniu; opuszczają je wyłącznie jako dzienne sumy, jeśli włączysz synchronizację."
  * `authWhyAccount` says "Only daily totals can ever be uploaded" (PL: "Wysyłane mogą być wyłącznie dzienne sumy"). The
    account also stores country, currency and price settings and the device's model code and battery capacity
    (`docs/AUTO_SETUP.md`, the privacy manifest), and AI insights send this month's totals. Wanted: say what cloud sync
    uploads, not what can ever leave the phone, e.g. EN "Your account comes first: after that WattByte sets everything up
    for you. Cloud sync uploads daily totals only, and only if you turn it on."
  * `dataCollectionBody` ("Nothing is uploaded unless you turn on cloud sync") passes the rule because it is about the
    usage and battery statistics the switch reads; account settings and the device registration do go to the server
    without the sync switch. Consider "Usage and battery statistics stay on this device unless you turn on cloud sync."
* `docs/privacy.md` is behind the implementation: it says the settings values and the device model are never uploaded;
  `docs/AUTO_SETUP.md` and `ios/Runner/PrivacyInfo.xcprivacy` say the account stores country, currency, price mode and
  manual price, and the device registration carries model code, the design capacity and (Android) the estimated
  full-charge capacity with their sources. (With the battery capacity split `docs/privacy.md` got a row for the capacity
  data; the model-code and price statements are still behind.)
* `app_pl.arb` still holds four identical copies of template metadata (`@syncCounts`, `@syncLast`, `@syncDone`,
  `@aiRemaining`). Harmless; the test lists them (`plMetadataCopies`) and requires them to equal the template's. Delete
  them and the list.
* `SecureTokenStore.write` writes seven keys one after another: another isolate can read a mixed record in between.
  `SessionManager` already re-reads and adopts a newer stored session, so this is a smell, not a failure; one JSON key
  would make it atomic but needs a migration of existing installs.

## Test infrastructure notes

* `rootBundle` caches the future of every asset for the whole process. A future created in one test's fake-async zone
  cannot be awaited from the next test's zone, so the second test in a file that runs the device detection (it loads
  `assets/device_specs/devices.json`) hangs for ever. `onboarding_persistence_test.dart`, `widgets_regression_test.dart`
  and the AI-card group of `api_error_handling_test.dart` call `setUp(rootBundle.clear)`. `AppHarness.create` is the
  place to do it once (it is in `test/support`, not owned here). Real file I/O also does not advance with `pump`: the
  onboarding test waits with `tester.runAsync` between pumps.
* `ApiFactory` now wraps the client in `RetryAfterClient`; retry and back-off are tested by the sync agent
  (`retry_policy_test.dart`), not here.
* The theme test does not import the app (`wb_widgets.dart` pulls in all of it) so another team's half-finished edit
  cannot hide a contrast regression; `widgets_regression_test.dart` checks that `accentWash` still starts from the colour
  the theme test assumes.

## End to end

`test/e2e/contract_e2e_test.dart` calls register, login, refresh, account, settings, devices, usage, AI, **config** and the
**cloud-data routes through the generated classes** (`ConfigApi`, `AccountApi`; no `invokeAPI`): the typed export document,
its headers, the CSV variant (the plain response of `apiV1MeExportGetWithHttpInfo`), the 400 for an unknown format, the 401
without a token, delete cloud data (counts, idempotence, device and settings kept, sync resumes, `?devices=true`), and the
old tokens after deleting the account.

```
createdb wb_regress        # your own database, e.g. docker exec -i docker-postgres-1 psql -U wattbyte -d wattbyte -c 'CREATE DATABASE wb_regress'
cd apps/api && DATABASE_URL=postgres://wattbyte:wattbyte@localhost:55432/wb_regress npx pnpm migrate
DATABASE_URL=... NODE_ENV=development APP_ENV=development AI_MOCK=1 AI_FREE_DAILY_LIMIT=4 \
  AUTH_RATE_LIMIT_PER_MIN=1000 RATE_LIMIT_PER_MIN=10000 AI_RATE_LIMIT_PER_MIN=1000 PORT=18260 HOST=127.0.0.1 \
  NODE_ENV=development JWT_SECRET=<40 random characters> node --conditions=development --import tsx src/main.ts
WATTBYTE_E2E_API_URL=http://127.0.0.1:18260 flutter test test/e2e/contract_e2e_test.dart
```

`GET /me/export` is limited to 6 requests per minute per IP (`CLOUD_EXPORT_RATE_LIMIT_PER_MIN`) and one run makes 5: wait a
minute before running it again against the same server. The suite makes no call to the public internet (the Eurostat
price is in `api_e2e_test.dart`, which is not this suite's).

## Verification

All in `apps/mobile`, 2026-10-13, Flutter 3.41.6; what was really run and what came out.

| Command | Result |
|---|---|
| `dart format --set-exit-if-changed` on `lib/export`, `lib/features/auth/{data,domain}` and every file listed above | no changes needed |
| `dart analyze` on the same paths | no issues |
| `flutter test` on the 16 files this suite owns (`exporter`, `export_csv`, `export_json`, `settings_persistence`, `settings_persistence_restart`, `onboarding_persistence`, `auth_form_state`, `delete_account_auth_cleanup`, `api_error_handling`, `l10n_parity`, `widgets_regression`, `config/native_config`, `theme_contrast`, `generated_client_contract`, `secure_token_store`, `e2e/contract_e2e`) | 447 passed, 22 skipped, 0 failed: the 5 blocked tests above and the 17 end-to-end tests (no API address given in that run) |
| `WATTBYTE_E2E_API_URL=http://127.0.0.1:18260 flutter test test/e2e/contract_e2e_test.dart` against the API of this workspace (`AI_MOCK=1`, `AI_FREE_DAILY_LIMIT=4`) on its own PostgreSQL 16 database (migrations 0001-0004, dropped afterwards) | 17 of 17 passed, twice (INTEGRATION VERIFIED for the contract between the generated client, the API and PostgreSQL, on a development build) |
| mutation check of the export tests: five faults put into `exporter.dart` one at a time (currency not escaped, negative zero kept, unknown shown as zero, NaN not guarded, no formula hygiene) | every fault failed at least one test; the file was restored (checked with `diff`) |
| the blocked tests with their `skip:` removed (in a throw-away copy) | `wrong types`, `corrupt autoPrice` and `failed deletion keeps SignedIn` fail with the messages quoted above; the outline test fails with the ratios listed |
| `flutter test` (the whole suite, once, with the other agents' work in progress at that moment, before the token-store fix) | 1253 passed, 31 skipped, exit 0 |

Not run: any `flutter build`, the iOS Simulator, an Android build or emulator, a device.
