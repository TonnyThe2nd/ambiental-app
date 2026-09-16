from datetime import datetime
from psycopg.types.json import Jsonb
from ...database import pool


class PostgresObservationRepository:
    async def save(self, d: object) -> None:
        async with pool.connection() as c:
            await c.execute("""INSERT INTO environmental_observations
              (region_key,observed_at,source,temperature_c,humidity_percent,rainfall_mm,air_quality_index,payload)
              VALUES (%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (region_key,observed_at,source) DO UPDATE SET
              temperature_c=EXCLUDED.temperature_c,humidity_percent=EXCLUDED.humidity_percent,
              rainfall_mm=EXCLUDED.rainfall_mm,air_quality_index=EXCLUDED.air_quality_index,payload=EXCLUDED.payload""",
              (d.region_key,d.observed_at,d.source,d.temperature_c,d.humidity_percent,d.rainfall_mm,d.air_quality_index,Jsonb(d.payload)))
            await c.commit()

    async def history(self, region_key: str, since: datetime) -> list[dict]:
        async with pool.connection() as c:
            result=await c.execute("""SELECT observed_at,source,temperature_c,humidity_percent,rainfall_mm,
              air_quality_index,payload FROM environmental_observations WHERE region_key=%s AND observed_at>=%s
              ORDER BY observed_at DESC LIMIT 1000""",(region_key,since))
            return await result.fetchall()
