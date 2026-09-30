import asyncio
import json

from src import messaging
from src.realtime.infrastructure.event_listener import RealtimeEventListener


class Exchange:
    def __init__(self):
        self.published = []

    async def publish(self, message, routing_key, mandatory):
        self.published.append((routing_key, mandatory, dict(message.headers or {})))


class Channel:
    def __init__(self):
        self.exchange = Exchange()

    async def get_exchange(self, name):
        return self.exchange


def test_so_eventos_criticos_exigem_consumidor_duravel():
    publisher = messaging.EventPublisher()
    publisher.channel = Channel()
    created = {"data": {"id": "i1", "geohash": "6gyf4bf"}}
    validation = {"data": {"id": "i1", "geohash": "6gyf4bf"}}
    asyncio.run(publisher.publish_envelope(created, "e1", "incident.created.v1"))
    asyncio.run(publisher.publish_envelope(validation, "e2", "incident.validation.updated.v1"))
    (_, created_mandatory, headers), (_, validation_mandatory, _) = publisher.channel.exchange.published
    # Antes, a validação era publicada com mandatory=True sem fila ligada: o broker devolvia
    # a mensagem e a outbox ficava reagendando o evento para sempre.
    assert created_mandatory is True and validation_mandatory is False
    assert headers == {"x-geohash": "6gyf4bf", "x-geo-partition": "6gyf"}


class Hub:
    def __init__(self):
        self.events = []

    async def publish(self, envelope):
        self.events.append(envelope)
        return 1


class Cache:
    def __init__(self):
        self.invalidations = 0

    async def invalidate(self):
        self.invalidations += 1


def test_evento_do_barramento_invalida_cache_e_vai_para_o_hub():
    hub, cache = Hub(), Cache()
    listener = RealtimeEventListener(hub, cache)
    body = json.dumps({"eventType": "incident.created.v1", "data": {"geohash": "6gyf4bf"}}).encode()
    assert asyncio.run(listener.handle(body)) == 1
    assert cache.invalidations == 1 and hub.events[0]["eventType"] == "incident.created.v1"
    assert asyncio.run(listener.handle(b"{quebrado")) == 0
