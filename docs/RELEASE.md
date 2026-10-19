# Release preparation

How to get WattByte from this repository to a device, TestFlight and the stores, what is already prepared, and what cannot be
done (or verified) without an Apple Developer account and a Google Play key. The automated route is the manual
`release.yml` workflow (`docs/CI.md`, "Release workflow"); this page is the human checklist behind it.

Statuses: IMPLEMENTED, TESTED, BUILD VERIFIED, NOT VERIFIED, BLOCKED (see `docs/FIX_REPORT.md`). Everything that needs an
Apple Developer Program membership, App Store Connect, a Play Console account or a release key is **BLOCKED** in this
environment and says so. Nothing below was executed against Apple's or Google's services.

## Identifiers and versions

| Item | Value |
|---|---|
| iOS bundle ids | `pl.wattbyte.app`, widget `pl.wattbyte.app.WattByteWidget` |
| App Group | `group.pl.wattbyte.app` (both ids) |
| Background task id | `pl.wattbyte.refresh` (Info.plist, Dart, `AppDelegate`; not registered anywhere) |
| Android application id | `pl.wattbyte.app` |
| Version | `pubspec.yaml` `version: 1.0.0+1` -> `CFBundleShortVersionString` / `versionName` 1.0.0, `CFBundleVersion` / `versionCode` 1. Override per build with `--build-name` / `--build-number`; both stores need a build number that only ever increases |
| Server address | compiled in: `--dart-define-from-file=config/production.json` (copy `config/production.example.json`, real `https://` hosts; the app refuses http and `.invalid` placeholders in production). A profile or release build is **invalid without `API_BASE_URL`**: the Dart compile fails with `[WB-CONFIG-001]`; with `LOCAL_ONLY_DEV` set to anything but `false` it fails with `[WB-CONFIG-002]` (`[WB-CONFIG-001]` when the address is missing as well; local-only is a debug-only development mode and can never be released). A configuration that compiles but is unusable (an `http` or placeholder address for production) stops at start-up on the "Invalid build configuration" screen instead of running. Without `APP_ENV` a profile or release build is validated as **production** (https only, no `.invalid` host), the app and the check alike, so a build made by `release.yml`, which passes `API_BASE_URL` only, gets the production address rules too. Check a configuration before building: `dart run tool/check_backend_config.dart --build-mode=release --dart-define-from-file=config/production.json` in `apps/mobile` (exit 0 = valid). Rules and layers: `docs/CONFIGURATION_MOBILE.md` |

## iOS

### What is prepared (IMPLEMENTED, BUILD VERIFIED on the simulator and with `--no-codesign`)

* No Team ID anywhere in the tree. Signing is *Automatic* for Runner and the widget; the team comes from
  `ios/Flutter/Local.xcconfig` (git-ignored; copy `Local.xcconfig.example`). A different bundle id prefix can be set there with
  `WB_BUNDLE_ID`; the widget id and the App Group follow it.
* Runner and WattByteWidget both have `CODE_SIGN_ENTITLEMENTS` with `com.apple.security.application-groups = $(WB_APP_GROUP)`;
  the widget extension is embedded in `Runner.app/PlugIns`; deployment target 15.0 everywhere; iPhone only, portrait.
* Privacy manifests for the app, the widget and the first-party plugin; `ITSAppUsesNonExemptEncryption = false`.
* Development-only local-network keys exist **only** in Debug/Profile builds (proved absent from a Release build,
  `docs/PLATFORM_SUPPORT.md`).
* The icon set and launch screen are derived from the in-app mark and are **provisional** (`assets/branding/README.md`).

### Steps in an Apple Developer account (BLOCKED here: no account is available)

1. Enrol in the Apple Developer Program (paid). Note the 10-character **Team ID**.
2. Certificates, Identifiers & Profiles -> Identifiers:
   * register the explicit App ID `pl.wattbyte.app` with the **App Groups** capability;
   * register `pl.wattbyte.app.WattByteWidget` with **App Groups**;
   * register the App Group `group.pl.wattbyte.app` and assign it to both App IDs.
   With automatic signing Xcode can create all of this the first time you build for a device with a team selected (if the ids are
   free); if `pl.wattbyte.app` belongs to someone else, set `WB_BUNDLE_ID` to your own prefix. **Required, not verifiable
   from this repository.** There is no Keychain-sharing, Push, HealthKit, Location or Background-Modes capability to enable:
   `fetch` is an Info.plist key, and the Keychain uses the app's default access group.
