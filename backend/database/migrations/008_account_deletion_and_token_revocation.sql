ALTER TABLE incidents
  DROP CONSTRAINT IF EXISTS incidents_reported_by_fkey;

ALTER TABLE incidents
  ADD CONSTRAINT incidents_reported_by_fkey
  FOREIGN KEY (reported_by) REFERENCES users(id) ON DELETE SET NULL;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS users_active_accounts_idx
  ON users (id) WHERE deleted_at IS NULL;

ALTER TABLE incident_reviews
  DROP CONSTRAINT IF EXISTS incident_reviews_reviewer_id_fkey;

ALTER TABLE incident_reviews
  ADD CONSTRAINT incident_reviews_reviewer_id_fkey
  FOREIGN KEY (reviewer_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE citizen_contributions
  DROP CONSTRAINT IF EXISTS citizen_contributions_user_id_fkey;

ALTER TABLE citizen_contributions
  ADD CONSTRAINT citizen_contributions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

CREATE TABLE IF NOT EXISTS revoked_tokens (
  jti UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS revoked_tokens_expires_at_idx
  ON revoked_tokens (expires_at);
