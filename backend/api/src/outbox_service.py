import asyncio
import logging
import os

from .database import lifespan_pool, pool
from .messaging import publisher

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("urbaneye.outbox")
POLL_SECONDS = float(os.getenv("OUTBOX_POLL_SECONDS", "2"))
BATCH_SIZE = int(os.getenv("OUTBOX_BATCH_SIZE", "50"))
CLAIM_SECONDS = int(os.getenv("OUTBOX_CLAIM_SECONDS", "300"))


async def claim_batch() -> list[dict]:
    """Reserva eventos em uma transação curta antes de fazer I/O com o broker."""
    async with pool.connection() as connection:
        async with connection.transaction():
            result = await connection.execute(
                """
                WITH candidates AS (
                    SELECT id FROM outbox
                    WHERE available_at <= NOW()
                      AND (processing_token IS NULL OR locked_until <= NOW())
                    ORDER BY created_at
                    FOR UPDATE SKIP LOCKED LIMIT %s
                )
                UPDATE outbox AS event
                SET processing_token = gen_random_uuid(),
                    locked_until = NOW() + (%s * INTERVAL '1 second')
                FROM candidates
                WHERE event.id = candidates.id
                RETURNING event.id, event.event_type, event.payload, event.processing_token
                """,
                (BATCH_SIZE, CLAIM_SECONDS),
            )
            return await result.fetchall()


async def mark_published(event_id, processing_token) -> bool:
    async with pool.connection() as connection:
        async with connection.transaction():
            result = await connection.execute(
                "DELETE FROM outbox WHERE id = %s AND processing_token = %s RETURNING id",
                (event_id, processing_token),
            )
            return await result.fetchone() is not None


async def reschedule_failed(event_id, processing_token, error: Exception) -> bool:
    async with pool.connection() as connection:
        async with connection.transaction():
            result = await connection.execute(
                """UPDATE outbox SET attempts = attempts + 1, last_error = %s,
                   available_at = NOW() + (LEAST(3600, POWER(2, LEAST(attempts, 11))) * INTERVAL '1 second'),
                   processing_token = NULL, locked_until = NULL
                   WHERE id = %s AND processing_token = %s
                   RETURNING id""",
                (str(error)[:2000], event_id, processing_token),
            )
            return await result.fetchone() is not None


async def publish_batch() -> int:
    rows = await claim_batch()
    published = 0
    for row in rows:
        try:
            await publisher.publish_envelope(row["payload"], str(row["id"]), row["event_type"])
            if await mark_published(row["id"], row["processing_token"]):
                published += 1
            else:
                logger.warning("Outbox %s foi reassumida antes da confirmação", row["id"])
        except Exception as error:
            logger.exception("Falha ao publicar outbox %s", row["id"])
            if not await reschedule_failed(row["id"], row["processing_token"], error):
                logger.warning("Outbox %s foi reassumida antes do reagendamento", row["id"])
    return published


async def run() -> None:
    async with lifespan_pool():
        await publisher.connect()
        try:
            while True:
                count = await publish_batch()
                if count:
                    logger.info("Outbox: %s evento(s) confirmado(s) pelo broker", count)
                await asyncio.sleep(POLL_SECONDS)
        finally:
            await publisher.close()


if __name__ == "__main__":
    asyncio.run(run())
