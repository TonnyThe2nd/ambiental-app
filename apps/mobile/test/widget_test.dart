// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/incident/domain/entities/incident.dart';
import 'package:urbaneye_mobile/features/incident/domain/repositories/incident_repository.dart';
import 'package:urbaneye_mobile/features/incident/domain/usecases/create_incident_use_case.dart';

void main() {
  test('cria ocorrência pendente e persiste antes da sincronização', () async {
    final repository = _MemoryRepository();
    final incident = await CreateIncidentUseCase(repository)(
      imagePath: '/tmp/photo.jpg',
      category: 'alagamento',
      latitude: -23.5,
      longitude: -46.6,
      reportedById: 'user-1',
      reportedByName: 'Usuário Teste',
    );
    expect(incident.status, IncidentStatus.pending);
    expect(repository.saved.single.id, incident.id);
  });
  test('rejeita coordenadas inválidas', () async {
    expect(
      () => CreateIncidentUseCase(_MemoryRepository())(
        imagePath: '/tmp/photo.jpg',
        category: 'lixo',
        latitude: 91,
        longitude: 0,
        reportedById: 'user-1',
        reportedByName: 'Usuário Teste',
      ),
      throwsArgumentError,
    );
  });
}

class _MemoryRepository implements IncidentRepository {
  final saved = <Incident>[];
  @override
  Future<void> save(Incident incident) async => saved.add(incident);
  @override
  Future<List<Incident>> getAll() async => saved;
  @override
  Future<List<Incident>> pending() async => saved;
  @override
  Future<void> markFailed(Incident incident, Object error) async {}
  @override
  Future<void> markSynced(Incident incident, String imageUrl) async {}
  @override
  Future<Incident> upload(Incident incident) async => incident;
  @override
  Stream<List<Incident>> watchRemote() => Stream.value(const []);
}
