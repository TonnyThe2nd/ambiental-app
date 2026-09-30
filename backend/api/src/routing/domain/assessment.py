"""Roteamento preventivo: compara rotas candidatas pelo risco das ocorrências no caminho.

As rotas vêm de um motor de rotas (OSRM) no app; o servidor cruza cada uma com as
ocorrências ativas no PostGIS e recomenda a de menor risco. Categorias que bloqueiam a
passagem (alagamento, árvore caída, erosão, fogo) pesam o dobro.
"""
from dataclasses import dataclass, field

OBSTRUCTIVE_CATEGORIES = frozenset({"alagamento", "arvore_caida", "erosao", "queimada", "incendio"})
SEVERITY_WEIGHT = {"leve": 1, "moderado": 2, "critico": 3}


@dataclass(frozen=True)
class RouteIncident:
    id: str
    category: str
    severity: str
    distance_m: float
    latitude: float
    longitude: float
    impact_radius_m: int


@dataclass
class RouteAssessment:
    id: str
    incidents: list[RouteIncident] = field(default_factory=list)
    distance_m: float | None = None
    duration_s: float | None = None

    @property
    def risk_score(self) -> int:
        return sum(incident_weight(i.category, i.severity) for i in self.incidents)

    @property
    def blocked(self) -> bool:
        """Há alagamento/obstrução crítica no caminho: a rota não deveria ser usada."""
        return any(i.category in OBSTRUCTIVE_CATEGORIES and i.severity == "critico" for i in self.incidents)


def incident_weight(category: str, severity: str) -> int:
    weight = SEVERITY_WEIGHT.get(severity, 2)
    return weight * 2 if category in OBSTRUCTIVE_CATEGORIES else weight


def recommend(assessments: list[RouteAssessment]) -> RouteAssessment:
    """Menor risco vence; bloqueadas vão para o fim; empate fica com a mais curta/rápida."""
    if not assessments:
        raise ValueError("Nenhuma rota para avaliar.")
    return min(enumerate(assessments), key=lambda item: (
        item[1].blocked, item[1].risk_score,
        item[1].duration_s if item[1].duration_s is not None else float("inf"), item[0]))[1]
