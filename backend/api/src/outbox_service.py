import asyncio
import logging
import os

from .database import lifespan_pool, pool
from .messaging import publisher

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("urbaneye.outbox")
POLL_SECONDS = float(os.getenv("OUTBOX_POLL_SECONDS", "2"))
BATCH_SIZE = int(os.getenv("OUTBOX_BATCH_SIZE", "50"))


async def publish_batch() -> int:
    async with pool.connection() as connection:
        async with connection.transaction():
            async with connection.cursor() as cursor:
                await cursor.execute(
                    """
                    SELECT id, event_type, payload FROM outbox
                    WHERE available_at <= NOW()
                    ORDER BY created_at
                    FOR UPDATE SKIP LOCKED LIMIT %s
                    """,
                    (BATCH_SIZE,),
                )
                rows = await cursor.fetchall()
            published = 0
            for row in rows:
                try:
                    await publisher.publish_envelope(row["payload"], str(row["id"]), row["event_type"])
                    await connection.execute("DELETE FROM outbox WHERE id = %s", (row["id"],))
                    published += 1
                except Exception as error:
                    logger.exception("Falha ao publicar outbox %s", row["id"])
                    await connection.execute(
                        """UPDATE outbox SET attempts = attempts + 1, last_error = %s,
                           available_at = NOW() + (LEAST(3600, POWER(2, LEAST(attempts, 11))) * INTERVAL '1 second')
                           WHERE id = %s""",
                        (str(error)[:2000], row["id"]),
                    )
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
