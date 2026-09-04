import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
  NotificationService(this._auth, this._location, {http.Client? client, String? baseUrl})
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
  final LocationService _location;
  final http.Client _client;
  final Uri _baseUri;
  final _seenIds = <String>{};
  final _notifications = <AppNotification>[];
  Timer? _timer;
  Timer? _locationTimer;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _tokenRefresh;
  Location? _lastSentLocation;
  AppNotification? _latestUnread;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount =>
      _notifications.where((item) => item.readAt == null).length;

  AppNotification? consumeLatestUnread() {
    final notification = _latestUnread;
    _latestUnread = null;
    return notification;
  }

  Future<void> registerPushToken() async {
    if (!_auth.isAuthenticated) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) await _sendPosition(token: token, force: true);
      await _tokenRefresh?.cancel();
      _tokenRefresh = messaging.onTokenRefresh.listen(
        (value) => _sendPosition(token: value, force: true),
      );
      await _foregroundMessages?.cancel();
      _foregroundMessages = FirebaseMessaging.onMessage.listen((_) => _poll());
      await _openedMessages?.cancel();
      _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen((_) => _poll());
    } catch (error) {
      debugPrint('FCM não pôde ser inicializado: $error');
    }
  }

  Future<void> checkProximity({bool background = false}) =>
      _sendPosition(force: true, background: background);

  Future<void> _sendPosition({String? token, bool force = false, bool background = false}) async {
    try {
      final position = await _location.current(background: background);
      final previous = _lastSentLocation;
      if (!force && previous != null) {
        if (_distanceMeters(previous, position) < 250) return;
      }
      final response = await _client.put(
        _baseUri.resolve('/auth/me/location'),
        headers: _auth.authorizedHeaders(json: true),
        body: jsonEncode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'fcmToken': ?token,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _lastSentLocation = position;
        unawaited(_poll());
      }
    } catch (error) {
      debugPrint('Atualização de proximidade adiada: $error');
    }
  }

  double _distanceMeters(Location a, Location b) {
    const earthRadius = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
    final deltaLon = (b.longitude - a.longitude) * math.pi / 180;
    final value = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(deltaLon / 2) * math.sin(deltaLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  void start() {
    if (!_auth.isAuthenticated || _timer != null) return;
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
    unawaited(_sendPosition(force: true));
    _locationTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _sendPosition(),
    );
  }

  void stop({bool clear = false}) {
    _timer?.cancel();
    _timer = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _lastSentLocation = null;
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
      unawaited(registerPushToken());
    } else {
      stop(clear: true);
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChange);
    stop();
    _foregroundMessages?.cancel();
    _openedMessages?.cancel();
    _tokenRefresh?.cancel();
    super.dispose();
  }
}
