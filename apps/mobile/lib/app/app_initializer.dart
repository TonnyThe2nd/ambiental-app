import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../features/incident/data/datasources/hive_incident_local_data_source.dart';
import '../features/incident/data/repositories/incident_repository_impl.dart';
import '../features/incident/domain/repositories/incident_repository.dart';
import '../services/camera/camera_service.dart';
import '../services/auth/auth_service.dart';
import '../services/location/location_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/remote/http_incident_remote_data_source.dart';
import '../services/sync/sync_service.dart';
import '../services/sync/background_sync.dart';

class AppDependencies {
  AppDependencies({
    required this.repository,
    required this.camera,
    required this.location,
    required this.sync,
    required this.auth,
    required this.notifications,
  });
  final IncidentRepository repository;
  final CameraService camera;
  final LocationService location;
  final SyncService sync;
  final AuthService auth;
  final NotificationService notifications;
}

class AppInitializer {
  static Future<AppDependencies> initialize({
    bool registerBackground = true,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    final local = HiveIncidentLocalDataSource(
      await Hive.openBox<Map<dynamic, dynamic>>('incidents'),
    );
    final auth = AuthService();
    await auth.restoreSession();
    final notifications = NotificationService(auth);
    final location = GeolocatorLocationService();
    final remote = HttpIncidentRemoteDataSource(auth);
    final repository = IncidentRepositoryImpl(local: local, remote: remote);
    final dependencies = AppDependencies(
      repository: repository,
      camera: ImagePickerCameraService(),
      location: location,
      sync: SyncService(repository, auth),
      auth: auth,
      notifications: notifications,
    );
    if (registerBackground) {
      await BackgroundSync.initialize();
      await BackgroundSync.schedule(attempts: 0);
      unawaited(notifications.registerPushToken(location));
    }
    return dependencies;
  }
}
