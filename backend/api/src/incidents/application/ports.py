from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID


class IncidentRepository(Protocol):
    async def create(self, incident: object, reporter_id: UUID) -> tuple[object, object]: ...
    async def list(self, filters: "IncidentFilters") -> list[dict]: ...
    async def validate(self, incident_id: UUID, user_id: UUID, data: object) -> dict: ...
    async def review(self, incident_id: UUID, reviewer_id: UUID, decision: str, notes: str | None) -> None: ...
    async def heatmap(self, filters: "HeatmapFilters") -> list[dict]: ...
    async def save_photo(self, incident_id: UUID, user_id: UUID, content: bytes, content_type: str) -> None: ...
    async def load_photo(self, incident_id: UUID) -> dict | None: ...


class ReadCache(Protocol):
    async def get_or_load(self, namespace: str, params: dict, loader, ttl: int | None = None): ...


class IncidentFilters:
    def __init__(self, *, updated_since: datetime | None, updated_after_id: UUID | None,
                 categories: list[str], severities: list[str], active_only: bool,
                 limit: int, latitude: float | None, longitude: float | None, radius_m: int) -> None:
        if (latitude is None) != (longitude is None):
            raise ValueError("Latitude e longitude devem ser informadas juntas.")
        self.updated_since, self.updated_after_id = updated_since, updated_after_id
        self.categories, self.severities, self.active_only = categories, severities, active_only
        self.limit, self.latitude, self.longitude, self.radius_m = limit, latitude, longitude, radius_m

    def as_key(self) -> dict:
        # Coordenadas arredondadas (~110 m) para que usuários vizinhos compartilhem a chave.
        return {"categories": sorted(self.categories), "severities": sorted(self.severities),
                "active_only": self.active_only, "limit": self.limit, "radius_m": self.radius_m,
                "latitude": None if self.latitude is None else round(self.latitude, 3),
                "longitude": None if self.longitude is None else round(self.longitude, 3)}


class HeatmapFilters:
    """Agregação por célula GeoHash (quadrante) para o mapa de calor."""

    def __init__(self, *, precision: int, days: int, categories: list[str],
                 active_only: bool, cells: list[str]) -> None:
        from ...shared.domain import geohash
        if len(cells) > 50:
            raise ValueError("No máximo 50 células por consulta.")
        if precision not in geohash.HEATMAP_PRECISIONS:
            raise ValueError("A precisão do mapa de calor deve estar entre 3 e 7.")
        if any(not geohash.is_valid(cell) or len(cell) > precision for cell in cells):
            raise ValueError("Células GeoHash inválidas ou mais finas que a precisão pedida.")
        self.precision, self.days, self.categories = precision, days, categories
        self.active_only, self.cells = active_only, cells

    def as_key(self) -> dict:
        return {"precision": self.precision, "days": self.days, "categories": sorted(self.categories),
                "active_only": self.active_only, "cells": sorted(self.cells)}
