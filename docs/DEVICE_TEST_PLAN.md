# Device test plan (physical iPhone and Android phone)

A runnable checklist for the tests that only a real phone can answer: signing, a real charging session, real network
counters, background execution, notifications, widgets and the App Group. Every result starts as **NOT VERIFIED**; a row
changes only when someone ran it on a device and attached evidence. Nothing in this repository has been DEVICE VERIFIED.

Result values: `NOT VERIFIED` (default), `DEVICE VERIFIED` (passed, evidence attached), `FAILED` (bug, link the evidence),
`BLOCKED` (could not run, say why), `NOT APPLICABLE`.

Related: `docs/PLATFORM_SUPPORT.md` (support matrix, native configuration), `docs/RELEASE.md` (signing),
`docs/AUTO_SETUP.md` (setup flow), `docs/IOS_SIMULATOR_REPORT.md` (what the simulator already showed).

## 0. Rules for honest results

* **iOS gives apps very little.** There is no per-app data usage, no charge or energy counter, and no continuous background
  monitoring. The only network source is the `getifaddrs` interface counters (`en0` = Wi-Fi, `pdp_ip*` = cellular, since boot,
  32-bit, summed over all apps and the system). Do not compare the iOS app with features iOS does not offer publicly (per-app
  "Data by app", mAh counters, minute-by-minute charging curves). Compare it only with Settings -> Cellular (system totals
  over a period you reset yourself) and with the battery percentage.
* **Never promise continuous monitoring on iOS.** Background refresh runs when iOS decides (see section 7); the app samples
  when it is open, on resume, every 60 s in the foreground, and in the occasional `BGAppRefreshTask`. Sessions on iOS are
  therefore built from sparse samples and say so ("Times are approximate: samples were far apart.").
* Values the app computes from a percentage are labelled **Estimated**; values read from a system counter are not. A test
  fails if an estimated value is shown without the label, or a value is shown that the platform cannot provide.
* **Two capacities, never one.** The *design capacity* is the published nominal capacity of the phone model (catalog or
  typed by the user); it is shown as a plain figure with its source. The *estimated full charge capacity* is an estimate for
  this one battery, extrapolated from the Android charge counter; it is shown as `~X mAh` with "Estimated" wording and a
  confidence. A test fails if the charge counter, or anything derived from it, is shown as the nominal capacity, or if an
  estimate appears on iOS (`docs/BATTERY_CAPACITY.md`).
* Use the real charger and the real battery. `adb shell dumpsys battery set ...` and the emulator's battery controls are for
  debugging the UI only and never count as a result here.
* Record the build: `git`-less repo, so write the app version, the build date, `flutter --version`, the `--dart-define`s the
  build was made with (never a secret; in particular whether `LOCAL_ONLY_DEV` was set: a result from a local-only build
  says nothing about the account flow; and `APP_ENV`: unset means development in a debug build and production in a profile or
  release build), the OS version and the
  device model (`xcrun devicectl list devices`, `adb shell getprop ro.product.model`, `adb shell getprop ro.build.version.release`).

### Evidence

Create `evidence/<yyyy-mm-dd>-<device>/<test id>/` (not committed) and put there: a screenshot or screen recording
(`xcrun devicectl device capture ...` is not needed: use the device's own screenshot, or on Android
`adb exec-out screencap -p > shot.png` and `adb shell screenrecord /sdcard/r.mp4` then `adb pull`), the command output named in
the Evidence column, and one line of notes. Copy the result into the Result column with the date and your initials.

## 1. Preparation (both platforms)

| ID | Steps | Expected | Evidence | Result |
|---|---|---|---|---|
| P1 | Start the API on the Mac: `apps/api` with `DATABASE_URL`, `NODE_ENV=development`, `HOST=0.0.0.0` (so the phone can reach it), `AI_MOCK=1`. Note the Mac's LAN address. The phone and the Mac are on the same Wi-Fi. | `curl http://<lan-ip>:<port>/health` from the Mac answers 200; from the phone's browser too | `curl -i` output | NOT VERIFIED |
| P2 | Build the app with the LAN API: `flutter build ios --debug --dart-define=API_BASE_URL=http://<lan-ip>:<port>` / `flutter build apk --debug --dart-define=API_BASE_URL=http://<lan-ip>:<port>` (plain `http://` is accepted in a debug build only while `APP_ENV` is unset or `development`; `APP_ENV=staging` and `production` refuse it, and so does a profile or release build without `APP_ENV`, which is validated as production: `lib/config/app_environment.dart`, `lib/config/backend_config.dart`). Do **not** add `LOCAL_ONLY_DEV`: it is the no-backend development mode and is rejected together with an address. A build with neither define starts at the "Invalid build configuration" screen (Y6) | Builds; the log line `WattByte: Debug build, added NSLocalNetworkUsageDescription and NSAllowsLocalNetworking` appears for iOS | build log | NOT VERIFIED |
| P3 | Fully charge, then unplug, reboot the phone once so counters start from a known boot. Note the battery percentage, the date and the time. | A known starting state | screenshot of the lock screen | NOT VERIFIED |

