import asyncio

import pytest

from src.realtime.domain.hub import RealtimeHub, validate_prefixes


class Channel:
    def __init__(self, fail=False):
        self.sent, self.fail = [], fail

    async def send_json(self, data):
        if self.fail:
            raise RuntimeError("socket fechado")
        self.sent.append(data)


def _event(cell):
    return {"eventId": "e1", "eventType": "incident.created.v1", "data": {"id": "i1", "geohash": cell}}


def test_entrega_somente_para_quem_assinou_o_quadrante():
    hub = RealtimeHub()
    sp, rj = Channel(), Channel()
    hub.connect(sp, "u1").prefixes = {"6gyf"}
    hub.connect(rj, "u2").prefixes = {"75cm"}

    delivered = asyncio.run(hub.publish(_event("6gyf4bf")))

    assert delivered == 1
    assert sp.sent[0]["eventType"] == "incident.created.v1"
    assert rj.sent == []


def test_conexao_morta_e_removida():
    hub = RealtimeHub()
    hub.connect(Channel(fail=True), "u1").prefixes = {"6gy"}
    assert asyncio.run(hub.publish(_event("6gyf4bf"))) == 0
    assert hub.connections == 0


def test_evento_sem_geohash_vai_para_assinantes_ativos():
    hub = RealtimeHub()
    active, idle = Channel(), Channel()
    hub.connect(active, "u1").prefixes = {"6gyf"}
    hub.connect(idle, "u2")
    asyncio.run(hub.publish({"eventType": "x", "data": {}}))
    assert len(active.sent) == 1 and idle.sent == []


@pytest.mark.parametrize("value", [["6g"], ["6gyf4bf12"], ["6gya"], "6gyf", [1], ["6gyf"] * 51])
def test_assinatura_invalida_e_rejeitada(value):
    with pytest.raises(ValueError):
        validate_prefixes(value)
