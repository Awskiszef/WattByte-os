# Automatic setup

How WattByte configures itself after the account is created, what it detects,
where every value comes from, and what the user can override. Nothing in this
flow asks the user for a number the app can establish itself; nothing in it
invents a number the app cannot establish.

## Flow

```
Launch
  └─ Splash (restore session: SecureTokenStore → refresh if expired → GET /me)
       ├─ no session   → Welcome → Create account | Sign in   (Flutter → API → PostgreSQL)
       │                 (also when the restore itself fails: an error is "no session")
       └─ session      → setup finished? → Dashboard
                                        → Device setup
Device setup
  ├─ "Setting up WattByte…"  region ∥ device/battery ∥ account settings → electricity price
  ├─ "Your setup"            one review screen, Edit per value, one Continue
  ├─ Permissions             explanation first, system prompt only on tap
  └─ Dashboard
```

The rule is `startDestination()` in `apps/mobile/lib/setup/setup_controller.dart`
(unit-tested in `test/config/start_destination_test.dart`: unauthenticated →
welcome; authenticated + incomplete → setup; authenticated + complete →
dashboard; a failed session restore, an error without a value, → welcome instead
of throwing inside `StartGate`). The account comes before any configuration:
currency, price, battery and sync are not reachable without it, in every build
mode, debug included.

The single exception is the explicit development mode `LOCAL_ONLY_DEV=true`
(debug builds only): there is no backend and no account, so the app goes straight
to the device setup and then the dashboard, under a red strip that reads
`LOCAL ONLY DEVELOPMENT MODE`. `startDestination` receives that mode as a flag
(`AppConfig.isLocalOnlyDev`, true only for a debug build started with
`LOCAL_ONLY_DEV=true` in the development environment) and nothing else can skip the
account: a build without `API_BASE_URL` is not a local build but an invalid
configuration (a compile error `[WB-CONFIG-001]` in profile and release, the
"Invalid build configuration" screen at start-up otherwise), and a missing or broken
address never reaches this rule. See `docs/CONFIGURATION_MOBILE.md`, "Backend mode
and the release guard".

## Region and currency

`RegionDetectionService` (`lib/setup/region_detection.dart`) tries, in order:

| Source | Where it comes from | Confidence |
|---|---|---|
| `deviceRegion` | iOS Region setting (`Locale.current.region`), Android system locale country | 0.9 |
| `deviceLocale` | country part of the preferred-language tag (`en-PL`) | 0.7 |
| `backendCountry` | `GET /api/v1/region`: a proxy header such as `cf-ipcountry`, only when the deployment sets `COUNTRY_HEADER` | 0.5 |
| `manual` | Settings → Region | 1.0 |

No location permission is requested and no location is stored; the API neither
logs nor stores the derived country. Currency follows the country through an
explicit ISO 3166 → ISO 4217 table (`kCurrencyByCountry`, e.g. PL → PLN, US →
USD, GB → GBP, DE/FR → EUR, CH → CHF, CZ → CZK). A country outside the table gets
no currency and the user is asked, instead of a CLDR fallback that silently
answers USD for unknown locales.

Detection runs during the first setup, after a manual region change and on
"Detect again" — never on every launch, so a weekend in Germany does not turn
PLN into EUR. A currency chosen by hand has `currencySource = manual` and is
never replaced; "Use detected currency (PLN)" in Settings switches back. A currency or
region that came from the user's account is `accountSynced` (with the account's origin as
`originalSource`), not `manual`: the model, the priorities and the migration are in
`docs/SETTING_SOURCES.md`.

## Device and battery capacity

Two different facts are kept apart (`docs/BATTERY_CAPACITY.md` is the binding design):

* **Design capacity**: the nominal capacity of the phone *model*, a published figure from a device
  database or a number the user typed. This is what setup detects, shows as "Battery Capacity" and
  stores in `Settings`.
* **Estimated full charge capacity**: an *estimate* of what *this* battery holds today. It is not
  detected during setup and is never a setting; see below.

The Android `BATTERY_PROPERTY_CHARGE_COUNTER` is the charge **currently stored** in the battery, not a
capacity. It is never used as, or written to, a design capacity.

### Design capacity: sources and order

`DeviceSpecificationService` (`lib/setup/device_specification.dart`) resolves the nominal capacity in this
order (`DesignCapacity.resolve`: the first known candidate wins):

1. **WattByte device database** bundled with the app (`assets/device_specs/devices.json`); source
   `localDeviceDatabase`
2. **backend device database**: the same catalog served by
   `GET /api/v1/devices/specifications/:identifier` for models newer than the app build; asked only when
   the bundled catalog does not know the model, and a cached answer (SharedPreferences, for offline
   launches) is used before any request; source `backendDeviceDatabase`
