import '../../domain/entities/incident.dart';
import '../../domain/repositories/incident_repository.dart';
import '../datasources/hive_incident_local_data_source.dart';
import '../../../../services/remote/http_incident_remote_data_source.dart';

class IncidentRepositoryImpl implements IncidentRepository {
  IncidentRepositoryImpl({required this.local, this.remote});
  final HiveIncidentLocalDataSource local;
  final HttpIncidentRemoteDataSource? remote;
  @override
  Future<void> save(Incident i) => local.put(i);
  @override
  Future<List<Incident>> getAll() async => local.all();
  @override
  Future<List<Incident>> pending() async =>
      local.all().where((i) => i.status != IncidentStatus.synced).toList();
  @override
  Future<void> markSynced(Incident i, String imageUrl) => local.put(
    i.copyWith(
      status: IncidentStatus.synced,
      imageUrl: imageUrl,
      lastError: '',
    ),
  );
  @override
  Future<void> markFailed(Incident i, Object error) => local.put(
    i.copyWith(
      status: IncidentStatus.failed,
      attempts: i.attempts + 1,
      lastError: error.toString(),
    ),
  );
  @override
  Future<Incident> upload(Incident i) {
    final value = remote;
    if (value == null) {
      throw StateError('API PostgreSQL não configurada. Defina API_BASE_URL.');
    }
    return value.upload(i);
  }

  @override
  Stream<List<Incident>> watchRemote() =>
      remote?.watch() ?? Stream.value(const []);
}
