import asyncio
import os

from ..domain.proximity import ProximityAlert


class FirebasePushNotificationGateway:
    def __init__(self):
        self._enabled = os.getenv("FCM_ENABLED", "false").lower() in {"1", "true", "yes"}

    async def send(self, token: str, alert: ProximityAlert) -> None:
        if not self._enabled:
            return
        await asyncio.to_thread(self._send, token, alert)

    @staticmethod
    def _send(token: str, alert: ProximityAlert) -> None:
        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
            firebase_admin.initialize_app(credentials.Certificate(path) if path else None)
        messaging.send(messaging.Message(
            token=token,
            notification=messaging.Notification(title=alert.title, body=alert.message),
            data={"notificationId": str(alert.id), "incidentId": str(alert.incident.id),
                  "type": "proximity_entry"},
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(headers={"apns-priority": "10"}),
        ))
