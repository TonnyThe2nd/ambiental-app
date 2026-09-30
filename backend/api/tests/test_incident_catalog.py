from uuid import uuid4

import pytest
from pydantic import ValidationError

from src.incidents.domain.categories import normalize_category, normalize_environmental_context
from src.incidents.presentation.schemas import IncidentInput, IncidentOutput


def _payload(**overrides):
    base = {"id": str(uuid4()), "category": "alagamento", "latitude": -23.55, "longitude": -46.63,
            "createdAt": "2026-09-30T12:00:00Z", "idempotencyKey": "a" * 64}
    return {**base, **overrides}


def test_categoria_e_normalizada():
    assert normalize_category("  Alagamento ") == "alagamento"


def test_categoria_fora_do_catalogo_e_rejeitada_na_entrada():
    with pytest.raises(ValidationError):
        IncidentInput.model_validate(_payload(category="enchente-inventada"))


def test_leitura_nao_revalida_dados_antigos():
    output = IncidentOutput.model_validate(_payload(category="categoria-legada"))
    assert output.category == "categoria-legada"


def test_contexto_ambiental_numerico_e_validado():
    assert normalize_environmental_context({"rainfallMm": 35, "airQualityIndex": 120.0, "fonte": "open-meteo"}) == {
        "rainfallMm": 35.0, "airQualityIndex": 120, "fonte": "open-meteo"}
    with pytest.raises(ValueError):
        normalize_environmental_context({"rainfallMm": "muita"})
    with pytest.raises(ValueError):
        normalize_environmental_context({"airQualityIndex": -1})


def test_contexto_invalido_vira_erro_de_validacao_e_nao_500():
    with pytest.raises(ValidationError):
        IncidentInput.model_validate(_payload(environmentalContext={"rainfallMm": "x"}))
