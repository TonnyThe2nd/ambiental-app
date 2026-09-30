from __future__ import annotations

import json
from uuid import UUID, uuid4
from ...community_validation import validate_incident
from ...database import pool as default_pool
from ...producer import create_incident_with_outbox
from ..application.ports import HeatmapFilters, IncidentFilters


STATUS_EVENT_TYPE = "incident.status.updated.v1"


class PostgresIncidentRepository:
    def __init__(self, database_pool=default_pool) -> None:
        self._pool = database_pool

    async def create(self, incident: object, reporter_id: UUID) -> tuple[object, object]:
        return await create_incident_with_outbox(incident, reporter_id)

    async def validate(self, incident_id: UUID, user_id: UUID, data: object) -> dict:
        return await validate_incident(incident_id, user_id, data)

    async def list(self, f: IncidentFilters) -> list[dict]:
        async with self._pool.connection() as connection:
            result = await connection.execute(
                """SELECT i.id, i.category, i.latitude, i.longitude, i.occurred_at AS created_at,
                   i.image_url, i.severity, i.risk_score, i.health_impact, i.ecosystem_impact,
                   i.community_impact, i.workflow_status, i.environmental_context, i.updated_at, i.geohash, i.impact_radius_m,
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

    async def heatmap(self, f: HeatmapFilters) -> list[dict]:
        """Agrega ocorrências por prefixo GeoHash; o índice text_pattern_ops atende ao LIKE."""
        prefixes = [cell + "%" for cell in f.cells]
        async with self._pool.connection() as connection:
            result = await connection.execute(
                """SELECT left(i.geohash, %s) AS cell, count(*)::int AS total,
                          round(avg(i.risk_score)::numeric, 2)::float8 AS avg_risk,
                          max(i.risk_score)::float8 AS max_risk,
                          count(*) FILTER (WHERE i.severity = 'critico')::int AS critical,
                          array_agg(DISTINCT i.category ORDER BY i.category) AS categories
                   FROM incidents i
                   WHERE i.geohash IS NOT NULL
                     AND i.occurred_at >= NOW() - (%s * INTERVAL '1 day')
                     AND (cardinality(%s::text[]) = 0 OR i.category = ANY(%s))
                     AND (%s = FALSE OR i.workflow_status NOT IN ('rejeitado', 'resolvido'))
                     AND (cardinality(%s::text[]) = 0 OR i.geohash LIKE ANY(%s::text[]))
                   GROUP BY 1 ORDER BY total DESC, cell LIMIT 2000""",
                (f.precision, f.days, f.categories, f.categories, f.active_only, prefixes, prefixes),
            )
            return await result.fetchall()

    async def save_photo(self, incident_id: UUID, user_id: UUID, content: bytes, content_type: str) -> None:
        async with self._pool.connection() as connection:
            async with connection.transaction():
                result = await connection.execute(
                    "SELECT reported_by FROM incidents WHERE id=%s FOR UPDATE", (incident_id,))
                row = await result.fetchone()
                if row is None: raise LookupError("incident")
                if row["reported_by"] != user_id: raise PermissionError("not_reporter")
                await connection.execute(
                    """INSERT INTO incident_photos (incident_id, content, content_type, size_bytes, uploaded_by)
                       VALUES (%s, %s, %s, %s, %s)
                       ON CONFLICT (incident_id) DO UPDATE SET content = EXCLUDED.content,
                         content_type = EXCLUDED.content_type, size_bytes = EXCLUDED.size_bytes,
                         updated_at = NOW()""",
                    (incident_id, content, content_type, len(content), user_id))
                # updated_at avança para o feed incremental do mapa trazer a nova foto.
                await connection.execute(
                    "UPDATE incidents SET image_url = %s, updated_at = NOW() WHERE id = %s",
                    (f"/incidents/{incident_id}/photo", incident_id))

    async def load_photo(self, incident_id: UUID) -> dict | None:
        async with self._pool.connection() as connection:
            result = await connection.execute(
                "SELECT content, content_type FROM incident_photos WHERE incident_id = %s", (incident_id,))
            return await result.fetchone()

    async def review(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None:
        async with self._pool.connection() as connection:
            async with connection.transaction():
                result = await connection.execute(
                    "SELECT latitude, longitude, geohash FROM incidents WHERE id=%s FOR UPDATE", (incident_id,))
                incident = await result.fetchone()
                if incident is None: raise LookupError("incident")
                await connection.execute("""INSERT INTO incident_reviews (incident_id,reviewer_id,decision,notes)
                    VALUES (%s,%s,%s,%s) ON CONFLICT (incident_id,reviewer_id) DO UPDATE SET
                    decision=EXCLUDED.decision,notes=EXCLUDED.notes,created_at=NOW()""",
                    (incident_id, reviewer_id, decision, notes))
                await connection.execute("""UPDATE incidents SET workflow_status=%s,
                    verification_count=(SELECT count(*) FROM incident_reviews WHERE incident_id=%s),
                    updated_at=NOW() WHERE id=%s""", (decision, incident_id, incident_id))
                # Mudança de estado pela moderação também vira evento, para o mapa em tempo real.
                event_id = uuid4()
                payload = {"eventId": str(event_id), "eventType": STATUS_EVENT_TYPE,
                           "data": {"id": str(incident_id), "workflowStatus": decision,
                                    "latitude": incident["latitude"], "longitude": incident["longitude"],
                                    "geohash": incident["geohash"]}}
                await connection.execute(
                    "INSERT INTO outbox (id, aggregate_id, event_type, payload) VALUES (%s, %s, %s, %s::jsonb)",
                    (event_id, incident_id, STATUS_EVENT_TYPE, json.dumps(payload)))
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
