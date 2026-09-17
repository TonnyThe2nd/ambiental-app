import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/alerts/application/notification_service.dart';

void main() {
  group('NotificationContent', () {
    test('uses notification payload when present', () {
      final message = RemoteMessage(
        notification: const RemoteNotification(
          title: 'Alerta da nuvem',
          body: 'Queimada detectada',
        ),
        data: const {'title': 'Ignorado', 'body': 'Ignorado'},
      );

      final content = NotificationContent.fromMessage(message);

      expect(content.title, 'Alerta da nuvem');
      expect(content.body, 'Queimada detectada');
    });

    test('uses title and body from data-only payload', () {
      final content = NotificationContent.fromMessage(RemoteMessage(
        data: const {'title': 'Alerta local', 'body': 'Enchente detectada'},
      ));

      expect(content.title, 'Alerta local');
      expect(content.body, 'Enchente detectada');
    });

    test('accepts message field and has safe defaults', () {
      final withMessage = NotificationContent.fromMessage(RemoteMessage(
        data: const {'message': 'Qualidade do ar ruim'},
      ));
      final empty = NotificationContent.fromMessage(const RemoteMessage());

      expect(withMessage.title, 'Novo alerta ambiental');
      expect(withMessage.body, 'Qualidade do ar ruim');
      expect(empty.title, 'Novo alerta ambiental');
      expect(empty.body, 'Há uma ocorrência próxima de você.');
    });

    test('uses the high importance Android channel', () {
      expect(SystemNotificationService.channelId, 'environmental_alerts');
      expect(SystemNotificationService.channelName, 'Alertas ambientais');
    });
  });
}
