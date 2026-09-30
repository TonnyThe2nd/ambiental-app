import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/device/location_service.dart';
import '../../auth/application/auth_service.dart';
import '../domain/notification_gateway.dart';
import '../domain/proximity_zone.dart';
import '../infrastructure/hive_proximity_store.dart';

typedef ProximityNotifier = Future<void> Function(ZoneEntry entry);

/// Alerta de proximidade: avisa quando o usuário entra na área de uma ocorrência.
///
/// Funciona em três situações:
/// * app aberto ou minimizado — rastreamento contínuo (serviço em primeiro plano no
///   Android) avaliando as áreas localmente a cada deslocamento;
/// * app fechado — tarefa periódica do WorkManager ([backgroundCheck]);
/// * sem rede — as áreas ficam em cache no Hive e a avaliação é local.
///
/// A posição também vai ao servidor (``localGeofencing: true``), que registra o
/// histórico e devolve entradas que o cache local ainda não conhecia; o push do
/// servidor é suprimido para não duplicar a notificação.
class ProximityMonitor extends ChangeNotifier {
  ProximityMonitor({
    required AuthService auth,
    required LocationService location,
    required LocationTracker tracker,
    required NotificationGateway gateway,
    required HiveProximityStore store,
    required ProximityNotifier notifier,
    DateTime Function()? clock,
  }) : _auth = auth,
       _location = location,
       _tracker = tracker,
       _gateway = gateway,
       _store = store,
       _notifier = notifier,
       _clock = clock ?? DateTime.now;

  final AuthService _auth;
  final LocationService _location;
  final LocationTracker _tracker;
  final NotificationGateway _gateway;
  final HiveProximityStore _store;
  final ProximityNotifier _notifier;
  final DateTime Function() _clock;

  /// Raio das áreas baixadas para o cache local.
  static const zonesRadiusMeters = 20000;

  /// Cache de áreas vale 10 minutos ou até o usuário se afastar 5 km do centro.
  static const zonesMaxAge = Duration(minutes: 10);
  static const zonesMaxDriftMeters = 5000.0;

  /// Envio de posição ao servidor: a cada 150 m ou 2 minutos.
  static const reportMinDistanceMeters = 150.0;
  static const reportMinInterval = Duration(minutes: 2);

  StreamSubscription<Location>? _subscription;
  Location? _lastPosition;
  Location? _lastReported;
  DateTime? _lastReportedAt;
  bool _checking = false;
  DateTime? _lastHeartbeat;
  LocationAccess _access = LocationAccess.denied;
  List<ZoneEntry> _recentEntries = const [];

  bool get enabled => _store.enabled;
  bool get tracking => _subscription != null;
  LocationAccess get access => _access;
  Location? get lastPosition => _lastPosition;
  List<ProximityZone> get zones => _store.zones;
  List<ZoneEntry> get recentEntries => _recentEntries;
  List<List<double>>? get activeRoute => _store.activeRoute;

  /// Começa o rastreamento contínuo, se habilitado e com permissão.
  Future<void> start() async {
    if (!_auth.isAuthenticated || !enabled || _subscription != null) return;
    _access = await _location.access();
    if (!_access.granted) {
      notifyListeners();
      return;
    }
    _subscription = _tracker.watch().listen(
      (position) => unawaited(_onPosition(position)),
      onError: (Object error) {
        debugPrint('Rastreamento de proximidade interrompido: $error');
        unawaited(stop());
      },
    );
    notifyListeners();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await _store.setEnabled(value);
    if (value) {
      await start();
    } else {
      await stop();
    }
    notifyListeners();
  }

  /// Pede as permissões necessárias (notificação é pedida pelo chamador).
  Future<LocationAccess> requestAccess({bool background = true}) async {
    _access = await _location.requestAccess(background: background);
    notifyListeners();
    if (_access.granted && enabled) await start();
    return _access;
  }

  Future<bool> openSettings() => _location.openSettings();

  Future<void> refreshAccess() async {
    _access = await _location.access();
    notifyListeners();
  }

  /// Checagem imediata (app aberto): posição atual + envio ao servidor.
  Future<List<ZoneEntry>> checkNow({String? fcmToken}) async {
    try {
      final position = await _location.current();
      return await checkPosition(position, fcmToken: fcmToken, forceReport: true);
    } catch (error) {
      debugPrint('Checagem de proximidade adiada: $error');
      return const [];
    }
  }

  /// Chamado pelo WorkManager com o app fechado.
  Future<List<ZoneEntry>> backgroundCheck() async {
    if (!_auth.isAuthenticated || !enabled) return const [];
    final heartbeat = _store.trackingHeartbeat;
    if (heartbeat != null && _clock().toUtc().difference(heartbeat) < const Duration(minutes: 3)) {
      return const []; // o rastreamento contínuo do app já está cuidando disso
    }
    try {
      final position = await _location.current(background: true);
      return await checkPosition(position, forceReport: true);
    } catch (error) {
      debugPrint('Checagem de proximidade em segundo plano falhou: $error');
      return const [];
    }
  }

