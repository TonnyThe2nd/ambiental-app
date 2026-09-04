from enum import StrEnum
from uuid import UUID
from pydantic import BaseModel, ConfigDict, EmailStr, Field

class Severity(StrEnum):
    LEVE = "leve"
    MODERADO = "moderado"
    CRITICO = "critico"

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

class AuthResponse(BaseModel):
    access_token: str = Field(serialization_alias="accessToken")
    token_type: str = Field(default="bearer", serialization_alias="tokenType")
    user: UserOutput

class AlertPreferencesInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    radius_meters: int = Field(default=10_000, ge=500, le=50_000, validation_alias="radiusMeters")
    categories: list[str] = Field(default_factory=list, max_length=30)
    minimum_severity: Severity = Field(default=Severity.MODERADO, validation_alias="minimumSeverity")
    cooldown_minutes: int = Field(default=60, ge=5, le=1440, validation_alias="cooldownMinutes")
    quiet_hours_start: str | None = Field(default=None, validation_alias="quietHoursStart", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    quiet_hours_end: str | None = Field(default=None, validation_alias="quietHoursEnd", pattern=r"^([01]\d|2[0-3]):[0-5]\d$")

class UserLocationInput(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    fcm_token: str | None = Field(default=None, validation_alias="fcmToken", max_length=4096)
    route: list[tuple[float, float]] | None = Field(default=None, max_length=500)
    route_alert_radius_meters: int = Field(default=750, ge=100, le=5000, validation_alias="routeAlertRadiusMeters")
    route_ttl_minutes: int = Field(default=120, ge=5, le=1440, validation_alias="routeTtlMinutes")
