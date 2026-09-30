import 'app_notification.dart';
import 'proximity_zone.dart';

/// Resultado do envio de posição: áreas em que o servidor detectou a entrada.
class PositionReport {
  const PositionReport(this.alerts);
  final List<ServerProximityAlert> alerts;
}

class ServerProximityAlert {
  const ServerProximityAlert({
    required this.incidentId,
    required this.title,
    required this.message,
    required this.zone,
  });

  final String incidentId;
  final String title;
  final String message;
  final ProximityZone? zone;

  factory ServerProximityAlert.fromJson(Map<String, dynamic> json) {
    ProximityZone? zone;
    if (json['latitude'] is num && json['longitude'] is num && json['category'] is String) {
      zone = ProximityZone.fromIncidentJson({...json, 'id': json['incidentId']});
    }
    return ServerProximityAlert(
      incidentId: json['incidentId'] as String,
      title: json['title'] as String? ?? 'Você entrou em uma área de risco',
      message: json['message'] as String? ?? 'Há uma ocorrência ambiental nesta área.',
      zone: zone,
    );
  }
}

abstract interface class NotificationGateway {
  Future<bool> updatePosition({required double latitude, required double longitude, String? fcmToken});

  /// Envia a posição (e opcionalmente a rota ativa) e devolve as entradas em área
  /// detectadas no servidor. ``localGeofencing`` pede ao servidor para não mandar push
  /// (o app mostra a notificação). Retorna ``null`` se não foi possível enviar.
  Future<PositionReport?> reportPosition({
    required double latitude,
    required double longitude,
    String? fcmToken,
    bool localGeofencing = false,
    List<List<double>>? route,
  });

  /// Ocorrências ativas perto do ponto, para o cache de áreas do geofencing local.
  Future<List<ProximityZone>?> nearbyZones({
    required double latitude,
    required double longitude,
    int radiusMeters = 20000,
  });

  Future<List<AppNotification>> list();
  Future<bool> markRead(String id);
}
