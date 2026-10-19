-- Automatic setup: device-bound battery specification, account-bound region /
-- currency / electricity price mode, and a cache of household electricity prices
-- so the last known value survives API restarts and source outages.

ALTER TABLE devices
  ADD COLUMN model_identifier            text,
  ADD COLUMN battery_capacity_mah        numeric(8, 1) CHECK (battery_capacity_mah IS NULL OR battery_capacity_mah > 0),
  ADD COLUMN battery_capacity_wh         numeric(8, 3) CHECK (battery_capacity_wh IS NULL OR battery_capacity_wh > 0),
  ADD COLUMN battery_specification_source text
    CHECK (battery_specification_source IS NULL OR battery_specification_source IN
      ('system', 'localDatabase', 'backendDatabase', 'estimated', 'manual', 'unknown'));

ALTER TABLE user_settings
  ADD COLUMN country_code           char(2),
  ADD COLUMN electricity_price_mode text NOT NULL DEFAULT 'automatic'
    CHECK (electricity_price_mode IN ('automatic', 'manual')),
  ADD COLUMN manual_price_per_kwh   numeric(10, 4) CHECK (manual_price_per_kwh IS NULL OR manual_price_per_kwh >= 0),
  ALTER COLUMN currency DROP NOT NULL,
  ALTER COLUMN currency DROP DEFAULT;

CREATE TABLE electricity_prices (
  country_code  char(2) PRIMARY KEY,
  currency      char(3) NOT NULL,
  price_per_kwh numeric(12, 6) NOT NULL CHECK (price_per_kwh >= 0),
  period        text NOT NULL,
  source        text NOT NULL CHECK (source IN ('eurostat', 'government', 'manual', 'fallback')),
  includes_taxes          boolean,
  includes_network_costs  boolean,
  fetched_at    timestamptz NOT NULL DEFAULT now()
);
