from uuid import UUID
from typing import Protocol
from .ports import IncidentFilters, IncidentRepository

class CreateIncidentUseCase(Protocol):
    async def execute(self, incident: object, reporter_id: UUID) -> tuple[object, object]: ...
class ListIncidentsUseCase(Protocol):
    async def execute(self, filters: IncidentFilters) -> list[dict]: ...
class ValidateIncidentUseCase(Protocol):
    async def execute(self, incident_id: UUID, user_id: UUID, data: object) -> dict: ...
class ReviewIncidentUseCase(Protocol):
    async def execute(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None: ...

class CreateIncident(CreateIncidentUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, incident: object, reporter_id: UUID) -> tuple[object, object]:
        return await self._repository.create(incident, reporter_id)


class ListIncidents(ListIncidentsUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, filters: IncidentFilters) -> list[dict]: return await self._repository.list(filters)


class ValidateIncident(ValidateIncidentUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, incident_id: UUID, user_id: UUID, data: object) -> dict:
        return await self._repository.validate(incident_id, user_id, data)


class ReviewIncident(ReviewIncidentUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None:
        await self._repository.review(incident_id, reviewer_id, decision, notes)
