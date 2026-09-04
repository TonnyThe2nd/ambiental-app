import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

load_dotenv()


class Database:
    """Owns the connection pool and its application lifecycle."""

    def __init__(self, url: str | None = None):
        connection_url = url or os.getenv("DATABASE_URL")
        if not connection_url:
            raise RuntimeError("DATABASE_URL precisa estar configurada.")
        self.pool = AsyncConnectionPool(
            conninfo=connection_url,
            kwargs={"row_factory": dict_row},
            open=False,
        )

    @asynccontextmanager
    async def lifespan(self):
        await self.pool.open()
        try:
            yield
        finally:
            await self.pool.close()


database = Database()
pool = database.pool
