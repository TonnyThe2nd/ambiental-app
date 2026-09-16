from uuid import UUID
from fastapi import APIRouter, Response, status
from ...auth import CurrentUser
from ...models import NotificationOutput
from ..application.notification_use_cases import ListNotificationsUseCase, MarkNotificationReadUseCase


def create_alerts_router(list_notifications: ListNotificationsUseCase, mark_read: MarkNotificationReadUseCase) -> APIRouter:
    router = APIRouter(tags=["alerts"])

    @router.get("/notifications", response_model=list[NotificationOutput])
    async def list_all(user: CurrentUser, unread_only: bool = True) -> list[NotificationOutput]:
        return [NotificationOutput(**row) for row in await list_notifications.execute(user.id, unread_only)]

    @router.post("/notifications/{notification_id}/read", status_code=status.HTTP_204_NO_CONTENT)
    async def read(notification_id: UUID, user: CurrentUser) -> Response:
        await mark_read.execute(notification_id, user.id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return router
