import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/application/auth_service.dart';
import '../domain/app_notification.dart';
import '../domain/notification_gateway.dart';
import '../domain/proximity_zone.dart';

class HttpNotificationGateway implements NotificationGateway {
  HttpNotificationGateway(this._auth, {http.Client? client, String? baseUrl})
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

  @override
  Future<bool> updatePosition({
    required double latitude,
    required double longitude,
    String? fcmToken,
  }) async =>
      await reportPosition(latitude: latitude, longitude: longitude, fcmToken: fcmToken) != null;

  @override
  Future<PositionReport?> reportPosition({
    required double latitude,
    required double longitude,
    String? fcmToken,
    bool localGeofencing = false,
    List<List<double>>? route,
  }) async {
    if (!_auth.isAuthenticated) return null;
    final response = await _client
        .put(
          _baseUri.resolve('/auth/me/location'),
          headers: _auth.authorizedHeaders(json: true),
          body: jsonEncode({
            'latitude': latitude,
            'longitude': longitude,
            'fcmToken': ?fcmToken,
            'localGeofencing': localGeofencing,
            'route': ?route,
          }),
        )
        .timeout(_timeout);
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    if (response.body.isEmpty) return const PositionReport([]);
    final decoded = jsonDecode(response.body);
    final alerts = decoded is Map<String, dynamic> ? decoded['alerts'] : null;
    return PositionReport([
      if (alerts is List)
        for (final item in alerts.whereType<Map<String, dynamic>>())
          ServerProximityAlert.fromJson(item),
    ]);
  }

  @override
  Future<List<ProximityZone>?> nearbyZones({
    required double latitude,
    required double longitude,
    int radiusMeters = 20000,
  }) async {
    if (!_auth.isAuthenticated) return null;
    final response = await _client
        .get(
          _baseUri.resolve('/incidents').replace(queryParameters: {
            'latitude': latitude.toString(),
            'longitude': longitude.toString(),
            'radius_m': radiusMeters.toString(),
            'active_only': 'true',
            'limit': '1000',
          }),
          headers: _auth.authorizedHeaders(),
        )
        .timeout(_timeout);
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(ProximityZone.fromIncidentJson)
        .toList();
  }

  @override
  Future<List<AppNotification>> list() async {
    final response = await _client.get(
      _baseUri.resolve('/notifications?unread_only=false'),
      headers: _auth.authorizedHeaders(),
    );
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      return [];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    return (jsonDecode(response.body) as List)
        .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<bool> markRead(String id) async {
    final response = await _client.post(
      _baseUri.resolve('/notifications/$id/read'),
      headers: _auth.authorizedHeaders(),
    );
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      return false;
    }
    return response.statusCode >= 200 && response.statusCode < 300;
  }
}
