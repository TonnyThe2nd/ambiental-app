import 'dart:math' as math;

/// Área de impacto de uma ocorrência: raio em que a pessoa está "dentro" do risco.
///
/// Espelha ``backend/api/src/incidents/domain/impact.py``. O servidor já devolve
/// ``impactRadiusM``; esta tabela é o fallback para avaliar a entrada na área mesmo
/// sem rede (geofencing local).
const incidentBaseImpactRadiusMeters = <String, int>{
  'alagamento': 400,
  'poluicao': 1500,
  'queimada': 2000,
  'incendio': 1500,
  'desmatamento': 1000,
  'esgoto': 200,
  'lixo': 150,
  'ruido': 300,
  'erosao': 300,
  'arvore_caida': 100,
  'animal_morto': 100,
  'outro': 250,
};

const _severityFactor = <String, double>{
  'leve': 0.75,
  'moderado': 1.0,
  'critico': 1.5,
};

int incidentImpactRadiusMeters(String category, String severity) {
  final base = incidentBaseImpactRadiusMeters[category.trim().toLowerCase()] ??
      incidentBaseImpactRadiusMeters['outro']!;
  final radius = base * (_severityFactor[severity] ?? 1.0);
  final rounded = (radius / 10 + 0.5).floor() * 10;
  return math.min(5000, math.max(50, rounded));
}

/// Categorias que bloqueiam a passagem (pesam mais no roteamento preventivo).
const obstructiveIncidentCategories = {
  'alagamento',
  'arvore_caida',
  'erosao',
  'queimada',
  'incendio',
};
