from uuid import UUID
from ...database import pool


class PostgresNotificationRepository:
    async def list_for_user(self, user_id: UUID, unread_only: bool) -> list[dict]:
        async with pool.connection() as connection:
            result = await connection.execute(
                """SELECT id, incident_id, title, message, distance_km, read_at,
                          created_at, severity FROM notifications
                   WHERE user_id = %s AND (%s = FALSE OR read_at IS NULL)
                   ORDER BY created_at DESC LIMIT 50""",
                (user_id, unread_only),
            )
            return await result.fetchall()

    async def mark_read(self, notification_id: UUID, user_id: UUID) -> None:
        async with pool.connection() as connection:
            await connection.execute(
                """UPDATE notifications SET read_at = NOW()
                   WHERE id = %s AND user_id = %s AND read_at IS NULL""",
                (notification_id, user_id),
            )
            await connection.commit()
