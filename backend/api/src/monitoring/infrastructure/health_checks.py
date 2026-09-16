from ...database import pool
from ...messaging import check_rabbitmq_connection


class PostgresHealthCheck:
    async def check(self) -> bool:
        async with pool.connection() as connection:
            await connection.execute("SELECT 1")
        return True


class RabbitMqHealthCheck:
    async def check(self) -> bool:
        await check_rabbitmq_connection()
        return True
