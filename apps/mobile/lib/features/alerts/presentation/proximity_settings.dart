import 'package:flutter/material.dart';

import '../../../core/device/location_service.dart';
import '../application/notification_service.dart';
import '../application/proximity_monitor.dart';

/// Fluxo de ativação dos alertas de área: notificações + localização "o tempo todo".
Future<void> enableProximityAlerts(BuildContext context, ProximityMonitor monitor) async {
  final messenger = ScaffoldMessenger.of(context);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.shield_outlined),
      title: const Text('Alertas de área de risco'),
      content: const Text(
        'Para avisar quando você entrar em uma área com alagamento, queimada ou outra '
        'ocorrência — inclusive com o app minimizado ou fechado — o UrbanEye precisa de '
        'notificações e da localização "Permitir o tempo todo".\n\n'
        'A localização é usada só para comparar sua posição com as áreas de risco.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Agora não')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
      ],
    ),
  );
  if (proceed != true) return;
  await SystemNotificationService.requestPermission();
  await monitor.setEnabled(true);
  final access = await monitor.requestAccess(background: true);
  if (!context.mounted) return;
  switch (access) {
    case LocationAccess.always:
      messenger.showSnackBar(const SnackBar(
        content: Text('Alertas ativos, inclusive com o app fechado.'),
      ));
    case LocationAccess.whileInUse:
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Falta um passo'),
          content: const Text(
            'Com a permissão "Durante o uso do app" os alertas funcionam com o app aberto '
            'ou minimizado. Para receber alertas com o app fechado, abra as configurações '
            'e escolha "Permitir o tempo todo" em Localização.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Depois')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir configurações')),
          ],
        ),
      );
      if (openSettings == true) await monitor.openSettings();
    case LocationAccess.serviceDisabled:
      messenger.showSnackBar(const SnackBar(content: Text('Ative a localização do aparelho.')));
    case LocationAccess.denied:
      messenger.showSnackBar(const SnackBar(
        content: Text('Sem permissão de localização os alertas de área não funcionam.'),
      ));
  }
}

String proximityStatusText(ProximityMonitor monitor) {
  if (!monitor.enabled) return 'Desativado';
  return switch (monitor.access) {
    LocationAccess.always => monitor.tracking
        ? 'Ativo — avisa mesmo com o app fechado'
        : 'Ativo com o app fechado (verificação a cada 15 min)',
    LocationAccess.whileInUse => 'Ativo com o app aberto ou minimizado',
    LocationAccess.serviceDisabled => 'Localização do aparelho desligada',
    LocationAccess.denied => 'Sem permissão de localização',
  };
}

/// Linha de configuração para a tela de conta.
class ProximitySettingsTile extends StatelessWidget {
  const ProximitySettingsTile({super.key, required this.monitor});
  final ProximityMonitor monitor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: monitor,
    builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.shield_outlined),
      title: const Text('Alertas de área de risco'),
      subtitle: Text(proximityStatusText(monitor)),
      value: monitor.enabled && monitor.access.granted,
      onChanged: (value) async {
        if (value) {
          await enableProximityAlerts(context, monitor);
        } else {
          await monitor.setEnabled(false);
        }
      },
    ),
  );
}
