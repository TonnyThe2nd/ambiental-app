import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../auth/application/auth_service.dart';
import '../domain/proximity_zone.dart';

/// Votos enviados pela confirmação no local (os mesmos do mapa).
const confirmVote = 'confirmar';
const rejectVote = 'rejeitar';

enum ConfirmationOutcome { recorded, notAllowed, notFound }

abstract interface class IncidentConfirmationGateway {
  /// Voto atual do usuário na ocorrência, ou ``null`` se ainda não votou.
  Future<String?> myVote(String incidentId);

  Future<ConfirmationOutcome> submit(String incidentId, String vote);
}

/// Pedido para o usuário dizer se a ocorrência ainda está no local.
class ConfirmationRequest {
  const ConfirmationRequest({required this.incidentId, this.zone, this.distanceMeters});

  final String incidentId;

  /// Área em cache; pode faltar quando o pedido vem de uma notificação antiga.
  final ProximityZone? zone;
  final double? distanceMeters;
}

/// Confirmação comunitária ao entrar numa área de ocorrência.
///
/// Quando o usuário entra na área com o app na tela, pergunta se a ocorrência
/// ainda está ali. Com o app minimizado ou fechado, a pergunta vai na própria
/// notificação de entrada (botões "Ainda está aqui" / "Não está mais") e o
/// toque na notificação reabre este pedido na tela.
///
/// Não pergunta ao autor do relato, a quem já votou nem duas vezes na mesma
/// sessão.
class IncidentConfirmationService {
  IncidentConfirmationService({
    required this._auth,
    required this._gateway,
    Stream<ZoneEntry>? entries,
    List<ProximityZone> Function()? zones,
    Future<void> Function(String incidentId)? dismissNotification,
    bool Function()? isForeground,
  }) : _zones = zones ?? (() => const []),
       _dismissNotification = dismissNotification,
       _isForeground = isForeground ?? _appIsResumed {
    _entrySubscription = entries?.listen((entry) => unawaited(_onEntry(entry)));
  }

  final AuthService _auth;
  final IncidentConfirmationGateway _gateway;
  final List<ProximityZone> Function() _zones;
  final Future<void> Function(String incidentId)? _dismissNotification;
  final bool Function() _isForeground;
  final _requests = StreamController<ConfirmationRequest>.broadcast();
  final _handled = <String>{};
  final _pending = <String>{};
  StreamSubscription<ZoneEntry>? _entrySubscription;

  Stream<ConfirmationRequest> get requests => _requests.stream;

  static bool _appIsResumed() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool canAsk(ProximityZone? zone) {
    final reporter = zone?.reportedById;
    return reporter == null || reporter != _auth.currentUser?.id;
  }

  Future<void> _onEntry(ZoneEntry entry) async {
    // Fora da tela, a notificação de entrada já traz a pergunta.
    if (!_isForeground()) return;
    await offer(ConfirmationRequest(
      incidentId: entry.zone.incidentId,
      zone: entry.zone,
      distanceMeters: entry.distanceMeters,
    ));
  }

  /// Toque na notificação de entrada: reabre a pergunta na tela.
  Future<void> openFromNotification(String incidentId) async {
    ProximityZone? zone;
    for (final candidate in _zones()) {
      if (candidate.incidentId == incidentId) zone = candidate;
    }
    _handled.remove(incidentId); // o usuário pediu explicitamente para responder
    await offer(ConfirmationRequest(incidentId: incidentId, zone: zone));
  }

  /// Emite o pedido se o usuário ainda não respondeu e pode votar.
  Future<bool> offer(ConfirmationRequest request) async {
    final id = request.incidentId;
    if (!_auth.isAuthenticated || !canAsk(request.zone)) return false;
    if (_handled.contains(id) || !_pending.add(id)) return false;
    try {
      String? vote;
      try {
        vote = await _gateway.myVote(id);
      } catch (error) {
        // Sem rede: pergunta assim mesmo (o voto é idempotente no servidor).
        debugPrint('Voto atual não consultado: $error');
      }
      if (vote != null) {
        _handled.add(id);
        return false;
      }
      if (_requests.isClosed) return false;
      _requests.add(request);
      return true;
    } finally {
      _pending.remove(id);
    }
  }

  /// Resposta do usuário na tela. ``vote == null`` significa "agora não".
  Future<ConfirmationOutcome?> answer(String incidentId, String? vote) async {
    if (vote == null) {
      _handled.add(incidentId);
      return null;
    }
    // Se o envio falhar, a pergunta continua disponível pela notificação.
    final outcome = await _gateway.submit(incidentId, vote);
    _handled.add(incidentId);
    try {
      await _dismissNotification?.call(incidentId);
    } catch (_) {
      // A notificação pode já ter sido removida pelo usuário.
    }
    return outcome;
  }

  Future<void> dispose() async {
    await _entrySubscription?.cancel();
    await _requests.close();
  }
}
