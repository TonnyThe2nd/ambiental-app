-- Domínio operacional de vigilância ambiental (idempotente para deploys repetidos).
DO $$ BEGIN CREATE TYPE incident_severity AS ENUM ('leve', 'moderado', 'critico'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE incident_workflow_status AS ENUM ('reportado', 'em_analise', 'validado', 'rejeitado', 'resolvido'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE user_role AS ENUM ('cidadao', 'moderador', 'administrador'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS role user_role NOT NULL DEFAULT 'cidadao',
  ADD COLUMN IF NOT EXISTS trust_score NUMERIC(5,2) NOT NULL DEFAULT 50 CHECK (trust_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS alert_radius_m INTEGER NOT NULL DEFAULT 10000 CHECK (alert_radius_m BETWEEN 500 AND 50000),
  ADD COLUMN IF NOT EXISTS alert_categories TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS minimum_alert_severity incident_severity NOT NULL DEFAULT 'moderado',
  ADD COLUMN IF NOT EXISTS alert_cooldown_minutes INTEGER NOT NULL DEFAULT 60 CHECK (alert_cooldown_minutes BETWEEN 5 AND 1440);

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS severity incident_severity NOT NULL DEFAULT 'moderado',
  ADD COLUMN IF NOT EXISTS risk_score NUMERIC(5,2) NOT NULL DEFAULT 50 CHECK (risk_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS health_impact TEXT,
  ADD COLUMN IF NOT EXISTS ecosystem_impact TEXT,
  ADD COLUMN IF NOT EXISTS community_impact TEXT,
  ADD COLUMN IF NOT EXISTS workflow_status incident_workflow_status NOT NULL DEFAULT 'reportado',
  ADD COLUMN IF NOT EXISTS verification_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS source VARCHAR(40) NOT NULL DEFAULT 'mobile',
  ADD COLUMN IF NOT EXISTS environmental_context JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS location geography(Point, 4326);

UPDATE incidents SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE location IS NULL;
CREATE INDEX IF NOT EXISTS incidents_location_gist_idx ON incidents USING GIST (location);
CREATE INDEX IF NOT EXISTS incidents_dashboard_idx ON incidents (workflow_status, severity, occurred_at DESC);

CREATE TABLE IF NOT EXISTS sensitive_areas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name VARCHAR(160) NOT NULL,
  area_type VARCHAR(60) NOT NULL, criticality SMALLINT NOT NULL CHECK (criticality BETWEEN 1 AND 5),
  location geography(Point, 4326) NOT NULL, protection_radius_m INTEGER NOT NULL DEFAULT 1000,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS sensitive_areas_location_gist_idx ON sensitive_areas USING GIST (location);

CREATE TABLE IF NOT EXISTS incident_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID NOT NULL REFERENCES incidents(id),
  reviewer_id UUID NOT NULL REFERENCES users(id), decision incident_workflow_status NOT NULL,
  notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (incident_id, reviewer_id)
);

CREATE TABLE IF NOT EXISTS processed_events (
  consumer VARCHAR(120) NOT NULL, event_id UUID NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), PRIMARY KEY (consumer, event_id)
);

CREATE TABLE IF NOT EXISTS environmental_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), region_key VARCHAR(80) NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL, source VARCHAR(100) NOT NULL,
  temperature_c NUMERIC(5,2), humidity_percent NUMERIC(5,2), rainfall_mm NUMERIC(8,2),
  air_quality_index INTEGER, payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (region_key, observed_at, source)
);
CREATE INDEX IF NOT EXISTS environmental_observations_history_idx
  ON environmental_observations (region_key, observed_at DESC);

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS severity incident_severity NOT NULL DEFAULT 'moderado';
CREATE INDEX IF NOT EXISTS notifications_cooldown_idx ON notifications (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), title VARCHAR(160) NOT NULL, description TEXT NOT NULL,
  campaign_type VARCHAR(60) NOT NULL, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL,
  points_reward INTEGER NOT NULL DEFAULT 0, active BOOLEAN NOT NULL DEFAULT TRUE,
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS citizen_contributions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES users(id),
  incident_id UUID REFERENCES incidents(id), contribution_type VARCHAR(60) NOT NULL,
  points INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
