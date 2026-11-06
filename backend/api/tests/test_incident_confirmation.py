from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from src.auth import get_current_user
from src.incidents.application.use_cases import ValidateIncident
from src.incidents.presentation.router import create_incidents_router
from src.models import UserOutput

USER = UserOutput(id=uuid4(), name="Ana", email="ana@example.com")


class FakeRepository:
    def __init__(self):
        self.votes = {}

    async def my_vote(self, incident_id, user_id):
        return self.votes.get((incident_id, user_id))

    async def validate(self, incident_id, user_id, data):
        self.votes[(incident_id, user_id)] = data.vote
        return {"id": str(incident_id)}


def _client(repository):
    app = FastAPI()
    validate = ValidateIncident(repository)
    app.include_router(create_incidents_router(None, None, validate, None))
    app.dependency_overrides[get_current_user] = lambda: USER
    return TestClient(app)


def test_voto_do_usuario_e_nulo_antes_de_confirmar():
    client = _client(FakeRepository())
    response = client.get(f"/incidents/{uuid4()}/community-validation")
    assert response.status_code == 200
    assert response.json() == {"vote": None}


def test_confirmacao_no_local_fica_registrada_para_o_usuario():
    repository = FakeRepository()
    client = _client(repository)
    incident_id = uuid4()
    assert client.put(f"/incidents/{incident_id}/community-validation",
                      json={"vote": "confirmar"}).status_code == 200
    assert client.get(f"/incidents/{incident_id}/community-validation").json() == {"vote": "confirmar"}
