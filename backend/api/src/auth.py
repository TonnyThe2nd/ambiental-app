"""FastAPI identity adapter kept stable for existing imports."""
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .identity.application.services import AuthenticationService, UserProfileService
from .identity.domain.entities import User
from .identity.infrastructure import (JwtTokenService, PostgresRevokedTokenRepository,
                                     PostgresUserRepository)
from .models import AlertPreferencesInput, AuthResponse, LoginInput, RegisterInput, UserLocationInput, UserOutput
from .shared.domain.exceptions import ConflictError, EntityNotFound

_repository = PostgresUserRepository()
_revoked_tokens = PostgresRevokedTokenRepository()
_authentication = AuthenticationService(_repository, JwtTokenService(), _revoked_tokens)
_profiles = UserProfileService(_repository)
bearer = HTTPBearer(auto_error=False)


def _output(user: User) -> UserOutput:
    return UserOutput(id=user.id, name=user.name, email=user.email,
                      role=user.role.value, trust_score=user.trust_score)


def create_access_token(user_id):
    return _authentication._tokens.create(user_id)


async def register_user(data: RegisterInput) -> AuthResponse:
    try:
        token, user = await _authentication.register(**data.model_dump())
    except ConflictError as error:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="E-mail já cadastrado.") from error
    return AuthResponse(access_token=token, user=_output(user))


async def login_user(data: LoginInput) -> AuthResponse:
    try:
        token, user = await _authentication.login(**data.model_dump())
    except EntityNotFound as error:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="E-mail ou senha inválidos.") from error
    return AuthResponse(access_token=token, user=_output(user))


async def update_user_location(user_id, data: UserLocationInput) -> None:
    await _profiles.update_location(user_id, **data.model_dump())


async def update_alert_preferences(user_id, data: AlertPreferencesInput) -> None:
    values = data.model_dump()
    values["minimum_severity"] = values["minimum_severity"].value
    await _profiles.update_alert_preferences(user_id, **values)


async def revoke_access_token(token: str) -> None:
    await _authentication.revoke(token)


async def delete_account(user_id, token: str) -> bool:
    removed = await _profiles.delete_account(user_id)
    await _authentication.revoke(token)
    return removed


def _unauthorized() -> HTTPException:
    return HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticação necessária.", headers={"WWW-Authenticate": "Bearer"})


async def get_access_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized()
    return credentials.credentials


async def get_current_user(token: Annotated[str, Depends(get_access_token)]) -> UserOutput:
    try:
        return _output(await _authentication.authenticate(token))
    except Exception as error:
        raise _unauthorized() from error


AccessToken = Annotated[str, Depends(get_access_token)]
CurrentUser = Annotated[UserOutput, Depends(get_current_user)]
