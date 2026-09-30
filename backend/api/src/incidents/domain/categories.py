"""Catálogo fechado de categorias aceitas no relato colaborativo.

Mantido em sincronia com o app (``incident_category_visual.dart``) e com o risco base
de ``RiskAssessmentService``. Um valor fora do catálogo é rejeitado na API em vez de
virar uma categoria nova silenciosamente (que receberia risco genérico e quebraria filtros).
"""

INCIDENT_CATEGORIES: frozenset[str] = frozenset({
    "alagamento", "poluicao", "queimada", "incendio", "desmatamento", "esgoto",
    "lixo", "ruido", "erosao", "arvore_caida", "animal_morto", "outro",
})


def normalize_category(value: str) -> str:
    normalized = value.strip().lower()
    if normalized not in INCIDENT_CATEGORIES:
        raise ValueError(
            f"Categoria desconhecida: {value!r}. Use uma de: {', '.join(sorted(INCIDENT_CATEGORIES))}."
        )
    return normalized


def normalize_environmental_context(context: dict) -> dict:
    """Valida os metadados ambientais usados no cálculo de risco.

    Campos conhecidos precisam ser numéricos e plausíveis; demais chaves são preservadas
    como metadados livres (limitadas em tamanho para não inflar o evento).
    """
    limits = {"rainfallMm": (0, 1000), "airQualityIndex": (0, 1000), "temperatureC": (-60, 70)}
    if len(context) > 20:
        raise ValueError("Contexto ambiental com chaves demais.")
    cleaned: dict = {}
    for key, value in context.items():
        if key in limits:
            if value is None:
                continue
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f"{key} deve ser numérico.")
            low, high = limits[key]
            if not low <= value <= high:
                raise ValueError(f"{key} fora do intervalo {low}–{high}.")
            cleaned[key] = int(value) if key == "airQualityIndex" else float(value)
        elif isinstance(value, (str, int, float, bool)) or value is None:
            cleaned[str(key)[:40]] = value[:200] if isinstance(value, str) else value
    return cleaned