## 2. Install and signing

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| I1 | iOS | Developer Mode on (Settings -> Privacy & Security). `cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig`, put your Team ID in it (and `WB_BUNDLE_ID` if `pl.wattbyte.app` is not yours). `xcrun devicectl list devices` shows the phone as available. | Phone listed, paired, `available` | `xcrun devicectl list devices` | NOT VERIFIED |
| I2 | iOS | `flutter build ios --debug --dart-define=API_BASE_URL=http://<lan-ip>:<port>` (the defines of P2), then `xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app`; trust the developer certificate on the phone (Settings -> General -> VPN & Device Management) | Installs without a signing error; the WattByte icon is the blue square with the yellow bolt (provisional artwork); the app opens | install output, screenshot of the home screen | NOT VERIFIED |
| I3 | iOS | `codesign -d --entitlements :- build/ios/iphoneos/Runner.app` and the same for `build/ios/iphoneos/Runner.app/PlugIns/WattByteWidget.appex` | both show `com.apple.security.application-groups` containing `group.<bundle id>`; same team id on both | command output | NOT VERIFIED |
| I4 | iOS | `xcrun devicectl device process launch --device <udid> --console --terminate-existing pl.wattbyte.app` | the app launches on the launch screen (page background colour + the mark) and then the welcome screen; no crash, no red screen; dark mode shows the dark launch background | console output, screenshots in light and dark | NOT VERIFIED |
| I5 | iOS | First launch: the Local Network permission prompt (development build only) appears; allow it | prompt text is the development text from `ios_setup_project.rb`; allowing lets the app reach the Mac API | screenshot | NOT VERIFIED |
| I6 | iOS | The orientation lock: rotate the phone with the lock off | the app stays portrait | screen recording | NOT VERIFIED |
| A1 | Android | Developer options + USB debugging on; `adb devices` | device listed as `device` | `adb devices -l` | NOT VERIFIED |
| A2 | Android | `adb install -r build/app/outputs/flutter-apk/app-debug.apk`; `adb shell pm list packages pl.wattbyte.app` | `Success`; the adaptive icon is shown (try a circle and a squircle launcher shape); with Android 13+ themed icons on, the monochrome bolt follows the wallpaper | `adb install` output, screenshots | NOT VERIFIED |
| A3 | Android | `adb shell dumpsys package pl.wattbyte.app \| grep -E "versionName\|targetSdk\|usesCleartext\|allowBackup"` | targetSdk 36 for the debug build; `allowBackup=false` | command output | NOT VERIFIED |
| A4 | Android | `adb shell am start -n pl.wattbyte.app/.MainActivity`; rotate the phone | portrait only on a phone | screen recording | NOT VERIFIED |

## 3. First run and automatic setup

