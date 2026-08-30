from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from uuid import UUID
from fastapi import FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from psycopg.types.json import Jsonb

from .database import lifespan_pool, pool
from .auth import CurrentUser, login_user, register_user, update_alert_preferences, update_user_location
from .producer import DuplicateIncidentError, create_incident_with_outbox
from .models import (
    AlertPreferencesInput,
    AuthResponse,
    IncidentAccepted,
    EnvironmentalObservationInput,
    IncidentInput,
    IncidentOutput,
    LoginInput,
    NotificationOutput,
    RegisterInput,
    ReviewInput,
    UserLocationInput,
    UserOutput,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    async with lifespan_pool():
        yield


app = FastAPI(title="UrbanEye API", version="2.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrinja para os domínios do app web antes de publicar.
    allow_methods=["GET", "POST", "PUT"],
    allow_headers=["*"],
)


@app.post("/auth/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(data: RegisterInput) -> AuthResponse:
    return await register_user(data)


@app.post("/auth/login", response_model=AuthResponse)
async def login(data: LoginInput) -> AuthResponse:
    return await login_user(data)


@app.get("/auth/me", response_model=UserOutput)
async def me(user: CurrentUser) -> UserOutput:
    return user


@app.put("/auth/me/location", status_code=status.HTTP_204_NO_CONTENT)
async def update_location(data: UserLocationInput, user: CurrentUser) -> Response:
    await update_user_location(user.id, data)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.put("/auth/me/alert-preferences", status_code=status.HTTP_204_NO_CONTENT)
async def alert_preferences(data: AlertPreferencesInput, user: CurrentUser) -> Response:
    await update_alert_preferences(user.id, data)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/health")
async def health(response: Response) -> dict[str, str]:
    checks = {"api": "up", "database": "down"}
    try:
        async with pool.connection() as connection:
            await connection.execute("SELECT 1")
        checks["database"] = "up"
    except Exception:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return checks


@app.get("/ping")
async def ping() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/incidents", response_model=IncidentAccepted, status_code=status.HTTP_202_ACCEPTED)
async def create_incident(incident: IncidentInput, user: CurrentUser) -> IncidentAccepted:
    try:
        _, assessment = await create_incident_with_outbox(incident, user.id)
    except DuplicateIncidentError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Incidente duplicado.") from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Não foi possível persistir o incidente.",
        ) from error
    return IncidentAccepted(
        **incident.model_dump(), reported_by=user, severity=assessment.severity,
        risk_score=assessment.score, health_impact=assessment.health_impact,
        ecosystem_impact=assessment.ecosystem_impact, community_impact=assessment.community_impact,
    )


@app.get("/incidents", response_model=list[IncidentOutput])
async def list_incidents(_: CurrentUser) -> list[IncidentOutput]:
    async with pool.connection() as connection:
        async with connection.cursor() as cursor:
            await cursor.execute(
                """
                SELECT i.id, i.category, i.latitude, i.longitude, i.occurred_at, i.image_url,
                       i.severity, i.risk_score, i.health_impact, i.ecosystem_impact,
                       i.community_impact, i.workflow_status, i.environmental_context,
                       u.id AS user_id, u.name AS user_name, u.email AS user_email,
                       u.role AS user_role, u.trust_score AS user_trust_score
                FROM incidents i LEFT JOIN users u ON u.id = i.reported_by
                ORDER BY occurred_at DESC
                """
            )
            rows = await cursor.fetchall()
    return [
        IncidentOutput(
            id=row["id"],
            category=row["category"],
            latitude=row["latitude"],
            longitude=row["longitude"],
            created_at=row["occurred_at"],
            image_url=row["image_url"],
            environmental_context=row["environmental_context"], severity=row["severity"],
            risk_score=row["risk_score"], health_impact=row["health_impact"],
            ecosystem_impact=row["ecosystem_impact"], community_impact=row["community_impact"],
            workflow_status=row["workflow_status"],
            reported_by={"id": row["user_id"], "name": row["user_name"], "email": row["user_email"],
                         "role": row["user_role"], "trustScore": row["user_trust_score"]}
            if row["user_id"] else None,
        )
        for row in rows
    ]


@app.get("/notifications", response_model=list[NotificationOutput])
async def list_notifications(user: CurrentUser, unread_only: bool = True) -> list[NotificationOutput]:
    async with pool.connection() as connection:
        async with connection.cursor() as cursor:
            await cursor.execute(
                """
                SELECT id, incident_id, title, message, distance_km, read_at, created_at, severity
                FROM notifications
                WHERE user_id = %s AND (%s = FALSE OR read_at IS NULL)
                ORDER BY created_at DESC
                LIMIT 50
                """,
                (user.id, unread_only),
            )
            rows = await cursor.fetchall()
    return [
        NotificationOutput(
            id=row["id"],
            incident_id=row["incident_id"],
            title=row["title"],
            message=row["message"],
            distance_km=row["distance_km"],
            read_at=row["read_at"],
            created_at=row["created_at"],
            severity=row["severity"],
        )
        for row in rows
    ]


@app.post("/notifications/{notification_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_notification_read(notification_id: UUID, user: CurrentUser) -> Response:
    async with pool.connection() as connection:
        await connection.execute(
            "UPDATE notifications SET read_at = NOW() WHERE id = %s AND user_id = %s AND read_at IS NULL",
            (notification_id, user.id),
        )
        await connection.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def require_operator(user: UserOutput) -> None:
    if user.role not in {"moderador", "administrador"}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Perfil de moderação necessário.")


@app.post("/incidents/{incident_id}/reviews", status_code=status.HTTP_204_NO_CONTENT)
async def review_incident(incident_id: UUID, data: ReviewInput, user: CurrentUser) -> Response:
    require_operator(user)
    async with pool.connection() as connection:
        async with connection.transaction():
            exists = await connection.execute("SELECT 1 FROM incidents WHERE id = %s", (incident_id,))
            if await exists.fetchone() is None:
                raise HTTPException(status_code=404, detail="Ocorrência não encontrada.")
            await connection.execute(
                """INSERT INTO incident_reviews (incident_id, reviewer_id, decision, notes)
                   VALUES (%s, %s, %s, %s)
                   ON CONFLICT (incident_id, reviewer_id) DO UPDATE SET
                   decision = EXCLUDED.decision, notes = EXCLUDED.notes, created_at = NOW()""",
                (incident_id, user.id, data.decision, data.notes),
            )
            await connection.execute(
                """UPDATE incidents SET workflow_status = %s,
                   verification_count = (SELECT count(*) FROM incident_reviews WHERE incident_id = %s),
                   updated_at = NOW() WHERE id = %s""", (data.decision, incident_id, incident_id),
            )
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get("/dashboard/summary")
async def dashboard_summary(user: CurrentUser, days: int = 30) -> dict:
    require_operator(user)
    days = min(max(days, 1), 365)
    since = datetime.now(timezone.utc) - timedelta(days=days)
    async with pool.connection() as connection:
        categories = await connection.execute(
            """SELECT category, severity, workflow_status, count(*) AS total,
                      round(avg(risk_score), 2) AS average_risk
               FROM incidents WHERE occurred_at >= %s
               GROUP BY category, severity, workflow_status ORDER BY total DESC""", (since,)
        )
        breakdown = await categories.fetchall()
        hotspots = await connection.execute(
            """SELECT ST_Y(ST_Centroid(ST_Collect(location::geometry))) AS latitude,
                      ST_X(ST_Centroid(ST_Collect(location::geometry))) AS longitude,
                      count(*) AS total, max(risk_score) AS maximum_risk
               FROM incidents WHERE occurred_at >= %s
               GROUP BY ST_SnapToGrid(location::geometry, 0.01)
               HAVING count(*) >= 2 ORDER BY total DESC LIMIT 50""", (since,)
        )
        hotspot_rows = await hotspots.fetchall()
        trend = await connection.execute(
            """SELECT date_trunc('day', occurred_at) AS day, count(*) AS total,
                      count(*) FILTER (WHERE severity = 'critico') AS critical
               FROM incidents WHERE occurred_at >= %s GROUP BY day ORDER BY day""", (since,)
        )
        trend_rows = await trend.fetchall()
    return {"periodDays": days, "breakdown": breakdown, "hotspots": hotspot_rows, "trend": trend_rows}


@app.get("/operations/metrics")
async def operational_metrics(user: CurrentUser) -> dict:
    if user.role != "administrador":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso administrativo necessário.")
    async with pool.connection() as connection:
        result = await connection.execute(
            """SELECT (SELECT count(*) FROM outbox) AS outbox_pending,
                 (SELECT count(*) FROM outbox WHERE attempts > 0) AS outbox_retries,
                 (SELECT count(*) FROM notifications WHERE created_at >= NOW() - INTERVAL '24 hours') AS notifications_24h,
                 (SELECT count(*) FROM processed_events WHERE processed_at >= NOW() - INTERVAL '24 hours') AS events_24h"""
        )
        return await result.fetchone()


@app.post("/environmental-observations", status_code=status.HTTP_202_ACCEPTED)
async def ingest_observation(data: EnvironmentalObservationInput, user: CurrentUser) -> dict[str, str]:
    if user.role != "administrador":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Acesso administrativo necessário.")
    async with pool.connection() as connection:
        await connection.execute(
            """INSERT INTO environmental_observations
               (region_key, observed_at, source, temperature_c, humidity_percent,
                rainfall_mm, air_quality_index, payload)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (region_key, observed_at, source) DO UPDATE SET
               temperature_c = EXCLUDED.temperature_c, humidity_percent = EXCLUDED.humidity_percent,
               rainfall_mm = EXCLUDED.rainfall_mm, air_quality_index = EXCLUDED.air_quality_index,
               payload = EXCLUDED.payload""",
            (data.region_key, data.observed_at, data.source, data.temperature_c,
             data.humidity_percent, data.rainfall_mm, data.air_quality_index, Jsonb(data.payload)),
        )
        await connection.commit()
    return {"status": "accepted"}


@app.get("/environmental-observations/{region_key}")
async def observation_history(region_key: str, user: CurrentUser, days: int = 30) -> list[dict]:
    days = min(max(days, 1), 365)
    since = datetime.now(timezone.utc) - timedelta(days=days)
    async with pool.connection() as connection:
        result = await connection.execute(
            """SELECT observed_at, source, temperature_c, humidity_percent, rainfall_mm,
                      air_quality_index, payload FROM environmental_observations
               WHERE region_key = %s AND observed_at >= %s ORDER BY observed_at DESC LIMIT 1000""",
            (region_key, since),
        )
        return await result.fetchall()
