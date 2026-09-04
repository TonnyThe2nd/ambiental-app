from uuid import UUID

from ...shared.infrastructure.database import pool
from ..domain.proximity import NearbyIncident, ProximityAlert


class PostgresProximityAlertRepository:
    async def find_push_token(self, user_id: UUID) -> str | None:
        async with pool.connection() as connection:
            result = await connection.execute("SELECT fcm_token FROM users WHERE id = %s", (user_id,))
            row = await result.fetchone()
        return row["fcm_token"] if row else None

    async def create_for_nearby_incidents(self, user_id: UUID) -> list[ProximityAlert]:
        """ST_DWithin uses the GiST geography indexes and distances are in meters."""
        async with pool.connection() as connection:
            async with connection.transaction():
                result = await connection.execute(
                    """WITH eligible AS (
                         SELECT i.id, i.category, i.severity::text AS severity,
                                ST_Distance(u.location, i.location) / 1000.0 AS distance_km
                         FROM users u JOIN incidents i ON ST_DWithin(u.location, i.location, u.alert_radius_m)
                         WHERE u.id = %s AND u.location IS NOT NULL
                           AND i.workflow_status NOT IN ('rejeitado', 'resolvido')
                           AND i.reported_by IS DISTINCT FROM u.id
                           AND (cardinality(u.alert_categories) = 0 OR i.category = ANY(u.alert_categories))
                           AND CASE u.minimum_alert_severity WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                               <= CASE i.severity WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                           AND (i.severity = 'critico' OR u.quiet_hours_start IS NULL OR u.quiet_hours_end IS NULL OR
                             CASE WHEN u.quiet_hours_start < u.quiet_hours_end
                               THEN LOCALTIME NOT BETWEEN u.quiet_hours_start AND u.quiet_hours_end
                               ELSE LOCALTIME > u.quiet_hours_end AND LOCALTIME < u.quiet_hours_start END)
                       ), inserted AS (
                         INSERT INTO notifications
                           (id,user_id,incident_id,title,message,distance_km,severity,reason,risk_score)
                         SELECT gen_random_uuid(), %s, e.id, 'Alerta ambiental na sua região',
                           'Você entrou na área de um registro de ' || e.category || ' a ' ||
                           to_char(e.distance_km, 'FM999990.0') || ' km.', e.distance_km,
                           e.severity::incident_severity, 'geofence_entry', i.risk_score
                         FROM eligible e JOIN incidents i ON i.id=e.id
                         ON CONFLICT (user_id,incident_id) DO NOTHING
                         RETURNING id,user_id,incident_id,title,message,distance_km,severity::text AS severity
                       ) SELECT n.*, i.category FROM inserted n JOIN incidents i ON i.id=n.incident_id""",
                    (user_id, user_id),
                )
                rows = await result.fetchall()
        return [ProximityAlert(
            id=row["id"], user_id=row["user_id"],
            incident=NearbyIncident(row["incident_id"], row["category"], row["severity"], float(row["distance_km"])),
            title=row["title"], message=row["message"],
        ) for row in rows]
