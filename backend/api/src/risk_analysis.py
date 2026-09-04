"""Compatibility facade for the incident risk domain service."""
from .incidents.domain.risk import RiskAssessment, RiskAssessmentService

def assess_risk(category: str, sensitive_area_criticality: int = 0,
                rainfall_mm: float | None = None, air_quality_index: int | None = None) -> RiskAssessment:
    return RiskAssessmentService().assess(category,
        sensitive_area_criticality=sensitive_area_criticality,
        rainfall_mm=rainfall_mm, air_quality_index=air_quality_index)

__all__ = ["RiskAssessment", "assess_risk"]
