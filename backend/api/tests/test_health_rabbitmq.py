import asyncio
from contextlib import asynccontextmanager

from src import messaging
from src.monitoring.application.health_service import GetSystemHealth
from src.monitoring.infrastructure.health_checks import PostgresHealthCheck, RabbitMqHealthCheck


class HealthyDatabasePool:
    @asynccontextmanager
    async def connection(self):
        yield HealthyDatabaseConnection()


class HealthyDatabaseConnection:
    async def execute(self, query: str) -> None:
        assert query == "SELECT 1"


class RabbitMqChannel:
    def __init__(self): self.closed = False
    async def close(self) -> None: self.closed = True


class RabbitMqConnection:
    def __init__(self):
        self.channel_instance = RabbitMqChannel()
        self.closed = False
    async def channel(self) -> RabbitMqChannel: return self.channel_instance
    async def close(self) -> None: self.closed = True


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


def test_health_retorna_down_quando_rabbitmq_esta_indisponivel():
    async def unavailable() -> None: raise ConnectionError("indisponível")
    use_case = GetSystemHealth(
        PostgresHealthCheck(HealthyDatabasePool()),
        RabbitMqHealthCheck(unavailable),
    )
    report = asyncio.run(use_case.execute())
    assert report.as_dict() == {"api": "up", "database": "up", "rabbitmq": "down"}
    assert not report.healthy


def test_health_retorna_componentes_up():
    async def available() -> None: return None
    use_case = GetSystemHealth(
        PostgresHealthCheck(HealthyDatabasePool()),
        RabbitMqHealthCheck(available),
    )
    report = asyncio.run(use_case.execute())
    assert report.as_dict() == {"api": "up", "database": "up", "rabbitmq": "up"}
    assert report.healthy
