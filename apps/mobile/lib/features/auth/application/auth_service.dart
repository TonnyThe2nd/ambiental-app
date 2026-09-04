import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/entities/auth_user.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    http.Client? client,
    FlutterSecureStorage? storage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage(),
       _baseUri = Uri.parse(
         baseUrl ??
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://10.0.2.2:8000',
             ),
       );

  static const _tokenKey = 'urbaneye.jwt';
  static const _userKey = 'urbaneye.user';
  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Uri _baseUri;
  String? _token;
  AuthUser? _user;

  String? get token => _token;
  AuthUser? get currentUser => _user;
  bool get isAuthenticated => _token != null && _user != null;

  Future<void> restoreSession() async {
    _token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (_token != null && userJson != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) =>
      _authenticate('/auth/login', {
        'email': email.trim(),
        'password': password,
      });

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required double latitude,
    required double longitude,
  }) => _authenticate('/auth/register', {
    'name': name.trim(),
    'email': email.trim(),
    'password': password,
    'latitude': latitude,
    'longitude': longitude,
  });

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.put(
      _baseUri.resolve('/auth/me/location'),
      headers: authorizedHeaders(json: true),
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const AuthException('Não foi possível atualizar sua localização.');
    }
  }

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          _baseUri.resolve(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(
        decoded['detail'] as String? ?? 'Não foi possível entrar.',
      );
    }
    _token = decoded['accessToken'] as String;
    _user = AuthUser.fromJson(decoded['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: _userKey, value: jsonEncode(_user!.toJson()));
    notifyListeners();
  }

  Map<String, String> authorizedHeaders({bool json = false}) {
    final value = _token;
    if (value == null) throw const AuthException('Faça login novamente.');
    return {
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $value',
    };
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    notifyListeners();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
