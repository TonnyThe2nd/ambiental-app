from datetime import datetime
from uuid import UUID
from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from ...auth import CurrentUser
from ...models import CommunityValidationInput, IncidentAccepted, IncidentInput, IncidentOutput, ReporterPublic, ReviewInput
from ...producer import DuplicateIncidentError
from ...shared.domain import geohash
from ..domain.impact import impact_radius_m
from ..application.ports import HeatmapFilters, IncidentFilters
from ..application.use_cases import CreateIncidentUseCase, IncidentPhotos, ListHeatmap, ListIncidentsUseCase, ReviewIncidentUseCase, ValidateIncidentUseCase


def create_incidents_router(create: CreateIncidentUseCase, listing: ListIncidentsUseCase, validate: ValidateIncidentUseCase, review: ReviewIncidentUseCase, heatmap: ListHeatmap | None = None, photos: IncidentPhotos | None = None) -> APIRouter:
    router = APIRouter(prefix="/incidents", tags=["incidents"])

    @router.post("", response_model=IncidentAccepted, status_code=202)
    async def create_one(data: IncidentInput, user: CurrentUser) -> IncidentAccepted:
        try: _, assessment = await create.execute(data, user.id)
        except DuplicateIncidentError as e: raise HTTPException(409, "Incidente duplicado.") from e
        except Exception as e: raise HTTPException(500, "Não foi possível persistir o incidente.") from e
        return IncidentAccepted(**data.model_dump(), reported_by=ReporterPublic(id=user.id,name=user.name,trust_score=user.trust_score), severity=assessment.severity, risk_score=assessment.score, health_impact=assessment.health_impact, ecosystem_impact=assessment.ecosystem_impact, community_impact=assessment.community_impact, geohash=geohash.encode(data.latitude, data.longitude), impact_radius_m=impact_radius_m(data.category, assessment.severity))

    @router.get("", response_model=list[IncidentOutput])
    async def list_all(_: CurrentUser, updated_since: datetime|None=None, updated_after_id: UUID|None=None, categories:list[str]=Query(default=[]), severities:list[str]=Query(default=[]), active_only:bool=True, limit:int=Query(500,ge=1,le=2000), latitude:float|None=Query(None,ge=-90,le=90), longitude:float|None=Query(None,ge=-180,le=180), radius_m:int=Query(50000,ge=1000,le=100000)) -> list[IncidentOutput]:
        try: rows=await listing.execute(IncidentFilters(updated_since=updated_since,updated_after_id=updated_after_id,categories=categories,severities=severities,active_only=active_only,limit=limit,latitude=latitude,longitude=longitude,radius_m=radius_m))
        except ValueError as e: raise HTTPException(422,str(e)) from e
        return [IncidentOutput(**{**r,"reported_by": ReporterPublic(id=r["user_id"],name=r["user_name"],trust_score=r["user_trust_score"]) if r["user_id"] else None}) for r in rows]

    @router.get("/heatmap")
    async def heatmap_cells(_: CurrentUser, precision: int = Query(5, ge=3, le=7), days: int = Query(30, ge=1, le=365),
                            categories: list[str] = Query(default=[]), active_only: bool = True,
                            cells: list[str] = Query(default=[])) -> list[dict]:
        """Mapa de calor: contagem e risco por quadrante GeoHash (lido do cache distribuído)."""
        if heatmap is None: raise HTTPException(404, "Mapa de calor indisponível.")
        try: return await heatmap.execute(HeatmapFilters(precision=precision, days=days, categories=categories, active_only=active_only, cells=cells))
        except ValueError as e: raise HTTPException(422, str(e)) from e

    @router.put("/{incident_id}/photo", status_code=204)
    async def upload_photo(incident_id: UUID, request: Request, user: CurrentUser) -> Response:
        """Recebe a foto crua (image/jpeg, image/png ou image/webp) enviada pelo app após o relato."""
        if photos is None: raise HTTPException(404, "Envio de fotos indisponível.")
        declared = int(request.headers.get("content-length") or 0)
        if declared > photos.max_bytes: raise HTTPException(413, "Foto maior que 5 MB.")
        chunks, size = [], 0
        async for chunk in request.stream():
            size += len(chunk)
            if size > photos.max_bytes: raise HTTPException(413, "Foto maior que 5 MB.")
            chunks.append(chunk)
        content = b"".join(chunks)
        try: await photos.save(incident_id, user.id, content)
        except LookupError as e: raise HTTPException(404, "Ocorrência não encontrada.") from e
        except PermissionError as e: raise HTTPException(403, "Só o autor pode enviar a foto do relato.") from e
        except OverflowError as e: raise HTTPException(413, "Foto maior que 5 MB.") from e
        except ValueError as e: raise HTTPException(415, str(e)) from e
        return Response(status_code=204)

    @router.get("/{incident_id}/photo")
    async def download_photo(incident_id: UUID, _: CurrentUser) -> Response:
        if photos is None: raise HTTPException(404, "Foto indisponível.")
        photo = await photos.load(incident_id)
        if photo is None: raise HTTPException(404, "Ocorrência sem foto.")
        return Response(content=bytes(photo["content"]), media_type=photo["content_type"],
                        headers={"Cache-Control": "private, max-age=86400"})

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
