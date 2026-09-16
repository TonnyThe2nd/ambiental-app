import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from .database import lifespan_pool
from .identity.presentation.router import create_identity_router
from .alerts.application.notification_use_cases import ListNotifications, MarkNotificationRead
from .alerts.infrastructure.postgres_notification_repository import PostgresNotificationRepository
from .alerts.presentation.router import create_alerts_router
from .incidents.application.use_cases import CreateIncident, ListIncidents, ReviewIncident, ValidateIncident
from .incidents.infrastructure.postgres_incident_repository import PostgresIncidentRepository
from .incidents.presentation.router import create_incidents_router
from .monitoring.application.health_service import GetSystemHealth
from .monitoring.application.observation_use_cases import GetObservationHistory, SaveObservation
from .monitoring.infrastructure.health_checks import PostgresHealthCheck, RabbitMqHealthCheck
from .monitoring.infrastructure.postgres_observation_repository import PostgresObservationRepository
from .monitoring.presentation.router import create_monitoring_router
from .operations.application.use_cases import OperationsUseCases
from .operations.infrastructure.postgres_operations_repository import PostgresOperationsRepository
from .operations.presentation.router import create_operations_router


@asynccontextmanager
async def lifespan(_: FastAPI):
    async with lifespan_pool(): yield


def create_app() -> FastAPI:
    production = os.getenv("ENV", "development") == "production"
    application = FastAPI(title="UrbanEye API", version="2.0.0", lifespan=lifespan,
        docs_url=None if production else "/docs", redoc_url=None,
        openapi_url=None if production else "/openapi.json")
    limiter = Limiter(key_func=get_remote_address)
    application.state.limiter = limiter
    application.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    origins = [item.strip() for item in os.getenv("ALLOWED_ORIGINS", "").split(",") if item.strip()]
    application.add_middleware(CORSMiddleware, allow_origins=origins or ["http://localhost:3000"],
        allow_methods=["GET", "POST", "PUT", "DELETE"], allow_headers=["Authorization", "Content-Type"])

    notifications = PostgresNotificationRepository()
    incidents = PostgresIncidentRepository()
    observations = PostgresObservationRepository()
    operations = PostgresOperationsRepository()
    application.include_router(create_identity_router(limiter))
    application.include_router(create_alerts_router(ListNotifications(notifications), MarkNotificationRead(notifications)))
    application.include_router(create_incidents_router(CreateIncident(incidents), ListIncidents(incidents), ValidateIncident(incidents), ReviewIncident(incidents)))
    application.include_router(create_monitoring_router(GetSystemHealth(PostgresHealthCheck(), RabbitMqHealthCheck()), SaveObservation(observations), GetObservationHistory(observations)))
    application.include_router(create_operations_router(OperationsUseCases(operations)))

    @application.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if production: response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        return response
    return application


app = create_app()
