from uuid import UUID

from pwdlib import PasswordHash

from ...shared.domain.exceptions import ConflictError, EntityNotFound
from ..domain.entities import User
from .ports import UserRepository


class AuthenticationService:
    def __init__(self, repository: UserRepository, tokens):
        self._repository = repository
        self._tokens = tokens
        self._passwords = PasswordHash.recommended()
        self._dummy_hash = self._passwords.hash("urbaneye-dummy-password")

    async def register(self, *, name: str, email: str, password: str,
                       latitude: float, longitude: float) -> tuple[str, User]:
        try:
            user = await self._repository.create(
                name=name.strip(), email=email.strip().lower(),
                password_hash=self._passwords.hash(password),
                latitude=latitude, longitude=longitude,
            )
        except ConflictError:
            raise
        return self._tokens.create(user.id), user

    async def login(self, *, email: str, password: str) -> tuple[str, User]:
        credentials = await self._repository.find_credentials_by_email(email.strip().lower())
        stored_hash = credentials[1] if credentials else self._dummy_hash
        valid = self._passwords.verify(password, stored_hash)
        if credentials is None or not valid:
            raise EntityNotFound("invalid_credentials")
        return self._tokens.create(credentials[0].id), credentials[0]

    async def authenticate(self, token: str) -> User:
        user = await self._repository.find_by_id(self._tokens.subject(token))
        if user is None:
            raise EntityNotFound("invalid_token")
        return user


class UserProfileService:
    def __init__(self, repository: UserRepository):
        self._repository = repository

    async def update_location(self, user_id: UUID, **values) -> None:
        await self._repository.update_location(user_id, **values)

    async def update_alert_preferences(self, user_id: UUID, **values) -> None:
        await self._repository.update_alert_preferences(user_id, **values)