3. Create the app in App Store Connect (name, primary language English, Polish localization, bundle id, SKU).

### Development build on your own iPhone (BLOCKED without a team; nothing was installed on a device)

```sh
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig   # put your Team ID in it
cd apps/mobile
flutter run -d <device> --dart-define=API_BASE_URL=http://<mac-lan-ip>:<port>   # Debug: allowed over the LAN, iOS asks for Local Network access once
# or build, then install and launch with devicectl:
flutter build ios --debug --dart-define=API_BASE_URL=http://<mac-lan-ip>:<port>
xcrun devicectl list devices
xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <udid> --console pl.wattbyte.app
```

The iPhone must be in Developer Mode and have trusted the developer certificate (Settings -> General -> VPN & Device Management).
Without `API_BASE_URL` the app starts at the "Invalid build configuration" screen; `--dart-define=LOCAL_ONLY_DEV=true` (and no address) is
the debug-only mode without a backend and without an account, with a `LOCAL ONLY DEVELOPMENT MODE` strip on every screen.
Check the signed app: `codesign -d --entitlements :- build/ios/iphoneos/Runner.app` must show
`com.apple.security.application-groups` with `group.pl.wattbyte.app`, and the same for `PlugIns/WattByteWidget.appex`.

### Distribution, TestFlight, App Store (BLOCKED — RELEASE KEY REQUIRED)

1. Build and sign: either in CI (`release.yml`, `platform: ios`: needs `IOS_TEAM_ID` and an App Store Connect API key, `docs/CI.md`)
   or locally: `flutter build ipa --release --dart-define-from-file=config/production.json` (the file must carry `API_BASE_URL`, and no
   `LOCAL_ONLY_DEV` other than `false`, or the compile fails; `--export-method app-store` is the
   default in Flutter 3.41; the CI job uses an ExportOptions.plist with method `app-store-connect` instead). A distribution
   certificate and an App Store profile are created by Xcode with automatic signing and `-allowProvisioningUpdates`.
2. Verify the archive: `PlugIns/WattByteWidget.appex` present, `codesign --verify --deep --strict`, team id as expected, and
   `plutil -p Runner.app/Info.plist` has **no** `NSAppTransportSecurity`, `NSLocalNetworkUsageDescription` or `NSBonjourServices`.
3. Upload with Xcode Organizer, Transporter or `xcodebuild -exportArchive` with `destination upload`.
4. **TestFlight**: the build appears after processing; internal testers (App Store Connect users) need no review; external
   testers need Beta App Review and the beta test information. Test on the device with `docs/DEVICE_TEST_PLAN.md` first.
5. **App Store Connect metadata**: privacy policy URL (must be a public https page; `docs/privacy.md` is only the working
   draft), App Privacy answers matching `ios/Runner/PrivacyInfo.xcprivacy` (email, user id, device id, other usage data, other
   data: all linked, App Functionality, no tracking; see the mismatches listed in `docs/PLATFORM_SUPPORT.md`), age rating,
   category, screenshots for the required iPhone sizes, support URL, review notes with a demo account and the API reachable
   from Apple's network, export compliance (already answered by `ITSAppUsesNonExemptEncryption = false`).
6. Decide App Store availability on iPad and Mac for an iPhone-only app (see `docs/PLATFORM_SUPPORT.md`).

| iOS step | Status |
|---|---|
| Release no-codesign build, Info.plist without the development keys | BUILD VERIFIED |
| Signing, App ID / App Group registration, provisioning | BLOCKED (no Apple Developer account) |
| Entitlements as embedded in a signed build | NOT VERIFIED (simulator builds embed them ad hoc; a device build was not possible) |
| IPA export, TestFlight, App Store Connect | BLOCKED |

## Android

### Signing configuration (IMPLEMENTED; behaviour verified on this Mac)

`android/app/build.gradle.kts` reads the upload key from `android/key.properties` (git-ignored; template
`key.properties.example`) or the environment variables `WATTBYTE_KEYSTORE_FILE`, `WATTBYTE_KEYSTORE_PASSWORD`,
`WATTBYTE_KEY_ALIAS`, `WATTBYTE_KEY_PASSWORD`. The debug key is never used for release. No keystore, password or
`key.properties` is in the tree (checked with a file and content search).

