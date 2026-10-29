-- Per-account sign-in throttle (A-02): consecutive failed logins per normalised e-mail, shared by every API instance.
-- `key` is a SHA-256 of the lower-cased e-mail (no address is stored, and an unknown e-mail is tracked exactly like a
-- known one, so the throttle is no existence oracle). Purged by the retention job.
-- Additive: a new table, nothing existing changes.
CREATE TABLE login_throttle (
  key          text PRIMARY KEY,
  failures     integer     NOT NULL CHECK (failures >= 0),
  locked_until timestamptz,
  updated_at   timestamptz NOT NULL
);
CREATE INDEX login_throttle_updated_idx ON login_throttle (updated_at);
