from uuid import UUID
from ...community_validation import validate_incident
from ...database import pool
from ...producer import create_incident_with_outbox
from ..application.ports import IncidentFilters


class PostgresIncidentRepository:
    async def create(self, incident: object, reporter_id: UUID) -> tuple[object, object]:
        return await create_incident_with_outbox(incident, reporter_id)

    async def validate(self, incident_id: UUID, user_id: UUID, data: object) -> dict:
        return await validate_incident(incident_id, user_id, data)

    async def list(self, f: IncidentFilters) -> list[dict]:
        async with pool.connection() as connection:
            result = await connection.execute(
                """SELECT i.id, i.category, i.latitude, i.longitude, i.occurred_at AS created_at,
                   i.image_url, i.severity, i.risk_score, i.health_impact, i.ecosystem_impact,
                   i.community_impact, i.workflow_status, i.environmental_context, i.updated_at,
                   i.confidence_score, i.priority_score, i.confirmation_count, i.rejection_count,
                   i.complement_count, u.id AS user_id, u.name AS user_name,
                   u.trust_score AS user_trust_score FROM incidents i LEFT JOIN users u ON u.id=i.reported_by
                   WHERE (%s::timestamptz IS NULL OR i.updated_at>%s OR
                     (i.updated_at=%s AND %s::uuid IS NOT NULL AND i.id>%s))
                   AND (cardinality(%s::text[])=0 OR i.category=ANY(%s))
                   AND (cardinality(%s::text[])=0 OR i.severity::text=ANY(%s))
                   AND (%s=FALSE OR i.workflow_status NOT IN ('rejeitado','resolvido'))
                   AND (%s::float8 IS NULL OR ST_DWithin(i.location,
                     ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography,%s))
                   ORDER BY i.updated_at,i.id LIMIT %s""",
                (f.updated_since, f.updated_since, f.updated_since, f.updated_after_id, f.updated_after_id,
                 f.categories, f.categories, f.severities, f.severities, f.active_only,
                 f.latitude, f.longitude, f.latitude, f.radius_m, f.limit),
            )
            return await result.fetchall()

    async def review(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None:
        async with pool.connection() as connection:
            async with connection.transaction():
                result = await connection.execute("SELECT 1 FROM incidents WHERE id=%s", (incident_id,))
                if await result.fetchone() is None: raise LookupError("incident")
                await connection.execute("""INSERT INTO incident_reviews (incident_id,reviewer_id,decision,notes)
                    VALUES (%s,%s,%s,%s) ON CONFLICT (incident_id,reviewer_id) DO UPDATE SET
                    decision=EXCLUDED.decision,notes=EXCLUDED.notes,created_at=NOW()""",
                    (incident_id, reviewer_id, decision, notes))
                await connection.execute("""UPDATE incidents SET workflow_status=%s,
                    verification_count=(SELECT count(*) FROM incident_reviews WHERE incident_id=%s),
                    updated_at=NOW() WHERE id=%s""", (decision, incident_id, incident_id))
                if decision in {"validado", "rejeitado"}:
                    adjustments = await connection.execute(
                        """INSERT INTO incident_trust_adjustments (incident_id,user_id,delta)
                        SELECT v.incident_id,v.user_id,CASE
                          WHEN (v.vote='confirmar' AND %s='validado') OR
                               (v.vote='rejeitar' AND %s='rejeitado') THEN 2
                          WHEN v.vote IN ('confirmar','rejeitar') THEN -3 ELSE 0 END
                        FROM incident_validations v WHERE v.incident_id=%s
                        ON CONFLICT (incident_id,user_id) DO NOTHING RETURNING user_id,delta""",
                        (decision, decision, incident_id),
                    )
                    for adjustment in await adjustments.fetchall():
                        await connection.execute(
                            "UPDATE users SET trust_score=LEAST(100,GREATEST(0,trust_score+%s)) WHERE id=%s",
                            (adjustment["delta"], adjustment["user_id"]),
                        )
