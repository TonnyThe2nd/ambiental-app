from fastapi import APIRouter, Response, status

from ..application.health_service import GetSystemHealthUseCase
from ..application.observation_use_cases import GetObservationHistoryUseCase, SaveObservationUseCase
from ...auth import CurrentUser
from ...models import EnvironmentalObservationInput


def create_monitoring_router(get_health: GetSystemHealthUseCase, save_observation: SaveObservationUseCase, get_history: GetObservationHistoryUseCase) -> APIRouter:
    router = APIRouter(tags=["monitoring"])

    @router.get("/health")
    async def health(response: Response) -> dict[str, str]:
        report = await get_health.execute()
        if not report.healthy:
            response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return report.as_dict()

    @router.get("/ping")
    async def ping() -> dict[str, str]:
        return {"status": "ok"}

    @router.post("/environmental-observations", status_code=status.HTTP_202_ACCEPTED)
    async def ingest(data: EnvironmentalObservationInput, user: CurrentUser) -> dict[str, str]:
        if user.role != "administrador":
            from fastapi import HTTPException
            raise HTTPException(status_code=403, detail="Acesso administrativo necessário.")
        await save_observation.execute(data)
        return {"status": "accepted"}

    @router.get("/environmental-observations/{region_key}")
    async def history(region_key: str, _: CurrentUser, days: int = 30) -> list[dict]:
        return await get_history.execute(region_key, days)

    return router
