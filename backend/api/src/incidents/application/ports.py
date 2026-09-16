from datetime import datetime
from typing import Protocol
from uuid import UUID


class IncidentRepository(Protocol):
    async def create(self, incident: object, reporter_id: UUID) -> tuple[object, object]: ...
    async def list(self, filters: "IncidentFilters") -> list[dict]: ...
    async def validate(self, incident_id: UUID, user_id: UUID, data: object) -> dict: ...
    async def review(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None: ...


class IncidentFilters:
    def __init__(self, *, updated_since: datetime | None, updated_after_id: UUID | None,
                 categories: list[str], severities: list[str], active_only: bool,
                 limit: int, latitude: float | None, longitude: float | None, radius_m: int) -> None:
        if (latitude is None) != (longitude is None):
            raise ValueError("Latitude e longitude devem ser informadas juntas.")
        self.updated_since, self.updated_after_id = updated_since, updated_after_id
        self.categories, self.severities, self.active_only = categories, severities, active_only
        self.limit, self.latitude, self.longitude, self.radius_m = limit, latitude, longitude, radius_m
