from uuid import UUID
from typing import Protocol
from ...shared.domain import geohash
from .ports import HeatmapFilters, IncidentFilters, IncidentRepository, ReadCache

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


class _NoCache:
    async def get_or_load(self, namespace, params, loader, ttl=None): return await loader()


class ListIncidents(ListIncidentsUseCase):
    """Snapshot inicial do mapa passa pelo cache distribuído; deltas (cursor) vão ao banco."""
    def __init__(self, repository: IncidentRepository, cache: ReadCache | None = None) -> None:
        self._repository, self._cache = repository, cache or _NoCache()

    async def execute(self, filters: IncidentFilters) -> list[dict]:
        if filters.updated_since is not None:
            return await self._repository.list(filters)
        return await self._cache.get_or_load("incidents", filters.as_key(), lambda: self._repository.list(filters))


class ListHeatmap:
    def __init__(self, repository: IncidentRepository, cache: ReadCache | None = None) -> None:
        self._repository, self._cache = repository, cache or _NoCache()

    async def execute(self, filters: HeatmapFilters) -> list[dict]:
        async def load() -> list[dict]:
            cells = []
            for row in await self._repository.heatmap(filters):
                lat_min, lon_min, lat_max, lon_max = geohash.bounds(row["cell"])
                latitude, longitude = geohash.decode(row["cell"])
                cells.append({**row, "latitude": latitude, "longitude": longitude,
                              "bounds": [lat_min, lon_min, lat_max, lon_max]})
            return cells
        return await self._cache.get_or_load("heatmap", filters.as_key(), load, ttl=60)


class ValidateIncident(ValidateIncidentUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, incident_id: UUID, user_id: UUID, data: object) -> dict:
        return await self._repository.validate(incident_id, user_id, data)


class ReviewIncident(ReviewIncidentUseCase):
    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository
    async def execute(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None:
        await self._repository.review(incident_id, reviewer_id, decision, notes)


def detect_image_type(content: bytes) -> str:
    """Identifica o formato pelos bytes iniciais, sem confiar no Content-Type do cliente."""
    if content.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(content) >= 12 and content[:4] == b"RIFF" and content[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("Formato de imagem não suportado (use JPEG, PNG ou WebP).")


class IncidentPhotos:
    max_bytes = 5 * 1024 * 1024

    def __init__(self, repository: IncidentRepository) -> None: self._repository = repository

    async def save(self, incident_id: UUID, user_id: UUID, content: bytes) -> None:
        if not content:
            raise ValueError("Corpo vazio: envie os bytes da imagem.")
        if len(content) > self.max_bytes:
            raise OverflowError("photo_too_large")
        await self._repository.save_photo(incident_id, user_id, content, detect_image_type(content))

    async def load(self, incident_id: UUID) -> dict | None:
        return await self._repository.load_photo(incident_id)
