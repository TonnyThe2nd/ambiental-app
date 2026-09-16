from dataclasses import dataclass
from typing import Protocol

from .ports import HealthCheck


@dataclass(frozen=True)
class HealthReport:
    api: str
    database: str
    rabbitmq: str

    @property
    def healthy(self) -> bool:
        return self.database == "up" and self.rabbitmq == "up"

    def as_dict(self) -> dict[str, str]:
        return {"api": self.api, "database": self.database, "rabbitmq": self.rabbitmq}


class GetSystemHealthUseCase(Protocol):
    async def execute(self) -> HealthReport: ...


class GetSystemHealth(GetSystemHealthUseCase):
    def __init__(self, database: HealthCheck, message_broker: HealthCheck) -> None:
        self._database = database
        self._message_broker = message_broker

    async def execute(self) -> HealthReport:
        return HealthReport(
            api="up",
            database="up" if await self._safe_check(self._database) else "down",
            rabbitmq="up" if await self._safe_check(self._message_broker) else "down",
        )

    @staticmethod
    async def _safe_check(check: HealthCheck) -> bool:
        try:
            return await check.check()
        except Exception:
            return False
