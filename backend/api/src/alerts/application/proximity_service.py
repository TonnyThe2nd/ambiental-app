import logging
from uuid import UUID

from .ports import ProximityAlertRepository, PushNotificationGateway, UserPushTokenRepository


class EvaluateUserProximity:
    """Creates one alert when a user's new position enters an active incident radius."""

    def __init__(self, alerts: ProximityAlertRepository,
                 users: UserPushTokenRepository, push: PushNotificationGateway):
        self._alerts = alerts
        self._users = users
        self._push = push

    async def execute(self, user_id: UUID, push: bool = True) -> int:
        return len(await self.evaluate(user_id, push=push))

    async def evaluate(self, user_id: UUID, push: bool = True) -> list:
        """Cria as notificações de entrada em área e (opcionalmente) envia o push.

        ``push=False`` é usado quando o próprio app faz o geofencing local e mostra a
        notificação do sistema: o servidor só registra o histórico e devolve os alertas,
        evitando notificação duplicada no aparelho.
        """
        alerts = await self._alerts.create_for_nearby_incidents(user_id)
        token = await self._users.find_push_token(user_id) if push and alerts else None
        if token:
            for alert in alerts:
                try:
                    await self._push.send(token, alert)
                except Exception:
                    logging.getLogger("urbaneye.alerts").exception(
                        "Falha no push %s; notificação permaneceu persistida", alert.id
                    )
        return alerts