| Situation | What `flutter build appbundle --release` / `apk --release` does |
|---|---|
| no key, nothing set | **Fails before compiling** (`:app:requireReleaseSigning`) with `BLOCKED - RELEASE KEY REQUIRED: no Android release signing key (missing: storeFile (WATTBYTE_KEYSTORE_FILE), ...)`, listing which of the four values are missing (never their values) |
| no key, `WATTBYTE_ALLOW_UNSIGNED_RELEASE=1` (or `-Pwattbyte.allowUnsignedRelease=true`) | Builds an **unsigned** artifact (R8 and shrinking still run) and logs `WARNING - UNSIGNED RELEASE ARTIFACT`. It cannot be uploaded or installed. Use it to check R8 without secrets. Add `--dart-define=API_BASE_URL=https://<host>`: a release build without an address now stops at the Dart compile with `[WB-CONFIG-001]`, and one with `LOCAL_ONLY_DEV=true` with `[WB-CONFIG-002]`. `tool/check_release_guard.sh --builds` uses this switch on purpose for its three release builds: those two must stop with their markers, and the third, with a valid made-up address (`--target-platform android-arm64`), must build an unsigned APK, which the script inspects for the development banner text and then deletes |
| key present | Builds and signs with it (proved with a throwaway key below) |

The earlier behaviour was a quiet configuration-time warning and an unsigned bundle that looked like a normal success.

**Environment note for this Mac:** `flutter build appbundle --release` finishes Gradle successfully but then exits 1 with
"Release app bundle failed to strip debug symbols from native libraries" because the Android SDK here has no `cmdline-tools`
(`flutter doctor`: "cmdline-tools component is missing"), and Flutter uses `apkanalyzer` from them to check the bundle. The
bundle is complete and stripped (it contains `BUNDLE-METADATA/com.android.tools.build.debugsymbols/*/libflutter.so.sym`). Fix:
install "Android SDK Command-line Tools" in Android Studio (SDK Manager). CI (`ubuntu-latest`) has them. Not installed here
because that is a download that needs your approval.

### Proof that signing works end to end (done with a throwaway key, since deleted)

A keystore was generated with `keytool` in a temporary directory outside the repository, handed to Gradle only through the four
environment variables, and deleted afterwards. The results are in the verification section below.

### Real release (BLOCKED — RELEASE KEY REQUIRED)

1. Create the **upload key** once and keep it, with its passwords, outside the repository and in a password manager:
   `keytool -genkey -v -keystore ~/wattbyte-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   (BLOCKED — RELEASE KEY REQUIRED: this must be done by the owner; do not generate release keys in a shared tree).
2. Put the values in `android/key.properties` locally, or in the four CI secrets (`docs/CI.md`).
3. Check the configuration, then build: `dart run tool/check_backend_config.dart --build-mode=release --dart-define-from-file=config/production.json`
   (exit 0), then `flutter build appbundle --release --dart-define-from-file=config/production.json --build-number=<n>` (or run `release.yml`:
   it runs the same check first and compiles in only `API_BASE_URL`; without `APP_ENV` that is validated as production, so the address rules
   are the production ones, but `PRIVACY_POLICY_URL` is not passed, so use the file build when the privacy-policy URL must be compiled in, `docs/CI.md`).
   Confirm the signer: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` matches
   `keytool -list -v -keystore <jks> -alias <alias>` (SHA-256); `jarsigner -verify` prints `jar is unsigned` for an unsigned one.
4. **Play Console** (BLOCKED, no account): create the app; enrol in **Play App Signing** on the first upload (you upload with the
   upload key, Google holds the app signing key and re-signs; keep the upload key because a lost upload key needs a reset
   through Google support); start with the **Internal testing** track, then closed/open testing, then production.
5. Store listing and declarations, to be filled from `docs/privacy.md` after its mismatches are fixed: privacy policy URL,
   **Data safety** form (account e-mail and id, device id, app activity / usage totals, device model and settings; data in
   transit encrypted; deletion available in the app), content rating, target audience, and any permission declaration the console
   asks for **`PACKAGE_USAGE_STATS` (Usage access)**: the app's core feature is data totals and Data by app, which need it;
   check Play Console -> App content for the current form (NOT VERIFIED). The app deliberately avoids `QUERY_ALL_PACKAGES`
   (a `<queries>` launcher intent is used) and starts no foreground service of its own.
