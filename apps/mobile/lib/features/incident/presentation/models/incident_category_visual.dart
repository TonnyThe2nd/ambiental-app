import 'package:flutter/material.dart';

@immutable
class IncidentCategoryVisual {
  const IncidentCategoryVisual({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const incidentCategories = <IncidentCategoryVisual>[
  IncidentCategoryVisual(id: 'alagamento', label: 'Alagamento ou enchente', icon: Icons.flood, color: Color(0xFF1976D2)),
  IncidentCategoryVisual(id: 'queimada', label: 'Incêndio ou queimada', icon: Icons.local_fire_department, color: Color(0xFFE64A19)),
  IncidentCategoryVisual(id: 'poluicao', label: 'Poluição do ar, solo ou água', icon: Icons.factory_outlined, color: Color(0xFF6D4C41)),
  IncidentCategoryVisual(id: 'lixo', label: 'Descarte irregular de lixo', icon: Icons.delete_outline, color: Color(0xFF546E7A)),
  IncidentCategoryVisual(id: 'esgoto', label: 'Esgoto a céu aberto', icon: Icons.water_damage_outlined, color: Color(0xFF5D4037)),
  IncidentCategoryVisual(id: 'desmatamento', label: 'Desmatamento', icon: Icons.forest_outlined, color: Color(0xFF2E7D32)),
  IncidentCategoryVisual(id: 'ruido', label: 'Poluição sonora', icon: Icons.volume_up_outlined, color: Color(0xFF7B1FA2)),
  IncidentCategoryVisual(id: 'erosao', label: 'Erosão ou deslizamento', icon: Icons.landslide_outlined, color: Color(0xFF8D6E63)),
  IncidentCategoryVisual(id: 'arvore_caida', label: 'Árvore caída ou em risco', icon: Icons.park_outlined, color: Color(0xFF388E3C)),
  IncidentCategoryVisual(id: 'animal_morto', label: 'Animal morto em via pública', icon: Icons.pets_outlined, color: Color(0xFF795548)),
  IncidentCategoryVisual(id: 'outro', label: 'Outro problema ambiental', icon: Icons.report_problem_outlined, color: Color(0xFF607D8B)),
];

IncidentCategoryVisual incidentCategoryVisual(String category) {
  final normalized = category == 'incendio' ? 'queimada' : category;
  return incidentCategories.firstWhere(
    (item) => item.id == normalized,
    orElse: () => incidentCategories.last,
  );
}
