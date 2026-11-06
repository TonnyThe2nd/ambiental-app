import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/alerts/application/incident_confirmation.dart';
import 'package:urbaneye_mobile/features/alerts/application/notification_service.dart';
import 'package:urbaneye_mobile/features/alerts/domain/proximity_zone.dart';
import 'package:urbaneye_mobile/features/auth/application/auth_service.dart';
import 'package:urbaneye_mobile/features/auth/domain/entities/auth_user.dart';
import 'package:urbaneye_mobile/features/auth/domain/repositories/auth_gateway.dart';

const _flood = ProximityZone(
  incidentId: 'flood-1',
  category: 'alagamento',
  severity: 'critico',
  latitude: -23.5505,
  longitude: -46.6333,
  radiusMeters: 600,
  reportedById: 'other-user',
);

void main() {
  late _FakeConfirmationGateway gateway;
  late StreamController<ZoneEntry> entries;
  late List<String> dismissed;
  late bool foreground;
  late IncidentConfirmationService service;

  setUp(() async {
    gateway = _FakeConfirmationGateway();
    entries = StreamController<ZoneEntry>();
    dismissed = [];
    foreground = true;
    final auth = AuthService(_FakeAuthGateway(), _MemorySessionStore());
    await auth.restoreSession();
    service = IncidentConfirmationService(
      auth: auth,
      gateway: gateway,
      entries: entries.stream,
      zones: () => const [_flood],
      dismissNotification: (id) async => dismissed.add(id),
      isForeground: () => foreground,
    );
  });

  tearDown(() async {
    await entries.close();
    await service.dispose();
  });

  test('ao entrar na área com o app aberto pergunta se a ocorrência ainda está lá', () async {
    final request = service.requests.first;
    entries.add(const ZoneEntry(_flood, 120));
    final asked = await request.timeout(const Duration(seconds: 1));
    expect(asked.incidentId, 'flood-1');
    expect(asked.distanceMeters, 120);

    expect(await service.answer('flood-1', confirmVote), ConfirmationOutcome.recorded);
    expect(gateway.submitted, [('flood-1', confirmVote)]);
    expect(dismissed, ['flood-1']);
  });

  test('com o app em segundo plano a pergunta fica só na notificação', () async {
    foreground = false;
    final asked = <ConfirmationRequest>[];
    service.requests.listen(asked.add);
    entries.add(const ZoneEntry(_flood, 120));
    await pumpEventQueue();
    expect(asked, isEmpty);
  });

  test('não pergunta ao autor do relato nem a quem já votou', () async {
    const own = ProximityZone(
      incidentId: 'own-1', category: 'lixo', severity: 'leve',
      latitude: 0, longitude: 0, radiusMeters: 100, reportedById: 'user-1');
    expect(await service.offer(const ConfirmationRequest(incidentId: 'own-1', zone: own)), isFalse);

    gateway.votes['flood-1'] = rejectVote;
    expect(await service.offer(const ConfirmationRequest(incidentId: 'flood-1', zone: _flood)), isFalse);
  });

  test('"agora não" não volta a perguntar na sessão, mas o toque na notificação reabre', () async {
    expect(await service.offer(const ConfirmationRequest(incidentId: 'flood-1', zone: _flood)), isTrue);
    await service.answer('flood-1', null);
    expect(gateway.submitted, isEmpty);
    expect(await service.offer(const ConfirmationRequest(incidentId: 'flood-1', zone: _flood)), isFalse);

    final request = service.requests.first;
    await service.openFromNotification('flood-1');
    expect((await request).zone?.category, 'alagamento');
  });

  test('sem rede para consultar o voto, pergunta assim mesmo', () async {
    gateway.failLookup = true;
    expect(await service.offer(const ConfirmationRequest(incidentId: 'flood-1', zone: _flood)), isTrue);
  });

  group('ProximityNotificationAction', () {
    NotificationResponse response(String? payload, {String? actionId}) => NotificationResponse(
      notificationResponseType: actionId == null
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction,
      payload: payload,
      actionId: actionId,
    );

    test('lê a ocorrência e o voto do botão', () {
      final action = ProximityNotificationAction.parse(response('incident:abc', actionId: confirmVote))!;
      expect(action.incidentId, 'abc');
      expect(action.vote, confirmVote);
      expect(ProximityNotificationAction.parse(response('incident:abc'))!.vote, isNull);
    });

    test('ignora notificações que não são de área', () {
      expect(ProximityNotificationAction.parse(response('notification-9')), isNull);
      expect(ProximityNotificationAction.parse(response(null)), isNull);
      expect(ProximityNotificationAction.parse(response('incident:')), isNull);
    });
  });

  test('a área guarda o autor do relato vindo da API e do cache', () {
    final zone = ProximityZone.fromIncidentJson({
      'id': 'x', 'category': 'lixo', 'severity': 'leve', 'latitude': 1, 'longitude': 2,
      'reportedBy': {'id': 'author-7', 'name': 'Ana'},
    });
    expect(zone.reportedById, 'author-7');
    expect(ProximityZone.fromMap(zone.toMap()).reportedById, 'author-7');
  });
}

class _FakeConfirmationGateway implements IncidentConfirmationGateway {
  final votes = <String, String>{};
  final submitted = <(String, String)>[];
  bool failLookup = false;

  @override
  Future<String?> myVote(String incidentId) async {
    if (failLookup) throw StateError('offline');
    return votes[incidentId];
  }

  @override
  Future<ConfirmationOutcome> submit(String incidentId, String vote) async {
    submitted.add((incidentId, vote));
    votes[incidentId] = vote;
    return ConfirmationOutcome.recorded;
  }
}

class _FakeAuthGateway implements AuthGateway {
  @override
  Future<AuthSession> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AuthSession> register({
    required String name, required String email, required String password,
    double? latitude, double? longitude,
  }) => throw UnimplementedError();

  @override
  Future<void> updateLocation(String accessToken, {required double latitude, required double longitude}) async {}

  @override
  Future<void> revoke(String accessToken) async {}

  @override
  Future<void> deleteAccount(String accessToken) async {}
}

class _MemorySessionStore implements AuthSessionStore {
  AuthSession? _session = const AuthSession(
    accessToken: 'token',
    user: AuthUser(id: 'user-1', name: 'Teste', email: 'teste@example.com'),
  );

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
