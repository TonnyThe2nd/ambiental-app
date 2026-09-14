from uuid import UUID

from pwdlib import PasswordHash

from ...shared.domain.exceptions import ConflictError, EntityNotFound
from ..domain.entities import User
from .ports import RevokedTokenRepository, UserRepository


class AuthenticationService:
    def __init__(self, repository: UserRepository, tokens,
                 revoked_tokens: RevokedTokenRepository | None = None):
        self._repository = repository
        self._tokens = tokens
        self._revoked_tokens = revoked_tokens
        self._passwords = PasswordHash.recommended()
        self._dummy_hash = self._passwords.hash("urbaneye-dummy-password")

    async def register(self, *, name: str, email: str, password: str,
                       latitude: float | None = None,
                       longitude: float | None = None) -> tuple[str, User]:
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
        valid = self._verify(password, stored_hash)
        if credentials is None or not valid:
            raise EntityNotFound("invalid_credentials")
        return self._tokens.create(credentials[0].id), credentials[0]

    def _verify(self, password: str, stored_hash: str) -> bool:
        try:
            return self._passwords.verify(password, stored_hash)
        except Exception:
            self._passwords.verify(password, self._dummy_hash)
            return False

    async def authenticate(self, token: str) -> User:
        user_id, jti, _ = self._tokens.identity(token)
        if self._revoked_tokens is not None and jti is not None:
            if await self._revoked_tokens.is_revoked(jti):
                raise EntityNotFound("revoked_token")
        user = await self._repository.find_by_id(user_id)
        if user is None:
            raise EntityNotFound("invalid_token")
        return user

    async def revoke(self, token: str) -> None:
        if self._revoked_tokens is None:
            return
        user_id, jti, expires_at = self._tokens.identity(token)
        if jti is None:
            return
        await self._revoked_tokens.revoke(jti=jti, user_id=user_id, expires_at=expires_at)


class UserProfileService:
    def __init__(self, repository: UserRepository):
        self._repository = repository

    async def update_location(self, user_id: UUID, **values) -> None:
        await self._repository.update_location(user_id, **values)

    async def update_alert_preferences(self, user_id: UUID, **values) -> None:
        await self._repository.update_alert_preferences(user_id, **values)

    async def delete_account(self, user_id: UUID) -> bool:
        return await self._repository.anonymize(user_id)
