import asyncio
from contextlib import asynccontextmanager

import pytest

from src.incidents.application.ports import IncidentFilters
from src.incidents.application.use_cases import ListIncidents
from src.incidents.infrastructure.postgres_incident_repository import PostgresIncidentRepository


class Result:
    async def fetchall(self): return []


class Connection:
    def __init__(self):
        self.query = ""
        self.params = ()
    async def execute(self, query, params):
        self.query, self.params = query, params
        return Result()


class Pool:
    def __init__(self): self.connection_instance = Connection()
    @asynccontextmanager
    async def connection(self): yield self.connection_instance


def filters(**overrides):
    values = dict(updated_since=None, updated_after_id=None, categories=[], severities=[],
                  active_only=True, limit=500, latitude=-23.5505,
                  longitude=-46.6333, radius_m=50000)
    values.update(overrides)
    return IncidentFilters(**values)


def test_list_incidents_uses_postgis_radius_filter():
    pool = Pool()
    use_case = ListIncidents(PostgresIncidentRepository(pool))
    result = asyncio.run(use_case.execute(filters()))
    assert result == []
    assert "ST_DWithin" in pool.connection_instance.query
    assert "i.location" in pool.connection_instance.query
    assert pool.connection_instance.params[-5:] == (-23.5505, -46.6333, -23.5505, 50000, 500)


def test_list_incidents_requires_complete_geographic_coordinates():
    with pytest.raises(ValueError, match="Latitude e longitude"):
        filters(longitude=None)
