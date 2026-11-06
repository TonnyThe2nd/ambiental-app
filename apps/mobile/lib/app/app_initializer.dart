import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
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
import '../features/alerts/application/incident_confirmation.dart';
import '../features/alerts/application/proximity_monitor.dart';
import '../features/alerts/infrastructure/http_incident_confirmation_gateway.dart';
import '../features/alerts/infrastructure/hive_proximity_store.dart';
import '../features/alerts/infrastructure/http_notification_gateway.dart';
import '../features/incident/infrastructure/remote/http_incident_remote_data_source.dart';
import '../features/incident/application/sync_incidents_service.dart';
import '../features/incident/infrastructure/sync/background_sync.dart';
import '../features/map/infrastructure/map_layers_service.dart';
import '../features/routing/infrastructure/route_planner.dart';
import '../features/weather/data/environmental_context_service.dart';

class AppDependencies {
  AppDependencies({
    required this.repository,
    required this.camera,
    required this.location,
    required this.sync,
    required this.auth,
    required this.notifications,
    required this.proximity,
    required this.confirmation,
    required this.mapLayers,
    required this.routePlanner,
  });
  final IncidentRepository repository;
  final CameraService camera;
  final LocationService location;
  final SyncIncidentsService sync;
  final AuthService auth;
  final NotificationService notifications;
  final ProximityMonitor proximity;
  final IncidentConfirmationService confirmation;
  final MapLayersService mapLayers;
  final RoutePlanner routePlanner;
}

class AppInitializer {
  static Future<AppDependencies> initialize({
    bool registerBackground = true,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    try {
      await Firebase.initializeApp();
    } catch (error) {
      // Keep the app usable in local builds without Firebase configuration.
      debugPrint('Firebase não pôde ser inicializado: $error');
    }
    await SystemNotificationService.initialize();
    await Hive.initFlutter();
    final local = HiveIncidentLocalDataSource(
      await Hive.openBox<Map<dynamic, dynamic>>('incidents'),
    );
    await local.purgeSyncedOlderThan(
      DateTime.now().toUtc().subtract(const Duration(days: 30)),
    );
    final auth = AuthService(HttpAuthGateway(), SecureAuthSessionStore());
    await auth.restoreSession();
    final location = GeolocatorLocationService();
    final notificationGateway = HttpNotificationGateway(auth);
    final proximity = ProximityMonitor(
      auth: auth,
      location: location,
      tracker: GeolocatorLocationTracker(),
      gateway: notificationGateway,
      store: await HiveProximityStore.open(),
      // A notificação de entrada pergunta se a ocorrência ainda está no local
      // (exceto ao autor do relato), com botões que votam sem abrir o app.
      notifier: (entry) => SystemNotificationService.showProximity(
        entry,
        askConfirmation: entry.zone.reportedById != auth.currentUser?.id,
      ),
    );
    final confirmation = IncidentConfirmationService(
      auth: auth,
      gateway: HttpIncidentConfirmationGateway(auth),
      entries: proximity.entries,
      zones: () => proximity.zones,
      dismissNotification: SystemNotificationService.dismissProximity,
    );
    final notifications = NotificationService(
      auth,
      location,
      notificationGateway,
      proximity: proximity,
    );
    final remote = HttpIncidentRemoteDataSource(
      auth,
      environment: OpenMeteoEnvironmentalContextProvider(),
    );
    final repository = IncidentRepositoryImpl(local: local, remote: remote);
    final dependencies = AppDependencies(
      repository: repository,
      camera: ImagePickerCameraService(),
      location: location,
      sync: SyncIncidentsService(repository, auth),
      auth: auth,
      notifications: notifications,
      proximity: proximity,
      confirmation: confirmation,
      mapLayers: MapLayersService(auth),
      routePlanner: RoutePlanner(auth),
    );
    if (registerBackground) {
      await BackgroundSync.initialize();
      await BackgroundSync.schedule(attempts: 0);
      await BackgroundSync.scheduleProximityChecks();
      unawaited(notifications.registerPushToken());
    }
    return dependencies;
  }
}
