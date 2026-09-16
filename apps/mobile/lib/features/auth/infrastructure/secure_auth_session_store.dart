import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/entities/auth_user.dart';
import '../domain/repositories/auth_gateway.dart';

class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  static const _tokenKey = 'urbaneye.jwt';
  static const _userKey = 'urbaneye.user';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final userJson = await _storage.read(key: _userKey);
    if (token == null || userJson == null) return null;
    try {
      return AuthSession(accessToken: token, user: AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>));
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    await _storage.write(key: _tokenKey, value: session.accessToken);
    await _storage.write(key: _userKey, value: jsonEncode(session.user.toJson()));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
