import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../features/incident/data/datasources/hive_incident_local_data_source.dart';
import '../features/incident/data/repositories/incident_repository_impl.dart';
import '../features/incident/domain/repositories/incident_repository.dart';
import '../features/incident/infrastructure/camera/camera_service.dart';
import '../features/auth/application/auth_service.dart';
import '../features/auth/infrastructure/http_auth_gateway.dart';
import '../features/auth/infrastructure/secure_auth_session_store.dart';
import '../core/device/location_service.dart';
import '../features/alerts/application/notification_service.dart';
import '../features/alerts/infrastructure/http_notification_gateway.dart';
import '../features/incident/infrastructure/remote/http_incident_remote_data_source.dart';
import '../features/incident/application/sync_incidents_service.dart';
import '../features/incident/infrastructure/sync/background_sync.dart';

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
  final SyncIncidentsService sync;
  final AuthService auth;
  final NotificationService notifications;
}

class AppInitializer {
  static Future<AppDependencies> initialize({
    bool registerBackground = true,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await Hive.initFlutter();
    final local = HiveIncidentLocalDataSource(
      await Hive.openBox<Map<dynamic, dynamic>>('incidents'),
    );
    await local.purgeSyncedOlderThan(
      DateTime.now().toUtc().subtract(const Duration(days: 30)),
    );
    final auth = AuthService(
      gateway: HttpAuthGateway(),
      store: SecureAuthSessionStore(),
    );
    await auth.restoreSession();
    final location = GeolocatorLocationService();
    final notifications = NotificationService(
      auth,
      location,
      HttpNotificationGateway(auth),
    );
    final remote = HttpIncidentRemoteDataSource(auth);
    final repository = IncidentRepositoryImpl(local: local, remote: remote);
    final dependencies = AppDependencies(
      repository: repository,
      camera: ImagePickerCameraService(),
      location: location,
      sync: SyncIncidentsService(repository, auth),
      auth: auth,
      notifications: notifications,
    );
    if (registerBackground) {
      await BackgroundSync.initialize();
      await BackgroundSync.schedule(attempts: 0);
      unawaited(notifications.registerPushToken());
    }
    return dependencies;
  }
}
