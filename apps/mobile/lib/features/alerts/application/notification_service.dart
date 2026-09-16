import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../../auth/application/auth_service.dart';
import '../../../core/device/location_service.dart';
import '../domain/notification_gateway.dart';
import '../domain/app_notification.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
const notificationFallbackPollingInterval = Duration(minutes: 5);
const locationFallbackPollingInterval = Duration(minutes: 5);

class NotificationService extends ChangeNotifier {
  NotificationService(this._auth, this._location, this._gateway) {
    _auth.addListener(_handleAuthChange);
  }

  final AuthService _auth;
  final LocationService _location;
  final NotificationGateway _gateway;
  final _seenIds = <String>{};
  static const _systemNotifications = MethodChannel('urbaneye/system_notifications');
  final _notifications = <AppNotification>[];
  Timer? _timer;
  Timer? _locationTimer;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  StreamSubscription<String>? _tokenRefresh;
  Location? _lastSentLocation;
  AppNotification? _latestUnread;
  bool _pollInProgress = false;

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
      _foregroundMessages = FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showSystemNotification(message));
        unawaited(_poll());
      });
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
      if (await _gateway.updatePosition(latitude: position.latitude, longitude: position.longitude, fcmToken: token)) {
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
    _timer = Timer.periodic(notificationFallbackPollingInterval, (_) => _poll());
    unawaited(_sendPosition(force: true));
    _locationTimer = Timer.periodic(
      locationFallbackPollingInterval,
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
    if (!await _gateway.markRead(id)) return;
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
    if (!_auth.isAuthenticated || _pollInProgress) return;
    _pollInProgress = true;
    try {
      final items = (await _gateway.list())
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
    } catch (_) {
    } finally {
      _pollInProgress = false;
    }
  }

  Future<void> _showSystemNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? 'Novo alerta ambiental';
    final body = notification?.body ?? 'Há uma ocorrência próxima de você.';
    try {
      await _systemNotifications.invokeMethod<void>('show', {
        'id': message.messageId?.hashCode ?? DateTime.now().microsecondsSinceEpoch,
        'title': title,
        'body': body,
      });
    } on PlatformException catch (error) {
      debugPrint('Notificação local não exibida: ${error.message}');
    }
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
