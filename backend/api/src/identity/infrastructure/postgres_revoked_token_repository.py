from datetime import datetime
from uuid import UUID

from ...shared.infrastructure.database import pool


class PostgresRevokedTokenRepository:
    async def revoke(self, *, jti: UUID, user_id: UUID, expires_at: datetime) -> None:
        async with pool.connection() as connection:
            await connection.execute(
                """INSERT INTO revoked_tokens (jti, user_id, expires_at)
                   VALUES (%s, %s, %s) ON CONFLICT (jti) DO NOTHING""",
                (jti, user_id, expires_at),
            )
            await connection.execute("DELETE FROM revoked_tokens WHERE expires_at < NOW()")
            await connection.commit()

    async def is_revoked(self, jti: UUID) -> bool:
        async with pool.connection() as connection:
            result = await connection.execute("SELECT 1 FROM revoked_tokens WHERE jti = %s", (jti,))
            return await result.fetchone() is not None
