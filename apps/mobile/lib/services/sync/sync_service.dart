import 'package:connectivity_plus/connectivity_plus.dart';

import '../../features/incident/domain/repositories/incident_repository.dart';

class SyncService {
  SyncService(this._repository);
  final IncidentRepository _repository;
  Future<int> synchronize() async {
    if ((await Connectivity().checkConnectivity()).contains(
      ConnectivityResult.none,
    )) {
      return 0;
    }
    var synced = 0;
    for (final incident in await _repository.pending()) {
      try {
        final uploaded = await _repository.upload(incident);
        await _repository.markSynced(incident, uploaded.imageUrl!);
        synced++;
      } catch (error) {
        await _repository.markFailed(incident, error);
      }
    }
    return synced;
  }
}
