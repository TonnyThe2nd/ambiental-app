import 'package:flutter_test/flutter_test.dart';
import 'package:urbaneye_mobile/features/incident/domain/entities/incident.dart';
import 'package:urbaneye_mobile/features/incident/infrastructure/remote/http_incident_remote_data_source.dart';

void main() {
  final incident = Incident(
    id: 'a4f8ee03-4b3c-4ca4-bd46-6bb0f0595f21',
    imagePath: '',
    category: 'alagamento',
    latitude: -23.5,
    longitude: -46.6,
    createdAt: DateTime.utc(2026, 1, 1),
    lastError: 'falhou',
    nextAttemptAt: DateTime.utc(2026, 1, 2),
  );

  test('copyWith limpa campos anulaveis quando recebe null', () {
    final cleared = incident.copyWith(lastError: null, nextAttemptAt: null);

    expect(cleared.lastError, isNull);
    expect(cleared.nextAttemptAt, isNull);
  });

  test('a chave de idempotencia e estavel por incidente e unica por UUID', () {
    final sameIncident = incident.copyWith();
    final anotherIncident = Incident(
      id: '8df3d631-3791-4943-a056-c5ea26ee397e',
      imagePath: '',
      category: incident.category,
      latitude: incident.latitude,
      longitude: incident.longitude,
      createdAt: incident.createdAt,
    );

    expect(incidentIdempotencyKey(sameIncident), incidentIdempotencyKey(incident));
    expect(incidentIdempotencyKey(anotherIncident), isNot(incidentIdempotencyKey(incident)));
  });
}
