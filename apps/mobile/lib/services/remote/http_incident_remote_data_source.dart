import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../../features/incident/domain/entities/incident.dart';
import '../auth/auth_service.dart';

class HttpIncidentRemoteDataSource {
  HttpIncidentRemoteDataSource(
    this._auth, {
    http.Client? client,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _baseUri = Uri.parse(
         baseUrl ??
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://10.0.2.2:8000',
             ),
       );

  final http.Client _client;
  final AuthService _auth;
  final Uri _baseUri;

  Uri get _incidentsUri => _baseUri.resolve('/incidents');

  Future<Incident> upload(Incident incident) async {
    final idempotencySource =
        '${incident.createdAt.toUtc().toIso8601String()}|'
        '${incident.latitude.toStringAsFixed(6)}|${incident.longitude.toStringAsFixed(6)}|${incident.category}';
    final response = await _client.post(
      _incidentsUri,
      headers: _auth.authorizedHeaders(json: true),
      body: jsonEncode({
        'id': incident.id,
        'category': incident.category,
        'latitude': incident.latitude,
        'longitude': incident.longitude,
        'createdAt': incident.createdAt.toUtc().toIso8601String(),
        'imageUrl': incident.imageUrl,
        'idempotencyKey': sha256
            .convert(utf8.encode(idempotencySource))
            .toString(),
      }),
    );
    if (response.statusCode == 409) {
      return incident.copyWith(status: IncidentStatus.synced);
    }
    _ensureSuccess(response, expectedStatus: 202);
    return _fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Stream<List<Incident>> watch() async* {
    yield await getAll();
    await for (final _ in Stream<void>.periodic(const Duration(seconds: 15))) {
      yield await getAll();
    }
  }

  Future<List<Incident>> getAll() async {
    final response = await _client.get(
      _incidentsUri,
      headers: _auth.authorizedHeaders(),
    );
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as List<dynamic>;
    return body.map((item) => _fromJson(item as Map<String, dynamic>)).toList();
  }

  Incident _fromJson(Map<String, dynamic> json) {
    final reporter = json['reportedBy'] as Map<String, dynamic>?;
    return Incident(
      id: json['id'] as String,
      imagePath: '',
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: IncidentStatus.synced,
      reportedById: reporter?['id'] as String?,
      reportedByName: reporter?['name'] as String?,
    );
  }

  void _ensureSuccess(http.Response response, {int? expectedStatus}) {
    final success = expectedStatus == null
        ? response.statusCode >= 200 && response.statusCode < 300
        : response.statusCode == expectedStatus;
    if (!success) {
      throw StateError('API respondeu com status ${response.statusCode}.');
    }
  }
}
