import json
import logging
from datetime import timezone
from uuid import UUID, uuid4

from psycopg.errors import UniqueViolation

from .database import pool
from .messaging import ROUTING_KEY
from .models import IncidentInput

logger = logging.getLogger("urbaneye.producer")


class DuplicateIncidentError(Exception):
    pass


async def create_incident_with_outbox(incident: IncidentInput, user_id: UUID) -> UUID:
    event_id = uuid4()
    payload = {
        "eventId": str(event_id),
        "eventType": ROUTING_KEY,
        "occurredAt": incident.created_at.astimezone(timezone.utc).isoformat(),
        "data": {**incident.model_dump(mode="json", by_alias=True), "reportedBy": str(user_id)},
    }
    try:
        async with pool.connection() as connection:
            async with connection.transaction():
                await connection.execute(
                    """
                    INSERT INTO incidents
                      (id, category, latitude, longitude, occurred_at, image_url, reported_by, idempotency_key)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    """,
                    (incident.id, incident.category, incident.latitude, incident.longitude,
                     incident.created_at, incident.image_url, user_id, incident.idempotency_key),
                )
                await connection.execute(
                    "INSERT INTO outbox (id, aggregate_id, event_type, payload) VALUES (%s, %s, %s, %s::jsonb)",
                    (event_id, incident.id, ROUTING_KEY, json.dumps(payload)),
                )
    except UniqueViolation as error:
        logger.info("Incidente duplicado rejeitado: key=%s", incident.idempotency_key)
        raise DuplicateIncidentError from error
    logger.info("Incidente %s e evento %s gravados atomicamente", incident.id, event_id)
    return event_id
