import json
import logging
from datetime import timezone
from uuid import UUID, uuid4

from psycopg.errors import UniqueViolation

from .database import pool
from .messaging import ROUTING_KEY
from .models import IncidentInput
from .geolocation_repository import nearest_sensitive_area_criticality
from .risk_analysis import RiskAssessment, assess_risk

logger = logging.getLogger("urbaneye.producer")


class DuplicateIncidentError(Exception):
    pass


async def create_incident_with_outbox(incident: IncidentInput, user_id: UUID) -> tuple[UUID, RiskAssessment]:
    event_id = uuid4()
    context = incident.environmental_context
    sensitive_criticality = await nearest_sensitive_area_criticality(incident.latitude, incident.longitude)
    assessment = assess_risk(
        incident.category,
        sensitive_area_criticality=sensitive_criticality,
        rainfall_mm=context.get("rainfallMm"),
        air_quality_index=context.get("airQualityIndex"),
    )
    payload = {
        "eventId": str(event_id),
        "eventType": ROUTING_KEY,
        "occurredAt": incident.created_at.astimezone(timezone.utc).isoformat(),
        "data": {**incident.model_dump(mode="json", by_alias=True), "reportedBy": str(user_id),
                 "severity": assessment.severity, "riskScore": assessment.score,
                 "sensitiveAreaCriticality": sensitive_criticality},
    }
    try:
        async with pool.connection() as connection:
            async with connection.transaction():
                await connection.execute(
                    """
                    INSERT INTO incidents
                      (id, category, latitude, longitude, location, occurred_at, image_url, reported_by,
                       idempotency_key, severity, risk_score, health_impact, ecosystem_impact,
                       community_impact, environmental_context)
                    VALUES (%s, %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography,
                            %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                    """,
                    (incident.id, incident.category, incident.latitude, incident.longitude,
                     incident.longitude, incident.latitude, incident.created_at, incident.image_url,
                     user_id, incident.idempotency_key, assessment.severity, assessment.score,
                     assessment.health_impact, assessment.ecosystem_impact, assessment.community_impact,
                     json.dumps(context)),
                )
                await connection.execute(
                    "INSERT INTO outbox (id, aggregate_id, event_type, payload) VALUES (%s, %s, %s, %s::jsonb)",
                    (event_id, incident.id, ROUTING_KEY, json.dumps(payload)),
                )
    except UniqueViolation as error:
        logger.info("Incidente duplicado rejeitado: key=%s", incident.idempotency_key)
        raise DuplicateIncidentError from error
    logger.info("Incidente %s e evento %s gravados atomicamente", incident.id, event_id)
    return event_id, assessment