6. Upload `build/app/outputs/bundle/release/app-release.aab`; the R8 mapping and native symbols travel inside the bundle
   (`BUNDLE-METADATA`), so crashes can be deobfuscated.
7. Check the target API requirement in force at submission (the app targets 36).

| Android step | Status |
|---|---|
| Release build fails clearly without a key; unsigned only on opt-in | BUILD VERIFIED |
| Signed bundle/APK with a throwaway key | BUILD VERIFIED (details below) |
| R8 / resource shrinking, `proguard-rules.pro`, `allowBackup=false`, no cleartext in release | BUILD VERIFIED (merged manifests and R8 output inspected); app behaviour of the minified build on a device NOT VERIFIED |
| Upload key, Play App Signing, Play Console, tracks, data safety | BLOCKED — RELEASE KEY REQUIRED |
| `flutter` exit code 0 for `appbundle --release` on this Mac | BLOCKED by the missing Android cmdline-tools (above) |

## Pre-submission checklist (both platforms)

- [ ] Final icon and launch artwork approved (`assets/branding/README.md`: currently derived and provisional).
- [ ] `config/production.json` with real https hosts and a public privacy-policy URL; `APP_ENV=production`; **no `LOCAL_ONLY_DEV`**
      (a release build with `LOCAL_ONLY_DEV` set to anything but `false` does not compile); it passes `dart run tool/check_backend_config.dart --build-mode=release --dart-define-from-file=config/production.json`.
- [ ] `docs/privacy.md` corrected (mismatches in `docs/PLATFORM_SUPPORT.md`) and published as the privacy policy.
- [ ] `docs/DEVICE_TEST_PLAN.md` executed on a real iPhone and a real Android phone, results filled in.
- [ ] Release build checked: no development keys in the iOS Info.plist, no cleartext in the Android merged manifest.
- [ ] Build numbers increased; version notes written (English and Polish).

## Verification log (this environment, 2026-10-13)

Apple silicon Mac, Xcode 27.0, Flutter 3.41.6, Android Studio JBR 21, Android SDK 36 without `cmdline-tools`. Logs were kept
outside the repository. "Real tree" is `apps/mobile`; "scratch copy" is a copy of the project with a trivial `main.dart`, used for
experiments that must not disturb the shared `build/` directory.

