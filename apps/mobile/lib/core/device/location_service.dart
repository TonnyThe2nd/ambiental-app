import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:geolocator/geolocator.dart';

class Location {
  const Location(this.latitude, this.longitude);
  final double latitude, longitude;
}

/// Nível de acesso à localização. Alertas com o app fechado exigem [always].
enum LocationAccess { serviceDisabled, denied, whileInUse, always }

extension LocationAccessX on LocationAccess {
  bool get granted => this == LocationAccess.whileInUse || this == LocationAccess.always;
}

abstract class LocationService {
  Future<Location> current({bool background = false});

  /// Situação atual, sem abrir diálogos.
  Future<LocationAccess> access() async => LocationAccess.whileInUse;

  /// Pede acesso. Com [background], pede também "Permitir o tempo todo"; no Android 11+
  /// o sistema só concede isso pela tela de configurações do app.
  Future<LocationAccess> requestAccess({bool background = false}) => access();

  Future<bool> openSettings() async => false;
}

class GeolocatorLocationService extends LocationService {
  @override
  Future<Location> current({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Ative o serviço de localização.');
    }
    var permission = await Geolocator.checkPermission();
    // Em segundo plano não há tela para mostrar o pedido de permissão: antes o app
    // tentava pedir aqui e a checagem falhava em silêncio.
    if (!background && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      throw StateError('Permissão de localização necessária.');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: background ? LocationAccuracy.medium : LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      ),
    );
    return Location(p.latitude, p.longitude);
  }

  @override
  Future<LocationAccess> access() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceDisabled;
    return _fromPermission(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> requestAccess({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Segundo pedido: com a permissão "durante o uso" já concedida, o geolocator pede
    // ACCESS_BACKGROUND_LOCATION (Android 10) ou leva às configurações (Android 11+).
    if (background && permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    return _fromPermission(permission);
  }

  @override
  Future<bool> openSettings() => Geolocator.openAppSettings();

  static LocationAccess _fromPermission(LocationPermission permission) => switch (permission) {
    LocationPermission.always => LocationAccess.always,
    LocationPermission.whileInUse => LocationAccess.whileInUse,
    _ => LocationAccess.denied,
  };
}

/// Fluxo contínuo de posições, inclusive com o app em segundo plano.
abstract class LocationTracker {
  Stream<Location> watch();
}

class GeolocatorLocationTracker implements LocationTracker {
  GeolocatorLocationTracker({this.distanceFilter = 25});

  /// Deslocamento mínimo (metros) entre posições entregues.
  final int distanceFilter;

  @override
  Stream<Location> watch() {
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Serviço em primeiro plano: mantém o GPS ativo com o app minimizado e mostra
      // uma notificação fixa, exigida pelo Android para localização em segundo plano.
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 20),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Monitorando áreas de risco',
          notificationText:
              'Você será avisado ao entrar em uma área com ocorrência ambiental.',
          notificationChannelName: 'Monitoramento de áreas de risco',
          enableWakeLock: true,
          setOngoing: true,
          color: Color(0xFF176B5B),
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilter);
    }
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((p) => Location(p.latitude, p.longitude));
  }
}
