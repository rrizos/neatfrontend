import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'http_client.dart' as http;

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
/// registration, and tap-to-navigate. No tray notification is ever shown
/// while the app is foregrounded (on either platform) — only when
/// backgrounded/killed, which Android/iOS handle natively from the FCM
/// `notification` payload without any app code running.
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
  // Receives the full push data map for an activity ("soft") notification so it
  // can navigate to the exact target (post / comment) like an in-app tap.
  void Function(Map<String, dynamic> data)? onNotificationTap;
  int? _pendingConversationId;
  bool _pendingSoft = false;
  Map<String, dynamic>? _pendingNotificationData;

  Future<void>? _initFuture;

  /// Idempotent — safe to call from main() and to await from
  /// registerForSession/unregisterForSession, which may run before main()'s
  /// fire-and-forget init() has finished (e.g. an auto-login on cold start).
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

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

    // Deliberately no FirebaseMessaging.onMessage listener: while the app is
    // foregrounded (the only time that stream fires), pushes shouldn't
    // interrupt with a tray notification — matching Instagram, and per
    // explicit request not to notify while already inside the app. The
    // in-app UI (notifications bell, conversation view) reflects new
    // activity through its own existing polling instead.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _dispatchTap(m.data));

    // Fire-and-forget: this is only for routing a cold-start tap, unrelated
    // to token registration. On this device it has been observed to hang
    // indefinitely (a known FlutterFire/iOS issue), which must never block
    // init() — registerForSession() awaits the same _initFuture.
    unawaited(_checkInitialMessage(messaging));
  }

  Future<void> _checkInitialMessage(FirebaseMessaging messaging) async {
    try {
      // On iOS, getInitialMessage() (the cold-start-from-a-tapped-notification
      // path) can hang or return null if it runs before the APNs device token
      // has been set — the same ordering dependency getToken() has. Waiting for
      // the token first is what lets a killed-app notification tap actually
      // route on iOS; without it the tap was silently dropped (it worked on
      // Android because Android has no APNs step). This is why a tapped DM
      // opened the chat on Android but not iOS.
      if (!kIsWeb && Platform.isIOS) await _waitForApnsToken();
      final initialMessage =
          await messaging.getInitialMessage().timeout(const Duration(seconds: 10));
      if (initialMessage != null) _dispatchTap(initialMessage.data);
    } catch (e) {
      debugPrint('PushService._checkInitialMessage failed: $e');
    }
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
    debugPrint('PushService.registerForSession: starting');
    _authToken = authToken;
    try {
      await init();
      debugPrint('PushService.registerForSession: init done');
      if (!kIsWeb && Platform.isIOS) await _waitForApnsToken();
      debugPrint('PushService.registerForSession: apns wait done, calling getToken');
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 15));
      debugPrint('PushService.registerForSession: getToken returned ${token == null ? 'null' : 'a token'}');
      if (token == null) return;
      _fcmToken = token;
      await _postToken(authToken, token);
      debugPrint('PushService.registerForSession: done');
    } catch (e) {
      debugPrint('PushService.registerForSession failed: $e');
    }
  }

  /// On iOS, FirebaseMessaging.getToken() errors out ("APNS device token not
  /// set") if called before the native APNs token has round-tripped through
  /// Apple's servers via didRegisterForRemoteNotificationsWithDeviceToken —
  /// which requestPermission() only kicks off, it doesn't wait for it. This
  /// has no Android equivalent, and getToken()'s failure here was previously
  /// swallowed silently, so registration always silently failed on iOS.
  Future<void> _waitForApnsToken() async {
    final messaging = FirebaseMessaging.instance;
    for (var i = 0; i < 10; i++) {
      if (await messaging.getAPNSToken() != null) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('PushService: APNS token never arrived after 5s');
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
    } catch (e) {
      debugPrint('PushService.unregisterForSession failed: $e');
    }
  }

  Future<void> _postToken(String authToken, String fcmToken) async {
    try {
      final res = await http
          .post(
            registerDeviceEndpoint,
            headers: authJsonHeaders(authToken),
            body: jsonEncode({
              'token': fcmToken,
              'platform': Platform.isIOS ? 'ios' : 'android',
            }),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('PushService._postToken: response ${res.statusCode}');
    } catch (e) {
      debugPrint('PushService._postToken failed: $e');
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
    } else if (data['type'] == 'notification') {
      // Activity push: navigate to the exact target (post/comment). Fall back
      // to just opening the notifications bell if the rich handler isn't wired.
      final handler = onNotificationTap;
      if (handler != null) {
        handler(data);
      } else if (onSoftTap != null) {
        onSoftTap!();
      } else {
        _pendingNotificationData = data;
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
    final notifData = _pendingNotificationData;
    if (notifData != null) {
      _pendingNotificationData = null;
      if (onNotificationTap != null) {
        onNotificationTap!(notifData);
      } else {
        onSoftTap?.call();
      }
    }
    if (_pendingSoft) {
      _pendingSoft = false;
      onSoftTap?.call();
    }
  }
}
