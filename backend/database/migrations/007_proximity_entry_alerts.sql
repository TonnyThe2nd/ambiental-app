-- Documents why an alert was created and supports auditing geofence-entry notifications.
-- The existing unique (user_id, incident_id) index is the idempotency boundary: a citizen
-- receives at most one proximity alert for the same active environmental incident.
ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS reason VARCHAR(40) NOT NULL DEFAULT 'incident_created',
  ADD COLUMN IF NOT EXISTS risk_score DOUBLE PRECISION NOT NULL DEFAULT 50;

CREATE INDEX IF NOT EXISTS notifications_proximity_audit_idx
  ON notifications (user_id, reason, created_at DESC);
