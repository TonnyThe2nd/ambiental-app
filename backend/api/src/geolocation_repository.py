from dataclasses import dataclass
from uuid import UUID

from .database import pool


@dataclass(frozen=True)
class NearbyUser:
    id: UUID
    fcm_token: str | None
    distance_km: float
    reason: str


async def find_users_within_radius(
    latitude: float, longitude: float, category: str, severity: str
) -> list[NearbyUser]:
    """Uses the partial GiST geography index; ST_DWithin is index-assisted."""
    point_sql = "ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography"
    async with pool.connection() as connection:
        async with connection.cursor() as cursor:
            await cursor.execute(
                f"""
                SELECT id, fcm_token,
                       ST_Distance(location, {point_sql}) / 1000.0 AS distance_km
                       , CASE WHEN alert_route IS NOT NULL AND alert_route_expires_at > NOW() AND
                         ST_DWithin(alert_route, {point_sql}, route_alert_radius_m)
                         THEN 'route' ELSE 'proximity' END AS reason
                FROM users
                WHERE location IS NOT NULL
                  AND (ST_DWithin(location, {point_sql}, alert_radius_m) OR
                       (alert_route IS NOT NULL AND alert_route_expires_at > NOW() AND
                        ST_DWithin(alert_route, {point_sql}, route_alert_radius_m)))
                  AND (cardinality(alert_categories) = 0 OR %s = ANY(alert_categories))
                  AND CASE minimum_alert_severity
                        WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                      <= CASE %s WHEN 'leve' THEN 1 WHEN 'moderado' THEN 2 ELSE 3 END
                  AND NOT EXISTS (
                    SELECT 1 FROM notifications n WHERE n.user_id = users.id
                      AND n.created_at > NOW() - (alert_cooldown_minutes * INTERVAL '1 minute')
                      AND n.severity = %s
                  )
                  AND (%s = 'critico' OR quiet_hours_start IS NULL OR quiet_hours_end IS NULL OR
                       CASE WHEN quiet_hours_start < quiet_hours_end
                         THEN LOCALTIME NOT BETWEEN quiet_hours_start AND quiet_hours_end
                         ELSE LOCALTIME > quiet_hours_end AND LOCALTIME < quiet_hours_start END)
                """,
                (longitude, latitude, longitude, latitude, longitude, latitude, longitude, latitude,
                 category, severity, severity, severity),
            )
            rows = await cursor.fetchall()
    return [NearbyUser(row["id"], row["fcm_token"], row["distance_km"], row["reason"]) for row in rows]


async def nearest_sensitive_area_criticality(latitude: float, longitude: float) -> int:
    """Returns criticality only when the event is inside an area's protection radius."""
    async with pool.connection() as connection:
        result = await connection.execute(
            """SELECT criticality FROM sensitive_areas
               WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography,
                                protection_radius_m)
               ORDER BY criticality DESC, ST_Distance(location,
                       ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) LIMIT 1""",
            (longitude, latitude, longitude, latitude),
        )
        row = await result.fetchone()
    return int(row["criticality"]) if row else 0
