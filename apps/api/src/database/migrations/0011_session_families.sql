-- Refresh-token families (A-05, A-06, A-07, A-08, C-03).
--
-- A session row is one refresh token. Rotation creates a successor; all tokens that descend from one sign-in form a
-- FAMILY. A family is what a device holds, so it is what logout, theft detection and "sign out this device" act on:
-- revoking a family never touches another device, and reuse of an old token revokes its family, not the whole account.
-- family_started_at is the sign-in time: the absolute session lifetime counts from it, however often the token rotates.
--
-- users.tokens_valid_after lets "sign out everywhere" and a password change invalidate the ACCESS tokens that were
-- issued before it (they otherwise live until they expire).
--
-- Additive and backward compatible: existing rows are assigned to families by walking replaced_by, nothing is deleted.
ALTER TABLE sessions ADD COLUMN family_id uuid, ADD COLUMN family_started_at timestamptz;

WITH RECURSIVE chain(id, root, root_created) AS (
  SELECT s.id, s.id, s.created_at
  FROM sessions s
  WHERE NOT EXISTS (SELECT 1 FROM sessions p WHERE p.replaced_by = s.id)
  UNION ALL
  SELECT n.id, c.root, c.root_created
  FROM chain c
  JOIN sessions cur ON cur.id = c.id
  JOIN sessions n ON n.id = cur.replaced_by
)
UPDATE sessions s SET family_id = c.root, family_started_at = c.root_created FROM chain c WHERE s.id = c.id;

UPDATE sessions SET family_id = id, family_started_at = created_at WHERE family_id IS NULL;

ALTER TABLE sessions ALTER COLUMN family_id SET NOT NULL, ALTER COLUMN family_started_at SET NOT NULL;
CREATE INDEX sessions_family_idx ON sessions (family_id);

ALTER TABLE users ADD COLUMN tokens_valid_after timestamptz;
