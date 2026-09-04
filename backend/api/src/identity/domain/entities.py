from dataclasses import dataclass
from enum import StrEnum
from uuid import UUID


class UserRole(StrEnum):
    CITIZEN = "cidadao"
    MODERATOR = "moderador"
    ADMINISTRATOR = "administrador"


@dataclass(frozen=True)
class User:
    id: UUID
    name: str
    email: str
    role: UserRole = UserRole.CITIZEN
    trust_score: float = 50

    @property
    def can_moderate(self) -> bool:
        return self.role in {UserRole.MODERATOR, UserRole.ADMINISTRATOR}

    @property
    def is_administrator(self) -> bool:
        return self.role is UserRole.ADMINISTRATOR
