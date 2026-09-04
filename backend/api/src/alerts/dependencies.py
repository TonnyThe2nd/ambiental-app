from .application import EvaluateUserProximity
from .infrastructure import FirebasePushNotificationGateway, PostgresProximityAlertRepository

_repository = PostgresProximityAlertRepository()
evaluate_user_proximity = EvaluateUserProximity(
    _repository, _repository, FirebasePushNotificationGateway(),
)
