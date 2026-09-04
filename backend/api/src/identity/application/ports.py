from typing import Protocol
from uuid import UUID

from ..domain.entities import User


class UserRepository(Protocol):
    async def create(self, *, name: str, email: str, password_hash: str,
                     latitude: float, longitude: float) -> User: ...

    async def find_credentials_by_email(self, email: str) -> tuple[User, str] | None: ...

    async def find_by_id(self, user_id: UUID) -> User | None: ...

    async def update_location(self, user_id: UUID, **values) -> None: ...

    async def update_alert_preferences(self, user_id: UUID, **values) -> None: ...
