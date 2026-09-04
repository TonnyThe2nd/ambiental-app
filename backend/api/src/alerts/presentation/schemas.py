from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field

class NotificationOutput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: UUID
    incident_id: UUID = Field(serialization_alias="incidentId")
    title: str
    message: str
    distance_km: float = Field(serialization_alias="distanceKm")
    read_at: datetime | None = Field(default=None, serialization_alias="readAt")
    created_at: datetime = Field(serialization_alias="createdAt")
    severity: str = "moderado"
