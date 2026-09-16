from fastapi import APIRouter, HTTPException, status
from ...auth import CurrentUser
from ...models import CampaignInput, SensitiveAreaInput
from ..application.use_cases import OperationsUseCase


def create_operations_router(use_cases: OperationsUseCase) -> APIRouter:
    router = APIRouter(tags=["operations"])

    def admin(user: object) -> None:
        if user.role != "administrador": raise HTTPException(403, "Acesso administrativo necessário.")

    def operator(user: object) -> None:
        if user.role not in {"moderador", "administrador"}: raise HTTPException(403, "Perfil de moderação necessário.")

    @router.get("/campaigns")
    async def campaigns(_: CurrentUser) -> list[dict]: return await use_cases.campaigns()

    @router.post("/campaigns", status_code=status.HTTP_201_CREATED)
    async def create_campaign(data: CampaignInput, user: CurrentUser) -> dict:
        admin(user)
        try: item_id = await use_cases.create_campaign(data)
        except ValueError as error: raise HTTPException(422, str(error)) from error
        return {"id": str(item_id), "status": "created"}
    
    @router.post("/sensitive-areas", status_code=status.HTTP_201_CREATED)
    async def sensitive(data: SensitiveAreaInput, user: CurrentUser) -> dict:
        admin(user); return {"id": str(await use_cases.create_sensitive_area(data)), "status": "created"}
    
    @router.get("/contributions/me")
    async def contributions(user: CurrentUser) -> list[dict]: return await use_cases.contributions(user.id)

    @router.get("/dashboard/summary")
    async def dashboard(user: CurrentUser, days: int = 30) -> dict:
        operator(user); return await use_cases.dashboard(days)
    
    @router.get("/operations/metrics")
    async def metrics(user: CurrentUser) -> dict:
        admin(user); return await use_cases.metrics()
    return router
