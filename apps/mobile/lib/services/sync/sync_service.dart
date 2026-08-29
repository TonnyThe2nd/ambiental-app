import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/incident/domain/repositories/incident_repository.dart';
import '../auth/auth_service.dart';
import 'background_sync.dart';

class SyncService {
  SyncService(this._repository, this._auth);
  final IncidentRepository _repository;
  final AuthService _auth;
  Future<int> synchronize() async {
    if ((await Connectivity().checkConnectivity()).contains(
      ConnectivityResult.none,
    )) {
      await BackgroundSync.schedule(attempts: 0);
      return 0;
    }
    var synced = 0;
    for (final incident in await _repository.pending()) {
      if (incident.reportedById != _auth.currentUser?.id) continue;
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
