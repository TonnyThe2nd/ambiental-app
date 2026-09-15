import '../entities/incident.dart';

abstract class IncidentRepository {
  Future<void> save(Incident incident);
  Future<List<Incident>> getAll();
  Future<List<Incident>> pending();
  Future<void> markSynced(Incident incident, String imageUrl);
  Future<void> markFailed(Incident incident, Object error);
  Future<Incident> upload(Incident incident);
  Stream<List<Incident>> watchRemote({
    double? latitude,
    double? longitude,
    int radiusMeters = 50000,
  });
  Future<void> validate(String incidentId, String vote, {String? comment});
}
