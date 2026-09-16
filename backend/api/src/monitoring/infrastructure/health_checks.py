from ...database import pool as default_pool
from ...messaging import check_rabbitmq_connection as default_rabbitmq_check


class PostgresHealthCheck:
    def __init__(self, database_pool=default_pool) -> None:
        self._pool = database_pool

    async def check(self) -> bool:
        async with self._pool.connection() as connection:
            await connection.execute("SELECT 1")
        return True


class RabbitMqHealthCheck:
    def __init__(self, check_connection=default_rabbitmq_check) -> None:
        self._check_connection = check_connection

    async def check(self) -> bool:
        await self._check_connection()
        return True
