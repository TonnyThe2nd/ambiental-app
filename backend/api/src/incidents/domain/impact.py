"""Área de impacto de uma ocorrência: o raio em que uma pessoa está "dentro" do risco.

É diferente do raio de alerta do usuário (até onde ele quer ser avisado de novos relatos).
A área de impacto responde "estou numa área de ocorrência?": um alagamento afeta algumas
quadras, a fumaça de uma queimada alcança quilômetros. O app Flutter espelha esta tabela
em ``incident_impact.dart`` para avaliar a entrada na área mesmo sem rede.
"""

BASE_IMPACT_RADIUS_M: dict[str, int] = {
    "alagamento": 400,
    "poluicao": 1500,
    "queimada": 2000,
    "incendio": 1500,
    "desmatamento": 1000,
    "esgoto": 200,
    "lixo": 150,
    "ruido": 300,
    "erosao": 300,
    "arvore_caida": 100,
    "animal_morto": 100,
    "outro": 250,
}
SEVERITY_FACTOR: dict[str, float] = {"leve": 0.75, "moderado": 1.0, "critico": 1.5}
MIN_RADIUS_M, MAX_RADIUS_M = 50, 5000


def impact_radius_m(category: str, severity: str) -> int:
    base = BASE_IMPACT_RADIUS_M.get(category.strip().lower(), BASE_IMPACT_RADIUS_M["outro"])
    radius = base * SEVERITY_FACTOR.get(severity, 1.0)
    # Arredonda meio para cima (igual ao round() do PostgreSQL e do Dart).
    return int(min(MAX_RADIUS_M, max(MIN_RADIUS_M, int(radius / 10 + 0.5) * 10)))
