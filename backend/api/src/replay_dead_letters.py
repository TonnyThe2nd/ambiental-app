import asyncio
import logging
import os

import aio_pika
from aio_pika import DeliveryMode, Message

from .messaging import (
    DEAD_QUEUE,
    EVENT_EXCHANGE,
    RABBITMQ_URL,
    ROUTING_KEY,
    declare_topology,
)

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("urbaneye.replay")


async def replay() -> None:
    connection = await aio_pika.connect_robust(RABBITMQ_URL)
    async with connection:
        channel = await connection.channel(publisher_confirms=True, on_return_raises=True)
        await declare_topology(channel)
        source = await channel.get_queue(DEAD_QUEUE)
        destination = await channel.get_exchange(EVENT_EXCHANGE)
        replayed = 0
        while True:
            incoming = await source.get(fail=False)
            if incoming is None:
                break
            headers = dict(incoming.headers or {})
            headers.pop("x-error-reason", None)
            await destination.publish(
                Message(
                    body=incoming.body,
                    content_type=incoming.content_type,
                    delivery_mode=DeliveryMode.PERSISTENT,
                    message_id=incoming.message_id,
                    correlation_id=incoming.correlation_id,
                    type=ROUTING_KEY,
                    headers=headers,
                ),
                routing_key=ROUTING_KEY,
                mandatory=True,
            )
            await incoming.ack()
            replayed += 1
        logger.info("Eventos recuperados da DLQ: %s", replayed)


if __name__ == "__main__":
    asyncio.run(replay())
