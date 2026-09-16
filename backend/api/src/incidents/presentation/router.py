from datetime import datetime
from uuid import UUID
from fastapi import APIRouter, HTTPException, Query, Response, status
from ...auth import CurrentUser
from ...models import CommunityValidationInput, IncidentAccepted, IncidentInput, IncidentOutput, ReporterPublic, ReviewInput
from ...producer import DuplicateIncidentError
from ..application.ports import IncidentFilters
from ..application.use_cases import CreateIncidentUseCase, ListIncidentsUseCase, ReviewIncidentUseCase, ValidateIncidentUseCase


def create_incidents_router(create: CreateIncidentUseCase, listing: ListIncidentsUseCase, validate: ValidateIncidentUseCase, review: ReviewIncidentUseCase) -> APIRouter:
    router = APIRouter(prefix="/incidents", tags=["incidents"])

    @router.post("", response_model=IncidentAccepted, status_code=202)
    async def create_one(data: IncidentInput, user: CurrentUser) -> IncidentAccepted:
        try: _, assessment = await create.execute(data, user.id)
        except DuplicateIncidentError as e: raise HTTPException(409, "Incidente duplicado.") from e
        except Exception as e: raise HTTPException(500, "Não foi possível persistir o incidente.") from e
        return IncidentAccepted(**data.model_dump(), reported_by=ReporterPublic(id=user.id,name=user.name,trust_score=user.trust_score), severity=assessment.severity, risk_score=assessment.score, health_impact=assessment.health_impact, ecosystem_impact=assessment.ecosystem_impact, community_impact=assessment.community_impact)

    @router.get("", response_model=list[IncidentOutput])
    async def list_all(_: CurrentUser, updated_since: datetime|None=None, updated_after_id: UUID|None=None, categories:list[str]=Query(default=[]), severities:list[str]=Query(default=[]), active_only:bool=True, limit:int=Query(500,ge=1,le=2000), latitude:float|None=Query(None,ge=-90,le=90), longitude:float|None=Query(None,ge=-180,le=180), radius_m:int=Query(50000,ge=1000,le=100000)) -> list[IncidentOutput]:
        try: rows=await listing.execute(IncidentFilters(updated_since=updated_since,updated_after_id=updated_after_id,categories=categories,severities=severities,active_only=active_only,limit=limit,latitude=latitude,longitude=longitude,radius_m=radius_m))
        except ValueError as e: raise HTTPException(422,str(e)) from e
        return [IncidentOutput(**{**r,"reported_by": ReporterPublic(id=r["user_id"],name=r["user_name"],trust_score=r["user_trust_score"]) if r["user_id"] else None}) for r in rows]

    @router.put("/{incident_id}/community-validation")
    async def validate_one(incident_id:UUID,data:CommunityValidationInput,user:CurrentUser)->dict:
        try: return await validate.execute(incident_id,user.id,data)
        except LookupError as e: raise HTTPException(404,"Ocorrência não encontrada.") from e
        except PermissionError as e: raise HTTPException(409,"O autor não pode validar a própria ocorrência.") from e

    @router.post("/{incident_id}/reviews",status_code=204)
    async def review_one(incident_id:UUID,data:ReviewInput,user:CurrentUser)->Response:
        if user.role not in {"moderador","administrador"}: raise HTTPException(403,"Perfil de moderação necessário.")
        try: await review.execute(incident_id,user.id,data.decision,data.notes)
        except LookupError as e: raise HTTPException(404,"Ocorrência não encontrada.") from e
        return Response(status_code=204)
    return router
