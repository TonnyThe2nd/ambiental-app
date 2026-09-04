import json
from uuid import UUID, uuid4

from psycopg.errors import UniqueViolation

from ...shared.domain.exceptions import ConflictError
from ...shared.infrastructure.database import pool
from ..domain.entities import User, UserRole


def _user(row) -> User:
    return User(row["id"], row["name"], row["email"], UserRole(row["role"]), float(row["trust_score"]))


class PostgresUserRepository:
    async def create(self, *, name: str, email: str, password_hash: str,
                     latitude: float, longitude: float) -> User:
        user_id = uuid4()
        try:
            async with pool.connection() as connection:
                await connection.execute(
                    """INSERT INTO users (id, name, email, password_hash, latitude, longitude, location, location_updated_at)
                       VALUES (%s, %s, %s, %s, %s, %s,
                       ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, NOW())""",
                    (user_id, name, email, password_hash, latitude, longitude, longitude, latitude),
                )
                await connection.commit()
        except UniqueViolation as error:
            raise ConflictError("email_already_registered") from error
        return User(user_id, name, email)

    async def find_credentials_by_email(self, email: str):
        async with pool.connection() as connection:
            result = await connection.execute(
                "SELECT id, name, email, password_hash, role, trust_score FROM users WHERE email = %s", (email,)
            )
            row = await result.fetchone()
        return (_user(row), row["password_hash"]) if row else None

    async def find_by_id(self, user_id: UUID):
        async with pool.connection() as connection:
            result = await connection.execute(
                "SELECT id, name, email, role, trust_score FROM users WHERE id = %s", (user_id,)
            )
            row = await result.fetchone()
        return _user(row) if row else None

    async def update_location(self, user_id: UUID, **v) -> None:
        route = None if v.get("route") is None else json.dumps(
            [{"latitude": p[0], "longitude": p[1]} for p in v["route"]]
        )
        async with pool.connection() as connection:
            await connection.execute(
                """UPDATE users SET latitude=%s, longitude=%s,
                location=ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography,
                fcm_token=COALESCE(%s,fcm_token), location_updated_at=NOW(),
                alert_route=CASE WHEN %s::jsonb IS NULL THEN alert_route WHEN jsonb_array_length(%s::jsonb)>=2 THEN
                  (SELECT ST_MakeLine(ST_SetSRID(ST_MakePoint(p.longitude,p.latitude),4326) ORDER BY p.ordinality)::geography
                   FROM jsonb_to_recordset(%s::jsonb) WITH ORDINALITY AS p(latitude float8,longitude float8,ordinality bigint)) ELSE NULL END,
                alert_route_expires_at=CASE WHEN %s::jsonb IS NULL THEN alert_route_expires_at WHEN jsonb_array_length(%s::jsonb)>=2
                  THEN NOW()+(%s*INTERVAL '1 minute') ELSE NULL END, route_alert_radius_m=%s WHERE id=%s""",
                (v["latitude"],v["longitude"],v["longitude"],v["latitude"],v.get("fcm_token"),
                 route,route,route,route,route,v.get("route_ttl_minutes",120),v.get("route_alert_radius_meters",750),user_id),
            )
            await connection.commit()

    async def update_alert_preferences(self, user_id: UUID, **v) -> None:
        async with pool.connection() as connection:
            await connection.execute(
                """UPDATE users SET alert_radius_m=%s,alert_categories=%s,minimum_alert_severity=%s,
                alert_cooldown_minutes=%s,quiet_hours_start=%s,quiet_hours_end=%s WHERE id=%s""",
                (v["radius_meters"],v["categories"],v["minimum_severity"],v["cooldown_minutes"],
                 v.get("quiet_hours_start"),v.get("quiet_hours_end"),user_id),
            )
            await connection.commit()
