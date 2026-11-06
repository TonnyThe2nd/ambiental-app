import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/application/auth_service.dart';
import '../application/incident_confirmation.dart';

/// Voto da comunidade em ``/incidents/{id}/community-validation``.
class HttpIncidentConfirmationGateway implements IncidentConfirmationGateway {
  HttpIncidentConfirmationGateway(this._auth, {http.Client? client, String? baseUrl})
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

  Uri _uri(String incidentId) =>
      _baseUri.resolve('/incidents/${Uri.encodeComponent(incidentId)}/community-validation');

  @override
  Future<String?> myVote(String incidentId) async {
    final response = await _client
        .get(_uri(incidentId), headers: _auth.authorizedHeaders())
        .timeout(_timeout);
    await _ensureSuccess(response);
    final body = jsonDecode(response.body);
    return body is Map<String, dynamic> ? body['vote'] as String? : null;
  }

  @override
  Future<ConfirmationOutcome> submit(String incidentId, String vote) async {
    final response = await _client
        .put(
          _uri(incidentId),
          headers: _auth.authorizedHeaders(json: true),
          body: jsonEncode({'vote': vote}),
        )
        .timeout(_timeout);
    // 409: é o autor do relato; 404: a ocorrência saiu do ar. Nada a confirmar.
    if (response.statusCode == 409) return ConfirmationOutcome.notAllowed;
    if (response.statusCode == 404) return ConfirmationOutcome.notFound;
    await _ensureSuccess(response);
    return ConfirmationOutcome.recorded;
  }

  Future<void> _ensureSuccess(http.Response response) async {
    if (response.statusCode == 401) {
      await _auth.handleUnauthorized();
      throw const AuthException(sessionExpiredMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('API respondeu com status ${response.statusCode}.');
    }
  }
}
