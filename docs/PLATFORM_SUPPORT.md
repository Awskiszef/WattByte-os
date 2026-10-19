# Platform support and native configuration

What WattByte v1 supports on iOS and Android, why, and how the native projects are configured. Statuses follow
`docs/FIX_REPORT.md` (IMPLEMENTED, TESTED, BUILD VERIFIED, INTEGRATION VERIFIED, SIMULATOR VERIFIED, DEVICE VERIFIED,
NOT VERIFIED, BLOCKED, NOT IMPLEMENTED). Nothing in this file is DEVICE VERIFIED: no physical phone was available to the
author of these changes. `docs/DEVICE_TEST_PLAN.md` is the checklist for that, `docs/RELEASE.md` covers signing and the stores.

## Support matrix

| | iOS | Android |
|---|---|---|
| Devices | **iPhone only** (`TARGETED_DEVICE_FAMILY = 1`, Runner and WattByteWidget) | **Phones only** |
| OS | iOS 15.0 and later (`IPHONEOS_DEPLOYMENT_TARGET = 15.0` everywhere: project, Runner, widget, tests, every pod, `wattbyte_system.podspec`) | Android 10 (API 29, `minSdk`; `NetworkStatsManager` without a subscriber id needs 29) and later; `targetSdk` 36 (Flutter's `targetSdkVersion`) |
| Orientation | **Portrait only** (`UISupportedInterfaceOrientations` = Portrait, no `~ipad` key) | **Portrait** (`android:screenOrientation="portrait"` on `MainActivity`) |
| Tablets, foldables, desktop | iPad: no (see below). Mac "Designed for iPad/iPhone": not evaluated | Not a target, but must not crash (see below) |
| Home-screen widget | WidgetKit `WattByteWidget`: small, medium, large | `AppWidgetProvider`, one provider, small / medium / large chosen by the widget's size |
| Battery capacity (`docs/BATTERY_CAPACITY.md`) | **Design capacity** only, from the catalog by `utsname.machine` (`SIMULATOR_MODEL_IDENTIFIER` on the simulator) or typed by the user; an unlisted model is "Battery capacity unavailable". iOS has no public charge counter or capacity API and no private one is used, so there is no estimated full charge capacity | **Design capacity** from the catalog by `Build.MODEL` or typed by the user, plus an **estimated full charge capacity** (an estimate for this battery, with a confidence) extrapolated from `BATTERY_PROPERTY_CHARGE_COUNTER` (the charge currently stored, in µAh) when the phone reports it; Wh only from a valid `BATTERY_PROPERTY_ENERGY_COUNTER`. The counter is never a design capacity. Units, sign and availability per maker: NOT VERIFIED on a device (`docs/DEVICE_TEST_PLAN.md`, section 12) |
| Languages | English, Polish (`CFBundleLocalizations`) | English, Polish |

### Why iPhone and portrait only

The Dashboard cards, the charts and the number formatting are designed and tested for a portrait phone column. A landscape or
iPad layout would have to be designed, built and tested (it is not a matter of unlocking rotation: the cards would stretch or
clip). v1 deliberately does not ship a broken wide layout; the restriction is declared, not accidental. To support them later:
design the layouts, add `UIInterfaceOrientationLandscape*` to `ios/Runner/Info.plist` and iPad family `2` back
(`DEVICE_FAMILY` in `tool/ios_setup_project.rb`), re-add the iPad icon sizes (`kIphoneIcons` in `tool/brand/brand_assets.dart`),
remove `android:screenOrientation` from the manifest, and extend the tests.

* **iPad**: an iPhone-only app is, by default, still offered to iPad users and runs in iPhone-sized compatibility mode, and
  can be offered on Apple-silicon Macs. Whether to keep or remove that availability is an App Store Connect decision
  (NOT VERIFIED here; nothing was run on an iPad or Mac).
* **Android 16 and large screens**: for apps targeting API 36 the system ignores `screenOrientation`, resizability and aspect-ratio
  restrictions on screens with a smallest width of 600 dp or more (tablets, unfolded foldables, desktop windowing, split-screen on
  those). So on such devices WattByte can still be shown landscape or in a resized window, and the layouts must not crash there.
  `MainActivity` already declares the relevant `configChanges`, so a resize does not recreate the activity. A teammate covers
  wide sizes in widget tests; no real large-screen device or emulator was used (NOT VERIFIED).

## iOS simulator architecture (`ARCHS`)

Previous state: `Flutter/Debug.xcconfig`, `Flutter/Release.xcconfig` and the Podfile forced `ARCHS[sdk=iphonesimulator*] = arm64`
and `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64` for the simulator. That fixed an Xcode 27 failure but broke Intel Macs and
replaced Flutter's own `EXCLUDED_ARCHS` (`i386`).

**The original error** (`flutter build ios --simulator`, Xcode 27, Flutter 3.41.6, observed again while writing this):

```
Target debug_unpack_ios failed: Exception: Binary .../Flutter.framework/Flutter does not contain architectures "arm64 x86_64".
lipo -info: Architectures in the fat file: ... are: x86_64 arm64
```

**Root cause.** The binary does contain both slices. Flutter's `UnpackDarwin.thinFramework` verifies them with one call,
`lipo <binary> -verify_arch arm64 x86_64`, and Xcode 27's `lipo` does not accept more than one architecture there: it prints its
usage text and exits with status 1 (`lipo ... -verify_arch arm64` and `... -verify_arch x86_64` each exit 0). The check fails
whenever `ARCHS` contains two architectures, which is Xcode's default for a generic simulator destination (`arm64 x86_64`).
The earlier explanation ("the order printed by `lipo -info` differs from ARCHS") was not the cause: `x86_64 arm64` fails too.

**Fix.** `ios/Flutter/WattByte.xcconfig` (included by Debug and Release.xcconfig, and therefore by Runner, the widget and the
Profile configuration) and the Podfile `post_install` set, for the simulator SDK only:

```
WB_SIM_ARCH_FOR_arm64  = arm64
WB_SIM_ARCH_FOR_arm64e = arm64
WB_SIM_ARCH_FOR_x86_64 = x86_64
ARCHS[sdk=iphonesimulator*] = $(WB_SIM_ARCH_FOR_$(NATIVE_ARCH_ACTUAL):default=$(ARCHS_STANDARD))
```

* One architecture, the host's: `arm64` on Apple silicon, `x86_64` on an Intel Mac.
* Why a lookup table and not `$(NATIVE_ARCH_ACTUAL)`: Flutter runs `arch -arm64e xcrun xcodebuild`, so inside the build
  `NATIVE_ARCH_ACTUAL` is `arm64e` (a device architecture; `ARCHS=arm64e` fails the same check with "does not contain
  architectures arm64e"). The table maps `arm64e` to `arm64`. A host the table does not know falls back to Xcode's default
  (`ARCHS_STANDARD`), i.e. the behaviour before this change.
* Not global: the condition `[sdk=iphonesimulator*]` leaves `iphoneos` builds alone (`ARCHS = arm64`, `EXCLUDED_ARCHS = armv7`
  from Flutter's `Generated.xcconfig`, both unchanged; confirmed with `xcodebuild -showBuildSettings -sdk iphoneos`).
  `EXCLUDED_ARCHS` is no longer overridden.
* `Local.xcconfig` is included last, so a developer can override any of this.

**Verification.**

| Check | Result |
|---|---|
| Original error reproduced in a scratch copy of the project with the old lines removed | reproduced (exit 255, message above) |
| `flutter build ios --simulator --debug` with the fix, Apple silicon, Xcode 27 (scratch copy and the real project) | BUILD VERIFIED: passes; `ARCHS=arm64` inside the build (although Flutter's `arch -arm64e` wrapper makes `NATIVE_ARCH_ACTUAL` `arm64e`); `Runner`, the widget, `Flutter.framework`, `App.framework` and all pods are arm64 |
| `xcodebuild -showBuildSettings -sdk iphonesimulator` | `ARCHS = arm64`, `EXCLUDED_ARCHS = i386` (Flutter's) |
| same with `-sdk iphoneos` | `ARCHS = arm64`, `EXCLUDED_ARCHS = armv7` (unchanged) |
| Intel resolution, simulated with `xcodebuild ... NATIVE_ARCH_ACTUAL=x86_64` | `ARCHS = x86_64`; a complete simulator build with that override succeeded and produced x86_64 `Runner`, widget, `Flutter.framework` and `App.framework` |
| `arch -x86_64 xcodebuild -showBuildSettings` on this Mac | **NOT VERIFIED on a real Intel host.** `arch -x86_64` cannot emulate one: Xcode 27's `xcodebuild` is arm64-only (`arch -x86_64 .../xcodebuild` fails with "Bad CPU type in executable"; the `/usr/bin` shim just starts the arm64 binary), so settings and builds keep resolving to the Apple-silicon host. The x86_64 table entry is exercised only through the override above |
| multi-arch simulator build (`ARCHS="arm64 x86_64"`) | still fails with Xcode 27 and Flutter 3.41.6 (the `lipo` problem above); not needed and not supported until Flutter's check changes |

## iOS configuration reference

### Identity, signing, App Group

| Setting | Value | Defined in |
|---|---|---|
| Runner bundle id | `pl.wattbyte.app` (`$(WB_BUNDLE_ID)`) | `ios/Flutter/WattByte.xcconfig`, overridable in `Local.xcconfig` |
| Widget bundle id | `pl.wattbyte.app.WattByteWidget` (`$(WB_BUNDLE_ID).WattByteWidget`) | `Runner.xcodeproj` (via `tool/ios_setup_project.rb`) |
| App Group | `group.pl.wattbyte.app` (`$(WB_APP_GROUP)` = `group.$(WB_BUNDLE_ID)`) | `WattByte.xcconfig`; used by both `.entitlements` files, `WBAppGroup` in both `Info.plist` files, `WattByteSystemPlugin.appGroupId`, `WidgetPublisher`, `WattByteWidget.swift` |
| Team | none committed. `DEVELOPMENT_TEAM` comes from the git-ignored `ios/Flutter/Local.xcconfig` (template: `Local.xcconfig.example`) | |
| Signing style | `CODE_SIGN_STYLE = Automatic` on Runner, WattByteWidget and RunnerTests; `ProvisioningStyle = Automatic` so Xcode's checkbox agrees | `Runner.xcodeproj` |
| Widget embedded | "Embed Foundation Extensions" phase puts `WattByteWidget.appex` in `Runner.app/PlugIns` (confirmed in the built app); Runner depends on the widget target | |
| Deployment target | 15.0 for all targets and pods | `Runner.xcodeproj`, `Podfile` |

Registering the two bundle ids and the App Group in an Apple Developer account is **required** before a device or store build
can be signed. That cannot be verified or done from this repository (BLOCKED without an account; see `docs/RELEASE.md`).
`WB_BUNDLE_ID` exists so a developer whose team does not own `pl.wattbyte.app` can still run on a device with their own id.

### `Info.plist` review (Runner)

| Key | Value | Why |
|---|---|---|
| `UIBackgroundModes` | `fetch` only | `workmanager` schedules the refresh as a `BGAppRefreshTask` (`registerPeriodicTask` -> `BGAppRefreshTaskRequest`), which needs `fetch`. `processing` was removed: nothing registers a `BGProcessingTask` |
| `BGTaskSchedulerPermittedIdentifiers` | `pl.wattbyte.refresh` | must equal `kRefreshTask` in Dart and the identifier registered in `AppDelegate.swift`. It is a task id, not an Apple-registered identifier |
| `UISupportedInterfaceOrientations` | Portrait | see above |
| `UIApplicationSceneManifest` | `SceneDelegate`, single scene | UIScene lifecycle is mandatory on iOS 27 (kept) |
| `ITSAppUsesNonExemptEncryption` | `false` | HTTPS and Keychain through the OS only |
| `CADisableMinimumFrameDurationOnPhone` | `true` | allows 120 Hz on ProMotion iPhones (Flutter) |
| `WBAppGroup` | `$(WB_APP_GROUP)` | one source for the App Group id |
| usage-description keys | none | no camera, photos, location, contacts, Bluetooth or tracking API is used; notifications need no key |

**Development-only local network access.** A physical iPhone can only reach a development API on the LAN over plain `http://`
if the app declares `NSLocalNetworkUsageDescription` (iOS 14+; without it the connection just fails). The Runner target has a
"WattByte Debug Local Network" Run Script phase (before Flutter's "Thin Binary") that, **for Debug and Profile builds only**,
edits the *built* `Info.plist` with `plutil`: it sets `NSLocalNetworkUsageDescription` and
`NSAppTransportSecurity = { NSAllowsLocalNetworking = true }`. For a Release build the script exits before writing anything.
Flutter's own phase additionally adds `NSBonjourServices = [_dartVmService._tcp]` to non-release builds (hot reload / `flutter
attach` discovery). The tracked `Info.plist` contains none of these keys. (`dart:io`'s `HttpClient`, which the `http` package
uses, is not subject to ATS; the exception is there for any `NSURLSession`-based code and to satisfy the requirement. The local
network *permission* applies to both.)

Evidence (built products, `plutil -p Runner.app/Info.plist`):

| Build | `NSAppTransportSecurity` | `NSLocalNetworkUsageDescription` | `NSBonjourServices` | `UIBackgroundModes` |
|---|---|---|---|---|
| `flutter build ios --simulator --debug` (real project) | `NSAllowsLocalNetworking = true` | present | `_dartVmService._tcp` | `fetch` |
| `flutter build ios --release --no-codesign` (scratch copy, clean build) | **absent** | **absent** | **absent** | `fetch` |

### Privacy manifests

`ios/Runner/PrivacyInfo.xcprivacy`, `ios/WattByteWidget/PrivacyInfo.xcprivacy` and (new) the manifest of the first-party pod
`wattbyte_system` were reviewed against the code that actually runs.

* **Tracking**: `NSPrivacyTracking = false`, no tracking domains. There is no analytics, advertising or attribution SDK.
* **Collected data** (Runner; sent only to the WattByte API after the user creates an account; all *linked*, purpose *App
  Functionality*, none used for tracking): `EmailAddress`; `UserID` (new: the account id); `DeviceID` (the random installation id,
  not a hardware or advertising id); `OtherUsageData` (per-day aggregates uploaded by cloud sync, month totals for AI insights);
  `OtherDataTypes` (new: platform, device model code such as `iPhone16,1`, the design (nominal) battery capacity of the model and its source, on Android also the estimated full-charge capacity with its
  confidence, country, currency, price mode and manual price). The widget collects nothing.
* **Required-reason APIs** declared: `UserDefaults` (`CA92.1` the app's own settings and background-task bookkeeping, `1C8F.1` the
  App Group suite shared with the widget; the widget declares `1C8F.1`); `SystemBootTime` `35F9.1` for
  `sysctlbyname("kern.boottime")` in `WattByteSystemPlugin.swift` (Runner and the `wattbyte_system` pod). The boot time is compared
  between two samples to detect a reboot, which resets the interface counters; it never leaves the device. `35F9.1` ("time elapsed
  between events within the app") is the closest published reason, not a perfect one: the alternative would be to stop reading the
  boot time and detect a reboot only from counters going backwards (a code change, not made).
* **Not declared on purpose**: file timestamps, disk space and active keyboards. A search of `lib/`, `ios/` and the plugin found no
  call (`File.stat`/`lastModified`, `statfs`, `volumeAvailableCapacity`, `NSFileModificationDate`, ...). The Flutter engine
  declares its own file-timestamp and boot-time use in `Flutter.framework`.
* **Third-party pods**: `shared_preferences_foundation`, `sqflite_darwin`, `flutter_secure_storage`, `share_plus`,
  `flutter_local_notifications` and `workmanager_apple` ship manifests; `home_widget` does not, and its UserDefaults use is covered
  by the Runner entry; `path_provider_foundation` has none and uses no required-reason API.
* The built app contains `PrivacyInfo.xcprivacy` in `Runner.app`, in the widget extension and in the `wattbyte_system` framework's resource bundle (checked in the Release no-codesign build, next to those of the third-party plugins).

Mismatches with `docs/privacy.md` (owner: whoever maintains that file; only its capacity rows were updated, with the battery capacity split):

1. It says only a random installation id and the platform are registered ("no device model"), but `SyncService._register` also
   sends `model`, `modelIdentifier`, the design capacity (`designCapacityMah`, `designCapacityWh`, `designCapacitySource`) and,
   when the collector has one, the estimated full-charge capacity (`estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`,
   `fullChargeCapacitySource`, `fullChargeCapacityConfidence`), and `AccountSettingsSync.push` sends country, currency, price mode
   and manual price. (`docs/privacy.md` now lists the capacity data in its own row; the "no device model" sentence is still there.)
2. "Never uploaded: ... the settings values (price, efficiency, capacity)": price is uploaded (account settings) and capacity is
   uploaded with the device record; efficiency, theme and notification choices are not. (The capacity part of the sentence was
   corrected in `docs/privacy.md`; the price part is still wrong there.)
3. Its "Apple privacy manifest" paragraph lists three data types; the manifest now declares five (adds `UserID`, `OtherDataTypes`).
4. The iOS permission row says "none beyond background refresh": the app also asks for notification permission (alert and sound).
5. "Sync is off by default": sign-up, device registration and account settings are sent after the account exists regardless of the
   cloud-sync switch (only the daily aggregates wait for it). The manifest comment used to say all of it required cloud sync.

### WidgetKit

`WattByteWidget.swift` declares `.supportedFamilies([.systemSmall, .systemMedium, .systemLarge])` and has a layout for each:
`.systemMedium` (three stats in a row), `.systemLarge` (header plus a 2x2 grid of today/month data, energy and cost) and the
`default` branch for `.systemSmall` (header and one stat). No other family is declared, so no family without a layout is offered.
Facts, not new features: `containerBackground` is used on iOS 17+ with a fallback below; the display name and description
(`"WattByte"`, `"Data and energy at a glance."`) are fixed English strings, not localized, and the placeholder values are English;
the timeline asks to reload after 30 minutes, which WidgetKit treats as a hint within its own budget. The small and medium
widgets were seen on the simulator (`docs/IOS_SIMULATOR_REPORT.md`); large was never run; nothing ran on a device.

## Android configuration reference

| Area | State | Where |
|---|---|---|
| Application id / namespace | `pl.wattbyte.app` | `android/app/build.gradle.kts` |
| `minSdk` / `targetSdk` / `compileSdk` | 29 / 36 / Flutter default | same, `flutter.*` |
| Backup | `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` excluding cloud backup and device transfer (Android 12+) | `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml` |
| Cleartext HTTP | `usesCleartextTraffic=false` in the main manifest; only `src/debug/AndroidManifest.xml` sets it to `true` (merged debug manifest confirmed) | |
| Permissions (merged) | `INTERNET` (API); `PACKAGE_USAGE_STATS` (Usage access: totals and Data by app); `POST_NOTIFICATIONS` (optional alerts); from libraries: `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE` (WorkManager), `VIBRATE` (`flutter_local_notifications`) | `wattbyte_system` manifest and libraries |
| Package visibility | a `<queries>` entry for launcher apps (labels in Data by app) instead of `QUERY_ALL_PACKAGES` | `wattbyte_system` manifest |
| Usage Access | a special permission the user grants in Settings; `capabilities.usageAccessState` handles granted / denied / unavailable | `WattByteSystemPlugin.kt` |
| Background work | WorkManager: periodic refresh (15 min, Dart) and a unique one-time `ChargingWorker` with the "requires charging" constraint that samples each minute while a charger is connected | `wattbyte_system`, `background_tasks.dart` |
| Widget | `WattByteWidgetProvider` (`APPWIDGET_UPDATE`, resizable 110x60 dp up to 360x320 dp; layout chosen by size) | manifest, `res/xml/wattbyte_widget_info.xml` |
| Launcher icon | adaptive (`mipmap-anydpi-v26`: background, foreground, monochrome) + round + legacy bitmaps; manifest references `ic_launcher` and `ic_launcher_round` | `assets/branding/README.md` |
| Splash | Android 12+: `windowSplashScreenBackground` + `windowSplashScreenAnimatedIcon` (`values-v31`, `values-night-v31`); before: `launch_background` (page colour + mark), light and dark | |
| R8 | minify and resource shrinking on for `release` (Flutter's plugin enables them; stated explicitly in `build.gradle.kts`); `android/app/proguard-rules.pro` keeps `ChargingWorker` by name (WorkManager stores the class name) | |
| Release signing | see `docs/RELEASE.md`; no keystore, password or `key.properties` in the tree (only `key.properties.example`) | |

Known Android notes for other owners: `AppNotifier` initializes `flutter_local_notifications` with `@mipmap/ic_launcher` as the
small notification icon; Android draws small icons from their alpha channel, so a coloured launcher bitmap shows as a white
square. The plugin already ships a monochrome `@drawable/ic_wb_bolt` (used by `ChargingNotifier`); `AppNotifier` should use that
(`lib/background/app_notifier.dart`, not changed here).

## What was run for this document

The build and signing results are in the "Verification log" at the end of `docs/RELEASE.md`; the architecture experiments are in
the table above. Anything not listed there was not run. Two Android facts seen while checking the packages:
`android:screenOrientation="portrait"` makes `aapt2` add an implied `uses-feature android.hardware.screen.portrait`
(required), so Google Play hides the app on devices without a portrait screen, which matches "phones only"; and Android's
manifest merger refused a debug `usesCleartextTraffic="true"` over the main manifest's `false` until `tools:replace` was added
(`src/debug/AndroidManifest.xml`).
