"""WebSocket de ocorrências em tempo real (comunicação bidirecional).

Protocolo (JSON):
  cliente → {"action": "subscribe", "geohashes": ["6gyf", "6gyc"]}
            {"action": "unsubscribe", "geohashes": ["6gyc"]}
            {"action": "ping"}
  servidor → {"type": "welcome", "partitionPrecision": 4}
             {"type": "subscribed", "geohashes": [...]}
             {"type": "event", "eventType": "incident.created.v1", "data": {...}}
             {"type": "pong"} | {"type": "error", "message": "..."}

O token JWT vai no cabeçalho Authorization ou em ``?token=`` (clientes que não enviam
cabeçalhos no handshake). A conexão é recusada com código 4401 se o token for inválido.
"""
import json
from typing import Callable

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ...auth import authenticate_token
from ...shared.domain.geohash import PARTITION_PRECISION
from ..domain.hub import RealtimeHub, validate_prefixes


def create_realtime_router(hub: RealtimeHub, available: Callable[[], bool] = lambda: True) -> APIRouter:
    router = APIRouter(tags=["realtime"])

    @router.websocket("/ws/incidents")
    async def incidents_stream(websocket: WebSocket, token: str | None = None) -> None:
        if not available():
            # Sem broker não chegam eventos: recusar faz o app voltar à consulta a cada 15 s
            # em vez de achar que o tempo real está ativo e consultar só a cada 5 min.
            await websocket.close(code=1013, reason="Tempo real indisponível no momento.")
            return
        header = websocket.headers.get("authorization", "")
        bearer = header[7:] if header.lower().startswith("bearer ") else None
        try:
            user = await authenticate_token(bearer or token or "")
        except Exception:
            await websocket.close(code=4401, reason="Autenticação necessária.")
            return
        await websocket.accept()
        subscriber = hub.connect(websocket, str(user.id))
        try:
            await websocket.send_json({"type": "welcome", "partitionPrecision": PARTITION_PRECISION})
            while True:
                raw = await websocket.receive_text()
                try:
                    message = json.loads(raw)
                    action = message.get("action") if isinstance(message, dict) else None
                    if action == "subscribe":
                        subscriber.prefixes |= validate_prefixes(message.get("geohashes"))
                    elif action == "unsubscribe":
                        subscriber.prefixes -= validate_prefixes(message.get("geohashes"))
                    elif action == "replace":
                        subscriber.prefixes = validate_prefixes(message.get("geohashes"))
                    elif action == "ping":
                        await websocket.send_json({"type": "pong"})
                        continue
                    else:
                        raise ValueError("Ação desconhecida.")
                except ValueError as error:
                    await websocket.send_json({"type": "error", "message": str(error)})
                    continue
                await websocket.send_json({"type": "subscribed", "geohashes": sorted(subscriber.prefixes)})
        except (WebSocketDisconnect, RuntimeError):
            pass
        finally:
            hub.disconnect(subscriber)

    return router
