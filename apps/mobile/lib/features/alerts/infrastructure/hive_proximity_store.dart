import 'package:hive_flutter/hive_flutter.dart';

import '../domain/proximity_zone.dart';

/// Persistência do geofencing local (áreas em cache, estado de entrada e preferência).
///
/// Fica no Hive para que a tarefa em segundo plano (outro isolate, app fechado)
/// avalie as áreas mesmo sem rede e sem repetir avisos já dados.
class HiveProximityStore {
  HiveProximityStore(this._box);

  static const boxName = 'proximity';
  final Box<dynamic> _box;

  static Future<HiveProximityStore> open() async =>
      HiveProximityStore(await Hive.openBox<dynamic>(boxName));

  /// Último sinal do rastreamento contínuo (app vivo). A tarefa do WorkManager não
  /// roda em paralelo com ele, para não haver dois isolates gravando o mesmo box.
  DateTime? get trackingHeartbeat =>
      DateTime.tryParse(_box.get('trackingHeartbeat') as String? ?? '');

  Future<void> markTrackingHeartbeat() =>
      _box.put('trackingHeartbeat', DateTime.now().toUtc().toIso8601String());

  bool get enabled => _box.get('enabled', defaultValue: true) as bool;
  Future<void> setEnabled(bool value) => _box.put('enabled', value);

  List<ProximityZone> get zones => ((_box.get('zones') as List<dynamic>?) ?? const [])
      .whereType<Map<dynamic, dynamic>>()
      .map(ProximityZone.fromMap)
      .toList();

  DateTime? get zonesFetchedAt {
    final value = _box.get('zonesFetchedAt') as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  ({double latitude, double longitude})? get zonesCenter {
    final value = _box.get('zonesCenter') as Map<dynamic, dynamic>?;
    if (value == null) return null;
    return (
      latitude: (value['latitude'] as num).toDouble(),
      longitude: (value['longitude'] as num).toDouble(),
    );
  }

  Future<void> saveZones(List<ProximityZone> zones, double latitude, double longitude) async {
    await _box.putAll({
      'zones': zones.map((zone) => zone.toMap()).toList(),
      'zonesFetchedAt': DateTime.now().toUtc().toIso8601String(),
      'zonesCenter': {'latitude': latitude, 'longitude': longitude},
    });
  }

  Map<String, ZoneState> get states {
    final raw = (_box.get('states') as Map<dynamic, dynamic>?) ?? const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is Map) entry.key as String: ZoneState.fromMap(entry.value as Map),
    };
  }

  Future<void> saveStates(Map<String, ZoneState> states) => _box.put('states', {
    for (final entry in states.entries) entry.key: entry.value.toMap(),
  });

  /// Rota ativa (roteamento preventivo), em pares [latitude, longitude].
  List<List<double>>? get activeRoute {
    final raw = _box.get('route') as List<dynamic>?;
    final expires = DateTime.tryParse(_box.get('routeExpiresAt') as String? ?? '');
    if (raw == null || expires == null || expires.isBefore(DateTime.now().toUtc())) return null;
    return raw
        .whereType<List<dynamic>>()
        .map((point) => [(point[0] as num).toDouble(), (point[1] as num).toDouble()])
        .toList();
  }

  Future<void> saveRoute(List<List<double>>? route, Duration ttl) async {
    if (route == null || route.isEmpty) {
      await _box.deleteAll(['route', 'routeExpiresAt']);
      return;
    }
    await _box.putAll({
      'route': route,
      'routeExpiresAt': DateTime.now().toUtc().add(ttl).toIso8601String(),
    });
  }
}
