import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

const _softChannelId = 'soft_channel';
const _messagesChannelId = 'messages_channel';

/// Background isolate entry point required by firebase_messaging. Real
/// notification display for background/killed app states is handled
/// natively by Android/iOS from the FCM `notification` payload — this is
/// just the mandatory hook the plugin needs registered.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Wires up Firebase Cloud Messaging: permission requests, device-token
/// registration, foreground display (Android needs it built manually —
/// unlike iOS, it doesn't auto-present FCM notifications while the app is
/// foregrounded), and tap-to-navigate.
///
/// Every push is either a "soft" notification-center item (likes, follows,
/// comments, event activity — silent, channel `soft_channel`) or a DM alert
/// (full ring + sender avatar, channel `messages_channel`); see
/// `push/senders.py` on the backend for how each is built.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();

  String? _authToken;
  String? _fcmToken;

  void Function(int conversationId)? onDmTap;
  VoidCallback? onSoftTap;
  int? _pendingConversationId;
  bool _pendingSoft = false;

  Future<void> init() async {
    await _initLocalNotifications();

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      final authToken = _authToken;
      if (authToken != null) unawaited(_postToken(authToken, token));
    });

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _dispatchTap(m.data));

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _dispatchTap(initialMessage.data);
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('ic_stat_neat');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          _dispatchTap(jsonDecode(payload) as Map<String, dynamic>);
        } catch (_) {}
      },
    );

    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _softChannelId,
      'Activity',
      description: 'Likes, follows, comments and other activity',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    ));
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      _messagesChannelId,
      'Messages',
      description: 'New direct messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
  }

  // ── Session wiring (called from auth_gate.dart on login/logout) ─────────

  Future<void> registerForSession(String authToken) async {
    _authToken = authToken;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      _fcmToken = token;
      await _postToken(authToken, token);
    } catch (_) {}
  }

  Future<void> unregisterForSession(String authToken) async {
    final token = _fcmToken;
    _authToken = null;
    if (token == null) return;
    try {
      await http.post(
        unregisterDeviceEndpoint,
        headers: authJsonHeaders(authToken),
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
  }

  Future<void> _postToken(String authToken, String fcmToken) async {
    try {
      await http.post(
        registerDeviceEndpoint,
        headers: authJsonHeaders(authToken),
        body: jsonEncode({
          'token': fcmToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );
    } catch (_) {}
  }

  // ── Foreground display (Android only — iOS auto-presents natively) ─────

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final data = message.data;
    final isDm = data['type'] == 'dm';
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final payload = jsonEncode(data);

    if (isDm) {
      final imageUrl = message.notification?.android?.imageUrl;
      final avatarBytes = await _fetchImageBytes(imageUrl);
      await _local.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _messagesChannelId,
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: avatarBytes != null
                ? BigPictureStyleInformation(
                    ByteArrayAndroidBitmap(avatarBytes),
                    largeIcon: ByteArrayAndroidBitmap(avatarBytes),
                  )
                : null,
            largeIcon:
                avatarBytes != null ? ByteArrayAndroidBitmap(avatarBytes) : null,
          ),
        ),
        payload: payload,
      );
    } else {
      await _local.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _softChannelId,
            'Activity',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            playSound: false,
            enableVibration: false,
          ),
        ),
        payload: payload,
      );
    }
  }

  Future<Uint8List?> _fetchImageBytes(String? url) async {
    if (url == null || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return null;
    }
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  // ── Tap → navigate ───────────────────────────────────────────────────────

  void _dispatchTap(Map<String, dynamic> data) {
    if (data['type'] == 'dm') {
      final id = int.tryParse('${data['conversationId']}');
      if (id == null) return;
      final handler = onDmTap;
      if (handler != null) {
        handler(id);
      } else {
        _pendingConversationId = id;
      }
    } else {
      final handler = onSoftTap;
      if (handler != null) {
        handler();
      } else {
        _pendingSoft = true;
      }
    }
  }

  /// Called once HomePage has registered [onDmTap]/[onSoftTap], in case a
  /// push was tapped before the handlers existed (cold start).
  void replayPending() {
    final id = _pendingConversationId;
    if (id != null) {
      _pendingConversationId = null;
      onDmTap?.call(id);
    }
    if (_pendingSoft) {
      _pendingSoft = false;
      onSoftTap?.call();
    }
  }
}
