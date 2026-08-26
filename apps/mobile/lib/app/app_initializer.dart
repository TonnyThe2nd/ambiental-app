import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../features/incident/data/datasources/hive_incident_local_data_source.dart';
import '../features/incident/data/repositories/incident_repository_impl.dart';
import '../features/incident/domain/repositories/incident_repository.dart';
import '../services/camera/camera_service.dart';
import '../services/firebase/firebase_incident_remote_data_source.dart';
import '../services/location/location_service.dart';
import '../services/sync/sync_service.dart';

class AppDependencies {
  AppDependencies({
    required this.repository,
    required this.camera,
    required this.location,
    required this.sync,
  });
  final IncidentRepository repository;
  final CameraService camera;
  final LocationService location;
  final SyncService sync;
}

class AppInitializer {
  static Future<AppDependencies> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    final local = HiveIncidentLocalDataSource(
      await Hive.openBox<Map<dynamic, dynamic>>('incidents'),
    );
    FirebaseIncidentRemoteDataSource? remote;
    try {
      await Firebase.initializeApp();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      remote = FirebaseIncidentRemoteDataSource();
    } catch (_) {
      // Offline and Firebase setup failures must not prevent local reporting.
    }
    final repository = IncidentRepositoryImpl(local: local, remote: remote);
    return AppDependencies(
      repository: repository,
      camera: ImagePickerCameraService(),
      location: GeolocatorLocationService(),
      sync: SyncService(repository),
    );
  }
}
