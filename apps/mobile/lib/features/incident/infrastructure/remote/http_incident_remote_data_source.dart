import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../../../../core/geo/geohash.dart';
import '../../domain/entities/incident.dart';
import '../../../auth/application/auth_service.dart';
import '../../../weather/data/environmental_context_service.dart';

const incidentFeedFallbackPollingInterval = Duration(minutes: 5);

/// Consulta incremental enquanto o WebSocket está fora do ar.
const incidentFeedPollingInterval = Duration(seconds: 15);

/// Com o tempo real conectado, a consulta periódica vira só o fallback de segurança
/// (eventos perdidos numa reconexão são recuperados pelo cursor ``updated_since``).
const incidentFeedRealtimeSafetyInterval = incidentFeedFallbackPollingInterval;

class HttpIncidentRemoteDataSource {
  HttpIncidentRemoteDataSource(
    this._auth, {
    http.Client? client,
    String? baseUrl,
    this._environment,
    this.realtimeEnabled = true,
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
  final EnvironmentalContextProvider? _environment;
  final bool realtimeEnabled;

  Uri get _incidentsUri => _baseUri.resolve('/incidents');

  Future<Incident> upload(Incident incident) async {
    final environmentalContext =
        await _environment?.contextFor(incident.latitude, incident.longitude) ??
        const <String, Object>{};
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
        'idempotencyKey': incidentIdempotencyKey(incident),
        if (environmentalContext.isNotEmpty) 'environmentalContext': environmentalContext,
      }),
    );
    if (response.statusCode == 409) {
      // Já aceito numa tentativa anterior: garante que a foto também chegou.
      final photoUrl = await uploadPhoto(incident);
      return incident.copyWith(status: IncidentStatus.synced, imageUrl: photoUrl ?? incident.imageUrl);
    }
    _ensureSuccess(response, expectedStatus: 202);
    final accepted = _fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    final photoUrl = await uploadPhoto(incident);
    return photoUrl == null ? accepted : accepted.copyWith(imageUrl: photoUrl);
  }

  /// Envia a foto capturada (antes ela ficava só no aparelho).
  ///
  /// Falha de rede lança erro para o relato voltar à fila e ser reenviado; a API
  /// responde 409 ao relato repetido e a foto é enviada de novo (operação idempotente).
  /// Foto recusada pelo servidor (tamanho/formato) não trava a fila.
  Future<String?> uploadPhoto(Incident incident) async {
    if (kIsWeb || incident.imagePath.isEmpty) return null;
    final file = File(incident.imagePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final lower = incident.imagePath.toLowerCase();
    final contentType = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final response = await _client.put(
      _baseUri.resolve('/incidents/${incident.id}/photo'),
      headers: {..._auth.authorizedHeaders(), 'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode == 413 || response.statusCode == 415) {
      debugPrint('Foto do relato ${incident.id} recusada (${response.statusCode}).');
      return null;
    }
    _ensureSuccess(response, expectedStatus: 204);
    return '/incidents/${incident.id}/photo';
  }

  /// Feed do mapa: snapshot inicial + deltas pelo cursor ``updated_since``.
  ///
  /// Os deltas são disparados pelo WebSocket de tempo real (eventos do barramento
  /// filtrados por quadrante GeoHash). Sem conexão, volta à consulta periódica.
  Stream<List<Incident>> watch({
    double? latitude,
    double? longitude,
    int radiusMeters = 50000,
  }) async* {
    final cache = <String, Incident>{};
    DateTime? cursor;
    String? cursorId;
    final initial = await getAll(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    for (final item in initial) { cache[item.id] = item; }
    cursor = initial.map((item) => item.updatedAt).whereType<DateTime>().fold<DateTime?>(
      null, (latest, value) => latest == null || value.isAfter(latest) ? value : latest,
    );
    if (cursor != null) {
      final last = initial.where((item) => item.updatedAt == cursor).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      cursorId = last.isEmpty ? null : last.last.id;
    }
    yield cache.values.toList();

    final triggers = StreamController<void>();
    final realtime = IncidentRealtimeConnection(
      baseUri: _baseUri,
      tokenProvider: () => _auth.token,
      geohashes: latitude != null && longitude != null
          ? geohashCellsAround(latitude, longitude, radiusMeters)
          : const <String>[],
      onEvent: () { if (!triggers.isClosed) triggers.add(null); },
    );
    if (realtimeEnabled && latitude != null && longitude != null) realtime.start();
    var lastFetch = DateTime.now();
    final ticker = Timer.periodic(incidentFeedPollingInterval, (_) {
      final interval = realtime.connected
          ? incidentFeedRealtimeSafetyInterval
          : incidentFeedPollingInterval;
      if (DateTime.now().difference(lastFetch) >= interval && !triggers.isClosed) {
        triggers.add(null);
      }
    });
    try {
      await for (final _ in triggers.stream) {
        lastFetch = DateTime.now();
        final List<Incident> changes;
        try {
          changes = await getAll(
            updatedSince: cursor,
            updatedAfterId: cursorId,
            includeInactive: true,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
          );
        } on AuthException {
          rethrow;
        } catch (error) {
          debugPrint('Falha ao atualizar o feed do mapa: $error');
          continue;
        }
        for (final item in changes) {
          cache[item.id] = item;
          if (item.updatedAt != null) {
            cursor = item.updatedAt;
            cursorId = item.id;
          }
        }
        if (changes.isNotEmpty) yield cache.values.where((item) => item.isActive).toList();
      }
    } finally {
      ticker.cancel();
      await realtime.stop();
      await triggers.close();
    }
  }

  Future<List<Incident>> getAll({
    DateTime? updatedSince,
    String? updatedAfterId,
    bool includeInactive = false,
    double? latitude,
    double? longitude,
    int radiusMeters = 50000,
  }) async {
    final queryParameters = <String, String>{
      if (updatedSince != null) ...{
        'updated_since': updatedSince.toUtc().toIso8601String(),
        'updated_after_id': ?updatedAfterId,
      },
      if (includeInactive) 'active_only': 'false',
      if (latitude != null && longitude != null) ...{
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius_m': radiusMeters.toString(),
      },
    };
    final uri = queryParameters.isEmpty
        ? _incidentsUri
        : _incidentsUri.replace(queryParameters: queryParameters);
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
      body: jsonEncode({'vote': vote, 'comment': ?comment}),
    );
    _ensureSuccess(response);
  }

  void _ensureSuccess(http.Response response, {int? expectedStatus}) {
    if (response.statusCode == 401) {
      unawaited(_auth.handleUnauthorized());
      throw const AuthException(sessionExpiredMessage);
    }
    final success = expectedStatus == null
        ? response.statusCode >= 200 && response.statusCode < 300
        : response.statusCode == expectedStatus;
    if (!success) {
      throw StateError('API respondeu com status ${response.statusCode}.');
    }
  }
}

String incidentIdempotencyKey(Incident incident) => sha256
    .convert(utf8.encode('incident:${incident.id}'))
    .toString();


/// Conexão WebSocket com ``/ws/incidents``: assina quadrantes GeoHash e avisa
/// quando chega um evento de ocorrência. Reconecta com espera crescente.
class IncidentRealtimeConnection {
  IncidentRealtimeConnection({
    required this.baseUri,
    required this.tokenProvider,
    required this.geohashes,
    required this.onEvent,
  });

  final Uri baseUri;
  final String? Function() tokenProvider;
  final List<String> geohashes;
  final void Function() onEvent;

  WebSocket? _socket;
  bool _running = false;
  bool connected = false;
  Duration _backoff = const Duration(seconds: 2);

  Uri get uri => baseUri.replace(
    scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
    path: '/ws/incidents',
  );

  void start() {
    if (kIsWeb || _running || geohashes.isEmpty) return;
    _running = true;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_running) {
      final token = tokenProvider();
      if (token == null) return;
      try {
        final socket = await WebSocket.connect(
          uri.toString(),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));
        socket.pingInterval = const Duration(seconds: 30);
        _socket = socket;
        socket.add(jsonEncode({'action': 'subscribe', 'geohashes': geohashes}));
        await for (final raw in socket) {
          if (raw is! String) continue;
          final message = jsonDecode(raw);
          if (message is! Map<String, dynamic>) continue;
          switch (message['type']) {
            case 'subscribed':
              connected = true;
              _backoff = const Duration(seconds: 2);
              onEvent(); // recupera o que mudou enquanto estava desconectado
            case 'event':
              onEvent();
          }
        }
      } catch (error) {
        debugPrint('Tempo real indisponível: $error');
      }
      connected = false;
      _socket = null;
      if (!_running) break;
      await Future<void>.delayed(_backoff);
      final next = _backoff * 2;
      _backoff = next > const Duration(minutes: 1) ? const Duration(minutes: 1) : next;
    }
  }

  Future<void> stop() async {
    _running = false;
    connected = false;
    await _socket?.close();
    _socket = null;
  }
}
