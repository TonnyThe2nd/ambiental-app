"""Hub de tempo real: roteia eventos de ocorrência para as conexões WebSocket interessadas.

Cada conexão assina prefixos GeoHash (quadrantes). Um evento com geohash ``6gyf4bf`` é
entregue a quem assinou ``6gyf`` ou ``6gy`` — a mesma chave de partição usada no cache e
no mapa de calor. Assim cada instância da API só empurra para cada celular o que está
na região que ele vê, em vez de difundir tudo para todos.
"""
import asyncio
import logging
from dataclasses import dataclass, field
from typing import Protocol

from ...shared.domain import geohash

logger = logging.getLogger("urbaneye.realtime")
MAX_SUBSCRIPTIONS = 50
MIN_PREFIX, MAX_PREFIX = 3, 7


class Channel(Protocol):
    async def send_json(self, data: dict) -> None: ...


@dataclass(eq=False)
class Subscriber:
    channel: Channel
    user_id: str
    prefixes: set[str] = field(default_factory=set)


def validate_prefixes(values: list) -> set[str]:
    if not isinstance(values, list) or len(values) > MAX_SUBSCRIPTIONS:
        raise ValueError(f"Envie uma lista com até {MAX_SUBSCRIPTIONS} células GeoHash.")
    cells = set()
    for value in values:
        if not isinstance(value, str) or not MIN_PREFIX <= len(value) <= MAX_PREFIX or not geohash.is_valid(value):
            raise ValueError(f"Célula GeoHash inválida: {value!r} (use precisão {MIN_PREFIX} a {MAX_PREFIX}).")
        cells.add(value)
    return cells


class RealtimeHub:
    def __init__(self) -> None:
        self._subscribers: set[Subscriber] = set()

    def connect(self, channel: Channel, user_id: str) -> Subscriber:
        subscriber = Subscriber(channel, user_id)
        self._subscribers.add(subscriber)
        return subscriber

    def disconnect(self, subscriber: Subscriber) -> None:
        self._subscribers.discard(subscriber)

    @property
    def connections(self) -> int:
        return len(self._subscribers)

    def targets(self, event_geohash: str | None) -> list[Subscriber]:
        if not event_geohash:
            # Evento sem localização (legado): quem tem assinatura ativa recebe.
            return [s for s in self._subscribers if s.prefixes]
        return [s for s in self._subscribers if geohash.matches(event_geohash, s.prefixes)]

    async def publish(self, envelope: dict) -> int:
        data = envelope.get("data") or {}
        message = {"type": "event", "eventType": envelope.get("eventType"),
                   "eventId": envelope.get("eventId"), "data": data}
        targets = self.targets(data.get("geohash"))
        results = await asyncio.gather(*(s.channel.send_json(message) for s in targets),
                                       return_exceptions=True)
        delivered = 0
        for subscriber, result in zip(targets, results):
            if isinstance(result, Exception):
                logger.info("Conexão de tempo real encerrada durante o envio: %s", result)
                self.disconnect(subscriber)
            else:
                delivered += 1
        return delivered


hub = RealtimeHub()
