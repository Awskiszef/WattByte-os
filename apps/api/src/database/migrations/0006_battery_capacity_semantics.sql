-- Battery capacity semantics: separate DESIGN capacity from the ESTIMATED FULL-CHARGE capacity.
--
-- Why: until now `devices.battery_capacity_*` held one number whose meaning depended on
-- `battery_specification_source`. For the sources 'system' and 'estimated' that number was derived from
-- Android's BATTERY_PROPERTY_CHARGE_COUNTER, which is the charge currently stored in a battery, NOT its
-- nominal capacity. Reading it as "capacity" mixed a measurement into a published figure. From here on:
--
--   design group    design_capacity_mah / design_capacity_wh / design_capacity_source
--                   the nominal capacity of the phone MODEL (catalog, API catalog or typed by the user)
--   estimate group  estimated_full_charge_capacity_mah / _wh, full_charge_capacity_source,
--                   full_charge_capacity_confidence
--                   an ESTIMATE for this one battery (charge counter extrapolated from the battery level)
--
-- Mapping of the existing rows (docs/BATTERY_CAPACITY.md):
--
--   old battery_specification_source   design group after                 estimate group after
--   localDatabase                      localDeviceDatabase, mAh/Wh kept   empty
--   backendDatabase                    backendDeviceDatabase, mAh/Wh kept empty
--   manual                             manual, mAh/Wh kept                empty
--   unknown                            unknown, numbers cleared           empty
--   system                             empty (all NULL)                   androidChargeCounter, high, mAh/Wh moved
--   estimated                          empty (all NULL)                   androidChargeCounter, low,  mAh/Wh moved
--   NULL, with a number                empty (all NULL), number dropped   empty
--   NULL, without numbers              unchanged (all NULL)               empty
--
-- A measurement is NEVER left in a design column. "Empty" means every column of the group is NULL, i.e. the
-- same state as a device that never reported the group: the database does not claim "unknown" for a device
-- that was never asked, and the next registration of the installation fills the group in.
--
-- Forward-only, in place, no data is copied to another table. `migrate()` runs this file in one transaction,
-- so a failing statement leaves the schema as it was.

-- 1. Rename the design columns. Constraints keep their names when a column is renamed; they are handled below.
ALTER TABLE devices RENAME COLUMN battery_capacity_mah          TO design_capacity_mah;
ALTER TABLE devices RENAME COLUMN battery_capacity_wh           TO design_capacity_wh;
ALTER TABLE devices RENAME COLUMN battery_specification_source  TO design_capacity_source;

-- 2. Drop the old source CHECK (auto-named by 0003: <table>_<column>_check for an inline column constraint).
--    It would reject the new source strings written in step 5, and its value list is replaced in step 6.
--    IF EXISTS keeps the migration usable on a database whose constraint was removed by hand.
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_battery_specification_source_check;

-- 3. The positive-value CHECKs of 0003 (`IS NULL OR > 0`) stay as they are, under names that describe them.
--    Their auto-generated names (devices_battery_capacity_{mah,wh}_check) still mention the old columns.
ALTER TABLE devices RENAME CONSTRAINT devices_battery_capacity_mah_check TO devices_design_capacity_mah_positive;
ALTER TABLE devices RENAME CONSTRAINT devices_battery_capacity_wh_check  TO devices_design_capacity_wh_positive;

-- 4. The estimate group. All nullable: a device that never reported an estimate has none. Same column
--    resolution as the design group (0.1 mAh, 0.001 Wh), which is also what the API enforces as a minimum.
ALTER TABLE devices
  ADD COLUMN estimated_full_charge_capacity_mah numeric(8, 1),
  ADD COLUMN estimated_full_charge_capacity_wh  numeric(8, 3),
  ADD COLUMN full_charge_capacity_source        text,
  ADD COLUMN full_charge_capacity_confidence    text;

-- 5. Move the measurements out of the design group, THEN clear them there, THEN rewrite the remaining sources.
--    The order matters: step 5a reads the old source, 5b erases the numbers it just copied, 5c renames strings.

-- 5a. 'system' / 'estimated' rows held a reading derived from the charge counter: it becomes the estimate.
--     Confidence follows the rule the old collector used: 'system' required a reading at >= 95 % of charge
--     (high); 'estimated' came from a reading somewhere in 40 - 94 % (low). The exact level was never stored,
--     so 'medium' cannot be told apart and is deliberately not invented.
--     Only rows that actually have a mAh value get an estimate: Wh alone is not an estimate (see the CHECK
--     "estimated Wh needs estimated mAh" below) and a source without a number would claim a measurement
--     that does not exist.
UPDATE devices
   SET estimated_full_charge_capacity_mah = design_capacity_mah,
       estimated_full_charge_capacity_wh  = design_capacity_wh,
       full_charge_capacity_source        = 'androidChargeCounter',
       full_charge_capacity_confidence    = CASE design_capacity_source WHEN 'system' THEN 'high' ELSE 'low' END
 WHERE design_capacity_source IN ('system', 'estimated')
   AND design_capacity_mah IS NOT NULL;

-- 5b. Clear the design group wherever the number was not a design figure:
--     - 'system' / 'estimated': a measurement (copied to the estimate above, or dropped when it was Wh only);
--     - NULL source with a number: no provenance at all, so it is not promoted to "design";
--     - 'unknown': by definition it carries no numbers (any legacy number next to it is dropped).
--     The source of the first two groups is cleared as well: nothing is known about the design capacity.
--     An 'unknown' row keeps its source (the app did say "not known").
UPDATE devices
   SET design_capacity_mah = NULL,
       design_capacity_wh  = NULL,
       design_capacity_source = CASE WHEN design_capacity_source = 'unknown' THEN 'unknown' ELSE NULL END
 WHERE design_capacity_source IN ('system', 'estimated')
    OR ((design_capacity_source IS NULL OR design_capacity_source = 'unknown')
        AND (design_capacity_mah IS NOT NULL OR design_capacity_wh IS NOT NULL));

