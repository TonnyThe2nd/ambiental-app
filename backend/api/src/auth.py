"""FastAPI identity adapter kept stable for existing imports."""
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .identity.application.services import AuthenticationService, UserProfileService
from .identity.domain.entities import User
from .identity.infrastructure import JwtTokenService, PostgresUserRepository
from .models import AlertPreferencesInput, AuthResponse, LoginInput, RegisterInput, UserLocationInput, UserOutput
from .shared.domain.exceptions import ConflictError, EntityNotFound

_repository = PostgresUserRepository()
_authentication = AuthenticationService(_repository, JwtTokenService())
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


async def get_current_user(credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]) -> UserOutput:
    unauthorized = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticação necessária.", headers={"WWW-Authenticate": "Bearer"})
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise unauthorized
    try:
        return _output(await _authentication.authenticate(credentials.credentials))
    except Exception as error:
        raise unauthorized from error


CurrentUser = Annotated[UserOutput, Depends(get_current_user)]
