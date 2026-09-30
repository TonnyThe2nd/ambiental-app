import asyncio
import re
from pathlib import Path
from uuid import uuid4

from src.alerts.application.proximity_service import EvaluateUserProximity
from src.alerts.domain.proximity import NearbyIncident, ProximityAlert
from src.incidents.domain.impact import BASE_IMPACT_RADIUS_M, impact_radius_m
from src.routing.domain.assessment import RouteAssessment, RouteIncident, recommend
from src.routing.infrastructure.postgres_route_repository import linestring_wkt


def test_area_de_impacto_depende_da_categoria_e_da_gravidade():
    assert impact_radius_m("alagamento", "moderado") == 400
    assert impact_radius_m("alagamento", "critico") == 600
    assert impact_radius_m("poluicao", "leve") == 1130  # 1125 arredonda para cima, igual ao SQL
    assert impact_radius_m("desconhecida", "moderado") == 250


def test_migracao_espelha_a_tabela_do_dominio():
    sql = (Path(__file__).parents[2] / "database" / "migrations" / "014_incident_impact_area.sql").read_text()
    in_sql = dict(re.findall(r"WHEN '(\w+)' THEN (\d+)$", sql, re.M))
    assert {key: int(value) for key, value in in_sql.items()} == BASE_IMPACT_RADIUS_M


def _incident(category, severity):
    return RouteIncident(str(uuid4()), category, severity, 10.0, -23.5, -46.6, 400)


def test_rota_recomendada_evita_alagamento_critico():
    fast = RouteAssessment("0", [_incident("alagamento", "critico")], 5000, 600)
    slow = RouteAssessment("1", [_incident("lixo", "leve")], 6500, 780)
    assert fast.blocked and not slow.blocked
    assert recommend([fast, slow]).id == "1"


def test_empate_de_risco_fica_com_a_rota_mais_rapida():
    a = RouteAssessment("a", [], 5000, 700)
    b = RouteAssessment("b", [], 4000, 500)
    assert recommend([a, b]).id == "b"


def test_wkt_usa_ordem_longitude_latitude():
    assert linestring_wkt([(-23.5, -46.6), (-23.6, -46.7)]) == \
        "SRID=4326;LINESTRING(-46.600000 -23.500000, -46.700000 -23.600000)"


class Repo:
    def __init__(self, alerts):
        self.alerts, self.token_calls = alerts, 0

    async def create_for_nearby_incidents(self, _):
        return self.alerts

    async def find_push_token(self, _):
        self.token_calls += 1
        return "token"


class Push:
    def __init__(self):
        self.sent = []

    async def send(self, token, alert):
        self.sent.append(alert.id)


def test_geofencing_local_registra_mas_nao_duplica_o_push():
    alert = ProximityAlert(uuid4(), uuid4(), NearbyIncident(uuid4(), "alagamento", "critico", .1, -23.5, -46.6, 600),
                           "Você entrou em uma área de risco", "Área de alagamento")
    repo, push = Repo([alert]), Push()
    alerts = asyncio.run(EvaluateUserProximity(repo, repo, push).evaluate(uuid4(), push=False))
    assert [a.id for a in alerts] == [alert.id]
    assert push.sent == [] and repo.token_calls == 0
