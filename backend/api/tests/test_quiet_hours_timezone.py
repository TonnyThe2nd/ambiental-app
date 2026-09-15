import pytest
from pydantic import ValidationError
from pathlib import Path

from src.identity.presentation.schemas import AlertPreferencesInput


def test_preferencias_de_alerta_aceitam_fuso_iana():
    preferences = AlertPreferencesInput.model_validate({
        "quietHoursStart": "22:00",
        "quietHoursEnd": "07:00",
        "timezone": "America/Manaus",
    })

    assert preferences.timezone == "America/Manaus"


def test_preferencias_de_alerta_rejeitam_fuso_invalido():
    with pytest.raises(ValidationError, match="fuso IANA"):
        AlertPreferencesInput(timezone="fuso-inexistente")


def test_consultas_de_horario_silencioso_usam_o_fuso_do_usuario():
    source_root = Path(__file__).parents[1] / "src"
    queries = [
        (source_root / "geolocation_repository.py").read_text(encoding="utf-8"),
        (source_root / "alerts" / "infrastructure" / "postgres_proximity_repository.py").read_text(encoding="utf-8"),
    ]

    for query in queries:
        assert "LOCALTIME" not in query
        assert "NOW() AT TIME ZONE u.timezone" in query
