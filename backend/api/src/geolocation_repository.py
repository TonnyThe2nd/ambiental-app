from dataclasses import dataclass
from uuid import UUID

from .database import pool


@dataclass(frozen=True)
class NearbyUser:
    id: UUID
    fcm_token: str | None
    distance_km: float


async def find_users_within_radius(
    latitude: float, longitude: float, radius_meters: int = 10_000
) -> list[NearbyUser]:
    """Uses the partial GiST geography index; ST_DWithin is index-assisted."""
    point_sql = "ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography"
    async with pool.connection() as connection:
        async with connection.cursor() as cursor:
            await cursor.execute(
                f"""
                SELECT id, fcm_token,
                       ST_Distance(location, {point_sql}) / 1000.0 AS distance_km
                FROM users
                WHERE location IS NOT NULL
                  AND ST_DWithin(location, {point_sql}, %s)
                """,
                (longitude, latitude, longitude, latitude, radius_meters),
            )
            rows = await cursor.fetchall()
    return [NearbyUser(row["id"], row["fcm_token"], row["distance_km"]) for row in rows]
