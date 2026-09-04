import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../auth/application/auth_service.dart';
import '../../../core/device/location_service.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final DateTime? readAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
      );
}

class NotificationService extends ChangeNotifier {
  NotificationService(this._auth, {http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = Uri.parse(
        baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8000',
            ),
      ) {
    _auth.addListener(_handleAuthChange);
  }

  final AuthService _auth;
  final http.Client _client;
  final Uri _baseUri;
  final _seenIds = <String>{};
  final _notifications = <AppNotification>[];
  Timer? _timer;
  AppNotification? _latestUnread;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount =>
      _notifications.where((item) => item.readAt == null).length;

  AppNotification? consumeLatestUnread() {
    final notification = _latestUnread;
    _latestUnread = null;
    return notification;
  }

  Future<void> registerPushToken(LocationService location) async {
    if (!_auth.isAuthenticated) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _sendPushToken(token, location);
      messaging.onTokenRefresh.listen(
        (value) => _sendPushToken(value, location),
      );
    } catch (error) {
      debugPrint('FCM não pôde ser inicializado: $error');
    }
  }

  Future<void> _sendPushToken(String token, LocationService location) async {
    try {
      final position = await location.current();
      await _client.put(
        _baseUri.resolve('/auth/me/location'),
        headers: _auth.authorizedHeaders(json: true),
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'fcmToken': token,
        }),
      );
    } catch (error) {
      debugPrint('Registro do token FCM adiado: $error');
    }
  }

  void start() {
    if (!_auth.isAuthenticated || _timer != null) return;
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
  }

  void stop({bool clear = false}) {
    _timer?.cancel();
    _timer = null;
    if (clear) {
      _seenIds.clear();
      _notifications.clear();
      _latestUnread = null;
      notifyListeners();
    }
  }

  Future<void> refresh() => _poll(announceNew: false);

  Future<void> markRead(String id) async {
    final response = await _client.post(
      _baseUri.resolve('/notifications/$id/read'),
      headers: _auth.authorizedHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = _notifications[index];
    _notifications[index] = AppNotification(
      id: current.id,
      title: current.title,
      message: current.message,
      createdAt: current.createdAt,
      readAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> _poll({bool announceNew = true}) async {
    if (!_auth.isAuthenticated) return;
    try {
      final response = await _client.get(
        _baseUri.resolve('/notifications?unread_only=false'),
        headers: _auth.authorizedHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final body = jsonDecode(response.body) as List<dynamic>;
      final items = body
          .map((item) => AppNotification.fromJson(item as Map<String, dynamic>))
          .toList();
      final fresh = items
          .where((item) => item.readAt == null && !_seenIds.contains(item.id))
          .toList();
      _notifications
        ..clear()
        ..addAll(items);
      _seenIds.addAll(items.map((item) => item.id));
      _latestUnread = announceNew && fresh.isNotEmpty ? fresh.first : null;
      notifyListeners();
    } catch (_) {}
  }

  void _handleAuthChange() {
    if (_auth.isAuthenticated) {
      start();
    } else {
      stop(clear: true);
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    stop();
    super.dispose();
  }
}
