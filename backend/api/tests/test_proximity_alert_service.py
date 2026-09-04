import asyncio
from uuid import uuid4

from src.alerts.application.proximity_service import EvaluateUserProximity
from src.alerts.domain.proximity import NearbyIncident, ProximityAlert


class FakeRepository:
    def __init__(self, alerts, token="device-token"):
        self.alerts = alerts
        self.token = token

    async def create_for_nearby_incidents(self, _user_id):
        return self.alerts

    async def find_push_token(self, _user_id):
        return self.token


class FakePush:
    def __init__(self):
        self.sent = []

    async def send(self, token, alert):
        self.sent.append((token, alert.id))


def test_new_proximity_alert_is_sent_to_device():
    user_id, incident_id, notification_id = uuid4(), uuid4(), uuid4()
    alert = ProximityAlert(notification_id, user_id,
        NearbyIncident(incident_id, "alagamento", "critico", 1.2), "Alerta", "Mensagem")
    repository, push = FakeRepository([alert]), FakePush()

    count = asyncio.run(EvaluateUserProximity(repository, repository, push).execute(user_id))

    assert count == 1
    assert push.sent == [("device-token", notification_id)]


def test_alert_is_persisted_but_not_sent_without_token():
    user_id = uuid4()
    alert = ProximityAlert(uuid4(), user_id,
        NearbyIncident(uuid4(), "lixo", "leve", .3), "Alerta", "Mensagem")
    repository, push = FakeRepository([alert], token=None), FakePush()

    count = asyncio.run(EvaluateUserProximity(repository, repository, push).execute(user_id))

    assert count == 1
    assert push.sent == []