| Command | Where | Result |
|---|---|---|
| `flutter build ios --simulator --debug` | real tree | BUILD VERIFIED (exit 0) |
| `flutter build ios --debug --no-codesign` | real tree | BUILD VERIFIED (exit 0) |
| `flutter build ios --release --no-codesign` | real tree and clean scratch copy | BUILD VERIFIED (exit 0); `Runner.app/Info.plist` has no `NSAppTransportSecurity`, `NSLocalNetworkUsageDescription` or `NSBonjourServices`; `UIBackgroundModes = [fetch]`, portrait only, `UIDeviceFamily = [1]`, `MinimumOSVersion 15.0`; `PlugIns/WattByteWidget.appex` present |
| `flutter build apk --debug` | real tree | BUILD VERIFIED (exit 0) after fixing a manifest-merge conflict found by this run (`usesCleartextTraffic` main vs debug; the debug manifest now has `tools:replace`); merged debug manifest has `usesCleartextTraffic="true"`, `screenOrientation="portrait"`, `roundIcon`, `dataExtractionRules`; `aapt2 dump badging`: targetSdk 36, icon `mipmap-anydpi-v26/ic_launcher.xml` |
| `flutter build appbundle --debug` | real tree | BUILD VERIFIED (exit 0) |
| `flutter build appbundle --release`, no key | real tree | **fails in 3 s** with `BLOCKED - RELEASE KEY REQUIRED: no Android release signing key (missing: storeFile ..., storePassword ..., keyAlias ..., keyPassword ...)`; no artifact is produced |
| `WATTBYTE_ALLOW_UNSIGNED_RELEASE=1 flutter build appbundle --release` | real tree | Gradle succeeds (R8 + resource shrinking run, `mapping.txt` produced); artifact is **unsigned** (`jarsigner -verify` prints `no manifest.`); the build prints `WARNING - UNSIGNED RELEASE ARTIFACT ...` (checked with `apk --release` on the scratch copy; Flutter hides Gradle warnings, so it is logged at error level); `flutter` then exits 1 because of the missing cmdline-tools (below) |
| `flutter build appbundle --release` and `apk --release` with a throwaway key (env variables only) | real tree | the bundle is signed: `jarsigner -verify` lists the signer, certificate SHA-256 equals the keystore's (`BB:62:00:7D:...:48:35`); the APK verifies with `apksigner` (v2 scheme; signer `CN=WattByte throwaway test key`). The keystore was created in a temporary directory outside the repository and deleted afterwards (checked). `flutter` exit code for the `.aab`: 1 because of the missing cmdline-tools; the `.apk` exit 0 |
| why `appbundle --release` exits 1 here | | `Failed to find cmdline-tools when checking final appbundle for debug symbols.` (Flutter's post-build `apkanalyzer` check). The bundle contains `libflutter.so.sym` for every ABI and `proguard.map`, i.e. stripping worked. BLOCKED here by the environment, fixed by installing the Android SDK Command-line Tools |
| Kotlin JVM tests (`gradle cleanTest test --offline`, `packages/wattbyte_system/android/jvm-tests`) | | TESTED: 5 tests, 0 failures (BatteryValuesTest 2, DayRangesTest 3) |
| `tool/generate_brand_assets.sh --check` | | TESTED: 3 tests pass (constants still equal the in-app mark; splash size; every icon/launch asset equals the renderer output) |
| `xcrun actool` / `ibtool` on the catalog and the storyboard | | no errors or warnings; `AppIcon`: 8 iPhone images + the 1024 marketing icon, all `Opaque`; `LaunchBackground` light and dark; `LaunchLogo` 1x/2x/3x |
| Simulator architecture experiments | | `docs/PLATFORM_SUPPORT.md` |

The Flutter build rows of the log above were made on 2026-10-13, before the backend-configuration guard existed, and the commands as
listed carry no `--dart-define`. A profile or release build now needs `API_BASE_URL`: the release rows that get as far as the Dart compile
(`flutter build ios --release --no-codesign`, and `appbundle --release` / `apk --release` once a key or the unsigned switch is set) stop
there with `[WB-CONFIG-001]` unless `--dart-define=API_BASE_URL=https://<host>` (or a `--dart-define-from-file`) is given; without a key
and without the switch the Gradle signing check still fails first, as in the table. The rows above were not re-run for this change, so they are history, not a re-verification; the runs made for this change are listed below
and in `docs/STATUS.md`. On iOS the compile error is only visible with `-v`: `flutter build ios --release --no-codesign` without
`API_BASE_URL` fails, but without `-v` Flutter prints a "Development Team" hint instead of `[WB-CONFIG-001]`. Debug builds are unaffected
(they compile without defines).

What the guard adds is `tool/check_release_guard.sh --builds`: three real `flutter build apk --release` runs (two refused with
`[WB-CONFIG-001]` / `[WB-CONFIG-002]`, one with a valid made-up address that builds an unsigned arm64 APK, which is inspected and deleted;
`docs/CI.md`). It is not an `appbundle` or an iOS build, and it signs nothing. Its results, and the results of the rest of the
verification run of that change (2026-10-14), are in `docs/REGRESSION_TESTS.md`, "Verification (2026-10-14)" and in `docs/STATUS.md`,
section 20. For the release builds: the three Android builds of the script behaved as specified (two refused with `[WB-CONFIG-001]` /
`[WB-CONFIG-002]`, one built, no banner text in `libapp.so`), `flutter build ios --release --no-codesign` with a made-up address built
(no banner text in `App.framework/App`), and without `API_BASE_URL` it failed with `[WB-CONFIG-001]` (visible with `-v`). No signed build, no
`appbundle` and no `ipa` was made.

The guard's CI jobs are CONFIGURED, NOT REMOTELY VERIFIED (`docs/CI.md`).

Not run: a physical iPhone or Android phone, the iOS simulator tools (reserved by the orchestrator), any Apple or Google
service, App Store Connect, Play Console, `flutter build ipa`, an Intel Mac.

One incremental-build artefact to know about: the simulator `Runner.app` that existed before the new icon set still contains
`AppIcon76x76@2x~ipad.png` (a leftover of the old icon set; Xcode does not delete files it no longer produces, and it is not
listed in `Info.plist`). It is absent from every clean build (checked in a scratch copy with an empty DerivedData and in the real
tree's release build). `flutter clean` removes it.

