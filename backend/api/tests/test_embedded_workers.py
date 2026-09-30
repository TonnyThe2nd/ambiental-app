import asyncio

from src.shared.infrastructure import embedded_workers
from src.shared.infrastructure.embedded_workers import EmbeddedWorkers, supervise


def test_desligado_por_padrao(monkeypatch):
    monkeypatch.delenv("EMBEDDED_WORKERS", raising=False)
    workers = EmbeddedWorkers()
    workers.start()
    assert workers._tasks == []


def test_supervisor_reinicia_o_laco_quando_o_broker_cai(monkeypatch):
    calls = []

    async def flaky_loop():
        calls.append(1)
        if len(calls) < 3:
            raise ConnectionError("broker fora do ar")
        raise asyncio.CancelledError  # encerra o teste na terceira execução

    async def no_sleep(_):
        return None

    monkeypatch.setattr(embedded_workers.asyncio, "sleep", no_sleep)

    async def scenario():
        try:
            await supervise("teste", flaky_loop)
        except asyncio.CancelledError:
            pass

    asyncio.run(scenario())
    assert len(calls) == 3
