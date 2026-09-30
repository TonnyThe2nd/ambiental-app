import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:urbaneye_mobile/core/device/location_service.dart';
import 'package:urbaneye_mobile/features/alerts/application/proximity_monitor.dart';
import 'package:urbaneye_mobile/features/alerts/domain/app_notification.dart';
import 'package:urbaneye_mobile/features/alerts/domain/notification_gateway.dart';
import 'package:urbaneye_mobile/features/alerts/domain/proximity_zone.dart';
import 'package:urbaneye_mobile/features/alerts/infrastructure/hive_proximity_store.dart';
import 'package:urbaneye_mobile/features/auth/application/auth_service.dart';
import 'package:urbaneye_mobile/features/auth/domain/entities/auth_user.dart';
import 'package:urbaneye_mobile/features/auth/domain/repositories/auth_gateway.dart';
import 'package:urbaneye_mobile/features/incident/domain/incident_impact.dart';

const _flood = ProximityZone(
  incidentId: 'flood-1',
  category: 'alagamento',
  severity: 'critico',
  latitude: -23.5505,
  longitude: -46.6333,
  radiusMeters: 600,
);

void main() {
  group('evaluateProximity', () {
    final now = DateTime.utc(2026, 9, 30, 12);

    test('avisa só na transição de fora para dentro', () {
      final outside = evaluateProximity(
        latitude: -23.58, longitude: -46.6333, zones: [_flood], previous: const {}, now: now);
      expect(outside.entries, isEmpty);

      final entering = evaluateProximity(
        latitude: -23.5510, longitude: -46.6333, zones: [_flood], previous: outside.states, now: now);
      expect(entering.entries.single.zone.incidentId, 'flood-1');

      final staying = evaluateProximity(
        latitude: -23.5512, longitude: -46.6333, zones: [_flood], previous: entering.states,
        now: now.add(const Duration(minutes: 1)));
      expect(staying.entries, isEmpty);
    });

    test('não repete o aviso ao sair e voltar logo em seguida', () {
      var states = evaluateProximity(
        latitude: -23.5505, longitude: -46.6333, zones: [_flood], previous: const {}, now: now).states;
      states = evaluateProximity(
        latitude: -23.60, longitude: -46.6333, zones: [_flood], previous: states,
        now: now.add(const Duration(minutes: 5))).states;
      final back = evaluateProximity(
        latitude: -23.5505, longitude: -46.6333, zones: [_flood], previous: states,
        now: now.add(const Duration(minutes: 10)));
      expect(back.entries, isEmpty);

      final later = evaluateProximity(
        latitude: -23.60, longitude: -46.6333, zones: [_flood], previous: back.states,
        now: now.add(const Duration(hours: 7)));
      final again = evaluateProximity(
        latitude: -23.5505, longitude: -46.6333, zones: [_flood], previous: later.states,
        now: now.add(const Duration(hours: 7, minutes: 1)));
      expect(again.entries, hasLength(1));
    });

    test('área de impacto espelha o backend', () {
      expect(incidentImpactRadiusMeters('alagamento', 'critico'), 600);
      expect(incidentImpactRadiusMeters('poluicao', 'leve'), 1130);
      expect(incidentImpactRadiusMeters('desconhecida', 'moderado'), 250);
    });
  });

  group('ProximityMonitor', () {
    late Directory directory;
    late HiveProximityStore store;
    late _FakeGateway gateway;
    late List<ZoneEntry> shown;
    late ProximityMonitor monitor;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('proximity_test');
      Hive.init(directory.path);
      store = HiveProximityStore(await Hive.openBox<dynamic>(HiveProximityStore.boxName));
      gateway = _FakeGateway();
      shown = [];
      monitor = ProximityMonitor(
        auth: await _authenticated(),
        location: _FakeLocation(),
        tracker: _FakeTracker(),
        gateway: gateway,
        store: store,
        notifier: (entry) async => shown.add(entry),
        clock: () => DateTime.utc(2026, 9, 30, 12),
      );
    });

    tearDown(() async {
      await Hive.close();
      await directory.delete(recursive: true);
    });

    test('baixa as áreas, avisa ao entrar e pede ao servidor para não duplicar o push', () async {
      gateway.zones = [_flood];
      final entries = await monitor.checkPosition(const Location(-23.5507, -46.6333));
      expect(entries.single.zone.incidentId, 'flood-1');
      expect(shown, hasLength(1));
      expect(gateway.localGeofencingFlags, [true]);

      await monitor.checkPosition(const Location(-23.5508, -46.6333), forceReport: true);
      expect(shown, hasLength(1));
    });

    test('funciona sem rede usando as áreas em cache', () async {
      await store.saveZones([_flood], -23.55, -46.63);
      gateway.offline = true;
      final entries = await monitor.checkPosition(const Location(-23.5506, -46.6333));
      expect(entries, hasLength(1));
    });

    test('mostra entrada detectada só pelo servidor (ocorrência fora do cache)', () async {
      gateway.alerts = const [
        ServerProximityAlert(incidentId: 'fire-9', title: 't', message: 'm', zone: ProximityZone(
          incidentId: 'fire-9', category: 'queimada', severity: 'critico',
          latitude: -23.5505, longitude: -46.6333, radiusMeters: 3000)),
      ];
      final entries = await monitor.checkPosition(const Location(-23.5505, -46.6333));
      expect(entries.map((e) => e.zone.incidentId), ['fire-9']);
    });
  });
}

Future<AuthService> _authenticated() async {
  final auth = AuthService(_FakeAuthGateway(), _MemorySessionStore());
  await auth.restoreSession();
  return auth;
}

class _FakeGateway implements NotificationGateway {
  List<ProximityZone> zones = const [];
  List<ServerProximityAlert> alerts = const [];
  bool offline = false;
  final localGeofencingFlags = <bool>[];

  @override
  Future<List<ProximityZone>?> nearbyZones({
    required double latitude, required double longitude, int radiusMeters = 20000,
  }) async {
    if (offline) throw const SocketException('offline');
    return zones;
  }

  @override
  Future<PositionReport?> reportPosition({
    required double latitude, required double longitude, String? fcmToken,
    bool localGeofencing = false, List<List<double>>? route,
  }) async {
    if (offline) throw const SocketException('offline');
    localGeofencingFlags.add(localGeofencing);
    return PositionReport(alerts);
  }

  @override
  Future<bool> updatePosition({required double latitude, required double longitude, String? fcmToken}) async => true;

  @override
  Future<List<AppNotification>> list() async => const [];

  @override
  Future<bool> markRead(String id) async => true;
}

class _FakeLocation extends LocationService {
  @override
  Future<Location> current({bool background = false}) async => const Location(-23.5505, -46.6333);

  @override
  Future<LocationAccess> access() async => LocationAccess.always;
}

class _FakeTracker implements LocationTracker {
  @override
  Stream<Location> watch() => const Stream.empty();
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
