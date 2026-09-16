from typing import Protocol


class HealthCheck(Protocol):
    async def check(self) -> bool: ...
