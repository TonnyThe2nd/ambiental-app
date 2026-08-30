from datetime import datetime
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RegisterInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    name: str = Field(min_length=2, max_length=120)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class LoginInput(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class UserOutput(BaseModel):
    id: UUID
    name: str
    email: EmailStr
    role: str = "cidadao"
    trust_score: float = Field(default=50, serialization_alias="trustScore")


class Severity(StrEnum):
    LEVE = "leve"
    MODERADO = "moderado"
    CRITICO = "critico"


class AlertPreferencesInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    radius_meters: int = Field(default=10_000, ge=500, le=50_000, validation_alias="radiusMeters")
    categories: list[str] = Field(default_factory=list, max_length=30)
    minimum_severity: Severity = Field(default=Severity.MODERADO, validation_alias="minimumSeverity")
    cooldown_minutes: int = Field(default=60, ge=5, le=1440, validation_alias="cooldownMinutes")


class UserLocationInput(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    fcm_token: str | None = Field(default=None, validation_alias="fcmToken", max_length=4096)


class AuthResponse(BaseModel):
    access_token: str = Field(serialization_alias="accessToken")
    token_type: str = Field(default="bearer", serialization_alias="tokenType")
    user: UserOutput


class IncidentInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: UUID
    category: str = Field(min_length=1, max_length=100)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    created_at: datetime = Field(validation_alias="createdAt", serialization_alias="createdAt")
    image_url: str | None = Field(default=None, validation_alias="imageUrl", serialization_alias="imageUrl", max_length=2048)
    environmental_context: dict = Field(default_factory=dict, validation_alias="environmentalContext", serialization_alias="environmentalContext")
    idempotency_key: str = Field(
        validation_alias="idempotencyKey", serialization_alias="idempotencyKey",
        min_length=32, max_length=64, pattern=r"^[a-fA-F0-9]+$",
    )


class IncidentOutput(IncidentInput):
    created_at: datetime = Field(serialization_alias="createdAt")
    idempotency_key: str | None = Field(default=None, serialization_alias="idempotencyKey")
    reported_by: UserOutput | None = Field(default=None, serialization_alias="reportedBy")
    severity: Severity = Severity.MODERADO
    risk_score: float = Field(default=50, serialization_alias="riskScore")
    health_impact: str | None = Field(default=None, serialization_alias="healthImpact")
    ecosystem_impact: str | None = Field(default=None, serialization_alias="ecosystemImpact")
    community_impact: str | None = Field(default=None, serialization_alias="communityImpact")
    workflow_status: str = Field(default="reportado", serialization_alias="workflowStatus")


class IncidentAccepted(IncidentOutput):
    status: str = "accepted"


class NotificationOutput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: UUID
    incident_id: UUID = Field(serialization_alias="incidentId")
    title: str
    message: str
    distance_km: float = Field(serialization_alias="distanceKm")
    read_at: datetime | None = Field(default=None, serialization_alias="readAt")
    created_at: datetime = Field(serialization_alias="createdAt")
    severity: Severity = Severity.MODERADO


class ReviewInput(BaseModel):
    decision: str = Field(pattern=r"^(em_analise|validado|rejeitado|resolvido)$")
    notes: str | None = Field(default=None, max_length=2000)


class EnvironmentalObservationInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    region_key: str = Field(validation_alias="regionKey", min_length=2, max_length=80)
    observed_at: datetime = Field(validation_alias="observedAt")
    source: str = Field(min_length=2, max_length=100)
    temperature_c: float | None = Field(default=None, validation_alias="temperatureC", ge=-80, le=70)
    humidity_percent: float | None = Field(default=None, validation_alias="humidityPercent", ge=0, le=100)
    rainfall_mm: float | None = Field(default=None, validation_alias="rainfallMm", ge=0)
    air_quality_index: int | None = Field(default=None, validation_alias="airQualityIndex", ge=0, le=500)
    payload: dict = Field(default_factory=dict)
