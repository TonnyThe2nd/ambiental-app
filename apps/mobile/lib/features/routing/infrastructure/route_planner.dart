import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/application/auth_service.dart';
import '../domain/route_option.dart';

/// Roteamento preventivo: busca rotas alternativas num motor OSRM e pede ao
/// backend a avaliação de risco de cada uma (ocorrências ativas no corredor).
class RoutePlanner {
  RoutePlanner(
    this._auth, {
    http.Client? client,
    String? apiBaseUrl,
    String? routingBaseUrl,
  }) : _client = client ?? http.Client(),
       _apiBaseUri = Uri.parse(
         apiBaseUrl ??
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://10.0.2.2:8000',
             ),
       ),
       _routingBaseUri = Uri.parse(
         routingBaseUrl ??
             const String.fromEnvironment(
               'ROUTING_BASE_URL',
               defaultValue: 'https://routing.openstreetmap.de',
             ),
       );

  final AuthService _auth;
  final http.Client _client;
  final Uri _apiBaseUri;
  final Uri _routingBaseUri;
  static const _timeout = Duration(seconds: 20);

  /// Pontos enviados ao backend para avaliação e para o alerta de rota.
  static const assessMaxPoints = 1500;
  static const alertRouteMaxPoints = 500;

  Future<List<RouteOption>> plan({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    TravelMode mode = TravelMode.foot,
  }) async {
    final candidates = await _fetchCandidates(
      fromLatitude, fromLongitude, toLatitude, toLongitude, mode);
    if (candidates.isEmpty) {
      throw StateError('Nenhuma rota encontrada até o destino.');
    }
    final response = await _client
        .post(
          _apiBaseUri.resolve('/routes/assess'),
          headers: _auth.authorizedHeaders(json: true),
          body: jsonEncode({
            'corridorMeters': mode == TravelMode.foot ? 60 : 100,
            'routes': [
              for (final route in candidates)
                {
                  'id': route.id,
                  'points': simplifyRoute(route.points, assessMaxPoints),
                  'distanceMeters': route.distanceMeters,
                  'durationSeconds': route.durationSeconds,
                },
            ],
          }),
        )
        .timeout(_timeout);
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      throw const AuthException(sessionExpiredMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Não foi possível avaliar o risco das rotas (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final assessments = {
      for (final item in (body['routes'] as List<dynamic>).whereType<Map<String, dynamic>>())
        item['id'] as String: item,
    };
    final options = [
      for (final route in candidates)
        assessments[route.id] == null ? route : route.withAssessment(assessments[route.id]!),
    ]..sort((a, b) {
        if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
        return a.riskScore.compareTo(b.riskScore);
      });
    return options;
  }

  Future<List<RouteOption>> _fetchCandidates(
    double fromLat, double fromLon, double toLat, double toLon, TravelMode mode,
  ) async {
    final (service, profile) = switch (mode) {
      TravelMode.foot => ('routed-foot', 'foot'),
      TravelMode.car => ('routed-car', 'driving'),
    };
    final coordinates = '$fromLon,$fromLat;$toLon,$toLat';
    final uri = _routingBaseUri.replace(
      path: '/$service/route/v1/$profile/$coordinates',
      queryParameters: {
        'alternatives': '3',
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('Serviço de rotas indisponível (${response.statusCode}).');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != 'Ok') {
      throw StateError('Nenhuma rota encontrada até o destino.');
    }
    final routes = (body['routes'] as List<dynamic>).whereType<Map<String, dynamic>>().toList();
    return [
      for (var index = 0; index < routes.length && index < 3; index++)
        RouteOption(
          id: '$index',
          points: [
            for (final coordinate in
                ((routes[index]['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>))
              [
                ((coordinate as List<dynamic>)[1] as num).toDouble(),
                (coordinate[0] as num).toDouble(),
              ],
          ],
          distanceMeters: (routes[index]['distance'] as num).toDouble(),
          durationSeconds: (routes[index]['duration'] as num).toDouble(),
        ),
    ];
  }
}
