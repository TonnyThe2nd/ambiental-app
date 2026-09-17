import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../auth/application/auth_service.dart';
import '../../../core/device/location_service.dart';
import '../domain/notification_gateway.dart';
import '../domain/app_notification.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await SystemNotificationService.initialize();

  if (message.notification == null) {
    await SystemNotificationService.show(message);
  }
}

class NotificationContent {
  const NotificationContent({required this.title, required this.body});

  final String title;
  final String body;

  factory NotificationContent.fromMessage(RemoteMessage message) {
    final data = message.data;
    return NotificationContent(
      title: message.notification?.title ??
          data['title'] ??
          'Novo alerta ambiental',
      body: message.notification?.body ??
          data['body'] ??
          data['message'] ??
          'Há uma ocorrência próxima de você.',
    );
  }
}

class SystemNotificationService {
  static const channelId = 'environmental_alerts';
  static const channelName = 'Alertas ambientais';
  static const channelDescription =
      'Alertas de ocorrências ambientais próximas';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
        ));
    _initialized = true;
  }

  static Future<void> requestPermission() async {
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(RemoteMessage message) async {
    await initialize();
    final content = NotificationContent.fromMessage(message);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(
      message.messageId?.hashCode ?? DateTime.now().microsecondsSinceEpoch,
      content.title,
      content.body,
      details,
      payload: message.data['notificationId'] ?? message.messageId,
    );
  }
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
      await SystemNotificationService.initialize();
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await SystemNotificationService.requestPermission();
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
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
      if (await messaging.getInitialMessage() != null) {
        unawaited(_poll());
      }
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
    try {
      await SystemNotificationService.show(message);
    } catch (error) {
      debugPrint('Notificação local não exibida: $error');
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