3. **manual value**: "Enter manually" (offered when the above found nothing) or Settings → Battery
   Capacity at any time; source `manual`. A stored manual value is **sticky**: automatic detection never
   replaces it; only the explicit "Detect again" does
4. **unknown**: "Battery capacity unavailable", source `unknown`, no number. A correct answer; the app
   never substitutes a "typical" 4 000 mAh

`manufacturerSpecification` (a figure taken directly from the maker's specification) exists in the model
but no code path produces it yet. A detection that finds nothing never downgrades a capacity the app
already has. Android and iOS behave the same here: the Android charge counter is not consulted for the
design capacity.

Identifiers: iOS `utsname.machine` (`iPhone16,1`; `SIMULATOR_MODEL_IDENTIFIER` on the simulator),
Android `Build.MODEL` (`Pixel 8`, `SM-S921B` matched by prefix because regional suffixes vary). No private
Apple API, no undocumented system property.

The catalog lives once, in `packages/device-specs/src/devices.json`; the mobile asset is a copy and
`pnpm device-specs:check` fails CI when they drift (`pnpm device-specs:sync` copies). Every entry is a
published nominal (design) figure, `designCapacityMah` and, where one exists, `designCapacityWh`
(manufacturer specification, regulatory filing or teardown); models without a documented figure, including
the iPhone 18 series at the time of writing, are absent on purpose. The derived nominal voltage is present
only where a published Wh exists; otherwise the calculator keeps its 3.85 V default and marks the energy as
estimated.

### The estimated full charge capacity is a separate thing

On Android the collector extrapolates every battery reading: `charge counter / (level / 100)`, only from a
level of 40 % or more and only when the result is a plausible battery (100 – 30 000 mAh). It keeps the best
reading it has seen, with a confidence that follows the level (`high` from 95 %, `medium` from 75 %,
`low` from 40 %); Wh only from a valid `BATTERY_PROPERTY_ENERGY_COUNTER`. Its places:

* **Settings → Device**: a read-only row "Estimated full charge capacity", `~3 274 mAh`, "Estimated from the
  battery charge counter. Confidence: high". Absent when there is no estimate. The setup review screen
  shows the design capacity only.
* **Device registration**: setup reads the collector's estimate and sends it with the design capacity as a
  second, separate group.
* **Energy estimate**: used for the `% -> mAh` estimate only when no design capacity is known.

An estimate is always labelled as one and never replaces the design capacity. There is no Battery Health in
the UI (`calculateEstimatedBatteryHealth` is a domain function only).

### iOS

iOS has no public API for the charge counter or the nominal capacity, and WattByte uses no private one.
There is therefore no estimate on iOS, and the design capacity comes only from the catalog by model
identifier (or from the user). A model that is in no catalog (the iPhone 18 series was missing at the time
of writing) shows "Battery capacity unavailable" with "Enter manually": a correct answer, which is exactly
why the catalog exists.

### Device-bound, not account-bound

Battery facts are device-bound: they are sent with the device registration (`POST /api/v1/devices`:
`modelIdentifier`; design capacity `designCapacityMah`, `designCapacityWh`, `designCapacitySource`;
estimate `estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`, `fullChargeCapacitySource`,
`fullChargeCapacityConfidence`) and stored on the `devices` row, so an account with an iPhone, an Android
phone and a tablet keeps one record per device. Each group is replaced as a whole when its source is
given; a registration that leaves a group's source empty keeps the stored group. The registration sent by
setup carries the design capacity the app **keeps** (a manual value survives detection), so the server never
disagrees with the app. Rules, wire format and the migration of existing rows: `docs/BATTERY_CAPACITY.md`.

## Electricity price

```
Flutter → GET /api/v1/electricity-price?country=PL → ElectricityPriceService → EurostatElectricityPriceProvider → Eurostat
```

The app never calls Eurostat. `EurostatElectricityPriceProvider`
(`apps/api/src/modules/electricity/eurostat.ts`) queries dataset `nrg_pc_204`
(electricity prices for household consumers, bi-annual) with:

- `siec=E7000` electricity, `nrg_cons=KWH2500-4999` consumption band DC (the
  standard "typical household" band), `tax=I_TAX` all taxes and levies
  included, `currency=NAC` national currency, `unit=KWH`;
- `lastTimePeriod=3`, taking the newest half-year that carries a value (the
  latest period is sometimes still empty for a country).

Spot, day-ahead and wholesale prices are never used: WattByte estimates what a
household pays. The result is the shared model `ElectricityPrice`
(`countryCode`, `currency`, `pricePerKwh`, `period` such as `2026-S1`, `source`
∈ eurostat | government | manual | fallback, `includesTaxes`,
`includesNetworkCosts`, `updatedAt`, `stale`). Country codes are validated as
ISO 3166-1 alpha-2 on the API; without `?country=` the account's saved country
is used.

### Cache and fallback

| Layer | Lifetime | On failure |
|---|---|---|
| API memory + `electricity_prices` table | `ELECTRICITY_PRICE_CACHE_HOURS` (default 168 h; Eurostat updates twice a year) | last known value with `stale: true`; nothing cached → 404 `electricity_price_unavailable` |
| App `Settings.autoPrice` | refreshed after 24 h, on launch, non-blocking | last known value stays; offline first setup shows "Electricity price will be updated when you're online." |

Concurrent requests for one country share a single source call. The dashboard
never waits for the price.

### Automatic vs manual

`electricityPriceMode` is `automatic` or `manual` (`Settings.priceMode`). In
automatic mode the app may update the price; in manual mode it never does. A
manual price is kept (`manualPricePerKwh`) even after switching back to
automatic, and the last automatic price is kept while manual is active, so both
switches are instant and offline. An automatic price is applied only when its
currency equals the display currency; a user who chose EUR in Poland sees
"price unavailable, enter manually" rather than a PLN number labelled EUR.

Settings → Electricity price shows the value, the mode, the basis ("Poland
household average"), the reporting period's fetch date and, when applicable,
"last known value". Costs derived from an average are labelled **Estimated
charging cost**; the word "exact" does not appear. AI never sets a price.

## Account-bound vs device-bound

| Account (`PUT /api/v1/me/settings`) | Device (`POST /api/v1/devices`) | Local only |
|---|---|---|
| `countryCode`, `currencyCode`, `electricityPriceMode`, `manualElectricityPrice`, and the origin of each decision (`countryCodeSource`, `currencyCodeSource`, `electricityPriceSource`) | `modelIdentifier`; design capacity (`designCapacityMah`, `designCapacityWh`, `designCapacitySource`); estimated full charge capacity (`estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`, `fullChargeCapacitySource`, `fullChargeCapacityConfidence`) | efficiency, units, theme, notifications, raw measurements (charge counter readings, samples) |

On setup the app also reads `GET /api/v1/me/settings`: values saved on another phone (a
manual tariff, a chosen currency, a detected region) rank above fresh detection and are
stored as `accountSynced`, with their origin as `originalSource`. A choice made on this
phone and not yet acknowledged by the account ranks above the account. These settings
belong to one account at a time on a phone (a second user of the phone starts from
nothing and the setup loads their own). All of it: `docs/SETTING_SOURCES.md`.

## Existing installs

`SettingsStore.load()` migrates preferences written by the old onboarding: a
stored price becomes `priceMode = manual` with `priceSource = migratedManual`, a stored
currency `currencySource = migratedManual` (a conscious choice that detection never
replaces; the first account to sign in adopts it and uploads it as `migratedManual`), a
stored capacity `designCapacitySource = manual` (it was typed by the user). The setup flag stays, so existing users go
straight to the dashboard; detection afterwards fills only what was never set
(region) and never replaces a conscious value. Tests: `test/setup_flow_test.dart`
("legacy preferences migration"); for the capacity split `test/settings_store_test.dart`
and `test/settings_persistence_test.dart` ("legacy capacity keys").

Builds from before the design / estimated split kept one capacity under three
differently named preference keys, with a source that could also be a system
measurement. Those keys are converted once on load: a measured value becomes an
unknown design capacity (the reading lives on as the collector's estimate), the
catalog sources are renamed and a manual value stays. The exact mapping, the
cached specification and the server rows are in `docs/BATTERY_CAPACITY.md`
("Mobile persistence", "Database migration").

## Privacy

- Region: device settings only; no GPS, no precise location, no storage of the
  coarse network country beyond the current request.
- Device: a model code shared by millions of phones; no serial number, IMEI,
  MAC or advertising id (`DeviceInfo` in `packages/wattbyte_system`). The
  registration adds the design capacity of that model with its source and, on
  Android, one estimated full charge capacity with its confidence; never the raw
  charge counter or the battery samples.
- Price: the API asks Eurostat for a country, never for a user; Eurostat sees
  the API's address, not the phone's.
- Account settings: four values and the origin of three of them, listed above; raw usage
  never leaves the phone.

## Tests

- `packages/device-specs/tests` — catalog lookups and sanity of every entry
- `apps/api/tests/electricity.test.ts` — Eurostat query shape, parsing (real
  response fixture), fallback to the previous half-year, cache, stale fallback,
  shared in-flight requests, endpoint validation
- `apps/api/tests/setup.test.ts` — account settings, device-bound specification,
  catalog endpoint, `/region`
- `apps/mobile/test/region_detection_test.dart`, `device_specification_test.dart`,
  `electricity_price_test.dart`, `setup_flow_test.dart` — the cases listed in the
  requirements (currency mapping, known/unknown devices, local / backend / cached
  catalog, manual stickiness, no "typical" value, the model and the estimate
  registered separately, provider/cache/manual price, routing by auth and setup
  state). The battery capacity model itself, the collector's estimate and the
  server side are in `docs/REGRESSION_TESTS.md` ("Battery capacity")
- `apps/mobile/test/e2e/api_e2e_test.dart` — the live path against a running
  API and PostgreSQL, including a real Eurostat call for PL

## Verification (2026-10-13)

Statuses follow `docs/VERIFICATION_STATUS.md`: SIMULATOR VERIFIED means observed on the
iOS Simulator against the local API and Docker PostgreSQL; nothing here was run
on a physical phone.

| Step | Result |
|---|---|
| `pnpm lint / typecheck / test / build` | PASS — API 47 tests (36 unit + 11 PostgreSQL integration, migration `0003` applied on a fresh and on the existing database), AI 64, device-specs 4 |
| `dart format --set-exit-if-changed`, `flutter analyze` | PASS (0 issues) |
| `flutter test` incl. `test/e2e` against the running API | PASS — 121 tests; the e2e suite fetched the real Eurostat PL price through the API (`2026-S1`, PLN) and registered a device with its battery specification |
| Kotlin plugin JVM tests (`gradle test`) | PASS |
| `flutter build ios --simulator --debug`, `flutter build apk --debug` | PASS |
| Fresh install (keychain reset) → Welcome → Create account → "Setting up WattByte…" → review | SIMULATOR VERIFIED (iPhone 18 Pro, iOS 27): `POST /auth/register` 201 → `GET /me/settings` → `GET /devices/specifications/iPhone19,2` 404 → `GET /electricity-price?country=PL` 200 → `PUT /me/settings` → `POST /devices` 201 |
| PL detected, PLN detected | SIMULATOR VERIFIED with the simulator Region set to `en_PL` ("Detected automatically"). With the host's default `en_PL@rg=uszzzz` (language English (Poland), Region override United States) the app reports US/USD — the Region setting wins over the language tag by design; Edit → PL then fetched the PLN price |
| Device detected | SIMULATOR VERIFIED: `iPhone` / `iPhone19,2` (`SIMULATOR_MODEL_IDENTIFIER`) |
| Battery capacity (design) | SIMULATOR VERIFIED both ways, with the build of that date, i.e. before the design / estimated split. iPhone 18 Pro (`iPhone19,2`): not in the catalog and iOS reports no capacity → "Battery capacity unavailable" + "Enter manually" (no invented value; the device row held no capacity, source `unknown`). iPhone 17 Pro simulator (`iPhone18,1`): "iPhone 17 Pro · 3,988 mAh · Detected from device specifications" from the bundled catalog, no `/devices/specifications` call needed; device row `3988` from the bundled catalog (after migration 0006 the two rows read `unknown` and `3988 / localDeviceDatabase`) |
| Electricity price returned | SIMULATOR VERIFIED: `1.27 PLN / kWh · Automatic · Poland (PL) household average · Updated: Oct 13, 2026`; server cache row `electricity_prices(PL, 1.2724, 2026-S1, eurostat)` |
| Review → Permissions → Dashboard | SIMULATOR VERIFIED; the notification prompt appeared only after the explanation screen and a tap, then "Granted"; the cost card reads "Estimated cost ~0.000 PLN" with the Estimated badge |
| Session restore | SIMULATOR VERIFIED: kill + relaunch → one `GET /me` → dashboard directly (no welcome, no setup, no price call while the cached price is fresh) |
| Manual price override | SIMULATOR VERIFIED: Settings → Use custom price → 0.95 → "Custom price"; PostgreSQL `manual / 0.95`; Use automatic price → 1.27 again, the custom value kept |
| Account settings on a second install | SIMULATOR VERIFIED: with the account's session still in the simulator keychain, a reinstall pulled country/currency from `GET /me/settings` instead of re-detecting |
| Android | BUILD VERIFIED only (debug APK). `Build.MODEL` lookup, charge-counter reading (and so the estimated full charge capacity) and Usage Access permission screen were NOT run on a device or emulator |
| Offline first setup, backend country header, iPad/landscape | NOT TESTED on the simulator (unit tests cover the offline price/cache branches) |

### Battery capacity split (2026-10-14)

The design / estimated full charge split is covered by unit, widget and PostgreSQL integration tests
(`docs/REGRESSION_TESTS.md`, "Battery capacity"). The rows above were observed before it, and this document
records no simulator or device run of the build with the split. In particular the Android charge counter, the
estimate on real batteries and the upgrade of an installed app are **NOT VERIFIED on a physical device**; the
checklist is "Battery capacity: remaining device verification" in `docs/DEVICE_TEST_PLAN.md`.
