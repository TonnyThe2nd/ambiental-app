import asyncio
import os

os.environ.setdefault("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/urbaneye_test")

from src import outbox_service


def test_publish_batch_publica_sem_manter_transacao_aberta(monkeypatch):
    event = {"id": "event-1", "event_type": "incident.created.v1", "payload": {}, "processing_token": "claim-1"}
    calls = []

    async def claim_batch():
        calls.append("claim")
        return [event]

    async def publish_envelope(payload, event_id, event_type):
        calls.append(("publish", event_id, event_type))

    async def mark_published(event_id, processing_token):
        calls.append(("mark", event_id, processing_token))
        return True

    monkeypatch.setattr(outbox_service, "claim_batch", claim_batch)
    monkeypatch.setattr(outbox_service.publisher, "publish_envelope", publish_envelope)
    monkeypatch.setattr(outbox_service, "mark_published", mark_published)

    assert asyncio.run(outbox_service.publish_batch()) == 1
    assert calls == ["claim", ("publish", "event-1", "incident.created.v1"), ("mark", "event-1", "claim-1")]


def test_publish_batch_reagenda_erro_com_o_token_da_reserva(monkeypatch):
    event = {"id": "event-1", "event_type": "incident.created.v1", "payload": {}, "processing_token": "claim-1"}
    calls = []

    async def claim_batch():
        return [event]

    async def publish_envelope(payload, event_id, event_type):
        raise RuntimeError("broker lento")

    async def reschedule_failed(event_id, processing_token, error):
        calls.append((event_id, processing_token, str(error)))
        return True

    monkeypatch.setattr(outbox_service, "claim_batch", claim_batch)
    monkeypatch.setattr(outbox_service.publisher, "publish_envelope", publish_envelope)
    monkeypatch.setattr(outbox_service, "reschedule_failed", reschedule_failed)

    assert asyncio.run(outbox_service.publish_batch()) == 0
    assert calls == [("event-1", "claim-1", "broker lento")]


def test_confirmacao_e_retentativa_exigem_token_da_reserva():
    source = (os.path.join(os.path.dirname(__file__), "..", "src", "outbox_service.py"))
    with open(source, encoding="utf-8") as file:
        code = file.read()

    assert "WHERE id = %s AND processing_token = %s" in code
    assert "rows = await claim_batch()" in code
    assert "await publisher.publish_envelope" in code


def test_migracao_adiciona_campos_de_reserva_idempotentes():
    migration = os.path.join(
        os.path.dirname(__file__), "..", "..", "database", "migrations", "011_outbox_publish_claims.sql"
    )
    with open(migration, encoding="utf-8") as file:
        code = file.read()

    assert "ADD COLUMN IF NOT EXISTS processing_token UUID" in code
    assert "ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ" in code