  Future<void> _onPosition(Location position) async {
    final now = _clock();
    if (_lastHeartbeat == null || now.difference(_lastHeartbeat!) >= const Duration(minutes: 1)) {
      _lastHeartbeat = now;
      unawaited(_store.markTrackingHeartbeat());
    }
    try {
      await checkPosition(position);
    } catch (error) {
      debugPrint('Falha ao avaliar áreas de risco: $error');
    }
  }

  /// Avalia a posição contra as áreas em cache, consulta o servidor e notifica.
  Future<List<ZoneEntry>> checkPosition(
    Location position, {
    String? fcmToken,
    bool forceReport = false,
  }) async {
    if (_checking && !forceReport) return const [];
    _checking = true;
    try {
      _lastPosition = position;
      await _refreshZonesIfNeeded(position);
      final now = _clock().toUtc();
      final evaluation = evaluateProximity(
        latitude: position.latitude,
        longitude: position.longitude,
        zones: _store.zones,
        previous: _store.states,
        now: now,
      );
      final states = Map<String, ZoneState>.of(evaluation.states);
      final entries = [...evaluation.entries];

      final report = await _report(position, fcmToken: fcmToken, force: forceReport);
      for (final alert in report?.alerts ?? const <ServerProximityAlert>[]) {
        // Entrada detectada só no servidor (ocorrência nova, ainda fora do cache).
        final zone = alert.zone;
        final known = states[alert.incidentId];
        if (zone == null || known?.notifiedAt != null) continue;
        final distance = distanceMeters(
          position.latitude, position.longitude, zone.latitude, zone.longitude);
        entries.add(ZoneEntry(zone, distance));
        states[alert.incidentId] = ZoneState(inside: true, notifiedAt: now);
      }

      await _store.saveStates(states);
      for (final entry in entries) {
        try {
          await _notifier(entry);
        } catch (error) {
          debugPrint('Notificação de área não exibida: $error');
        }
      }
      if (entries.isNotEmpty) {
        _recentEntries = entries;
      }
      notifyListeners();
      return entries;
    } finally {
      _checking = false;
    }
  }

  Future<void> _refreshZonesIfNeeded(Location position) async {
    final fetchedAt = _store.zonesFetchedAt;
    final center = _store.zonesCenter;
    final stale = fetchedAt == null ||
        _clock().toUtc().difference(fetchedAt) > zonesMaxAge ||
        center == null ||
        distanceMeters(position.latitude, position.longitude, center.latitude, center.longitude) >
            zonesMaxDriftMeters;
    if (!stale) return;
    try {
      final zones = await _gateway.nearbyZones(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: zonesRadiusMeters,
      );
      if (zones != null) await _store.saveZones(zones, position.latitude, position.longitude);
    } catch (error) {
      // Sem rede: segue com as áreas já em cache.
      debugPrint('Áreas de risco não atualizadas: $error');
    }
  }

  /// Atualiza as áreas imediatamente (ex.: evento de tempo real ou nova ocorrência).
  Future<void> invalidateZones() async {
    final position = _lastPosition;
    if (position == null) return;
    try {
      final zones = await _gateway.nearbyZones(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: zonesRadiusMeters,
      );
      if (zones != null) await _store.saveZones(zones, position.latitude, position.longitude);
    } catch (_) {
      // Mantém o cache atual.
    }
  }

  Future<PositionReport?> _report(
    Location position, {
    String? fcmToken,
    bool force = false,
    List<List<double>>? route,
  }) async {
    final last = _lastReported;
    final lastAt = _lastReportedAt;
    final now = _clock();
    final due = force ||
        fcmToken != null ||
        route != null ||
        last == null ||
        lastAt == null ||
        now.difference(lastAt) >= reportMinInterval ||
        distanceMeters(last.latitude, last.longitude, position.latitude, position.longitude) >=
            reportMinDistanceMeters;
    if (!due) return null;
    try {
      final report = await _gateway.reportPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        fcmToken: fcmToken,
        localGeofencing: true,
        route: route,
      );
      if (report != null) {
        _lastReported = position;
        _lastReportedAt = now;
      }
      return report;
    } catch (error) {
      debugPrint('Posição não enviada ao servidor: $error');
      return null;
    }
  }

  /// Roteamento preventivo: registra a rota escolhida no servidor, que passa a
  /// alertar sobre novas ocorrências no corredor. ``null`` encerra a rota.
  Future<bool> setRoute(List<List<double>>? route, {Duration ttl = const Duration(hours: 2)}) async {
    await _store.saveRoute(route, ttl);
    final position = _lastPosition ?? await _safeCurrent();
    if (position == null) return false;
    final report = await _report(position, force: true, route: route ?? const <List<double>>[]);
    notifyListeners();
    return report != null;
  }

  Future<Location?> _safeCurrent() async {
    try {
      return await _location.current();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
