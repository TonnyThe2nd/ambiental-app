from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field
from ...identity.presentation.schemas import UserOutput

class IncidentInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    id: UUID
    category: str = Field(min_length=1, max_length=100)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    created_at: datetime = Field(validation_alias="createdAt", serialization_alias="createdAt")
    image_url: str | None = Field(default=None, validation_alias="imageUrl", serialization_alias="imageUrl", max_length=2048)
    environmental_context: dict = Field(default_factory=dict, validation_alias="environmentalContext", serialization_alias="environmentalContext")
    idempotency_key: str = Field(validation_alias="idempotencyKey", serialization_alias="idempotencyKey", min_length=32, max_length=64, pattern=r"^[a-fA-F0-9]+$")

class IncidentOutput(IncidentInput):
    idempotency_key: str | None = Field(default=None, serialization_alias="idempotencyKey")
    reported_by: UserOutput | None = Field(default=None, serialization_alias="reportedBy")
    severity: str = "moderado"
    risk_score: float = Field(default=50, serialization_alias="riskScore")
    health_impact: str | None = Field(default=None, serialization_alias="healthImpact")
    ecosystem_impact: str | None = Field(default=None, serialization_alias="ecosystemImpact")
    community_impact: str | None = Field(default=None, serialization_alias="communityImpact")
    workflow_status: str = Field(default="reportado", serialization_alias="workflowStatus")
    confidence_score: float = Field(default=50, serialization_alias="confidenceScore")
    priority_score: float = Field(default=50, serialization_alias="priorityScore")
    confirmation_count: int = Field(default=0, serialization_alias="confirmationCount")
    rejection_count: int = Field(default=0, serialization_alias="rejectionCount")
    complement_count: int = Field(default=0, serialization_alias="complementCount")
    updated_at: datetime | None = Field(default=None, serialization_alias="updatedAt")

class IncidentAccepted(IncidentOutput):
    status: str = "accepted"

class ReviewInput(BaseModel):
    decision: str = Field(pattern=r"^(em_analise|validado|rejeitado|resolvido)$")
    notes: str | None = Field(default=None, max_length=2000)

class CommunityValidationInput(BaseModel):
    vote: str = Field(pattern=r"^(confirmar|rejeitar|complementar)$")
    comment: str | None = Field(default=None, max_length=2000)
    evidence_url: str | None = Field(default=None, validation_alias="evidenceUrl", max_length=2048)
