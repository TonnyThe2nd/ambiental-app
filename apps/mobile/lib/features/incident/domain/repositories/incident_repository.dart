import '../entities/incident.dart';

abstract class IncidentRepository {
  Future<void> save(Incident incident);
  Future<List<Incident>> getAll();
  Future<List<Incident>> pending();
  Future<void> markSynced(Incident incident, String imageUrl);
  Future<void> markFailed(Incident incident, Object error);
  Future<Incident> upload(Incident incident);
  Stream<List<Incident>> watchRemote();
}
