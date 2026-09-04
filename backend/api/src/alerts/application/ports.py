from typing import Protocol
from uuid import UUID

from ..domain.proximity import ProximityAlert


class ProximityAlertRepository(Protocol):
    async def create_for_nearby_incidents(self, user_id: UUID) -> list[ProximityAlert]: ...


class PushNotificationGateway(Protocol):
    async def send(self, token: str, alert: ProximityAlert) -> None: ...


class UserPushTokenRepository(Protocol):
    async def find_push_token(self, user_id: UUID) -> str | None: ...
