import 'package:uuid/uuid.dart';

import '../entities/incident.dart';
import '../repositories/incident_repository.dart';

class CreateIncidentUseCase {
  CreateIncidentUseCase(this._repository);
  final IncidentRepository _repository;
  Future<Incident> call({
    required String imagePath,
    required String category,
    required double latitude,
    required double longitude,
  }) async {
    if (imagePath.isEmpty || category.trim().isEmpty) {
      throw ArgumentError('Foto e categoria são obrigatórias.');
    }
    if (latitude.abs() > 90 || longitude.abs() > 180) {
      throw ArgumentError('Localização inválida.');
    }
    final incident = Incident(
      id: const Uuid().v4(),
      imagePath: imagePath,
      category: category.trim(),
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now().toUtc(),
    );
    await _repository.save(incident);
    return incident;
  }
}