-- 5b'. A design Wh without a design mAh cannot be kept (see the CHECK "design Wh needs design mAh" below).
--      The old API accepted that combination; the catalog never produced it.
UPDATE devices
   SET design_capacity_wh = NULL
 WHERE design_capacity_wh IS NOT NULL AND design_capacity_mah IS NULL;

-- 5c. Catalog sources get their final names; 'manual' and 'unknown' are unchanged.
UPDATE devices
   SET design_capacity_source = CASE design_capacity_source
         WHEN 'localDatabase'   THEN 'localDeviceDatabase'
         WHEN 'backendDatabase' THEN 'backendDeviceDatabase'
       END
 WHERE design_capacity_source IN ('localDatabase', 'backendDatabase');

-- 6. Constraints, one per rule so a failure names the rule that was broken. NULL-safe on purpose: a CHECK
--    passes when its expression is NULL, so every comparison with a nullable source uses IS [NOT] DISTINCT FROM
--    or an explicit IS NOT NULL.

-- design group
ALTER TABLE devices
  ADD CONSTRAINT devices_design_capacity_source_valid
    CHECK (design_capacity_source IS NULL OR design_capacity_source IN
      ('manufacturerSpecification', 'localDeviceDatabase', 'backendDeviceDatabase', 'manual', 'unknown')),
  -- 'unknown' says "nothing known": no number may sit next to it.
  ADD CONSTRAINT devices_design_capacity_unknown_has_no_numbers
    CHECK (design_capacity_source IS DISTINCT FROM 'unknown'
           OR (design_capacity_mah IS NULL AND design_capacity_wh IS NULL)),
  -- A design number needs a known provenance (a number without a source is exactly the old ambiguity).
  ADD CONSTRAINT devices_design_capacity_numbers_need_source
    CHECK (design_capacity_source IS NOT NULL
           OR (design_capacity_mah IS NULL AND design_capacity_wh IS NULL)),
  -- Energy is only meaningful next to the charge figure of the same battery.
  ADD CONSTRAINT devices_design_capacity_wh_needs_mah
    CHECK (design_capacity_wh IS NULL OR design_capacity_mah IS NOT NULL);

-- estimate group
ALTER TABLE devices
  ADD CONSTRAINT devices_estimated_full_charge_capacity_mah_positive
    CHECK (estimated_full_charge_capacity_mah IS NULL OR estimated_full_charge_capacity_mah > 0),
  ADD CONSTRAINT devices_estimated_full_charge_capacity_wh_positive
    CHECK (estimated_full_charge_capacity_wh IS NULL OR estimated_full_charge_capacity_wh > 0),
  ADD CONSTRAINT devices_full_charge_capacity_source_valid
    CHECK (full_charge_capacity_source IS NULL OR full_charge_capacity_source IN ('androidChargeCounter', 'unknown')),
  ADD CONSTRAINT devices_full_charge_capacity_confidence_valid
    CHECK (full_charge_capacity_confidence IS NULL OR full_charge_capacity_confidence IN ('low', 'medium', 'high')),
  -- An estimate number is only ever produced by a reading, never by 'unknown' or by a missing source.
  ADD CONSTRAINT devices_estimated_full_charge_capacity_needs_source
    CHECK ((estimated_full_charge_capacity_mah IS NULL AND estimated_full_charge_capacity_wh IS NULL)
           OR full_charge_capacity_source IS NOT DISTINCT FROM 'androidChargeCounter'),
  -- An estimate is always shown with how far it can be trusted.
  ADD CONSTRAINT devices_estimated_full_charge_capacity_needs_confidence
    CHECK ((estimated_full_charge_capacity_mah IS NULL AND estimated_full_charge_capacity_wh IS NULL)
           OR full_charge_capacity_confidence IS NOT NULL),
  ADD CONSTRAINT devices_estimated_full_charge_capacity_wh_needs_mah
    CHECK (estimated_full_charge_capacity_wh IS NULL OR estimated_full_charge_capacity_mah IS NOT NULL),
  -- Provenance without a value is a claim of a measurement that does not exist (no legacy row can break
  -- these two: step 5a only sets the source and the confidence together with a mAh value).
  ADD CONSTRAINT devices_full_charge_capacity_confidence_needs_estimate
    CHECK (full_charge_capacity_confidence IS NULL OR estimated_full_charge_capacity_mah IS NOT NULL),
  ADD CONSTRAINT devices_full_charge_capacity_measured_source_needs_estimate
    CHECK (full_charge_capacity_source IS DISTINCT FROM 'androidChargeCounter'
           OR estimated_full_charge_capacity_mah IS NOT NULL);

COMMENT ON COLUMN devices.design_capacity_mah IS
  'Design (nominal) capacity of the phone model, from a device database or typed by the user. Never a measurement.';
COMMENT ON COLUMN devices.design_capacity_source IS
  'manufacturerSpecification | localDeviceDatabase | backendDeviceDatabase | manual | unknown. NULL = never reported.';
COMMENT ON COLUMN devices.estimated_full_charge_capacity_mah IS
  'ESTIMATE of what this battery holds when full (charge counter / battery level). Always an estimate; see full_charge_capacity_confidence.';
COMMENT ON COLUMN devices.full_charge_capacity_confidence IS
  'low | medium | high: follows the battery level of the reading the estimate was extrapolated from.';
