"""Regras determinísticas e auditáveis de triagem; futuramente substituíveis por ML."""
from dataclasses import dataclass


@dataclass(frozen=True)
class RiskAssessment:
    severity: str
    score: float
    health_impact: str
    ecosystem_impact: str
    community_impact: str


CATEGORY_BASE_RISK = {
    "alagamento": 65, "poluicao": 60, "queimada": 80, "desmatamento": 70,
    "esgoto": 65, "lixo": 35, "ruido": 25,
}


def assess_risk(category: str, sensitive_area_criticality: int = 0,
                rainfall_mm: float | None = None, air_quality_index: int | None = None) -> RiskAssessment:
    normalized = category.strip().lower()
    score = float(CATEGORY_BASE_RISK.get(normalized, 40))
    score += min(max(sensitive_area_criticality, 0), 5) * 5
    if normalized == "alagamento" and rainfall_mm is not None:
        score += min(max(rainfall_mm - 20, 0) / 2, 15)
    if normalized in {"poluicao", "queimada"} and air_quality_index is not None:
        score += 15 if air_quality_index >= 151 else 8 if air_quality_index >= 101 else 0
    score = round(min(score, 100), 2)
    severity = "critico" if score >= 75 else "moderado" if score >= 45 else "leve"
    impacts = {
        "critico": ("Risco imediato a grupos vulneráveis", "Dano relevante ou persistente", "Pode exigir resposta emergencial"),
        "moderado": ("Possível exposição e sintomas localizados", "Impacto local que requer verificação", "Afeta mobilidade ou bem-estar local"),
        "leve": ("Baixo risco imediato", "Impacto localizado e reversível", "Incômodo pontual"),
    }[severity]
    return RiskAssessment(severity, score, *impacts)
