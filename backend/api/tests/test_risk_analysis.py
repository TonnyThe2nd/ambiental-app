from src.risk_analysis import assess_risk


def test_low_risk_incident_is_light():
    result = assess_risk("ruido")
    assert result.severity == "leve"
    assert result.score == 25


def test_sensitive_area_escalates_risk():
    result = assess_risk("poluicao", sensitive_area_criticality=5)
    assert result.severity == "critico"
    assert result.score == 85


def test_weather_context_escalates_flooding_but_caps_score():
    result = assess_risk("alagamento", sensitive_area_criticality=5, rainfall_mm=200)
    assert result.severity == "critico"
    assert result.score == 100
