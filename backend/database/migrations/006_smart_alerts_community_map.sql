-- Alertas contextuais, validação comunitária e feed incremental do mapa.
DO $$ BEGIN CREATE TYPE community_vote AS ENUM ('confirmar', 'rejeitar', 'complementar'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS quiet_hours_start TIME,
  ADD COLUMN IF NOT EXISTS quiet_hours_end TIME,
  ADD COLUMN IF NOT EXISTS alert_route geography(LineString, 4326),
  ADD COLUMN IF NOT EXISTS alert_route_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS route_alert_radius_m INTEGER NOT NULL DEFAULT 750
    CHECK (route_alert_radius_m BETWEEN 100 AND 5000);

CREATE INDEX IF NOT EXISTS users_active_alert_route_idx
  ON users (alert_route_expires_at)
  WHERE alert_route IS NOT NULL;

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS confirmation_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rejection_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS complement_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS confidence_score NUMERIC(5,2) NOT NULL DEFAULT 50
    CHECK (confidence_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS priority_score NUMERIC(7,2) NOT NULL DEFAULT 50;

CREATE TABLE IF NOT EXISTS incident_validations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, vote community_vote NOT NULL,
  comment TEXT, evidence_url TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), UNIQUE (incident_id, user_id)
);
CREATE INDEX IF NOT EXISTS incident_validations_incident_idx ON incident_validations (incident_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS incidents_map_incremental_idx ON incidents (updated_at, id);
CREATE INDEX IF NOT EXISTS incidents_active_priority_idx ON incidents (priority_score DESC, updated_at DESC)
  WHERE workflow_status NOT IN ('rejeitado', 'resolvido');

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS reason VARCHAR(30) NOT NULL DEFAULT 'proximity',
  ADD COLUMN IF NOT EXISTS risk_score NUMERIC(5,2) NOT NULL DEFAULT 50;
