import asyncio
from contextlib import asynccontextmanager

from src import main


class Cursor:
    def __init__(self):
        self.query = ""
        self.params = ()

    async def execute(self, query, params):
        self.query = query
        self.params = params

    async def fetchall(self):
        return []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return None


class Connection:
    def __init__(self, cursor):
        self.cursor_instance = cursor

    @asynccontextmanager
    async def cursor(self):
        yield self.cursor_instance


class Pool:
    def __init__(self, cursor):
        self.cursor = cursor

    @asynccontextmanager
    async def connection(self):
        yield Connection(self.cursor)


def test_list_incidents_uses_postgis_radius_filter(monkeypatch):
    cursor = Cursor()
    monkeypatch.setattr(main, "pool", Pool(cursor))

    result = asyncio.run(main.list_incidents(
        None,
        updated_since=None,
        updated_after_id=None,
        categories=[],
        severities=[],
        active_only=True,
        limit=500,
        latitude=-23.5505,
        longitude=-46.6333,
        radius_m=50000,
    ))

    assert result == []
    assert "ST_DWithin" in cursor.query
    assert "i.location" in cursor.query
    assert cursor.params[-5:] == (-23.5505, -46.6333, -23.5505, 50000, 500)


def test_list_incidents_requires_complete_geographic_coordinates():
    try:
        asyncio.run(main.list_incidents(
            None,
            updated_since=None,
            updated_after_id=None,
            categories=[],
            severities=[],
            active_only=True,
            limit=500,
            latitude=-23.5505,
            longitude=None,
            radius_m=50000,
        ))
    except main.HTTPException as error:
        assert error.status_code == 422
    else:
        raise AssertionError("A rota deveria rejeitar coordenadas incompletas.")
