CREATE UNIQUE INDEX IF NOT EXISTS citizen_contributions_unique_incident_type_idx
  ON citizen_contributions (user_id, incident_id, contribution_type)
  WHERE incident_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS campaigns_active_schedule_idx
  ON campaigns (starts_at, ends_at) WHERE active = TRUE;

CREATE INDEX IF NOT EXISTS citizen_contributions_user_created_idx
  ON citizen_contributions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS incident_trust_adjustments (
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delta SMALLINT NOT NULL CHECK (delta BETWEEN -10 AND 10),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (incident_id, user_id)
);
