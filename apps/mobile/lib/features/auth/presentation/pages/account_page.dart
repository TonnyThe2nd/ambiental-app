import 'package:flutter/material.dart';

import '../../../../services/auth/auth_service.dart';
import '../../../../services/notifications/notification_service.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.auth,
    required this.notifications,
  });
  final AuthService auth;
  final NotificationService notifications;
  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;
    return AnimatedBuilder(
      animation: notifications,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Minha conta'),
          actions: [
            IconButton(
              onPressed: notifications.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar notificações',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFD9EEE8),
                      child: Text(
                        user.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF176B5B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            style: const TextStyle(color: Color(0xFF667C75)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _NotificationsSection(notifications: notifications),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: auth.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({required this.notifications});
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    final items = notifications.notifications;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Alertas próximos',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (notifications.unreadCount > 0)
                  Badge(label: Text('${notifications.unreadCount}')),
              ],
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const Text(
                'Nenhum alerta no seu raio por enquanto.',
                style: TextStyle(color: Color(0xFF667C75)),
              )
            else
              ...items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.readAt == null
                        ? Icons.circle_notifications
                        : Icons.notifications_none,
                    color: item.readAt == null
                        ? const Color(0xFF176B5B)
                        : const Color(0xFF8AA098),
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.message),
                  trailing: item.readAt == null
                      ? IconButton(
                          onPressed: () => notifications.markRead(item.id),
                          icon: const Icon(Icons.done),
                          tooltip: 'Marcar como lida',
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
