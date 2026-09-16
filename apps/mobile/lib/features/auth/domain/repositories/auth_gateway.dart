import '../entities/auth_user.dart';

class AuthSession {
  const AuthSession({required this.accessToken, required this.user});
  final String accessToken;
  final AuthUser user;
}

abstract interface class AuthGateway {
  Future<AuthSession> login({required String email, required String password});
  Future<AuthSession> register({required String name, required String email, required String password, double? latitude, double? longitude});
  Future<void> updateLocation(String accessToken, {required double latitude, required double longitude});
  Future<void> revoke(String accessToken);
  Future<void> deleteAccount(String accessToken);
}

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

const sessionExpiredMessage = 'Sessão expirada. Entre novamente.';
