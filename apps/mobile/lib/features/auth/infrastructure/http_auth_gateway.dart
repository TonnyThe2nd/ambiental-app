import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/entities/auth_user.dart';
import '../domain/repositories/auth_gateway.dart';

class HttpAuthGateway implements AuthGateway {
  HttpAuthGateway({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = Uri.parse(baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000'));
  final http.Client _client;
  final Uri _baseUri;

  @override
  Future<AuthSession> login({required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email.trim(), 'password': password});

  @override
  Future<AuthSession> register({required String name, required String email, required String password, double? latitude, double? longitude}) =>
      _authenticate('/auth/register', {'name': name.trim(), 'email': email.trim(), 'password': password, if (latitude != null && longitude != null) ...{'latitude': latitude, 'longitude': longitude}});

  @override
  Future<void> updateLocation(String accessToken, {required double latitude, required double longitude}) async {
    final response = await _client.put(_baseUri.resolve('/auth/me/location'), headers: _headers(accessToken, json: true), body: jsonEncode({'latitude': latitude, 'longitude': longitude}));
    if (response.statusCode == 401) throw const AuthException(sessionExpiredMessage);
    if (!_successful(response.statusCode)) throw const AuthException('Não foi possível atualizar sua localização.');
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    final response = await _client.delete(_baseUri.resolve('/auth/me'), headers: _headers(accessToken));
    if (response.statusCode != 204 && response.statusCode != 401) throw const AuthException('Não foi possível excluir sua conta agora.');
  }

  @override
  Future<void> revoke(String accessToken) async {
    await _client.post(_baseUri.resolve('/auth/logout'), headers: _headers(accessToken)).timeout(const Duration(seconds: 10));
  }

  Future<AuthSession> _authenticate(String path, Map<String, dynamic> body) async {
    final response = await _client.post(_baseUri.resolve(path), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (!_successful(response.statusCode)) throw AuthException(decoded['detail'] as String? ?? 'Não foi possível entrar.');
    return AuthSession(accessToken: decoded['accessToken'] as String, user: AuthUser.fromJson(decoded['user'] as Map<String, dynamic>));
  }

  static bool _successful(int code) => code >= 200 && code < 300;
  static Map<String, String> _headers(String token, {bool json = false}) => {if (json) 'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
}