Follow `docs/AUTO_SETUP.md`. The API from P1 must be reachable.

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| S1 | both | Welcome -> Create account (e-mail, password of at least 8 characters) | the app goes to "Setting up WattByte..." then "Your setup"; no account fields are asked again | screen recording; API log lines `POST /auth/register` 201, `GET /me/settings` | NOT VERIFIED |
| S2 | both | Review screen: Region and currency | match the phone's Region setting (for example PL -> PLN) and say "Detected automatically"; no location permission was requested | screenshot; Settings -> Privacy shows no location entry for WattByte | NOT VERIFIED |
| S3 | iOS | Review screen: Device | the real model identifier (`iPhone19,2` on an iPhone 18 Pro), not `Simulator` | screenshot; `xcrun devicectl device info details --device <udid>` model | NOT VERIFIED |
| S4 | both | Review screen: Battery | the **design capacity** of the model with its source: "Detected from device specifications" (bundled catalog hit, `localDeviceDatabase`), "From the WattByte device database" (the API's catalog, `backendDeviceDatabase`), "Chosen manually" (`manual`), or "Battery capacity unavailable" + "This model is not in the device database." + "Enter manually" (model in no catalog, as the iPhone 18 series was at the time of writing; source `unknown`). It never shows an invented default such as 4000 mAh, and on Android never a value taken from the charge counter: the estimate is not on this screen (it is in Settings, B2) | screenshot; PostgreSQL `devices.design_capacity_mah`, `devices.design_capacity_source` for the row (no number when `unknown`) | NOT VERIFIED |
| S5 | both | Review screen: Electricity | the automatic household price for the country with its period (for example `2026-S1`) and "Updated:" date | screenshot; API log `GET /electricity-price?country=..` | NOT VERIFIED |
| S6 | iOS | Permissions screen | explains first, then the notification system prompt appears only after tapping; the text says iOS shares no per-app data and no charge counters | screenshots | NOT VERIFIED |
| S7 | Android | Permissions screen -> "Open settings" -> Usage access -> WattByte -> allow | back in the app the Dashboard fills with data totals; before granting it says "Allow usage access" and shows no invented numbers | screen recording; `adb shell cmd appops get pl.wattbyte.app GET_USAGE_STATS` shows `allow` | NOT VERIFIED |
| S8 | both | Kill the app and relaunch | goes directly to the Dashboard (one `GET /me` in the API log); settings kept | API log, screenshot | NOT VERIFIED |

## 4. Battery level and capacity

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| B1 | iOS | Open the Dashboard, compare the battery % with the status bar / Control Center | equal within 1 % (UIDevice reports whole percent steps of 5 % when monitoring is enabled on some models: write down what you see) | screenshot pair | NOT VERIFIED |
| B2 | Android | Compare with `adb shell dumpsys battery` (`level`, `status`, `Charge counter`, in microampere-hours); then Settings -> Device | level equal; with a `Charge counter` and a level of 40 % or more, the row "Estimated full charge capacity" shows `~X mAh` with "Confidence: high" (level 95 % or more), "medium" (75 to 94 %) or "low" (40 to 74 %), and X is roughly `Charge counter / 1000 / (level / 100)`; without a `Charge counter`, or below 40 % with no earlier reading, the row is absent; the "Battery Capacity" row (design capacity) does not change either way. The app keeps the best reading it has seen (replaced by an equal or better one, or after 30 days), so the displayed value may come from an earlier, higher-confidence reading: compare with the `meta` rows before calling it a mismatch | `dumpsys battery` output, screenshot of Settings -> Device, `adb exec-out run-as pl.wattbyte.app cat databases/wattbyte.db > /tmp/wb.db` then `sqlite3 /tmp/wb.db "select key, value from meta where key like 'calibrated_capacity%'"` (the key names are historical; the values are the estimate) | NOT VERIFIED |
| B3 | both | Settings -> Battery Capacity: type a value, then tap "Detect again" | the typed value is marked "Chosen manually" and the Energy and mAh figures use it (finite, no NaN, Infinity or negative); automatic detection (a relaunch, a new setup pass) leaves it alone; "Detect again" replaces it with the catalog value, or, for a model in no catalog, with "Battery capacity unavailable" (the estimate is never copied in as the design capacity); on Android the estimate row is unchanged by both | screenshots; PostgreSQL `devices.design_capacity_source` / `design_capacity_mah` after each step | NOT VERIFIED |

## 5. A real charging session (the key test)

Needs a real charger. Do it once with a normal cable charger and, if available, once with a wireless charger.

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| C1 | Android | Unplugged at 20-60 %. Open the app once (so the charging worker is scheduled). Plug in. `adb shell dumpsys jobscheduler \| grep -A3 wattbyte` shows the charging job. Wait until the percentage has risen by at least 5 % (usually 10 to 20 minutes). Unplug. Open the app | History -> Charging has a new row; the session sheet ("Charging Session") shows Battery `a% -> b%`, Added `b-a %`, Duration, Charge in mAh (**no Estimated badge** when the system charge counter exists), Battery Energy in Wh, Wall Energy Estimate and Cost with the **Estimated** badge, no "Times are approximate" note (samples one minute apart) | `adb shell dumpsys battery` before and after (charge counter delta in uAh / 1000 = mAh); screenshot of the sheet; `adb exec-out run-as pl.wattbyte.app cat databases/wattbyte.db > /tmp/wb.db` then `sqlite3 /tmp/wb.db "select * from charging_sessions order by start desc limit 1"` | NOT VERIFIED |
| C2 | Android | Check the numbers: mAh shown = (charge counter at the last sample - at the first) / 1000, within a few %; Wh shown = energy counter delta, or mAh x average voltage when there is no energy counter; Wall Wh = Wh / efficiency (Settings, default 85 %); Cost = Wall kWh x price | arithmetic matches to rounding; every derived figure is finite and non-negative | worked calculation in the notes | NOT VERIFIED |
| C3 | Android | During the charge keep the screen off for 10 minutes, then unplug with the app killed (swipe away) | the session is still recorded: the worker samples while charging and `onStopped` records the end state | `dumpsys jobscheduler` before, database after | NOT VERIFIED |
| C4 | iOS | Unplugged at 20-60 %. Open the app (a sample is taken), plug in, leave the app **open and the screen on** (Settings -> Display: Auto-Lock Never for the test) until the battery has risen by 5 % or more, unplug, keep the app open | a session appears with Battery `a% -> b%`; **mAh and Wh carry the Estimated badge** (iOS has no charge counter: they come from the percentage and the capacity from section 4); if the capacity is unknown the energy rows say so instead of showing numbers; Wall Energy Estimate and Cost are Estimated | screenshot of the sheet; `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier pl.wattbyte.app --source Documents/wattbyte.db --destination /tmp/wb-ios.db` then `sqlite3` as above (debug build only) | NOT VERIFIED |
| C5 | iOS | Repeat C4 with the app **in the background and the phone locked** for the whole charge | the session may be missing, shorter or marked "Times are approximate: samples were far apart.": record exactly what happened. This is expected iOS behaviour, not a bug, as long as the app invents nothing | screenshot, the database rows | NOT VERIFIED |
| C6 | both | A charge shorter than 1 minute, and a plug-in with no percentage change | no session row is created for under a minute (the builder needs 2 samples and at least 1 minute); a zero-change session, if recorded, shows 0 and never NaN | database, screenshot | NOT VERIFIED |
| C7 | both | Plug in and unplug twice within 30 minutes (Android) | two sessions on Android (gap rule 30 min applies to samples); on iOS the gap rule is 8 hours, so write down what you get | database | NOT VERIFIED |
| C8 | both | Dashboard while charging | "Charging now" / "since hh:mm" appears and disappears on unplug; the charging note for iOS says it is tracked while the app is open or refreshed in the background | screenshots | NOT VERIFIED |

## 6. Network counters

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| N1 | iOS | Settings -> Cellular -> note "Current Period" and reset statistics at the bottom; turn Wi-Fi off; use the phone for about 5 minutes (browse, stream 2 minutes); open WattByte | Dashboard "Data Used" Mobile is of the same order as the system's cellular delta (system totals include every app, WattByte too), labelled **Estimated** ("On iOS, data totals are sampled while WattByte runs or refreshes in the background, so they are estimates."); Wi-Fi is about 0 | screenshots of both screens | NOT VERIFIED |
| N2 | iOS | Wi-Fi on, cellular off, transfer something large; open the app | Wi-Fi total rises by about that amount; `en0` only (hotspot or VPN interfaces are not counted) | screenshots | NOT VERIFIED |
| N3 | iOS | App restart: kill and relaunch | the day's totals persist (counters are stored in the `meta` table as the last snapshot and folded into the daily table); no double counting; no drop to 0 | screenshots before and after | NOT VERIFIED |
| N4 | iOS | Reboot the phone (counters reset to 0), open the app | the day's total keeps growing from the earlier value instead of dropping or going negative (the boot time changed, so the fold restarts from the new counters) | screenshots; the boot time comparison is the `kern.boottime` check | NOT VERIFIED |
| N5 | iOS | Leave the phone for hours with the app not opened, then open it | the bytes accumulated meanwhile are spread linearly over the days they cover and marked Estimated (the app could not sample in between) | screenshot, History rows | NOT VERIFIED |
| N6 | iOS | A 32-bit counter wrap (about 4 GB on one interface since boot) | no negative or huge jump; documented as handled by the folder; only testable with a long session, mark NOT APPLICABLE if it does not occur | database | NOT VERIFIED |
| N7 | Android | With Usage access granted compare Dashboard Mobile and Wi-Fi totals for today with Settings -> Network & internet -> Data usage (and `adb shell dumpsys netstats \| head -60` for the raw buckets) | totals equal what the system reports within a small tolerance; not labelled Estimated | screenshots | NOT VERIFIED |
| N8 | Android | Data by App: open the screen, pick Last 7 Days | rows per app with the right names, plus Other apps / System / Tethering / Removed apps groups; sums equal the total; no numbers without Usage access | screenshot | NOT VERIFIED |
| N9 | Android | Revoke Usage access (Settings -> Special app access -> Usage access), reopen the app | the "Allow usage access" card returns; no crash; no stale numbers shown as new | screenshot | NOT VERIFIED |
| N10 | Android | Reboot the phone, open the app | history survives (system history plus the app's own table) | screenshot | NOT VERIFIED |

## 7. Background execution matrix

Real iOS limits (do not write "works" for anything the platform does not guarantee): a `BGAppRefreshTask` is requested with an
earliest begin date of 15 minutes, but iOS chooses when, how often and whether to run it (it learns from how you use the
phone); it gets roughly 30 seconds; it does not run if Background App Refresh is off for the app or globally, in Low Power
Mode, or after the user force-quits the app until the next manual launch. Test it, report what happened, and keep the
expectation "occasionally, not on a schedule". The background refresh (WorkManager on Android, `BGAppRefreshTask` on iOS) is
local-only by design and is not gated by the backend configuration. Dart schedules it only after the start-up check has
passed, so a build that stops at the "Invalid build configuration" screen never schedules it; on iOS the task handler is
registered natively in `AppDelegate` at launch regardless, and a task scheduled by an earlier valid build can still fire.

| ID | State | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|---|
| G1 | foreground | both | Keep the app open for 3 minutes while charging or downloading | Dashboard updates about every 60 s and on pull-to-refresh | screen recording | NOT VERIFIED |
| G2 | background (app switcher, screen on) | iOS | Leave the app in the background for 30 minutes with a download running | no crash; values update only after reopening or a background refresh: record whether a background refresh happened (the `refresh` row in the sync status or the widget changing without opening the app) | `xcrun devicectl device info processes --device <udid> --filter "Name CONTAINS 'Runner'"` (process state), widget screenshot | NOT VERIFIED |
| G3 | locked | iOS | Lock the phone for 1 hour | same as G2; nothing promised | as G2 | NOT VERIFIED |
| G4 | terminated by the system | iOS | Open many apps so WattByte is evicted; wait; check the widget and the app | a background refresh *may* relaunch it; otherwise data catch up on the next launch | as G2 | NOT VERIFIED |
| G5 | force-quit by the user | iOS | Swipe the app away in the switcher and wait 1 hour | no background refresh runs (documented iOS behaviour); the next manual launch catches up | widget screenshot | NOT VERIFIED |
| G6 | trigger a refresh on demand | iOS | Debug build run from Xcode: pause, then in the lldb console `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"pl.wattbyte.refresh"]` | the Dart refresh pipeline runs in the background isolate and the widget values update | Xcode console | NOT VERIFIED |
| G7 | Background App Refresh off | iOS | Settings -> General -> Background App Refresh -> off for WattByte | no background runs; no crash; the app works in the foreground | observation | NOT VERIFIED |
| G8 | background | Android | Home button, wait 30 minutes while charging | the charging worker keeps sampling each minute; `adb shell dumpsys jobscheduler \| grep -B2 -A8 wattbyte` lists the job; a periodic refresh runs about every 15 minutes (Doze and App Standby can delay it) | dumpsys output, database rows with `source = worker` | NOT VERIFIED |
| G9 | Doze | Android | Screen off, unplugged, stationary for 1 hour (`adb shell dumpsys deviceidle` shows `mState`) | refresh is deferred but not lost; no crash; data totals are complete anyway because they come from NetworkStats history | dumpsys output | NOT VERIFIED |
| G10 | force-stopped | Android | `adb shell am force-stop pl.wattbyte.app`, plug in | no worker runs until the app is opened once (Android rule for force-stopped apps); after opening it recovers | dumpsys jobscheduler | NOT VERIFIED |
| G11 | after reboot | Android | Reboot, do not open the app, plug in a charger | WorkManager reschedules itself (RECEIVE_BOOT_COMPLETED is declared by WorkManager): the charging job exists again | `dumpsys jobscheduler` | NOT VERIFIED |
| G12 | battery optimization | Android | Settings -> Apps -> WattByte -> Battery: Restricted | background work stops; the app must not crash and the foreground still works | observation | NOT VERIFIED |

## 8. Notifications

All notifications are optional and generated on the device (Settings -> Notifications).

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| T1 | iOS | Permission: Settings -> Notifications -> WattByte shows Alerts and Sounds; decline once and re-enable in system settings | declining does not break the app; the in-app switches stay consistent | screenshots | NOT VERIFIED |
| T2 | Android 13+ | The `POST_NOTIFICATIONS` prompt appears only after the explanation; `adb shell dumpsys package pl.wattbyte.app \| grep POST_NOTIFICATIONS` shows `granted=true` afterwards | as described | screenshot, dumpsys line | NOT VERIFIED |
| T3 | both | Turn on "Mobile data threshold" with a low threshold and use data | one notification "Mobile data - You've used X of mobile data today." per day | screenshot of the notification | NOT VERIFIED |
| T4 | Android | Turn on "Charging session completed" and finish a session of at least 2 minutes (C1) | one native notification from `ChargingNotifier` with the bolt icon; none for plug-ins shorter than 2 minutes | screenshot | NOT VERIFIED |
| T5 | iOS | Same switch, finish a session while the app is open | a local notification "Charging session completed"; it cannot appear for a session the app never saw | screenshot | NOT VERIFIED |
| T6 | both | Weekly energy summary / above-average rules | appear at most once per period (`sentNotifications` keys); check there is no duplicate after relaunch | screenshot | NOT VERIFIED |
| T7 | Android | The small icon of the app's own (Flutter) notifications | known issue: they use `@mipmap/ic_launcher` and may render as a plain white square; the charging notification uses the monochrome bolt. Record how it looks | screenshot | NOT VERIFIED |

## 9. Home-screen widgets

### iOS (WidgetKit `WattByteWidget`)

`WattByteWidget.swift` declares exactly `systemSmall`, `systemMedium` and `systemLarge` and has a layout for each. No lock-screen
(`accessory*`) or `systemExtraLarge` family is declared. The large widget has never been run anywhere.

| ID | Steps | Expected | Evidence | Result |
|---|---|---|---|---|
| W1 | Long-press the home screen -> + -> WattByte. Check the sizes offered | exactly Small, Medium and Large are offered | screenshot of the gallery | NOT VERIFIED |
| W2 | Add Small | header with bolt, one stat "Data today" with a value; never a truncated "k..."; text readable in light and dark | screenshots | NOT VERIFIED |
| W3 | Add Medium | three stats in a row: Data, Energy, Cost; values are not cut off (the medium layout once cut "~0.0000 kWh"; check it) | screenshots | NOT VERIFIED |
| W4 | Add Large | header + "Data today", "Energy today", "Monthly data", "Monthly cost" in a 2x2 grid | screenshots | NOT VERIFIED |
| W5 | Before the first data exists | placeholders show an em dash, not zeros or invented values | screenshot | NOT VERIFIED |
| W6 | Use the app, then watch the widget | values change after the app publishes (foreground refresh calls `reloadTimelines`); the widget also asks for a reload every 30 minutes but iOS decides | screenshots with timestamps | NOT VERIFIED |
| W7 | Change the app language to Polish and refresh | the labels the app publishes ("Dane dzisiaj", ...) are Polish; the widget name and description in the gallery stay English (not localized, known) | screenshots | NOT VERIFIED |
| W8 | Light and dark appearance, and iOS 18 tinted/clear icon styles | readable in all; record any problem | screenshots | NOT VERIFIED |

### App Group shared state (iOS)

| ID | Steps | Expected | Evidence | Result |
|---|---|---|---|---|
| X1 | After W6 copy the shared container's preferences: `xcrun devicectl device copy from --device <udid> --domain-type appGroupDataContainer --domain-identifier group.<bundle id> --source Library/Preferences/group.<bundle id>.plist --destination /tmp/wb-group.plist` and `plutil -p /tmp/wb-group.plist` | 13 keys (data_today, energy_today, cost_today, data_month, cost_month and eight labels) with the same strings the widget shows | plist dump | NOT VERIFIED |
| X2 | Install a build signed with a different team or without the App Group capability | the widget shows the em dash (no shared container): the failure is visible, not silent garbage | screenshot | NOT VERIFIED |
| X3 | Delete the app | the widget goes back to the placeholder; reinstalling and opening the app fills it again | screenshots | NOT VERIFIED |

### Android widget

| ID | Steps | Expected | Evidence | Result |
|---|---|---|---|---|
| W9 | Add the WattByte widget; resize it small -> medium -> large | layout switches by size (small: Data today; medium: Data/Energy/Cost; large: today and month figures); no crash while resizing | screen recording | NOT VERIFIED |
| W10 | Tap the widget | opens the app | recording | NOT VERIFIED |
| W11 | `adb shell dumpsys appwidget \| grep -A6 wattbyte` | provider registered with the sizes from `wattbyte_widget_info.xml` | output | NOT VERIFIED |
| W12 | Use the app, then watch the widget | updates after the app or the periodic refresh publishes (the system's own `updatePeriodMillis` is 30 minutes and only a floor) | screenshots | NOT VERIFIED |

## 10. Appearance, language, accessibility

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| L1 | both | System light and dark; Settings -> Appearance: System, Light, Dark | the whole app follows; buttons readable on light cards | screenshots | NOT VERIFIED |
| L2 | both | Polish: change the phone language | translated UI, Polish number format (81,23 MB) | screenshots | NOT VERIFIED |
| L3 | both | Largest text size | the app caps scaling at 1.35x; nothing overflows; the tab bar stays usable | screenshots | NOT VERIFIED |
| L4 | iOS | Launch screen in light and dark, after a cold start | page background colour with the mark, no white flash in dark | screen recording | NOT VERIFIED |
| L5 | Android 12+ | Cold start | system splash with the mark on the page background colour; Android 10/11 shows the `launch_background` window | recording | NOT VERIFIED |

## 11. Account, sync and a release-configuration check

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| Y1 | both | Settings -> Cloud sync on; "Sync now" | counts change from waiting to synced; PostgreSQL has `daily_usage` rows for this device; only daily totals were sent | screenshot, `select * from daily_usage` | NOT VERIFIED |
| Y2 | both | Airplane mode, then back | queue keeps pending and drains by itself | screenshots | NOT VERIFIED |
| Y3 | iOS | Run a **Release** build on the device (`flutter run --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=http://<lan-ip>:<port>`, needs a team) | the build compiles (the address is not empty) but the app **refuses** the http address (production requires https): it stops at the "Invalid build configuration" screen, which names the rule (`API_BASE_URL must use https in production`, never the address) and shows no development hints. It does **not** continue to Welcome, to the device setup or to any local-only mode, and no `LOCAL ONLY DEVELOPMENT MODE` strip appears (Y8 repeats this without `APP_ENV`); no Local Network prompt appears; the Info.plist of the build has none of `NSAppTransportSecurity`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` | screenshot; `plutil -p build/ios/iphoneos/Runner.app/Info.plist` | NOT VERIFIED |
| Y4 | Android | Run a **release** build (needs an upload key, `docs/RELEASE.md`; build with `--dart-define=APP_ENV=production` and `--dart-define=API_BASE_URL=https://<host>`, or `--dart-define-from-file=config/production.json`: a release build without `API_BASE_URL`, or with `LOCAL_ONLY_DEV`, does not compile) | the merged release manifest has no `usesCleartextTraffic=true` (`aapt2 dump xmltree`/`dumpsys package`); R8 did not break the charging worker or the widget (repeat C1 and W9) | output | NOT VERIFIED |
| Y5 | both | Delete the account in the app | the account and cloud rows disappear; local statistics stay | screenshot, SQL | NOT VERIFIED |
| Y6 | both | Install a **debug** build made without any define (`flutter run` / `flutter build ... --debug`, no `API_BASE_URL`, no `LOCAL_ONLY_DEV`) and start it | the "Invalid build configuration" screen, with the rule `API_BASE_URL is required` and the two `flutter run` hints; no Welcome, no sign-in form, no device setup, no strip. (The build itself succeeds: a green `flutter build ... --debug` only proves it compiles, not that the app starts) | screenshot | NOT VERIFIED |
| Y7 | both | Install a **debug** build made with `--dart-define=LOCAL_ONLY_DEV=true` and no `API_BASE_URL`, start it | the device setup opens at once (no Welcome, no Register / Login); the strip `LOCAL ONLY DEVELOPMENT MODE` is above every screen, in light and dark mode, and overlaps neither the status-bar icons nor the app's top bar; there is no account and no cloud action (no backend). The strip is a visual developer aid: VoiceOver / TalkBack do not read it out (known; a route's `BlockSemantics` hides it), record what you hear. Then reinstall with the build of P2: Welcome first, and no strip anywhere | screenshots of both builds | NOT VERIFIED |
| Y8 | both | Run a **release** (or profile) build made with an `http` address and **no** `APP_ENV` (`flutter run --release --dart-define=API_BASE_URL=http://<lan-ip>:<port>`; iOS needs a team, Android the upload key: `docs/RELEASE.md`) | a build without `APP_ENV` is validated as production: it compiles (the address is not empty) but stops at the "Invalid build configuration" screen, which names `API_BASE_URL must use https in production` (never the address) and shows no development hints; no Welcome, no setup, no strip | screenshot | NOT VERIFIED |

## 12. Battery capacity: remaining device verification

The design / estimated full charge split (`docs/BATTERY_CAPACITY.md`) is covered by unit, widget and PostgreSQL integration
tests (`docs/REGRESSION_TESTS.md`, "Battery capacity"), run against fakes, a simulated charge counter and a synthetic legacy
database. **Nothing below has been run on a physical phone**: every row is NOT VERIFIED. These are exactly the questions
that only hardware, or an install and a database that already hold real data, can answer. Use real batteries and real
chargers (section 0); record the phone, the Android build and the app build with each result.

| ID | Platform | Steps | Expected | Evidence | Result |
|---|---|---|---|---|---|
| K1 | Android (at least three makers, for example Google, Samsung and one of Xiaomi, OnePlus or Oppo) | Unit and sign of the charge counter. At about 80 % unplugged, then while charging, then at 100 % on the charger: `adb shell dumpsys battery` (`Charge counter`) and the app's `battery_samples` (`charge_uah`, `energy_nwh`); open Settings -> Device each time | the counter is in microampere-hours: about `capacity in mAh x 1000 x level / 100` (for a 4000 mAh battery at 80 % roughly 3 200 000). The app turns a value that is not positive into "no counter" and never guesses. A phone that reports **milliampere-hours** (about 3 200) or a counter that is **negative while discharging** must produce no estimate and no crash, and must not show a value off by a factor of 1000. Write down per phone: unit, sign when plugged and unplugged, whether it moves in steps, whether it resets at 100 % or after a reboot | `dumpsys battery` output, `sqlite3 /tmp/wb.db "select time_ms, level, plugged, charge_uah, energy_nwh from battery_samples order by time_ms desc limit 20"`, screenshots, one table row per phone | NOT VERIFIED |
| K2 | Android | Behaviour at 100, 95 and 50 % on a real battery. Reset the statistics first (Settings), then take one reading at each level (open the app; the collector runs on open): 100 %, then about 95 %, then about 50 %, noting the time of each | 100 % and 95 %: "Confidence: high"; about 50 %: "Confidence: low". Readings at 100 and 95 % agree within a few percent; the 50 % reading may differ more (a fuel gauge is not linear), which is why it is only "low". After the 100 % reading a later 50 % reading does **not** overwrite it (the shown value and the `meta` rows stay those of the 100 % reading for 30 days); below 40 % nothing changes | screenshots of Settings -> Device after each reading, `meta` rows (`calibrated_capacity%`) after each, `dumpsys battery` at each point | NOT VERIFIED |
| K3 | Android | Does `BATTERY_PROPERTY_ENERGY_COUNTER` exist, and is its Wh plausible? On each phone of K1 look at `battery_samples.energy_nwh` and, after a reading at 95 % or more, `meta` key `calibrated_capacity_wh`; then, on a phone registered to the API, `estimated_full_charge_capacity_wh` in PostgreSQL | where the counter is supported, the estimate Wh is consistent with the mAh estimate: `Wh / (mAh / 1000)` is the cell voltage, in practice 3.6 to 4.5 V (the app accepts 2.5 to 5 V and drops a Wh outside it); where the counter is not supported, or reports zero or a negative number, Wh is absent and the mAh estimate still works. The Wh is never computed from an assumed voltage | `sqlite3` output, SQL output, one table row per phone (counter present / absent, value, implied volts) | NOT VERIFIED |
| K4 | Android | Ratio of the estimate to the catalog design capacity on aged batteries. At least one almost new phone and one old or visibly aged phone of a model in the catalog, each read at 95 % or more | the app has no expected health value; record `estimate / design`. A healthy battery reads near or somewhat below 100 %; an aged one clearly lower. A ratio below 0.30 or above 1.20 on a phone that is not broken means a wrong catalog entry (a variant with another battery) or a wrong counter unit, and is a finding: `calculateEstimatedBatteryHealth` (domain only, no UI) refuses a ratio outside 0.30 to 1.20. If the phone has its own battery health page (Samsung "Battery information", Pixel "Battery health"), note it as a sanity reference only; it is not a ground truth | table: phone, age, catalog mAh, estimate mAh, ratio, confidence, the phone's own figure when it has one | NOT VERIFIED |
| K5 | iOS (a physical iPhone **and** the simulator) | Identifiers. Setup review screen and Settings -> Device on the device and on a simulator; for a model the catalog lists and one it does not (as of writing an iPhone 18 series model) | the real `utsname.machine` (for example `iPhone16,1`) is matched and the catalog design capacity shown with "Detected from device specifications"; the simulator shows the **simulated** model through `SIMULATOR_MODEL_IDENTIFIER`, not the Mac; a model in no catalog shows "Battery capacity unavailable" and "Enter manually". For the iPhone 17 Pro and Pro Max the catalog lists the SIM variant; eSIM-only variants carry a larger battery under the same identifier (catalog `remark`): record which figure the phone gets. There is **no** "Estimated full charge capacity" row on iOS, ever, and no private API is involved | screenshots, `xcrun devicectl device info details --device <udid>` model, PostgreSQL `devices.model_identifier`, `design_capacity_source`, `estimated_full_charge_capacity_mah` (NULL) | NOT VERIFIED |
| K6 | both | Upgrade from the previous build, on a phone that has the old build installed **with its data**. Install the previous build, create the account, finish setup and let it collect (Android: charge counter readings); then install the new build **over it** without uninstalling (`adb install -r`, or a run from Xcode over the installed app). Cover three starting states, on one or more phones: (a) a capacity from the catalog; (b) a capacity typed by hand; (c) Android only: a capacity the previous build took from the charge counter (its source line said "Measured by the system" or "Estimated from a partial system reading") | the app opens on the Dashboard with no setup and no crash; a catalog capacity stays, with "Detected from device specifications"; a manual capacity stays "Chosen manually"; a capacity the old build took from the charge counter is now "Battery capacity unavailable" unless the catalog knows the model, and the old reading shows as "Estimated full charge capacity" with a confidence derived from its level; with airplane mode on for the first launch, a model that is only in the API's catalog still shows its cached capacity ("From the WattByte device database"); the old preference keys are gone after the first saved change; the energy figures stay finite. The mapping to check is "Mobile persistence" in `docs/BATTERY_CAPACITY.md` | the preference file before and after (Android: `adb shell run-as pl.wattbyte.app cat shared_prefs/FlutterSharedPreferences.xml`; iOS: `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier pl.wattbyte.app --source Library/Preferences/pl.wattbyte.app.plist --destination /tmp/wb-prefs.plist` then `plutil -p`; keys carry a `flutter.` prefix), the `meta` rows before and after, screenshots | NOT VERIFIED |
| K7 | server | Upgrade of a **populated** database. On a copy of a real database (never the only copy) that holds `devices` rows of every old source, plus rows with a number and no source: run `pnpm migrate` on the copy; compare before and after row by row against the mapping table in `docs/BATTERY_CAPACITY.md`; time it and note the lock on `devices` for the real row count; then start the new API on the copy and register once from the new app and once from the old build | the row count is unchanged; every row matches the table (catalog and manual rows keep their numbers under the new names; `unknown` rows lose any number; measured rows move to the estimate group with `high` / `low` and **no design number is left**; a number with no source is cleared); `\d devices` shows the new constraints and none of the old names; the new app registers with 201; an old app build that still sends the old field names gets 201 and its capacity is ignored (the request schema drops unknown keys); the migration is recorded once. The column rename is **not zero-downtime**: confirm the window the migration needs and that the old API is stopped meanwhile. The automated test ran this only on a synthetic legacy database in a local container | SQL before and after, `\d devices`, API log, timing | NOT VERIFIED |
| K8 | Android | When the estimate reaches the server. Fresh install, create account, finish setup, then read `devices` for the row; open the app for a few minutes at 95 % or more; tap "Detect again" and read the row again | after setup the row has the design capacity and, if the collector had not yet read the battery, **no estimate** (`estimated_full_charge_capacity_mah` NULL); after "Detect again" it carries the estimate with its confidence and `androidChargeCounter`. There is no periodic re-upload, so the server value can lag the phone: confirm and write down how long | SQL output after each step, screenshots | NOT VERIFIED |
| K9 | Android | A phone whose model is in no catalog (or a manual reset of the capacity through "Detect again" on such a phone) with a charge counter | Settings shows "Battery capacity unavailable" **and** the estimate row; the Energy and mAh figures come out as `~` estimates based on the estimate; the JSON export (`settings`) has `designCapacityMah: null`, `designCapacitySource: "unknown"`, `estimateCapacityBasis: "estimatedFullCharge"`; the estimate is never shown under "Battery Capacity" | screenshots, the exported JSON | NOT VERIFIED |

## 13. Sign-off

| Field | Value |
|---|---|
| Tester / date | |
| App version and build | |
| Device, OS | |
| Sections run | |
| Open bugs (links) | |
| Overall | NOT VERIFIED |
