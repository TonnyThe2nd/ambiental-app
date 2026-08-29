CREATE EXTENSION IF NOT EXISTS postgis;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS location geography(Point, 4326),
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;

UPDATE users
SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE latitude IS NOT NULL AND longitude IS NOT NULL AND location IS NULL;

CREATE INDEX IF NOT EXISTS users_location_gist_idx
  ON users USING GIST (location)
  WHERE location IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_fcm_token_unique_idx
  ON users (fcm_token) WHERE fcm_token IS NOT NULL;

ALTER TABLE incidents ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS incidents_idempotency_key_unique_idx
  ON incidents (idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  event_type VARCHAR(120) NOT NULL,
  payload JSONB NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_error TEXT,
  CONSTRAINT outbox_attempts_positive CHECK (attempts >= 0)
);

CREATE INDEX IF NOT EXISTS outbox_pending_idx ON outbox (available_at, created_at);
