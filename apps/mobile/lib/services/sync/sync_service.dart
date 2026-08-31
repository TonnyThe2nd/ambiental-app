import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/incident/domain/repositories/incident_repository.dart';
import '../auth/auth_service.dart';
import 'background_sync.dart';

class SyncService {
  SyncService(this._repository, this._auth);
  final IncidentRepository _repository;
  final AuthService _auth;
  Future<int> synchronize() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      await BackgroundSync.schedule(attempts: 0);
      return 0;
    }
    var synced = 0;
    final queue = await _repository.pending();
    queue.sort((a, b) {
      final severity = {'critico': 3, 'moderado': 2, 'leve': 1};
      final aScore = (severity[a.severity] ?? 2) * 100 + a.priorityScore;
      final bScore = (severity[b.severity] ?? 2) * 100 + b.priorityScore;
      return bScore.compareTo(aScore);
    });
    for (final incident in queue) {
      if (incident.reportedById != _auth.currentUser?.id) continue;
      // Em rede móvel, preserva dados/bateria e envia primeiro apenas riscos altos.
      if (connectivity.contains(ConnectivityResult.mobile) &&
          incident.severity != 'critico' && incident.priorityScore < 75) {
        await BackgroundSync.schedule(attempts: incident.attempts);
        continue;
      }
      try {
        final uploaded = await _repository.upload(incident);
        await _repository.markSynced(incident, uploaded.imageUrl ?? '');
        synced++;
      } catch (error) {
        await _repository.markFailed(incident, error);
        await BackgroundSync.schedule(attempts: incident.attempts + 1);
      }
    }
    return synced;
  }
}
