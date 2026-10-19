# Battery capacity: design capacity vs estimated full-charge capacity

WattByte keeps two different facts about a battery apart. Mixing them is the bug this
document exists to prevent.

| | **Design capacity** | **Estimated full-charge capacity** |
|---|---|---|
| What it is | the nominal capacity of this phone *model* | an estimate of what *this* battery holds today |
| Fields | `designCapacityMah`, `designCapacityWh`, `designCapacitySource` | `estimatedFullChargeCapacityMah`, `estimatedFullChargeCapacityWh`, `fullChargeCapacitySource`, `fullChargeCapacityConfidence` |
| Comes from | device specification database (bundled, then API), or the user | Android `BATTERY_PROPERTY_CHARGE_COUNTER` extrapolated from the battery level |
| Can be exact? | it is a published figure | **never**: it is always an estimate and is always shown as one |
| iOS | catalog by `utsname.machine`; unknown model = "Battery capacity unavailable" | none (no public API; no private Apple API is used) |

`BATTERY_PROPERTY_CHARGE_COUNTER` is the charge **currently stored in the battery** (µAh),
not its capacity. It is only turned into a capacity estimate through
`charge / (level / 100)`, and the result is labelled `Estimated`. **It is never written to
a design-capacity field**, in the app, the API or the database. The API enforces this
structurally: the design source enum has no measurement member.

## Design capacity

Source (`DesignCapacitySource`, identical strings in Dart, the API, OpenAPI and PostgreSQL):

```
manufacturerSpecification   reserved: a figure taken directly from the maker's specification
localDeviceDatabase         bundled catalog (assets/device_specs/devices.json)
backendDeviceDatabase       the same catalog served by GET /api/v1/devices/specifications/:identifier
manual                      typed by the user
unknown                     nothing known; no number is stored
```

Priority among the candidates (`DesignCapacity.resolve`; the first *known* candidate wins):

```
1. local device specification database
2. backend device specification database   (cached for offline launches)
3. manual
4. unknown
```

