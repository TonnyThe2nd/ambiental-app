import asyncio
import os
from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest

os.environ.setdefault("JWT_SECRET", "segredo-de-teste-com-mais-de-32-caracteres")

from src.identity.application.services import AuthenticationService
from src.identity.domain.entities import User
from src.identity.infrastructure.jwt_tokens import JwtTokenService
from src.incidents.presentation.schemas import ReporterPublic
from src.shared.domain.exceptions import EntityNotFound


class FakeUserRepository:
    def __init__(self, user: User | None):
        self._user = user
        self.anonymized: list[UUID] = []
        self.created: list[dict] = []

    async def create(self, **values) -> User:
        self.created.append(values)
        return User(uuid4(), values["name"], values["email"])

    async def find_by_id(self, user_id: UUID) -> User | None:
        return self._user

    async def anonymize(self, user_id: UUID) -> bool:
        self.anonymized.append(user_id)
        return True


class FakeRevokedTokenRepository:
    def __init__(self):
        self.revoked: set[UUID] = set()

    async def revoke(self, *, jti: UUID, user_id: UUID, expires_at: datetime) -> None:
        assert expires_at > datetime.now(timezone.utc)
        self.revoked.add(jti)

    async def is_revoked(self, jti: UUID) -> bool:
        return jti in self.revoked


def test_reporter_public_nao_expoe_email():
    assert "email" not in ReporterPublic.model_fields
    payload = ReporterPublic(id=uuid4(), name="Denunciante").model_dump(by_alias=True)
    assert set(payload) == {"id", "name", "trustScore"}


def test_token_carrega_jti_unico():
    tokens = JwtTokenService()
    user_id = uuid4()
    first, second = tokens.create(user_id), tokens.create(user_id)
    _, first_jti, expires_at = tokens.identity(first)
    _, second_jti, _ = tokens.identity(second)
    assert first_jti is not None and first_jti != second_jti
    assert expires_at > datetime.now(timezone.utc)


def test_token_revogado_perde_a_validade():
    user = User(uuid4(), "Cidadã", "cidada@example.com")
    service = AuthenticationService(FakeUserRepository(user), JwtTokenService(),
                                    FakeRevokedTokenRepository())
    token = service._tokens.create(user.id)

    assert asyncio.run(service.authenticate(token)) == user
    asyncio.run(service.revoke(token))
    with pytest.raises(EntityNotFound):
        asyncio.run(service.authenticate(token))


def test_conta_removida_deixa_de_autenticar():
    service = AuthenticationService(FakeUserRepository(None), JwtTokenService(),
                                    FakeRevokedTokenRepository())
    token = service._tokens.create(uuid4())
    with pytest.raises(EntityNotFound):
        asyncio.run(service.authenticate(token))


def test_cadastro_sem_localizacao():
    repository = FakeUserRepository(None)
    service = AuthenticationService(repository, JwtTokenService(), FakeRevokedTokenRepository())
    asyncio.run(service.register(name="Sem GPS", email="Sem.GPS@Example.com ", password="senha-forte"))
    assert repository.created[0]["latitude"] is None
    assert repository.created[0]["longitude"] is None
    assert repository.created[0]["email"] == "sem.gps@example.com"
