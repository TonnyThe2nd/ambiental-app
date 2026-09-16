from datetime import datetime, timedelta, timezone
from typing import Protocol


class ObservationRepository(Protocol):
    async def save(self, data: object) -> None: ...
    async def history(self, region_key: str, since: datetime) -> list[dict]: ...

class SaveObservationUseCase(Protocol):
    async def execute(self, data: object) -> None: ...
class GetObservationHistoryUseCase(Protocol):
    async def execute(self, region_key: str, days: int) -> list[dict]: ...


class SaveObservation(SaveObservationUseCase):
    def __init__(self, repository: ObservationRepository) -> None: self._repository=repository
    async def execute(self, data: object) -> None: await self._repository.save(data)


class GetObservationHistory(GetObservationHistoryUseCase):
    def __init__(self, repository: ObservationRepository) -> None: self._repository=repository
    async def execute(self, region_key: str, days: int) -> list[dict]:
        days=min(max(days,1),365)
        return await self._repository.history(region_key, datetime.now(timezone.utc)-timedelta(days=days))
