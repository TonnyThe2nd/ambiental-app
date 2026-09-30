from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ...auth import CurrentUser
from ..domain.assessment import RouteAssessment, recommend


class RouteCandidate(BaseModel):
    id: str = Field(min_length=1, max_length=20)
    points: list[tuple[float, float]] = Field(min_length=2, max_length=2000)
    distance_m: float | None = Field(default=None, validation_alias="distanceMeters", ge=0)
    duration_s: float | None = Field(default=None, validation_alias="durationSeconds", ge=0)


class RouteAssessmentInput(BaseModel):
    routes: list[RouteCandidate] = Field(min_length=1, max_length=3)
    corridor_m: int = Field(default=100, validation_alias="corridorMeters", ge=30, le=500)


def _output(assessment: RouteAssessment, recommended_id: str) -> dict:
    return {
        "id": assessment.id, "riskScore": assessment.risk_score, "blocked": assessment.blocked,
        "recommended": assessment.id == recommended_id,
        "distanceMeters": assessment.distance_m, "durationSeconds": assessment.duration_s,
        "incidents": [{"id": i.id, "category": i.category, "severity": i.severity,
                       "distanceMeters": round(i.distance_m, 1), "latitude": i.latitude,
                       "longitude": i.longitude, "impactRadiusM": i.impact_radius_m}
                      for i in assessment.incidents],
    }


def create_routing_router(repository) -> APIRouter:
    router = APIRouter(prefix="/routes", tags=["routing"])

    @router.post("/assess")
    async def assess(data: RouteAssessmentInput, _: CurrentUser) -> dict:
        """Roteamento preventivo: risco de cada rota candidata e a recomendada."""
        for route in data.routes:
            if any(not (-90 <= lat <= 90 and -180 <= lon <= 180) for lat, lon in route.points):
                raise HTTPException(422, f"Rota {route.id} tem coordenadas inválidas.")
        assessments = [RouteAssessment(route.id, await repository.incidents_along(route.points, data.corridor_m),
                                       route.distance_m, route.duration_s) for route in data.routes]
        best = recommend(assessments)
        return {"recommendedId": best.id, "routes": [_output(a, best.id) for a in assessments]}

    return router
