import 'app_notification.dart';

abstract interface class NotificationGateway {
  Future<bool> updatePosition({required double latitude, required double longitude, String? fcmToken});
  Future<List<AppNotification>> list();
  Future<bool> markRead(String id);
}
