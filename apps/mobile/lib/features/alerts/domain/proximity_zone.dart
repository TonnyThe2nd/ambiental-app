import 'dart:math' as math;

import '../../incident/domain/incident_impact.dart';

/// Área de uma ocorrência ativa usada no geofencing local.
class ProximityZone {
  const ProximityZone({
    required this.incidentId,
    required this.category,
    required this.severity,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String incidentId;
  final String category;
  final String severity;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  factory ProximityZone.fromIncidentJson(Map<String, dynamic> json) {
    final category = json['category'] as String;
    final severity = json['severity'] as String? ?? 'moderado';
    return ProximityZone(
      incidentId: json['id'] as String,
      category: category,
      severity: severity,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['impactRadiusM'] as num?)?.toInt() ??
          incidentImpactRadiusMeters(category, severity),
    );
  }

  factory ProximityZone.fromMap(Map<dynamic, dynamic> map) => ProximityZone(
    incidentId: map['incidentId'] as String,
    category: map['category'] as String,
    severity: map['severity'] as String,
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
    radiusMeters: (map['radiusMeters'] as num).toInt(),
  );

  Map<String, Object> toMap() => {
    'incidentId': incidentId,
    'category': category,
    'severity': severity,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
  };
}

/// Estado de cada área: se o usuário estava dentro e quando foi avisado.
class ZoneState {
  const ZoneState({required this.inside, this.notifiedAt});
  final bool inside;
  final DateTime? notifiedAt;

  factory ZoneState.fromMap(Map<dynamic, dynamic> map) => ZoneState(
    inside: map['inside'] as bool? ?? false,
    notifiedAt: map['notifiedAt'] == null
        ? null
        : DateTime.tryParse(map['notifiedAt'] as String),
  );

  Map<String, Object?> toMap() => {
    'inside': inside,
    'notifiedAt': notifiedAt?.toUtc().toIso8601String(),
  };
}

/// Entrada detectada numa área de ocorrência.
class ZoneEntry {
  const ZoneEntry(this.zone, this.distanceMeters);
  final ProximityZone zone;
  final double distanceMeters;
}

class ProximityEvaluation {
  const ProximityEvaluation(this.entries, this.states);
  final List<ZoneEntry> entries;
  final Map<String, ZoneState> states;
}

/// Tempo mínimo para avisar de novo sobre a mesma ocorrência depois de sair e voltar.
const proximityRenotifyAfter = Duration(hours: 6);

/// Margem para sair da área (evita avisos repetidos com o GPS oscilando na borda).
const proximityExitHysteresisMeters = 50.0;

/// Avalia entradas em áreas: só avisa na transição fora → dentro.
ProximityEvaluation evaluateProximity({
  required double latitude,
  required double longitude,
  required List<ProximityZone> zones,
  required Map<String, ZoneState> previous,
  required DateTime now,
}) {
  final entries = <ZoneEntry>[];
  final states = <String, ZoneState>{};
  for (final zone in zones) {
    final distance = distanceMeters(latitude, longitude, zone.latitude, zone.longitude);
    final before = previous[zone.incidentId];
    final wasInside = before?.inside ?? false;
    final inside = wasInside
        ? distance <= zone.radiusMeters + proximityExitHysteresisMeters
        : distance <= zone.radiusMeters;
    var notifiedAt = before?.notifiedAt;
    if (inside && !wasInside &&
        (notifiedAt == null || now.difference(notifiedAt) >= proximityRenotifyAfter)) {
      entries.add(ZoneEntry(zone, distance));
      notifiedAt = now;
    }
    states[zone.incidentId] = ZoneState(inside: inside, notifiedAt: notifiedAt);
  }
  // Mantém o histórico de aviso de áreas que saíram do cache (evita repetir o aviso).
  for (final entry in previous.entries) {
    final notified = entry.value.notifiedAt;
    if (!states.containsKey(entry.key) && notified != null &&
        now.difference(notified) < proximityRenotifyAfter) {
      states[entry.key] = ZoneState(inside: false, notifiedAt: notified);
    }
  }
  const rank = {'critico': 3, 'moderado': 2, 'leve': 1};
  entries.sort((a, b) => (rank[b.zone.severity] ?? 0).compareTo(rank[a.zone.severity] ?? 0));
  return ProximityEvaluation(entries, states);
}

double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final deltaPhi = (lat2 - lat1) * math.pi / 180;
  final deltaLambda = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
      math.cos(phi1) * math.cos(phi2) *
          math.sin(deltaLambda / 2) * math.sin(deltaLambda / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
