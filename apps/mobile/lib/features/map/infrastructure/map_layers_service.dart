import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../core/geo/geohash.dart';
import '../../auth/application/auth_service.dart';

/// Ponto da grade ambiental (qualidade do ar e sensação térmica).
class EnvironmentalCell {
  const EnvironmentalCell({
    required this.latitude,
    required this.longitude,
    required this.latitudeSpan,
    required this.longitudeSpan,
    this.airQualityIndex,
    this.apparentTemperature,
  });

  final double latitude;
  final double longitude;
  final double latitudeSpan;
  final double longitudeSpan;
  final int? airQualityIndex;
  final double? apparentTemperature;
}

/// Quadrante do mapa de calor calculado no servidor (GeoHash + cache Redis).
class HeatmapCell {
  const HeatmapCell({
    required this.cell,
    required this.total,
    required this.averageRisk,
    required this.critical,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final String cell;
  final int total;
  final double averageRisk;
  final int critical;
  final double south, west, north, east;

  factory HeatmapCell.fromJson(Map<String, dynamic> json) {
    final bounds = (json['bounds'] as List<dynamic>).map((v) => (v as num).toDouble()).toList();
    return HeatmapCell(
      cell: json['cell'] as String,
      total: (json['total'] as num).toInt(),
      averageRisk: (json['avg_risk'] as num?)?.toDouble() ?? 0,
      critical: (json['critical'] as num?)?.toInt() ?? 0,
      south: bounds[0],
      west: bounds[1],
      north: bounds[2],
      east: bounds[3],
    );
  }
}

/// Ilha de calor: célula com sensação térmica bem acima da média da região visível.
const heatIslandDeltaCelsius = 1.5;

Set<int> heatIslandIndexes(List<EnvironmentalCell> cells) {
  final values = cells.map((c) => c.apparentTemperature).whereType<double>().toList();
  if (values.length < 3) return const {};
  final mean = values.reduce((a, b) => a + b) / values.length;
  return {
    for (var i = 0; i < cells.length; i++)
      if ((cells[i].apparentTemperature ?? double.negativeInfinity) >= mean + heatIslandDeltaCelsius) i,
  };
}

class MapLayersService {
  MapLayersService(this._auth, {http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = Uri.parse(
        baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8000',
            ),
      );

  final AuthService _auth;
  final http.Client _client;
  final Uri _baseUri;
  static const _timeout = Duration(seconds: 15);

  /// Grade [size] x [size] sobre a área visível, com AQI (EUA) e sensação térmica.
  /// A Open-Meteo aceita várias coordenadas numa única requisição.
  Future<List<EnvironmentalCell>> environmentalGrid({
    required double south,
    required double west,
    required double north,
    required double east,
    int size = 5,
  }) async {
    final latSpan = (north - south) / size;
    final lonSpan = (east - west) / size;
    final points = <({double lat, double lon})>[
      for (var row = 0; row < size; row++)
        for (var col = 0; col < size; col++)
          (lat: south + latSpan * (row + .5), lon: west + lonSpan * (col + .5)),
    ];
    final latitudes = points.map((p) => p.lat.toStringAsFixed(4)).join(',');
    final longitudes = points.map((p) => p.lon.toStringAsFixed(4)).join(',');
    final results = await Future.wait([
      _getList(Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
        'latitude': latitudes,
        'longitude': longitudes,
        'current': 'us_aqi',
      })),
      _getList(Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': latitudes,
        'longitude': longitudes,
        'current': 'apparent_temperature',
      })),
    ]);
    final air = results[0];
    final weather = results[1];
    return [
      for (var i = 0; i < points.length; i++)
        EnvironmentalCell(
          latitude: points[i].lat,
          longitude: points[i].lon,
          latitudeSpan: latSpan,
          longitudeSpan: lonSpan,
          airQualityIndex: _current(air, i, 'us_aqi')?.round(),
          apparentTemperature: _current(weather, i, 'apparent_temperature')?.toDouble(),
        ),
    ];
  }

  Future<List<dynamic>> _getList(Uri uri) async {
    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      // Uma coordenada devolve objeto; várias, uma lista na mesma ordem.
      return body is List ? body : [body];
    } catch (_) {
      return const [];
    }
  }

  num? _current(List<dynamic> list, int index, String key) {
    if (index >= list.length || list[index] is! Map) return null;
    final current = (list[index] as Map)['current'];
    if (current is! Map) return null;
    final value = current[key];
    return value is num ? value : null;
  }

  /// Mapa de calor das ocorrências por quadrante GeoHash (servidor).
  Future<List<HeatmapCell>> heatmap({
    required double latitude,
    required double longitude,
    required int radiusMeters,
    int days = 30,
  }) async {
    final cells = geohashCellsAround(latitude, longitude, radiusMeters);
    final minLength = cells.map((c) => c.length).reduce(math.min);
    final precision = math.min(7, minLength + 1);
    final uri = _baseUri.resolve('/incidents/heatmap').replace(queryParameters: {
      'precision': '$precision',
      'days': '$days',
      'cells': cells,
    });
    final response = await _client.get(uri, headers: _auth.authorizedHeaders()).timeout(_timeout);
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      return const [];
    }
    if (response.statusCode != 200) return const [];
    return (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(HeatmapCell.fromJson)
        .toList();
  }
}
