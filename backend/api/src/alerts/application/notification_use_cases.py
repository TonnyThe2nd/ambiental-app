from uuid import UUID
from typing import Protocol
from .ports import NotificationRepository

class ListNotificationsUseCase(Protocol):
    async def execute(self, user_id: UUID, unread_only: bool) -> list[dict]: ...
class MarkNotificationReadUseCase(Protocol):
    async def execute(self, notification_id: UUID, user_id: UUID) -> None: ...


class ListNotifications(ListNotificationsUseCase):
    def __init__(self, repository: NotificationRepository) -> None:
        self._repository = repository

    async def execute(self, user_id: UUID, unread_only: bool) -> list[dict]:
        return await self._repository.list_for_user(user_id, unread_only)


class MarkNotificationRead(MarkNotificationReadUseCase):
    def __init__(self, repository: NotificationRepository) -> None:
        self._repository = repository

    async def execute(self, notification_id: UUID, user_id: UUID) -> None:
        await self._repository.mark_read(notification_id, user_id)
