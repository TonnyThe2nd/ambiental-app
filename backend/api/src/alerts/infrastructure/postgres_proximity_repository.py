from uuid import UUID

from ...incidents.domain.categories import category_label_sql
from ...shared.infrastructure.database import pool
from ..domain.proximity import NearbyIncident, ProximityAlert

_CATEGORY_LABEL = category_label_sql("e.category")


class PostgresProximityAlertRepository:
    async def find_push_token(self, user_id: UUID) -> str | None:
        async with pool.connection() as connection:
            result = await connection.execute("SELECT fcm_token FROM users WHERE id = %s", (user_id,))
            row = await result.fetchone()
        return row["fcm_token"] if row else None

    async def create_for_nearby_incidents(self, user_id: UUID) -> list[ProximityAlert]:
        """Alerta de entrada em área: a posição do usuário está dentro da área de impacto.

        A área de impacto depende da categoria e da gravidade (``impact_radius_m``). Antes a
        consulta usava o raio de alerta do usuário (10 km por padrão), então "entrar na área"
        disparava para qualquer ocorrência da cidade. ST_DWithin usa os índices GiST.
        """
        async with pool.connection() as connection:
            async with connection.transaction():
                result = await connection.execute(
                    f"""WITH eligible AS (
                         SELECT i.id, i.category, i.severity::text AS severity,
                                ST_Distance(u.location, i.location) / 1000.0 AS distance_km,
                                COALESCE(i.impact_radius_m, 250) AS impact_radius_m
                         FROM users u JOIN incidents i
                           ON ST_DWithin(u.location, i.location, COALESCE(i.impact_radius_m, 250))
                         WHERE u.id = %s AND u.location IS NOT NULL AND u.deleted_at IS NULL
                           AND i.workflow_status NOT IN ('rejeitado', 'resolvido')
                           AND i.reported_by IS DISTINCT FROM u.id
                           AND (cardinality(u.alert_categories) = 0 OR i.category = ANY(u.alert_categories))
                           AND CASE u.minimum_alert_severity WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                               <= CASE i.severity WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                           AND (i.severity = 'critico' OR u.quiet_hours_start IS NULL OR u.quiet_hours_end IS NULL OR
                             CASE WHEN u.quiet_hours_start < u.quiet_hours_end
                               THEN (NOW() AT TIME ZONE u.timezone)::time NOT BETWEEN u.quiet_hours_start AND u.quiet_hours_end
                               ELSE (NOW() AT TIME ZONE u.timezone)::time > u.quiet_hours_end
                                    AND (NOW() AT TIME ZONE u.timezone)::time < u.quiet_hours_start END)
                       ), inserted AS (
                         INSERT INTO notifications
                           (id,user_id,incident_id,title,message,distance_km,severity,reason,risk_score)
                         SELECT gen_random_uuid(), %s, e.id, 'Você entrou em uma área de risco',
                           'Área de ' || {_CATEGORY_LABEL} || ' (' || e.severity ||
                           ') a ' || round(e.distance_km * 1000)::int || ' m de você. Raio de impacto: ' ||
                           e.impact_radius_m || ' m.', e.distance_km,
                           e.severity::incident_severity, 'geofence_entry', i.risk_score
                         FROM eligible e JOIN incidents i ON i.id=e.id
                         ON CONFLICT (user_id,incident_id) DO NOTHING
                         RETURNING id,user_id,incident_id,title,message,distance_km,severity::text AS severity
                       ) SELECT n.*, i.category, i.latitude, i.longitude,
                                COALESCE(i.impact_radius_m, 250) AS impact_radius_m
                         FROM inserted n JOIN incidents i ON i.id=n.incident_id""",
                    (user_id, user_id),
                )
                rows = await result.fetchall()
        return [ProximityAlert(
            id=row["id"], user_id=row["user_id"],
            incident=NearbyIncident(row["incident_id"], row["category"], row["severity"], float(row["distance_km"]),
                                    row["latitude"], row["longitude"], row["impact_radius_m"]),
            title=row["title"], message=row["message"],
        ) for row in rows]
