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
    final cache = <String, Incident>{};
    DateTime? cursor;
    final initial = await getAll();
    for (final item in initial) { cache[item.id] = item; }
    cursor = initial.map((item) => item.updatedAt).whereType<DateTime>().fold<DateTime?>(
      null, (latest, value) => latest == null || value.isAfter(latest) ? value : latest,
    );
    yield cache.values.toList();
    await for (final _ in Stream<void>.periodic(const Duration(seconds: 15))) {
      final changes = await getAll(updatedSince: cursor);
      for (final item in changes) {
        cache[item.id] = item;
        if (item.updatedAt != null && (cursor == null || item.updatedAt!.isAfter(cursor))) cursor = item.updatedAt;
      }
      if (changes.isNotEmpty) yield cache.values.where((item) => item.isActive).toList();
    }
  }

  Future<List<Incident>> getAll({DateTime? updatedSince}) async {
    final uri = updatedSince == null ? _incidentsUri : _incidentsUri.replace(
      queryParameters: {'updated_since': updatedSince.toUtc().toIso8601String()},
    );
    final response = await _client.get(
      uri,
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
      severity: json['severity'] as String? ?? 'moderado',
      workflowStatus: json['workflowStatus'] as String? ?? 'reportado',
      riskScore: (json['riskScore'] as num?)?.toDouble() ?? 50,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 50,
      priorityScore: (json['priorityScore'] as num?)?.toDouble() ?? 50,
      confirmationCount: json['confirmationCount'] as int? ?? 0,
      rejectionCount: json['rejectionCount'] as int? ?? 0,
      complementCount: json['complementCount'] as int? ?? 0,
      updatedAt: json['updatedAt'] == null ? null : DateTime.parse(json['updatedAt'] as String),
    );
  }

  Future<void> validate(String incidentId, String vote, {String? comment}) async {
    final response = await _client.put(
      _baseUri.resolve('/incidents/$incidentId/community-validation'),
      headers: _auth.authorizedHeaders(json: true),
      body: jsonEncode({'vote': vote, if (comment != null) 'comment': comment}),
    );
    _ensureSuccess(response);
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
