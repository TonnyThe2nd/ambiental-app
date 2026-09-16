import 'package:flutter/foundation.dart';
import '../domain/entities/auth_user.dart';
import '../domain/repositories/auth_gateway.dart';
export '../domain/repositories/auth_gateway.dart'
    show AuthException, sessionExpiredMessage;

class AuthService extends ChangeNotifier {
  AuthService(this._gateway, this._store);

  final AuthGateway _gateway;
  final AuthSessionStore _store;
  AuthSession? _session;

  String? get token => _session?.accessToken;
  AuthUser? get currentUser => _session?.user;
  bool get isAuthenticated => _session != null;

  Future<void> restoreSession() async {
    _session = await _store.read();
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async =>
      _setSession(await _gateway.login(email: email, password: password));

  Future<void> register({required String name, required String email, required String password, double? latitude, double? longitude}) async =>
      _setSession(await _gateway.register(name: name, email: email, password: password, latitude: latitude, longitude: longitude));

  Future<void> updateLocation({required double latitude, required double longitude}) async {
    try {
      await _gateway.updateLocation(_requireToken(), latitude: latitude, longitude: longitude);
    } on AuthException catch (error) {
      if (error.message == sessionExpiredMessage) await handleUnauthorized();
      rethrow;
    }
  }

  Future<void> deleteAccount() async {
    await _gateway.deleteAccount(_requireToken());
    await _clearSession();
  }

  Future<void> logout() async {
    final accessToken = token;
    if (accessToken != null) {
      try {
        await _gateway.revoke(accessToken);
      } on Object {
        // A sessão local deve terminar mesmo quando a API estiver indisponível.
      }
    }
    await _clearSession();
  }

  Future<void> handleUnauthorized() async {
    if (_session != null) await _clearSession();
  }

  Map<String, String> authorizedHeaders({bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    'Authorization': 'Bearer ${_requireToken()}',
  };

  String _requireToken() {
    final accessToken = token;
    if (accessToken == null) throw const AuthException('Faça login novamente.');
    return accessToken;
  }

  Future<void> _setSession(AuthSession session) async {
    await _store.write(session);
    _session = session;
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _session = null;
    await _store.clear();
    notifyListeners();
  }
}
