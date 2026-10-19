-- WattByte schema v1. The backend stores accounts and per-day aggregates only;
-- raw samples and per-app usage never leave the phone.

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL,
  password_hash text,                       -- NULL for Apple / Google only accounts
  display_name  text,
  plan          text NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'premium')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_key ON users (lower(email));

CREATE TABLE sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_hash  text NOT NULL UNIQUE,       -- sha256(refresh token)
  expires_at    timestamptz NOT NULL,
  revoked_at    timestamptz,
  replaced_by   uuid REFERENCES sessions(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions (user_id) WHERE revoked_at IS NULL;

CREATE TABLE devices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  installation_id text NOT NULL,            -- random per install, not a hardware id
  platform        text NOT NULL CHECK (platform IN ('android', 'ios')),
  model           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, installation_id)
);

CREATE TABLE user_settings (
  user_id          uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  currency         char(3) NOT NULL DEFAULT 'PLN',
  price_per_kwh    numeric(10, 4) NOT NULL DEFAULT 0 CHECK (price_per_kwh >= 0),
  efficiency       numeric(4, 3) NOT NULL DEFAULT 0.85 CHECK (efficiency > 0 AND efficiency <= 1),
  ai_mode          text NOT NULL DEFAULT 'normal' CHECK (ai_mode IN ('normal', 'friendly', 'funny', 'roast')),
  cloud_sync       boolean NOT NULL DEFAULT false,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE daily_usage (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id         uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  date              date NOT NULL,
  mobile_bytes      bigint NOT NULL DEFAULT 0 CHECK (mobile_bytes >= 0),
  wifi_bytes        bigint NOT NULL DEFAULT 0 CHECK (wifi_bytes >= 0),
  total_bytes       bigint GENERATED ALWAYS AS (mobile_bytes + wifi_bytes) STORED,
  charged_wh        numeric(12, 3) NOT NULL DEFAULT 0 CHECK (charged_wh >= 0),   -- battery energy
  wall_wh           numeric(12, 3) NOT NULL DEFAULT 0 CHECK (wall_wh >= 0),      -- battery / efficiency
  charging_sessions integer NOT NULL DEFAULT 0 CHECK (charging_sessions >= 0),
  estimated_cost    numeric(12, 4) NOT NULL DEFAULT 0 CHECK (estimated_cost >= 0),
  currency          char(3) NOT NULL,
  data_estimated    boolean NOT NULL DEFAULT false,
  energy_estimated  boolean NOT NULL DEFAULT true,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id, date)
);
CREATE INDEX daily_usage_user_date_idx ON daily_usage (user_id, date);

-- Per-session detail is optional and off by default; the table exists so a
-- future opt-in can store it without a schema change.
CREATE TABLE charging_summaries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id       uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  started_at      timestamptz NOT NULL,
  ended_at        timestamptz NOT NULL CHECK (ended_at >= started_at),
  start_percent   smallint NOT NULL CHECK (start_percent BETWEEN 0 AND 100),
  end_percent     smallint NOT NULL CHECK (end_percent BETWEEN 0 AND 100),
  mah             numeric(10, 1) NOT NULL DEFAULT 0,
  mah_estimated   boolean NOT NULL DEFAULT true,
  battery_wh      numeric(10, 3) NOT NULL DEFAULT 0,
  wall_wh         numeric(10, 3) NOT NULL DEFAULT 0,
  estimated_cost  numeric(12, 4) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id, started_at)
);

CREATE TABLE monthly_summaries (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  month             char(7) NOT NULL,       -- 'YYYY-MM'
  mobile_bytes      bigint NOT NULL DEFAULT 0,
  wifi_bytes        bigint NOT NULL DEFAULT 0,
  wall_wh           numeric(12, 3) NOT NULL DEFAULT 0,
  charging_sessions integer NOT NULL DEFAULT 0,
  estimated_cost    numeric(12, 4) NOT NULL DEFAULT 0,
  currency          char(3) NOT NULL,
  computed_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, month)
);

CREATE TABLE ai_generations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  generation_type    text NOT NULL CHECK (generation_type IN ('insight', 'weekly_summary', 'monthly_summary', 'roast')),
  mode               text NOT NULL,
  provider           text NOT NULL,
  model              text NOT NULL,
  input_tokens       integer NOT NULL DEFAULT 0,
  output_tokens      integer NOT NULL DEFAULT 0,
  estimated_cost_usd numeric(12, 6) NOT NULL DEFAULT 0,
  latency_ms         integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ai_generations_user_created_idx ON ai_generations (user_id, created_at);

CREATE TABLE subscriptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  store             text NOT NULL CHECK (store IN ('app_store', 'play')),
  product_id        text NOT NULL,
  original_tx_id    text NOT NULL,          -- store transaction id, verified server-side
  status            text NOT NULL CHECK (status IN ('active', 'grace', 'expired', 'revoked')),
  expires_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (store, original_tx_id)
);
CREATE INDEX subscriptions_user_idx ON subscriptions (user_id);
