import '../../incident/domain/incident_impact.dart';

enum TravelMode { foot, car }

extension TravelModeX on TravelMode {
  String get label => this == TravelMode.foot ? 'A pé' : 'Carro';
}

class RouteIncident {
  const RouteIncident({
    required this.id,
    required this.category,
    required this.severity,
    required this.distanceMeters,
    required this.latitude,
    required this.longitude,
    required this.impactRadiusMeters,
  });

  final String id;
  final String category;
  final String severity;
  final double distanceMeters;
  final double latitude;
  final double longitude;
  final int impactRadiusMeters;

  bool get obstructive => obstructiveIncidentCategories.contains(category);

  factory RouteIncident.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String;
    final severity = json['severity'] as String? ?? 'moderado';
    return RouteIncident(
      id: json['id'] as String,
      category: category,
      severity: severity,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      impactRadiusMeters: (json['impactRadiusM'] as num?)?.toInt() ??
          incidentImpactRadiusMeters(category, severity),
    );
  }
}

/// Rota candidata com a avaliação de risco feita no servidor (PostGIS).
class RouteOption {
  const RouteOption({
    required this.id,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.riskScore = 0,
    this.blocked = false,
    this.recommended = false,
    this.incidents = const [],
  });

  final String id;

  /// Pares [latitude, longitude].
  final List<List<double>> points;
  final double distanceMeters;
  final double durationSeconds;
  final int riskScore;
  final bool blocked;
  final bool recommended;
  final List<RouteIncident> incidents;

  RouteOption withAssessment(Map<String, dynamic> json) => RouteOption(
    id: id,
    points: points,
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    riskScore: (json['riskScore'] as num?)?.toInt() ?? 0,
    blocked: json['blocked'] as bool? ?? false,
    recommended: json['recommended'] as bool? ?? false,
    incidents: [
      for (final item in (json['incidents'] as List<dynamic>? ?? const []))
        if (item is Map<String, dynamic>) RouteIncident.fromJson(item),
    ],
  );

  String get summary {
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    final minutes = (durationSeconds / 60).round();
    final risk = incidents.isEmpty
        ? 'sem ocorrências no caminho'
        : '${incidents.length} ${incidents.length == 1 ? 'ocorrência' : 'ocorrências'} no caminho';
    return '$km km · $minutes min · $risk';
  }
}

/// Reduz a rota a no máximo [maxPoints] pontos, preservando início e fim.
List<List<double>> simplifyRoute(List<List<double>> points, int maxPoints) {
  if (points.length <= maxPoints || maxPoints < 2) return points;
  final step = (points.length - 1) / (maxPoints - 1);
  return [
    for (var i = 0; i < maxPoints - 1; i++) points[(i * step).round()],
    points.last,
  ];
}
