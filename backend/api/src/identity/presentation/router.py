from fastapi import APIRouter, Request, Response, status
from slowapi import Limiter

from ...alerts.dependencies import evaluate_user_proximity
from ...auth import (
    AccessToken,
    CurrentUser,
    delete_account,
    login_user,
    register_user,
    revoke_access_token,
    update_alert_preferences,
    update_user_location,
)
from ...models import (
    AlertPreferencesInput,
    AuthResponse,
    LoginInput,
    RegisterInput,
    UserLocationInput,
    UserOutput,
)


def create_identity_router(limiter: Limiter) -> APIRouter:
    router = APIRouter(prefix="/auth", tags=["identity"])

    @router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
    @limiter.limit("10/hour")
    async def register(request: Request, data: RegisterInput) -> AuthResponse:
        return await register_user(data)

    @router.post("/login", response_model=AuthResponse)
    @limiter.limit("5/minute")
    async def login(request: Request, data: LoginInput) -> AuthResponse:
        return await login_user(data)

    @router.get("/me", response_model=UserOutput)
    async def me(user: CurrentUser) -> UserOutput:
        return user

    @router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
    async def logout(token: AccessToken) -> Response:
        await revoke_access_token(token)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
    async def delete_me(user: CurrentUser, token: AccessToken) -> Response:
        await delete_account(user.id, token)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.put("/me/location", status_code=status.HTTP_204_NO_CONTENT)
    async def update_location(data: UserLocationInput, user: CurrentUser) -> Response:
        await update_user_location(user.id, data)
        await evaluate_user_proximity.execute(user.id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.put("/me/alert-preferences", status_code=status.HTTP_204_NO_CONTENT)
    async def alert_preferences(data: AlertPreferencesInput, user: CurrentUser) -> Response:
        await update_alert_preferences(user.id, data)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return router
