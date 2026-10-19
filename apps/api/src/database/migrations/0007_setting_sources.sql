-- Setting sources: where each account-level value came from on the device that saved it
-- ('detected' by the app, 'manual' = chosen by the user, 'migratedManual' = a conscious
-- answer carried over from an older version of the app). A device that pulls the value
-- records it as "synced from the account" and keeps this as its `originalSource`.
--
-- Additive and compatible: the three columns are nullable and every existing row keeps
-- NULL = "origin unknown". Nothing is inferred for rows written before this migration
-- (a stored PLN may have been detected or typed; the server cannot tell). 'accountSynced'
-- is not a legal value: it describes how a value reaches a device, not how the account
-- got it.

ALTER TABLE user_settings
  ADD COLUMN country_code_source      text
    CHECK (country_code_source IS NULL OR country_code_source IN ('detected', 'manual', 'migratedManual')),
  ADD COLUMN currency_source          text
    CHECK (currency_source IS NULL OR currency_source IN ('detected', 'manual', 'migratedManual')),
  ADD COLUMN electricity_price_source text
    CHECK (electricity_price_source IS NULL OR electricity_price_source IN ('detected', 'manual', 'migratedManual'));