`DeviceSpecificationService.detect()` runs steps 1 and 2 (the network is asked only when the
bundled catalog does not know the model; a cached backend answer is used before any request).
A manual value is not a detection result: it is typed in Settings and is **sticky**. Automatic
detection (`AutoSetup.apply`, first setup and every later automatic pass) never replaces a stored
`manual` value, and an unknown or failed detection never downgrades a known capacity. "Detect again"
is an explicit user action and does replace the stored value, a manual one too (see "Decisions and
known limits"). `manufacturerSpecification` is accepted wherever a source is read but no code
path produces it yet.

A model that is in no catalog stays `unknown` with no number. There is no "typical"
capacity, on any platform.

The catalog file uses the same names as the rest of the model: `designCapacityMah` and
`designCapacityWh` per entry (`packages/device-specs/src/devices.json`, copied to the app by
`pnpm device-specs:sync`).

## Estimated full-charge capacity

Computed by `FullChargeCapacityEstimator.estimate` (`apps/mobile/lib/domain/battery_capacity.dart`),
a pure function:

```
fraction = level / 100
mAh      = chargeUah / 1000 / fraction
Wh       = energyNwh / 1e9 / fraction        (only when BATTERY_PROPERTY_ENERGY_COUNTER is valid)
```

Nothing is estimated (the result is `unavailable`, confidence `none`) when:

* the charge counter is unsupported (`null`), zero, negative, `NaN` or infinite;
* the level is unknown (`< 0`), `0`, above 100, `NaN` or infinite, or below **40 %**
  (too far to extrapolate);
* the result is not a plausible battery: outside **100 – 30 000 mAh** (this also rejects a
  counter that reports mAh instead of µAh).

`Wh` is left `null` unless the energy counter is valid, finite, within 0 – 200 Wh and
implies a cell voltage between 2.5 V and 5.0 V. It is never derived from an assumed voltage.

Confidence follows the battery level of the reading:

| level | confidence |
|---|---|
| ≥ 95 % | `high` |
| 75 – 94 % | `medium` |
| 40 – 74 % | `low` |
| < 40 % / invalid | `none` (no estimate) |

Source (`FullChargeCapacitySource`): `androidChargeCounter` or `unknown`.

The collector keeps the best reading it has seen: a newer reading replaces the stored one
when its confidence is at least as high, or when the stored one is older than 30 days
(`FullChargeCapacityEstimator.prefer`). A 45 % reading therefore never overwrites a 100 %
reading taken last week.

Where it is used:

* **Settings → Device**: a read-only row "Estimated full charge capacity" with the value `~X mAh`
  and the text "Estimated from the battery charge counter. Confidence: high | medium | low",
  shown beside (never instead of) the "Battery Capacity" row, which is the design capacity with
  its source. The row is absent while there is no estimate. The setup review screen shows the
  design capacity only.
* **Device registration**: uploaded as the estimate group (see "Wire model").
* **Energy estimate**: the capacity for the `% -> mAh` estimate (`Settings.energyCalc`,
  the dashboard, the background refresh and the exports) is the design capacity; the estimate
  stands in **only when no design capacity is known**, whatever its confidence (low included).
  A design capacity always wins there. Measured session counters beat any capacity.
* **JSON export** (`Exporter.json`, `settings` block): `designCapacityMah` and
  `designCapacitySource` (the model's nominal capacity, `null` / `unknown` when not known) are kept
  apart from `estimateCapacityMah` and `estimateCapacityBasis` (`design`, `estimatedFullCharge` or
  `null`): the capacity the energy estimate actually used.

It is never presented as the nominal capacity.

## Estimated battery health (domain only)

```dart
EstimatedBatteryHealth? calculateEstimatedBatteryHealth(
    DesignCapacity design, EstimatedFullChargeCapacity fullCharge)
```

`fullCharge.mah / design.mah * 100`, only when **both** values are reliable, otherwise
`null` ("no result"):

* design: known source (not `unknown`), finite, 0 < mAh ≤ 30 000;
* estimate: available, source `androidChargeCounter`, confidence `high` or `medium`
  (a `low` confidence extrapolation from a half-charged battery is not good enough for a health figure);
* the ratio is between 0.30 and 1.20 (outside that the design figure or the reading is wrong,
  not the battery). A ratio above 1.0 is reported as 100 %.

`design = 4000`, `estimatedFull = 3600` gives `90 %`. There is no Battery Health UI yet.

## Wire model (API, OpenAPI, Dart client)

`POST /api/v1/devices` and `DeviceDto` / the account export carry, per device:

```
modelIdentifier
designCapacityMah, designCapacityWh, designCapacitySource
estimatedFullChargeCapacityMah, estimatedFullChargeCapacityWh,
fullChargeCapacitySource, fullChargeCapacityConfidence   (low | medium | high)
```

`GET /api/v1/devices/specifications/:identifier` returns `designCapacityMah` /
`designCapacityWh` (the catalog is design capacity by definition).

Field bounds (request schema, HTTP 400 otherwise): mAh 0.1 – 30 000, Wh 0.001 – 200, finite numbers
only. Cross-field rules enforced by the route (HTTP 400 `validation`, `validateBatteryCapacityGroups`):

* design: a number needs a `designCapacitySource`; `unknown` carries no numbers; a source other than
  `unknown` needs `designCapacityMah`; `designCapacityWh` needs `designCapacityMah`;
* estimate: a number needs a `fullChargeCapacitySource`; `unknown` carries no numbers and no
  confidence; the source `androidChargeCounter` and a `fullChargeCapacityConfidence` each need
  `estimatedFullChargeCapacityMah`, and an `estimatedFullChargeCapacityMah` needs a confidence;
  `estimatedFullChargeCapacityWh` needs `estimatedFullChargeCapacityMah`;
* the two groups are judged independently: a valid estimate does not excuse a broken design group.

`designCapacitySource: unknown` and `fullChargeCapacitySource: unknown` **without numbers** are valid
and mean "nothing known": they clear the stored group.

Each group is stored atomically: a registration that names a group's source replaces that
whole group (including its nulls); a registration that leaves the source `null` keeps what is
stored. A registration with every field `null` changes nothing. The database repeats the rules that keep
a number honest as CHECK constraints (migration 0006): a design number needs a source and `unknown`
carries none, an estimate needs the source `androidChargeCounter` and a confidence, Wh needs mAh. A second
writer therefore cannot store a number without provenance either. (A design source without a number is
allowed by the database, as legacy rows have it; only the route refuses to *accept* one.)

The previous names (`batteryCapacityMah`, `batteryCapacityWh`, `batterySpecificationSource`)
are gone from the API: they could not say whether a number was nominal or measured.

## Database migration `0006_battery_capacity_semantics.sql`

(`0004` and `0005` were already taken.) In place on `devices`, forward-only, in one transaction:

| old `battery_specification_source` | design group after | estimate group after |
|---|---|---|
| `localDatabase` | `localDeviceDatabase`, mAh/Wh kept | empty |
| `backendDatabase` | `backendDeviceDatabase`, mAh/Wh kept | empty |
| `manual` | `manual`, mAh/Wh kept | empty |
| `unknown` | `unknown`, numbers cleared | empty |
| `system` | **cleared** (mAh, Wh and the source are all `NULL`: it was not a design capacity) | `androidChargeCounter`, `high`, mAh/Wh moved (the old rule required a reading at ≥ 95 %) |
| `estimated` | **cleared** (as above) | `androidChargeCounter`, `low`, mAh/Wh moved (the old reading was somewhere in 40 – 94 %; `medium` cannot be told apart and is not invented) |
| `NULL`, with a number | **cleared** (a number with no provenance is not promoted to "design") | empty |
| `NULL`, no numbers | unchanged (`NULL`) | empty |

Details: a `system` / `estimated` row without a mAh value (Wh only) gets no estimate, because Wh alone is
not an estimate; a design Wh without a design mAh is dropped (Wh needs mAh); a catalog or manual row
without numbers keeps its source. "Empty" means every column of the group is `NULL`, the same state as a
device that never reported the group: the database does not claim `unknown` for a device that was never
asked, and the next registration of the installation fills the group in. The migration does not guess a
design capacity for a cleared row.

Columns are renamed (`battery_capacity_mah` → `design_capacity_mah`, `battery_capacity_wh` →
`design_capacity_wh`, `battery_specification_source` → `design_capacity_source`), the
`estimated_full_charge_capacity_mah|wh`, `full_charge_capacity_source` and
`full_charge_capacity_confidence` columns are added, the old source CHECK is dropped and replaced by
one CHECK per rule, and the two positive-value CHECKs are renamed (`devices_design_capacity_mah_positive`,
`devices_design_capacity_wh_positive`). Earlier migrations are untouched.

## Mobile persistence

`SharedPreferences` keys `wb.designCapacityMah`, `wb.designCapacityWh`, `wb.designCapacitySource`
replace `wb.batteryCapacityMah`, `wb.batteryCapacityWh`, `wb.capacitySource`. `SettingsStore.load()`
reads the old keys once, when the new source key is absent, and converts them: `localDatabase` →
`localDeviceDatabase`, `backendDatabase` → `backendDeviceDatabase`, `manual` → `manual`, a number with
no or an unrecognised source → `manual` (it was typed before sources existed); `system`, `estimated` and
`unknown` were measurements or "nothing", so they become **unknown design capacity** and their numbers
are dropped (the measurement itself lives in the collector's estimate, not in settings). The retired
strings `system` / `estimated` under the *new* key are treated the same way. `save()` writes the new keys
and removes the old ones; `Settings.sanitized()` keeps the three fields coherent on every load and save
(a known source needs a finite mAh in range, `unknown` carries no numbers, Wh needs mAh).

The cached backend specification (`wb.deviceSpecCache`, one JSON object, only for the current model
identifier) is read in the new layout and, once, in the old one (`batteryCapacityMah`, `source`): an old
entry labelled `backendDatabase` or `localDatabase` is accepted, every other old source is ignored and the
backend is asked again. Whatever the entry claims, it is relabelled `backendDeviceDatabase`: only the
backend writes this cache, so a damaged or hand-edited entry can never come back as `manual` (which is sticky).

The estimate is not a setting. It stays in the local database meta table
(`calibrated_capacity_mah`, `calibrated_capacity_level` as before, plus `calibrated_capacity_wh` and
`calibrated_capacity_at_ms`; the key names were kept on purpose so no data migration is needed). Existing
installs keep their stored reading, now interpreted as an estimate: the confidence is not stored, it is
derived from the stored level (an older entry without Wh and time is read as it is; without a time it
counts as stale, so the next usable reading replaces it). An entry that is
unparsable, below 40 % or implausible reads as "no estimate"; an implausible Wh or timestamp is dropped
and the mAh stay. "Reset statistics" removes the estimate with the other measurements.

## Decisions and known limits

* **Unknown and `null` are different things on the wire.** `designCapacitySource: unknown` (and
  `fullChargeCapacitySource: unknown`) is a statement, "nothing is known", and it clears the stored
  group. A `null` source is silence and leaves the stored group alone. The app therefore always sends the
  design group when it registers with a specification (`unknown` included, with no numbers) and sends the
  estimate group only when it has an estimate: with no estimate it sends four `null` fields, because
  sending `unknown` would erase the estimate the server already holds. The consequence: a phone that
  loses its local estimate ("Reset statistics") never clears the one the server already holds for that
  installation; only a new estimate replaces it.
* **The estimate reaches the server only with a registration.** The app registers the device at
  setup, on "Detect again" and when the design capacity is edited; there is no periodic re-upload of the
  estimate. The collector runs once the dashboard is on screen (or in a background job), so on a fresh
  install the registration made by setup normally carries no estimate yet, and the server's estimate can be
  absent or older than the local one until the next such registration. Nothing is lost locally.
* **Each group is atomic.** A design capacity is replaced as a whole (mAh, Wh and source, nulls
  included), and so is the estimate (mAh, Wh, source, confidence). A per-column merge would put a
  figure of one source next to the number of another.
* **A number without provenance is dropped, not promoted.** The migration clears a legacy design
  number whose source is `NULL`; the route refuses a number without a source; the database refuses it
  too. Nothing guesses "it was probably a catalog value".
* **Migration clears the design group of `system` / `estimated` rows, source included.** Their
  mAh/Wh become the estimate; the design group is left as if the device never reported one (`NULL`), and
  fills in again at the next registration of that installation. A row whose old source was `unknown`
  keeps `unknown`.
* **The retired sources `system` and `estimated` are `unknown` under the new key.** There is no
  member of `DesignCapacitySource` for them, in any layer.
* **A gap is filled once at launch.** A finished install whose design capacity is unknown while its
  model identifier is stored (typically an upgraded install whose old `system` / `estimated` capacity was
  dropped on load, or an offline first setup) looks the model up when the shell opens
  (`resolveMissingDesignCapacity`, `lib/ui/settings/setup_editors.dart`): the bundled catalog first, the
  network only for a model the catalog does not list. It only fills a gap: a known capacity (a manual one
  included) is never replaced, a failed or empty lookup changes nothing, and the result is registered as
  the design group together with the current estimate. Without it a catalog model would stay "unavailable"
  until the user found "Detect again".
* **A cached backend specification is relabelled `backendDeviceDatabase`** whatever the cache says.
* **The registration sent by setup carries the design capacity the app KEEPS**, not the raw detection
  result. A manual value survives automatic detection, so the server's record never disagrees with the
  app (`SetupController.run` builds the registration from the saved settings).
* **"Detect again" replaces, it does not merge.** It is an explicit request, so it overwrites a manual
  value with what the catalogs know, and for a model in no catalog that is nothing: the design
  capacity becomes `unknown`. It never copies the estimate in (pinned by a widget test).
* **The energy calculator falls back to the estimate, at any confidence, only when no design capacity
  is known.** A low-confidence estimate (a half-charged battery) is better than no `% -> mAh` figure but
  is never preferred over a design capacity. The calculator's capacity is therefore not always a design
  capacity; the JSON export says which one it used (`estimateCapacityBasis`).
* **The estimate's Wh comes only from a valid `BATTERY_PROPERTY_ENERGY_COUNTER`.** No voltage is
  assumed; with no valid energy counter Wh is `null` and the mAh estimate stands alone. A Wh that fails
  the 0 – 200 Wh or 2.5 – 5.0 V checks is dropped, and the registration also leaves out a Wh outside
  0 – 200 instead of failing. The app does not display an estimate Wh at all; it only keeps and uploads it.
* **A counter that reports milliampere-hours instead of microampere-hours is rejected, not guessed.**
  Read as µAh it yields an implausibly small battery (below 100 mAh), so no estimate is produced; a
  counter in a unit a thousand times finer is caught by the 30 000 mAh ceiling. The app never rescales a
  counter because it "looks like" another unit. Which Android devices do this is only knowable on hardware (see
  `docs/DEVICE_TEST_PLAN.md`).
* **The old API field names are gone.** `batteryCapacityMah`, `batteryCapacityWh` and
  `batterySpecificationSource` are not in the request, the response, the export or the OpenAPI document.
  The request schema is not strict, so an old app build that still sends them is not rejected: its
  registration succeeds, the unknown keys are dropped and the capacity stays `NULL` ("never reported")
  until the build is updated.
* **The column rename is not zero-downtime.** Migration 0006 renames columns of `devices` in place.
  The API does not migrate on start (`pnpm migrate` is a separate step), so an old API build running
  against the migrated schema cannot write a device (`POST /devices` fails on the missing columns) and its
  reads show no capacity, and a new build against the old schema cannot register one either. Plan a short
  maintenance window: stop the old API, run the migration, start the new one. The migration is
  forward-only; there is no down script.
* **No estimated battery health in the UI.** `calculateEstimatedBatteryHealth` exists as a domain
  function with tests only; nothing shows, uploads or stores a health figure.
* **No private Apple API, no iOS estimate.** iOS has no public charge counter; the design capacity of
  an iPhone comes from the catalog by `utsname.machine` (or the user), and an unlisted model shows
  "Battery capacity unavailable".
* **Not verified on hardware.** The units, sign and availability of the Android counters, the
  behaviour of a real battery and the upgrade of a populated install are open: see "Battery capacity:
  remaining device verification" in `docs/DEVICE_TEST_PLAN.md`.
