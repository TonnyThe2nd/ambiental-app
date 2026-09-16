import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../application/auth_service.dart';
import '../../../alerts/application/notification_service.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.auth,
    required this.notifications,
  });
  final AuthService auth;
  final NotificationService notifications;

  Future<void> _confirmDeletion(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir minha conta'),
        content: const Text(
          'Seus dados pessoais — nome, e-mail, senha e localização — são apagados '
          'em definitivo e você sai do aplicativo.\n\n'
          'As ocorrências que você registrou continuam no mapa como informação '
          'pública, sem ligação com você.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await auth.deleteAccount();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

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
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFD9EEE8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: Color(0xFF176B5B)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UrbanEye atualizado!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF174C42),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Você está usando o novo visual da versão 1.0.5.',
                            style: TextStyle(color: Color(0xFF35685E)),
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
            const _AppVersionCard(),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: auth.logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
            const SizedBox(height: 12),
            // Direito de eliminação (LGPD art. 18, VI): precisa estar ao alcance de
            // quem usa o app, não só como endpoint da API.
            TextButton.icon(
              onPressed: () => _confirmDeletion(context),
              icon: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
              label: const Text(
                'Excluir minha conta',
                style: TextStyle(color: Color(0xFFB3261E)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppVersionCard extends StatefulWidget {
  const _AppVersionCard();

  @override
  State<_AppVersionCard> createState() => _AppVersionCardState();
}

class _AppVersionCardState extends State<_AppVersionCard> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => Card(
    child: FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) => ListTile(
        leading: Icon(
          Icons.info_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Sobre o UrbanEye'),
        subtitle: Text(
          snapshot.hasData
              ? 'Versão ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
              : snapshot.hasError
              ? 'Versão indisponível'
              : 'Consultando versão…',
        ),
      ),
    ),
  );
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
