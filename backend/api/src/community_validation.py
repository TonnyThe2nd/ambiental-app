import json
from uuid import UUID, uuid4

from .database import pool
from .models import CommunityValidationInput
from .community_scoring import confidence_score, workflow_status

EVENT_TYPE = "incident.validation.updated.v1"


async def validate_incident(incident_id: UUID, user_id: UUID, data: CommunityValidationInput) -> dict:
    """Upserts one vote per citizen and recomputes scores atomically from weighted votes."""
    async with pool.connection() as connection:
        async with connection.transaction():
            incident = await connection.execute(
                "SELECT reported_by, risk_score FROM incidents WHERE id = %s FOR UPDATE", (incident_id,)
            )
            row = await incident.fetchone()
            if row is None:
                raise LookupError("incident_not_found")
            if row["reported_by"] == user_id:
                raise PermissionError("self_validation")
            await connection.execute(
                """INSERT INTO incident_validations (incident_id, user_id, vote, comment, evidence_url)
                   VALUES (%s, %s, %s, %s, %s)
                   ON CONFLICT (incident_id, user_id) DO UPDATE SET vote = EXCLUDED.vote,
                   comment = EXCLUDED.comment, evidence_url = EXCLUDED.evidence_url, updated_at = NOW()""",
                (incident_id, user_id, data.vote, data.comment, data.evidence_url),
            )
            await connection.execute(
                """INSERT INTO citizen_contributions (user_id, incident_id, contribution_type, points)
                   VALUES (%s, %s, 'community_validation', 2)
                   ON CONFLICT (user_id, incident_id, contribution_type) WHERE incident_id IS NOT NULL
                   DO UPDATE SET points = EXCLUDED.points, created_at = NOW()""",
                (user_id, incident_id),
            )
            scores = await connection.execute(
                """SELECT count(*) FILTER (WHERE v.vote = 'confirmar') AS confirmations,
                          count(*) FILTER (WHERE v.vote = 'rejeitar') AS rejections,
                          count(*) FILTER (WHERE v.vote = 'complementar') AS complements,
                          COALESCE(sum(CASE v.vote WHEN 'confirmar' THEN u.trust_score
                            WHEN 'rejeitar' THEN -u.trust_score ELSE 0 END), 0) AS weighted,
                          COALESCE(sum(CASE WHEN v.vote IN ('confirmar', 'rejeitar')
                            THEN u.trust_score ELSE 0 END), 0) AS decisive_weight,
                          count(*) FILTER (WHERE v.vote IN ('confirmar', 'rejeitar')) AS decisive_votes
                   FROM incident_validations v JOIN users u ON u.id = v.user_id
                   WHERE v.incident_id = %s""", (incident_id,)
            )
            aggregate = await scores.fetchone()
            confidence = confidence_score(weighted_votes=float(aggregate["weighted"]),
                decisive_weight=float(aggregate["decisive_weight"]), decisive_votes=int(aggregate["decisive_votes"]))
            priority = round(float(row["risk_score"]) * .65 + confidence * .35, 2)
            workflow = workflow_status(confidence, int(aggregate["decisive_votes"]))
            await connection.execute(
                """UPDATE incidents SET confirmation_count = %s, rejection_count = %s,
                   complement_count = %s, verification_count = %s, confidence_score = %s,
                   priority_score = %s, workflow_status = %s, updated_at = NOW() WHERE id = %s""",
                (aggregate["confirmations"], aggregate["rejections"], aggregate["complements"],
                 aggregate["confirmations"] + aggregate["rejections"] + aggregate["complements"],
                 confidence, priority, workflow, incident_id),
            )
            event_id = uuid4()
            payload = {"eventId": str(event_id), "eventType": EVENT_TYPE,
                       "data": {"id": str(incident_id), "confidenceScore": confidence,
                                "priorityScore": priority, "workflowStatus": workflow}}
            await connection.execute(
                "INSERT INTO outbox (id, aggregate_id, event_type, payload) VALUES (%s, %s, %s, %s::jsonb)",
                (event_id, incident_id, EVENT_TYPE, json.dumps(payload)),
            )
    return payload["data"]
