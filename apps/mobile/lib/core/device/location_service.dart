import 'package:geolocator/geolocator.dart';

class Location {
  const Location(this.latitude, this.longitude);
  final double latitude, longitude;
}

abstract class LocationService {
  Future<Location> current({bool background = false});
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<Location> current({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Ative o serviço de localização.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (background && permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Permissão de localização necessária.');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return Location(p.latitude, p.longitude);
  }
}
