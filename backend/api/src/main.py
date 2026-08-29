from contextlib import asynccontextmanager
from uuid import UUID
from fastapi import FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware

from .database import lifespan_pool, pool
from .auth import CurrentUser, login_user, register_user, update_user_location
from .producer import DuplicateIncidentError, create_incident_with_outbox
from .models import (
    AuthResponse,
    IncidentAccepted,
    IncidentInput,
    IncidentOutput,
    LoginInput,
    NotificationOutput,
    RegisterInput,
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


@app.get("/health")
async def health(response: Response) -> dict[str, str]:
    checks = {"database": "down"}
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
        await create_incident_with_outbox(incident, user.id)
    except DuplicateIncidentError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Incidente duplicado.") from error
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Não foi possível persistir o incidente.",
        ) from error
    return IncidentAccepted(**incident.model_dump(), reported_by=user)


@app.get("/incidents", response_model=list[IncidentOutput])
async def list_incidents(_: CurrentUser) -> list[IncidentOutput]:
    async with pool.connection() as connection:
        async with connection.cursor() as cursor:
            await cursor.execute(
                """
                SELECT i.id, i.category, i.latitude, i.longitude, i.occurred_at, i.image_url,
                       u.id AS user_id, u.name AS user_name, u.email AS user_email
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
            reported_by={"id": row["user_id"], "name": row["user_name"], "email": row["user_email"]}
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
                SELECT id, incident_id, title, message, distance_km, read_at, created_at
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
