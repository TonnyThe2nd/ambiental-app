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

    async def execute(self, user_id: UUID) -> int:
        alerts = await self._alerts.create_for_nearby_incidents(user_id)
        token = await self._users.find_push_token(user_id)
        if token:
            for alert in alerts:
                try:
                    await self._push.send(token, alert)
                except Exception:
                    logging.getLogger("urbaneye.alerts").exception(
                        "Falha no push %s; notificação permaneceu persistida", alert.id
                    )
        return len(alerts)
