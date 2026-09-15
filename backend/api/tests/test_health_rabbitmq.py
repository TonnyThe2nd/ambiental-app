import asyncio
import os
from contextlib import asynccontextmanager

from fastapi import Response, status

os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/urbaneye_test")
os.environ.setdefault("JWT_SECRET", "segredo-de-teste-com-mais-de-32-caracteres")

from src import main
from src import messaging


class HealthyDatabasePool:
    @asynccontextmanager
    async def connection(self):
        yield HealthyDatabaseConnection()


class HealthyDatabaseConnection:
    async def execute(self, query: str) -> None:
        assert query == "SELECT 1"


class RabbitMqChannel:
    def __init__(self):
        self.closed = False

    async def close(self) -> None:
        self.closed = True


class RabbitMqConnection:
    def __init__(self):
        self.channel_instance = RabbitMqChannel()
        self.closed = False

    async def channel(self) -> RabbitMqChannel:
        return self.channel_instance

    async def close(self) -> None:
        self.closed = True


def test_verificacao_rabbitmq_abre_e_fecha_conexao(monkeypatch):
    connection = RabbitMqConnection()

    async def connect(url: str, timeout: int) -> RabbitMqConnection:
        assert url == messaging.RABBITMQ_URL
        assert timeout == 5
        return connection

    monkeypatch.setattr(messaging.aio_pika, "connect", connect)

    asyncio.run(messaging.check_rabbitmq_connection())

    assert connection.channel_instance.closed
    assert connection.closed


def test_health_retorna_503_quando_rabbitmq_esta_indisponivel(monkeypatch):
    async def unavailable_rabbitmq() -> None:
        raise ConnectionError("RabbitMQ indisponível")

    monkeypatch.setattr(main, "pool", HealthyDatabasePool())
    monkeypatch.setattr(main, "check_rabbitmq_connection", unavailable_rabbitmq)
    response = Response()

    checks = asyncio.run(main.health(response))

    assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert checks == {"api": "up", "database": "up", "rabbitmq": "down"}


def test_health_retorna_componentes_up_quando_tudo_esta_disponivel(monkeypatch):
    async def available_rabbitmq() -> None:
        return None

    monkeypatch.setattr(main, "pool", HealthyDatabasePool())
    monkeypatch.setattr(main, "check_rabbitmq_connection", available_rabbitmq)
    response = Response()

    checks = asyncio.run(main.health(response))

    assert response.status_code == status.HTTP_200_OK
    assert checks == {"api": "up", "database": "up", "rabbitmq": "up"}
