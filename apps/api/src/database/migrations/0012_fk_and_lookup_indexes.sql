-- Indexes for the paths that scan whole tables today (C-02, C-05).
--
-- PostgreSQL does not index referencing columns. Without these, every deleted session fires a full scan of sessions
-- (ON DELETE SET NULL on replaced_by), DELETE /me and the retention purge scan sessions per row, and deleting a device
-- scans daily_usage / charging_summaries. Plain CREATE INDEX (the runner uses one transaction per file): it takes a
-- short write lock on each table, which is harmless while the tables are small; on a large production table create
-- the indexes beforehand with CREATE INDEX CONCURRENTLY (the same names, IF NOT EXISTS makes this file a no-op then).
--
-- Additive: nothing existing changes except that the partial sessions_user_idx is replaced by a full one (the cascade
-- DELETE ... WHERE user_id = $1 cannot use a partial index).
DROP INDEX IF EXISTS sessions_user_idx;
CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON sessions (user_id);
CREATE INDEX IF NOT EXISTS sessions_replaced_by_idx ON sessions (replaced_by) WHERE replaced_by IS NOT NULL;
-- retention purges `expires_at < cutoff OR revoked_at < cutoff`
CREATE INDEX IF NOT EXISTS sessions_expires_at_idx ON sessions (expires_at);
CREATE INDEX IF NOT EXISTS sessions_revoked_at_idx ON sessions (revoked_at) WHERE revoked_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS daily_usage_device_idx ON daily_usage (device_id);
CREATE INDEX IF NOT EXISTS charging_summaries_device_idx ON charging_summaries (device_id);

-- retention purges by age
CREATE INDEX IF NOT EXISTS ai_generations_created_idx ON ai_generations (created_at);
CREATE INDEX IF NOT EXISTS ai_quota_usage_day_idx ON ai_quota_usage (day);
