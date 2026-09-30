"""Assinante do barramento: cada instância da API recebe todos os eventos de ocorrência.

A instância declara uma fila exclusiva e temporária ligada a ``incident.#`` no exchange
topic. Com N instâncias, o RabbitMQ entrega uma cópia a cada uma (fan-out), e cada uma
repassa só para os seus WebSockets. Também invalida o cache distribuído, fechando o ciclo
de consistência eventual entre PostgreSQL, Redis e os celulares conectados.
"""
import asyncio
import json
import logging
import os

logger = logging.getLogger("urbaneye.realtime")


class RealtimeEventListener:
    def __init__(self, hub, cache, retry_seconds: float = 5.0) -> None:
        self._hub, self._cache, self._retry = hub, cache, retry_seconds
        self._task: asyncio.Task | None = None
        self._connection = None

    @staticmethod
    def enabled() -> bool:
        return os.getenv("REALTIME_ENABLED", "true").lower() not in {"0", "false", "no"}

    async def handle(self, body: bytes) -> int:
        try:
            envelope = json.loads(body)
        except json.JSONDecodeError:
            logger.warning("Evento de tempo real ignorado: JSON inválido")
            return 0
        await self._cache.invalidate()
        return await self._hub.publish(envelope)

    async def _run(self) -> None:
        import aio_pika
        from ...messaging import EVENT_EXCHANGE, RABBITMQ_URL, REALTIME_BINDING
        while True:
            try:
                self._connection = await aio_pika.connect_robust(RABBITMQ_URL)
                channel = await self._connection.channel()
                exchange = await channel.declare_exchange(EVENT_EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True)
                queue = await channel.declare_queue(exclusive=True, auto_delete=True)
                await queue.bind(exchange, REALTIME_BINDING)
                logger.info("Tempo real: assinando %s em %s", REALTIME_BINDING, EVENT_EXCHANGE)
                async with queue.iterator() as messages:
                    async for message in messages:
                        async with message.process(ignore_processed=True):
                            await self.handle(message.body)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                logger.warning("Tempo real sem broker (%s); nova tentativa em %ss", error, self._retry)
                await asyncio.sleep(self._retry)
            finally:
                if self._connection is not None:
                    await self._connection.close()
                    self._connection = None

    def start(self) -> None:
        if self.enabled() and self._task is None:
            self._task = asyncio.create_task(self._run(), name="realtime-listener")

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None
