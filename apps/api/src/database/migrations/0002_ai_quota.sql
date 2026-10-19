-- Atomic per-user, per-UTC-day AI quota counter. The API reserves a slot with a
-- single conditional upsert before calling a provider, so concurrent requests
-- can never exceed the plan limit.
CREATE TABLE ai_quota_usage (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day     date NOT NULL,
  used    integer NOT NULL DEFAULT 0 CHECK (used >= 0),
  PRIMARY KEY (user_id, day)
);
