import os
from contextlib import asynccontextmanager

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool
from dotenv import load_dotenv


load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL precisa estar configurada.")

pool = AsyncConnectionPool(
    conninfo=DATABASE_URL,
    kwargs={"row_factory": dict_row},
    open=False,
)


@asynccontextmanager
async def lifespan_pool():
    await pool.open()
    try:
        yield
    finally:
        await pool.close()
