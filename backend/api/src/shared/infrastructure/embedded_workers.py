"""Worker e outbox-poller dentro do processo da API (implantação gratuita).

No Render, processos em segundo plano (background workers) e serviços privados são
pagos. Com ``EMBEDDED_WORKERS=true`` a API executa os dois laços como tarefas asyncio
no próprio processo, compartilhando o pool do banco. O código continua separado por
responsabilidade (``outbox_service`` e ``worker``) e pode voltar a rodar em processos
próprios — basta desligar a variável e subir os serviços do ``render.yaml``/Compose.
"""
import asyncio
import logging
import os
from typing import Awaitable, Callable

logger = logging.getLogger("urbaneye.embedded")


def embedded_workers_enabled() -> bool:
    return os.getenv("EMBEDDED_WORKERS", "false").lower() in {"1", "true", "yes"}


async def supervise(name: str, loop: Callable[[], Awaitable[None]],
                    initial_delay: float = 5.0, max_delay: float = 60.0) -> None:
    """Mantém um laço vivo: se cair (ex.: broker fora do ar), reinicia com espera crescente."""
    delay = initial_delay
    while True:
        started = asyncio.get_running_loop().time()
        try:
            await loop()
            logger.warning("%s terminou; reiniciando", name)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            logger.warning("%s parou (%s); nova tentativa em %.0fs", name, error, delay)
        # Rodou por mais de um minuto antes de cair: volta à espera inicial.
        if asyncio.get_running_loop().time() - started > 60:
            delay = initial_delay
        await asyncio.sleep(delay)
        delay = min(delay * 2, max_delay)


class EmbeddedWorkers:
    def __init__(self) -> None:
        self._tasks: list[asyncio.Task] = []

    def start(self) -> None:
        if not embedded_workers_enabled() or self._tasks:
            return
        from ...outbox_service import run_loop as outbox_loop
        from ...worker import consume_loop as worker_loop
        self._tasks = [
            asyncio.create_task(supervise("outbox-poller", outbox_loop), name="embedded-outbox"),
            asyncio.create_task(supervise("worker", worker_loop), name="embedded-worker"),
        ]
        logger.info("Worker e outbox-poller rodando dentro da API (EMBEDDED_WORKERS=true)")

    async def stop(self) -> None:
        for task in self._tasks:
            task.cancel()
        for task in self._tasks:
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass
        self._tasks = []
