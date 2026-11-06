import 'dart:async';

import 'package:flutter/material.dart';

import '../../incident/presentation/models/incident_category_visual.dart';
import '../application/incident_confirmation.dart';
import '../application/notification_service.dart';

/// Mostra "Isso ainda está aqui?" quando o usuário entra na área de uma ocorrência
/// com o app aberto, ou quando toca na notificação de entrada.
class IncidentConfirmationPrompter extends StatefulWidget {
  const IncidentConfirmationPrompter({super.key, required this.service, required this.child});

  final IncidentConfirmationService service;
  final Widget child;

  @override
  State<IncidentConfirmationPrompter> createState() => _IncidentConfirmationPrompterState();
}

class _IncidentConfirmationPrompterState extends State<IncidentConfirmationPrompter> {
  StreamSubscription<ConfirmationRequest>? _requests;
  StreamSubscription<ProximityNotificationAction>? _taps;
  final _queue = <ConfirmationRequest>[];
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _requests = widget.service.requests.listen(_enqueue);
    _taps = SystemNotificationService.proximityTaps.listen(_onNotificationAction);
    unawaited(_handleLaunch());
  }

  @override
  void dispose() {
    unawaited(_requests?.cancel());
    unawaited(_taps?.cancel());
    super.dispose();
  }

  Future<void> _handleLaunch() async {
    try {
      final action = await SystemNotificationService.launchAction();
      if (action != null) await _onNotificationAction(action);
    } catch (error) {
      debugPrint('Notificação de abertura não lida: $error');
    }
  }

  Future<void> _onNotificationAction(ProximityNotificationAction action) async {
    final vote = action.vote;
    if (vote != null) {
      await _submit(action.incidentId, vote); // botão tratado no isolate principal
    } else {
      await widget.service.openFromNotification(action.incidentId);
    }
  }

  void _enqueue(ConfirmationRequest request) {
    if (_queue.any((item) => item.incidentId == request.incidentId)) return;
    _queue.add(request);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_showing) return;
    _showing = true;
    try {
      while (_queue.isNotEmpty) {
        if (!mounted) return;
        final request = _queue.removeAt(0);
        final vote = await showModalBottomSheet<String>(
          context: context,
          isDismissible: true,
          builder: (context) => _ConfirmationSheet(request: request),
        );
        if (!mounted) return;
        if (vote == null || vote.isEmpty) {
          await widget.service.answer(request.incidentId, null);
        } else {
          await _submit(request.incidentId, vote);
        }
      }
    } finally {
      _showing = false;
    }
  }

  Future<void> _submit(String incidentId, String vote) async {
    String message;
    try {
      final outcome = await widget.service.answer(incidentId, vote);
      message = switch (outcome) {
        ConfirmationOutcome.notAllowed => 'O autor do relato não pode confirmá-lo.',
        ConfirmationOutcome.notFound => 'Esta ocorrência não está mais ativa.',
        _ => vote == confirmVote
            ? 'Obrigado! Ocorrência confirmada no local.'
            : 'Obrigado! Informamos que a ocorrência não está mais no local.',
      };
    } catch (error) {
      message = 'Não foi possível enviar sua resposta: $error';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ConfirmationSheet extends StatelessWidget {
  const _ConfirmationSheet({required this.request});

  final ConfirmationRequest request;

  @override
  Widget build(BuildContext context) {
    final zone = request.zone;
    final theme = Theme.of(context);
    final distance = request.distanceMeters;
    final details = zone == null
        ? 'Você passou pela área de uma ocorrência registrada.'
        : '${incidentCategoryVisual(zone.category).label} '
            '(${severityLabel(zone.severity)})'
            '${distance == null ? '' : ' a ${distanceLabel(distance)} de você'}.';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(
                zone == null ? Icons.place_outlined : incidentCategoryVisual(zone.category).icon,
                color: zone == null ? theme.colorScheme.primary : incidentCategoryVisual(zone.category).color,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Isso ainda está aqui?', style: theme.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            Text('Você entrou na área de uma ocorrência. $details'),
            const SizedBox(height: 4),
            Text(
              'Sua resposta ajuda a comunidade a manter o mapa correto.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, confirmVote),
              icon: const Icon(Icons.check),
              label: const Text('Sim, ainda está aqui'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, rejectVote),
              icon: const Icon(Icons.close),
              label: const Text('Não está mais'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Agora não'),
            ),
          ],
        ),
      ),
    );
  }
}
