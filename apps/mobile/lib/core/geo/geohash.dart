import 'dart:math' as math;

/// GeoHash: mesma codificação usada pelo backend (``shared/domain/geohash.py``)
/// e pelo PostGIS (``ST_GeoHash``). O app assina as células da região que está
/// vendo no WebSocket de tempo real.
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Precisão das partições de tempo real (~39 km x 19,5 km no equador).
const geohashPartitionPrecision = 4;

/// Limite de células por assinatura aceito pelo servidor.
const geohashMaxSubscriptions = 50;

String geohashEncode(double latitude, double longitude, {int precision = 7}) {
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw ArgumentError('Coordenadas fora do intervalo válido.');
  }
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  final buffer = StringBuffer();
  var bits = 0, bitCount = 0;
  var even = true;
  while (buffer.length < precision) {
    if (even) {
      final middle = (lonMin + lonMax) / 2;
      if (longitude >= middle) {
        bits = (bits << 1) | 1;
        lonMin = middle;
      } else {
        bits <<= 1;
        lonMax = middle;
      }
    } else {
      final middle = (latMin + latMax) / 2;
      if (latitude >= middle) {
        bits = (bits << 1) | 1;
        latMin = middle;
      } else {
        bits <<= 1;
        latMax = middle;
      }
    }
    even = !even;
    if (++bitCount == 5) {
      buffer.write(_base32[bits]);
      bits = 0;
      bitCount = 0;
    }
  }
  return buffer.toString();
}

/// Altura e largura (em graus) de uma célula na precisão informada.
({double lat, double lon}) geohashCellSize(int precision) {
  final totalBits = precision * 5;
  final lonBits = (totalBits + 1) ~/ 2;
  final latBits = totalBits ~/ 2;
  return (lat: 180 / math.pow(2, latBits), lon: 360 / math.pow(2, lonBits));
}

/// Células que cobrem um círculo de [radiusMeters] em volta do ponto.
///
/// Se a cobertura passar do limite do servidor, usa uma precisão mais grossa.
List<String> geohashCellsAround(
  double latitude,
  double longitude,
  int radiusMeters, {
  int precision = geohashPartitionPrecision,
}) {
  for (var p = precision; p >= 3; p--) {
    final size = geohashCellSize(p);
    final latSpan = radiusMeters / 111320.0;
    final cosLat = math.cos(latitude * math.pi / 180).abs().clamp(0.01, 1.0);
    final lonSpan = radiusMeters / (111320.0 * cosLat);
    final cells = <String>{};
    for (var lat = latitude - latSpan; lat <= latitude + latSpan + size.lat; lat += size.lat) {
      for (var lon = longitude - lonSpan; lon <= longitude + lonSpan + size.lon; lon += size.lon) {
        final clampedLat = math.min(90.0, math.max(-90.0, math.min(lat, latitude + latSpan)));
        var wrappedLon = math.min(lon, longitude + lonSpan);
        wrappedLon = ((wrappedLon + 180) % 360) - 180;
        cells.add(geohashEncode(clampedLat, wrappedLon, precision: p));
      }
    }
    if (cells.length <= geohashMaxSubscriptions) return cells.toList()..sort();
  }
  return [geohashEncode(latitude, longitude, precision: 3)];
}
