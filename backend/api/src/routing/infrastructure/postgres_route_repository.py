from ...shared.infrastructure.database import pool
from ..domain.assessment import RouteIncident


def linestring_wkt(points: list[tuple[float, float]]) -> str:
    """Pontos (latitude, longitude) → WKT em ordem longitude/latitude, como o PostGIS espera."""
    return "SRID=4326;LINESTRING(" + ", ".join(f"{lon:.6f} {lat:.6f}" for lat, lon in points) + ")"


class PostgresRouteRepository:
    async def incidents_along(self, points: list[tuple[float, float]], corridor_m: int) -> list[RouteIncident]:
        """Ocorrências ativas cuja área de impacto (ou o corredor) toca a rota."""
        async with pool.connection() as connection:
            result = await connection.execute(
                """WITH route AS (SELECT ST_GeogFromText(%s) AS line)
                   SELECT i.id::text AS id, i.category, i.severity::text AS severity,
                          ST_Distance(route.line, i.location) AS distance_m,
                          i.latitude, i.longitude, COALESCE(i.impact_radius_m, 250) AS impact_radius_m
                   FROM incidents i, route
                   WHERE i.workflow_status NOT IN ('rejeitado', 'resolvido')
                     AND ST_DWithin(route.line, i.location, GREATEST(%s, COALESCE(i.impact_radius_m, 250)))
                   ORDER BY distance_m LIMIT 200""",
                (linestring_wkt(points), corridor_m),
            )
            rows = await result.fetchall()
        return [RouteIncident(r["id"], r["category"], r["severity"], float(r["distance_m"]),
                              r["latitude"], r["longitude"], r["impact_radius_m"]) for r in rows]
