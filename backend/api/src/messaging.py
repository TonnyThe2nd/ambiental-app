import json
import os
from datetime import datetime, timezone
from uuid import uuid4

import aio_pika
from aio_pika import DeliveryMode, ExchangeType, Message
from aio_pika.abc import AbstractRobustChannel, AbstractRobustConnection

from .models import IncidentInput

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost/")
EVENT_EXCHANGE = "urbaneye.events"
RETRY_EXCHANGE = "urbaneye.retry"
DEAD_EXCHANGE = "urbaneye.dead"
INCIDENT_QUEUE = "incidents.create"
RETRY_QUEUE = "incidents.create.retry"
DEAD_QUEUE = "incidents.create.dead"
ROUTING_KEY = "incident.created.v1"
RETRY_ROUTING_KEY = "incident.created.retry.v1"


async def declare_topology(channel: AbstractRobustChannel) -> None:
    events = await channel.declare_exchange(EVENT_EXCHANGE, ExchangeType.TOPIC, durable=True)
    retry = await channel.declare_exchange(RETRY_EXCHANGE, ExchangeType.DIRECT, durable=True)
    dead = await channel.declare_exchange(DEAD_EXCHANGE, ExchangeType.DIRECT, durable=True)
    queue = await channel.declare_queue(
        INCIDENT_QUEUE,
        durable=True,
        arguments={"x-queue-type": "quorum", "x-dead-letter-exchange": RETRY_EXCHANGE, "x-dead-letter-routing-key": RETRY_ROUTING_KEY},
    )
    await queue.bind(events, ROUTING_KEY)
    retry_queue = await channel.declare_queue(
        RETRY_QUEUE,
        durable=True,
        arguments={"x-queue-type": "quorum", "x-message-ttl": 5000, "x-dead-letter-exchange": EVENT_EXCHANGE, "x-dead-letter-routing-key": ROUTING_KEY},
    )
    await retry_queue.bind(retry, RETRY_ROUTING_KEY)
    dead_queue = await channel.declare_queue(DEAD_QUEUE, durable=True, arguments={"x-queue-type": "quorum"})
    await dead_queue.bind(dead, ROUTING_KEY)


class EventPublisher:
    def __init__(self) -> None:
        self.connection: AbstractRobustConnection | None = None
        self.channel: AbstractRobustChannel | None = None

    async def connect(self) -> None:
        self.connection = await aio_pika.connect_robust(RABBITMQ_URL)
        self.channel = await self.connection.channel(publisher_confirms=True, on_return_raises=True)
        await declare_topology(self.channel)

    async def close(self) -> None:
        if self.connection is not None:
            await self.connection.close()

    async def publish_incident_created(self, incident: IncidentInput, user_id: str) -> str:
        if self.channel is None:
            raise RuntimeError("Publisher RabbitMQ não inicializado.")
        event_id = str(uuid4())
        payload = {
            "eventId": event_id,
            "eventType": ROUTING_KEY,
            "occurredAt": datetime.now(timezone.utc).isoformat(),
            "data": {**incident.model_dump(mode="json", by_alias=True), "reportedBy": user_id},
        }
        message = Message(
            body=json.dumps(payload).encode(), content_type="application/json",
            delivery_mode=DeliveryMode.PERSISTENT, message_id=event_id,
            correlation_id=str(incident.id), type=ROUTING_KEY,
            timestamp=datetime.now(timezone.utc),
        )
        exchange = await self.channel.get_exchange(EVENT_EXCHANGE)
        await exchange.publish(message, routing_key=ROUTING_KEY, mandatory=True)
        return event_id

    async def publish_envelope(self, payload: dict, event_id: str, event_type: str) -> None:
        if self.channel is None:
            raise RuntimeError("Publisher RabbitMQ não inicializado.")
        message = Message(
            body=json.dumps(payload).encode(), content_type="application/json",
            delivery_mode=DeliveryMode.PERSISTENT, message_id=event_id,
            correlation_id=str(payload.get("data", {}).get("id", "")), type=event_type,
            timestamp=datetime.now(timezone.utc),
        )
        exchange = await self.channel.get_exchange(EVENT_EXCHANGE)
        await exchange.publish(message, routing_key=event_type, mandatory=True)


publisher = EventPublisher()
