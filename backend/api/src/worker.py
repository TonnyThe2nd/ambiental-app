import asyncio
import json
import logging
import os

import aio_pika
from aio_pika import DeliveryMode, Message
from aio_pika.abc import AbstractIncomingMessage
from pydantic import ValidationError

from .database import lifespan_pool, pool
from .geolocation_repository import NearbyUser, find_users_within_radius
from .messaging import DEAD_EXCHANGE, INCIDENT_QUEUE, RABBITMQ_URL, ROUTING_KEY, declare_topology
from .models import IncidentInput

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("urbaneye.worker")
MAX_RETRIES = int(os.getenv("WORKER_MAX_RETRIES", "5"))
PREFETCH_COUNT = int(os.getenv("WORKER_PREFETCH", "1"))
FCM_BATCH_SIZE, FCM_TIMEOUT_SECONDS = 500, 15


def retry_count(message: AbstractIncomingMessage) -> int:
    deaths = message.headers.get("x-death", []) if message.headers else []
    return sum(int(item.get("count", 0)) for item in deaths if item.get("queue") == INCIDENT_QUEUE)


def category_label(category: str) -> str:
    return {"alagamento": "alagamento", "poluicao": "poluição", "lixo": "descarte de lixo"}.get(category, "ocorrência ambiental")


async def persist_notifications(incident: IncidentInput, users: list[NearbyUser]) -> None:
    if not users:
        return
    async with pool.connection() as connection:
        async with connection.transaction():
            await connection.executemany(
                """INSERT INTO notifications (id, user_id, incident_id, title, message, distance_km)
                   VALUES (gen_random_uuid(), %s, %s, %s, %s, %s)
                   ON CONFLICT (user_id, incident_id) DO NOTHING""",
                [(u.id, incident.id, "Nova ocorrência perto de você",
                  f"Foi registrado {category_label(incident.category)} a {u.distance_km:.1f} km de você.", u.distance_km)
                 for u in users],
            )


def _send_fcm_batch(tokens: list[str], incident: IncidentInput):
    import firebase_admin
    from firebase_admin import credentials, messaging
    if not firebase_admin._apps:
        path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
        firebase_admin.initialize_app(credentials.Certificate(path) if path else None)
    return messaging.send_each_for_multicast(messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title="Nova ocorrência perto de você",
            body=f"Foi registrado {category_label(incident.category)} em um raio de 10 km.",
        ),
        data={"incidentId": str(incident.id), "category": incident.category},
    ))


async def dispatch_fcm(incident: IncidentInput, users: list[NearbyUser]) -> None:
    tokens = list(dict.fromkeys(u.fcm_token for u in users if u.fcm_token))
    if not tokens:
        logger.info("Incidente %s sem tokens FCM elegíveis", incident.id)
        return
    batches = [tokens[i:i + FCM_BATCH_SIZE] for i in range(0, len(tokens), FCM_BATCH_SIZE)]
    try:
        responses = await asyncio.wait_for(
            asyncio.gather(*(asyncio.to_thread(_send_fcm_batch, batch, incident) for batch in batches)),
            timeout=FCM_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError as error:
        logger.error("Timeout FCM após %ss para incidente %s", FCM_TIMEOUT_SECONDS, incident.id)
        raise RuntimeError("FCM timeout") from error
    logger.info("FCM incidente=%s batches=%s tokens=%s falhas=%s", incident.id, len(batches), len(tokens), sum(r.failure_count for r in responses))


async def process_event(envelope: dict) -> IncidentInput:
    incident = IncidentInput.model_validate(envelope["data"])
    users = await find_users_within_radius(incident.latitude, incident.longitude)
    await persist_notifications(incident, users)
    await dispatch_fcm(incident, users)
    return incident


async def consume() -> None:
    connection = await aio_pika.connect_robust(RABBITMQ_URL)
    async with connection, lifespan_pool():
        channel = await connection.channel(publisher_confirms=True)
        await channel.set_qos(prefetch_count=PREFETCH_COUNT)
        await declare_topology(channel)
        queue = await channel.get_queue(INCIDENT_QUEUE)
        async with queue.iterator() as messages:
            async for message in messages:
                try:
                    incident = await process_event(json.loads(message.body))
                except (json.JSONDecodeError, KeyError, ValidationError, ValueError) as error:
                    logger.error("Evento inválido enviado à DLQ: %s", error)
                    await _send_to_dead_letter(channel, message, str(error)); await message.ack()
                except Exception:
                    attempts = retry_count(message)
                    logger.exception("Falha ao processar %s (tentativa %s)", message.message_id, attempts + 1)
                    if attempts >= MAX_RETRIES:
                        await _send_to_dead_letter(channel, message, "Limite de tentativas excedido"); await message.ack()
                    else:
                        await message.reject(requeue=False)
                else:
                    await message.ack()  # somente após todos os lotes FCM terminarem
                    logger.info("Ocorrência %s notificada", incident.id)


async def _send_to_dead_letter(channel, source, reason: str) -> None:
    exchange = await channel.get_exchange(DEAD_EXCHANGE)
    headers = dict(source.headers or {}); headers["x-error-reason"] = reason[:500]
    await exchange.publish(Message(body=source.body, content_type=source.content_type,
        delivery_mode=DeliveryMode.PERSISTENT, message_id=source.message_id,
        correlation_id=source.correlation_id, type=source.type, headers=headers),
        routing_key=ROUTING_KEY, mandatory=True)


if __name__ == "__main__":
    asyncio.run(consume())
