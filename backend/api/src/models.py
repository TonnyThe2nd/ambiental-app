from datetime import datetime
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
    idempotency_key: str = Field(
        validation_alias="idempotencyKey", serialization_alias="idempotencyKey",
        min_length=32, max_length=64, pattern=r"^[a-fA-F0-9]+$",
    )


class IncidentOutput(IncidentInput):
    created_at: datetime = Field(serialization_alias="createdAt")
    idempotency_key: str | None = Field(default=None, serialization_alias="idempotencyKey")
    reported_by: UserOutput | None = Field(default=None, serialization_alias="reportedBy")


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
